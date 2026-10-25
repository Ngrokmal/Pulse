// Supabase Edge Function: send-push-notification
//
// PHASE 2K (Firebase -> Supabase, Push Notification Migration).
// Replaces the never-implemented `sendMessageNotification` Cloud Function
// that FcmTokenSyncService's comments referenced (it read `users/{uid}.fcmToken`
// from Firestore but nothing on the sending side ever existed in this repo).
//
// This function is the ONLY place in the whole project allowed to talk to
// Firebase — and it only talks to Firebase Cloud Messaging's HTTP v1 REST
// API, using a Google Service Account. No Firebase Admin SDK, no Firestore,
// no Auth. The FCM device token itself now lives in Supabase Postgres
// (`public.users.fcm_token`, written client-side by FcmTokenSyncService),
// not Firestore.
//
// Deploy target: the MAIN Supabase project (ref eqqlscbklniuttvrglmo) —
// the same project as `public.users` / `fcm_token` (see
// supabase/migrations/0010_fcm_token.sql) and the app's Supabase.initialize()
// call. This is a DIFFERENT Supabase project from the one hosting
// delete-image (ref qsnauioozvkhksbxajam) — do not deploy this function
// there; it would not be able to see the `users` table it depends on.
//
// Request JSON body:
//   {
//     targetUserId: string,        // public.users.id (uuid) of the recipient
//     title: string,
//     body: string,
//     data?: Record<string, string> // optional deep-link payload (chatId, messageId, type, ...)
//   }
//
// Success response:  200 { success: true, result: "sent" | "skipped", reason?: string }
// Error response:     <status> { error: { code: string, message: string } }
//
// Required secrets (set via `supabase secrets set`):
//   FCM_SERVICE_ACCOUNT_JSON   — full JSON key file contents for a Google
//                                Service Account with the
//                                "Firebase Cloud Messaging API" role,
//                                downloaded from the Firebase console
//                                (Project Settings -> Service Accounts).
// Auto-provided by the Supabase runtime:
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

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

class HttpError extends Error {
  code: ErrorCode;
  constructor(code: ErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}

function errorResponse(code: ErrorCode, message: string): Response {
  return new Response(
    JSON.stringify({ error: { code, message } }),
    { status: STATUS_BY_CODE[code], headers: { "Content-Type": "application/json", ...CORS_HEADERS } },
  );
}

function successResponse(result: string, extra: Record<string, unknown> = {}): Response {
  return new Response(
    JSON.stringify({ success: true, result, ...extra }),
    { status: 200, headers: { "Content-Type": "application/json", ...CORS_HEADERS } },
  );
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError("invalid-argument", `${fieldName} is required and must be a non-empty string.`);
  }
  return value;
}

// --- Auth: caller must hold a valid Supabase session (same pattern as
// the delete-image function) so random unauthenticated clients can't use
// this endpoint to spam arbitrary users with push notifications.
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

  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    throw new HttpError("unauthenticated", "Invalid or expired session.");
  }
}

// --- Google OAuth2 (service-account JWT-bearer flow), implemented with
// Deno's built-in Web Crypto so no npm Google Auth library is needed.
function base64UrlEncode(bytes: Uint8Array): string {
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(clean);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const nowSec = Math.floor(Date.now() / 1000);
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSec,
    exp: nowSec + 3600,
  };

  const encoder = new TextEncoder();
  const unsignedJwt =
    `${base64UrlEncode(encoder.encode(JSON.stringify(header)))}.` +
    `${base64UrlEncode(encoder.encode(JSON.stringify(claims)))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(unsignedJwt),
  );

  const signedJwt = `${unsignedJwt}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedJwt,
    }),
  });

  if (!tokenRes.ok) {
    const text = await tokenRes.text();
    throw new HttpError("unavailable", `Google OAuth token exchange failed: ${text}`);
  }

  const tokenJson = await tokenRes.json();
  const accessToken = tokenJson.access_token as string | undefined;
  if (!accessToken) {
    throw new HttpError("unavailable", "Google OAuth token exchange returned no access_token.");
  }
  return accessToken;
}

function loadServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new HttpError("internal", "Server misconfiguration: FCM_SERVICE_ACCOUNT_JSON is not set.");
  }
  try {
    const parsed = JSON.parse(raw);
    requireString(parsed.client_email, "service account client_email");
    requireString(parsed.private_key, "service account private_key");
    requireString(parsed.project_id, "service account project_id");
    return parsed as ServiceAccount;
  } catch (e) {
    throw new HttpError("internal", `FCM_SERVICE_ACCOUNT_JSON is not valid JSON: ${e instanceof Error ? e.message : String(e)}`);
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError("method-not-allowed", "Only POST is supported.");
    }

    await verifyAuth(req);

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      throw new HttpError("invalid-argument", "Request body must be valid JSON.");
    }
    const { targetUserId, title, notificationBody, data } = (() => {
      const b = body as Record<string, unknown>;
      return {
        targetUserId: requireString(b.targetUserId, "targetUserId"),
        title: requireString(b.title, "title"),
        notificationBody: requireString(b.body, "body"),
        data: (b.data && typeof b.data === "object") ? b.data as Record<string, unknown> : {},
      };
    })();

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new HttpError("internal", "Server misconfiguration: missing Supabase service-role environment variables.");
    }
    // Service-role client: reading another user's fcm_token must bypass
    // RLS (a user's own anon-key session cannot, and should not, be able
    // to read a stranger's device token directly).
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: userRow, error: userErr } = await adminClient
      .from("users")
      .select("fcm_token")
      .eq("id", targetUserId)
      .maybeSingle();

    if (userErr) {
      throw new HttpError("internal", `Failed to read target user's fcm_token: ${userErr.message}`);
    }
    const fcmToken = userRow?.fcm_token as string | null | undefined;
    if (!fcmToken) {
      // Not an error — the recipient simply has no push token registered
      // yet (never granted permission, signed out, etc). Degrade gracefully.
      return successResponse("skipped", { reason: "no_fcm_token" });
    }

    const serviceAccount = loadServiceAccount();
    const accessToken = await getGoogleAccessToken(serviceAccount);

    // FCM HTTP v1 requires all `data` values to be strings.
    const stringData: Record<string, string> = {};
    for (const [k, v] of Object.entries(data)) stringData[k] = String(v);

    // Floating Bell custom voice alerts route to a distinct Android
    // notification channel so their sound can be silenced/overridden
    // client-side in favor of the downloaded custom audio.
    const isCustomVoice =
      !!stringData.alertAudioUrl ||
      !!stringData.voice_url ||
      stringData.alert_type === "custom_voice";

    const androidChannelId = isCustomVoice
      ? "custom_voice_alerts_channel"
      : "normal_messages_channel";

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body: notificationBody },
            data: stringData,
            android: {
              priority: "high",
              notification: { channelId: androidChannelId },
            },
          },
        }),
      },
    );

    const fcmJson = await fcmRes.json().catch(() => ({}));

    if (!fcmRes.ok) {
      const fcmErrorStatus = fcmJson?.error?.status as string | undefined;
      // Stale/uninstalled-app tokens: clear it so future sends don't keep
      // retrying a dead token.
      if (fcmErrorStatus === "UNREGISTERED" || fcmErrorStatus === "NOT_FOUND") {
        await adminClient.from("users").update({ fcm_token: null }).eq("id", targetUserId);
        return successResponse("skipped", { reason: "stale_token_cleared" });
      }
      throw new HttpError("unavailable", `FCM send failed: ${JSON.stringify(fcmJson)}`);
    }

    return successResponse("sent", { fcmMessageId: fcmJson.name });
  } catch (e) {
    if (e instanceof HttpError) {
      return errorResponse(e.code, e.message);
    }
    return errorResponse("internal", e instanceof Error ? e.message : String(e));
  }
});
