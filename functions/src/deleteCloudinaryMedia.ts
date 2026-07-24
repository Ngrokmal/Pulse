// NOTE: superseded as of the Supabase Edge Function migration. The Flutter
// client's MediaRepositoryImpl.deleteMedia() now calls the `delete-image`
// Supabase Edge Function directly instead of this callable. Left deployed
// and untouched (not deleted/redesigned) — safe to decommission later once
// confirmed nothing else calls it.
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as crypto from "crypto";
import { requireString } from "./adminAuth";

const CLOUDINARY_CLOUD_NAME = defineSecret("CLOUDINARY_CLOUD_NAME");
const CLOUDINARY_API_KEY = defineSecret("CLOUDINARY_API_KEY");
const CLOUDINARY_API_SECRET = defineSecret("CLOUDINARY_API_SECRET");

const VALID_RESOURCE_TYPES = new Set(["image", "video", "raw"]);

export const deleteCloudinaryMedia = onCall(
  { secrets: [CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET] },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const publicId = requireString(request.data?.publicId, "publicId");
    const resourceType = requireString(request.data?.resourceType, "resourceType");

    if (!VALID_RESOURCE_TYPES.has(resourceType)) {
      throw new HttpsError("invalid-argument", "resourceType must be 'image', 'video', or 'raw'.");
    }

    const cloudName = CLOUDINARY_CLOUD_NAME.value();
    const apiKey = CLOUDINARY_API_KEY.value();
    const apiSecret = CLOUDINARY_API_SECRET.value();

    const timestamp = Math.floor(Date.now() / 1000).toString();
    const paramsToSign = `public_id=${publicId}&timestamp=${timestamp}`;
    const signature = crypto
      .createHash("sha1")
      .update(`${paramsToSign}${apiSecret}`)
      .digest("hex");

    const destroyUrl = `https://api.cloudinary.com/v1_1/${cloudName}/${resourceType}/destroy`;

    const body = new URLSearchParams({
      public_id: publicId,
      api_key: apiKey,
      timestamp,
      signature,
    });

    let response: Response;
    try {
      response = await fetch(destroyUrl, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body.toString(),
      });
    } catch (e) {
      throw new HttpsError("unavailable", `Cloudinary request failed: ${(e as Error).message}`);
    }

    const responseText = await response.text();
    if (!response.ok) {
      throw new HttpsError("internal", `Cloudinary delete failed (${response.status}): ${responseText}`);
    }

    let parsed: { result?: string };
    try {
      parsed = JSON.parse(responseText) as { result?: string };
    } catch {
      throw new HttpsError("internal", "Cloudinary returned an unparseable response.");
    }

    return { success: true, result: parsed.result ?? "unknown" };
  },
);
