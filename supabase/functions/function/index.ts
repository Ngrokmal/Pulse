// Supabase Edge Function: delete-image
//
// Migrated from the Firebase callable `deleteCloudinaryMedia`.
// Contract preserved for the Flutter client (MediaRepositoryImpl.deleteMedia()):
//   Request JSON body:  { publicId: string, resourceType: "image" | "video" | "raw" }
//   Success response:   200 { success: true, result: string }
//   Error response:     <status> { error: { code: string, message: string } }
//
// Required secrets (set via `supabase secrets set`):
//   CLOUDINARY_CLOUD_NAME
//   CLOUDINARY_API_KEY
//   CLOUDINARY_API_SECRET
// Auto-provided by the Supabase runtime:
//   SUPABASE_URL
//   SUPABASE_ANON_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

const VALID_RESOURCE_TYPES = new Set(["image", "video", "raw"]);

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ErrorCode =
  | "unauthenticated"
  | "invalid-argument"
  | "unavailable"
  | "internal"
  | "method-not-allowed";

const STATUS_BY_CODE: Record<ErrorCode, number> = {
  unauthenticated: 401,
  "invalid-argument": 400,
  unavailable: 503,
  internal: 500,
  "method-not-allowed": 405,
};

function errorResponse(code: ErrorCode, message: string): Response {
  return new Response(
    JSON.stringify({ error: { code, message } }),
    {
      status: STATUS_BY_CODE[code],
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    },
  );
}

function successResponse(result: string): Response {
  return new Response(
    JSON.stringify({ success: true, result }),
    {
      status: 200,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    },
  );
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError("invalid-argument", `${fieldName} is required and must be a non-empty string.`);
  }
  return value;
}

class HttpError extends Error {
  code: ErrorCode;
  constructor(code: ErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}

async function sha1Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-1", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyAuth(req: Request): Promise<void> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();

  if (!token) {
    throw new HttpError("unauthenticated", "Sign-in required.");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    throw new HttpError("internal", "Server misconfiguration: missing Supabase environment variables.");
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) {
    throw new HttpError("unauthenticated", "Sign-in required.");
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse("method-not-allowed", "Only POST is supported.");
  }

  try {
    await verifyAuth(req);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      throw new HttpError("invalid-argument", "Request body must be valid JSON.");
    }

    const publicId = requireString(body?.publicId, "publicId");
    const resourceType = requireString(body?.resourceType, "resourceType");

    if (!VALID_RESOURCE_TYPES.has(resourceType)) {
      throw new HttpError("invalid-argument", "resourceType must be 'image', 'video', or 'raw'.");
    }

    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
    const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");

    if (!cloudName || !apiKey || !apiSecret) {
      throw new HttpError("internal", "Server misconfiguration: missing Cloudinary secrets.");
    }

    const timestamp = Math.floor(Date.now() / 1000).toString();
    const paramsToSign = `public_id=${publicId}&timestamp=${timestamp}`;
    const signature = await sha1Hex(`${paramsToSign}${apiSecret}`);

    const destroyUrl = `https://api.cloudinary.com/v1_1/${cloudName}/${resourceType}/destroy`;

    const form = new URLSearchParams({
      public_id: publicId,
      api_key: apiKey,
      timestamp,
      signature,
    });

    let cloudinaryResponse: Response;
    try {
      cloudinaryResponse = await fetch(destroyUrl, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
    } catch (e) {
      throw new HttpError("unavailable", `Cloudinary request failed: ${(e as Error).message}`);
    }

    const responseText = await cloudinaryResponse.text();
    if (!cloudinaryResponse.ok) {
      throw new HttpError(
        "internal",
        `Cloudinary delete failed (${cloudinaryResponse.status}): ${responseText}`,
      );
    }

    let parsed: { result?: string };
    try {
      parsed = JSON.parse(responseText) as { result?: string };
    } catch {
      throw new HttpError("internal", "Cloudinary returned an unparseable response.");
    }

    return successResponse(parsed.result ?? "unknown");
  } catch (e) {
    if (e instanceof HttpError) {
      return errorResponse(e.code, e.message);
    }
    return errorResponse("internal", `Unexpected error: ${(e as Error).message}`);
  }
});
