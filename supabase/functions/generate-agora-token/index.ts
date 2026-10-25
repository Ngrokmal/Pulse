// Supabase Edge Function: generate-agora-token
//
// MILESTONE 4 PART A (Call module backend). Mints short-lived Agora RTC
// tokens server-side so the Agora App Certificate never reaches the
// client — the client only ever sees the resulting token (Phase 1 §9/§21).
//
// Called by CallRemoteDataSourceImpl.fetchAgoraToken
// (lib/features/call/data/datasources/call_remote_datasource_impl.dart),
// via a raw `http.Client` POST (mirroring send-push-notification's own
// call-site convention — no other Edge Function in this project uses
// supabase_flutter's FunctionsClient, so this keeps that one consistent
// precedent rather than introducing a second calling convention).
//
// Also serves BOTH of CallRepository's token methods — getAgoraToken
// (initial join) and refreshAgoraToken (Phase 1 §9 mid-call renewal,
// driven by AgoraCubit's AgoraTokenExpiringSoon handling): CallRepositoryImpl
// .refreshAgoraToken is literally the same request as .getAgoraToken, so
// this single endpoint is "Token renewal support" in full — no separate
// renew endpoint or DB state is needed.
//
// Deploy target: the MAIN Supabase project (ref eqqlscbklniuttvrglmo) —
// same project as send-push-notification and public.call_sessions
// (0023_call_sessions_and_events.sql). Matches
// SupabaseConfig.generateAgoraTokenFunctionUrl.
//
// Request JSON body:
//   {
//     callId: string,       // public.call_sessions.id (uuid)
//     channelName: string,  // must equal that row's channel_name
//     uid: number,          // must equal the caller's own
//                           // agora_uid_caller/agora_uid_callee on that row
//   }
//
// Success response: 200
//   { token: string, uid: number, channel: string, expires_at: string (ISO), app_id: string }
//   — exact shape AgoraTokenDto.fromJson expects (agora_token_dto.dart):
//   token/uid/channel/expires_at/app_id, no wrapper object.
// Error response: <status> { error: { code: string, message: string } }
//
// Required secrets (set via `supabase secrets set`):
//   AGORA_APP_ID            — Agora project App ID (not secret by itself,
//                             but kept server-side so the client never
//                             hardcodes it either — it comes back in the
//                             response and CallCubit passes it straight
//                             into AgoraRepository.initialize()).
//   AGORA_APP_CERTIFICATE   — Agora project App Certificate. MUST NEVER be
//                             sent to the client, logged, or embedded in
//                             any response — used only in-process here to
//                             sign the token.
// Auto-provided by the Supabase runtime:
//   SUPABASE_URL
//   SUPABASE_ANON_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";
import { RtcRole, RtcTokenBuilder } from "npm:agora-token@2.0.5";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ErrorCode =
  | "unauthenticated"
  | "permission-denied"
  | "not-found"
  | "invalid-argument"
  | "internal"
  | "method-not-allowed";

const STATUS_BY_CODE: Record<ErrorCode, number> = {
  unauthenticated: 401,
  "permission-denied": 403,
  "not-found": 404,
  "invalid-argument": 400,
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

function jsonResponse(body: Record<string, unknown>): Response {
  return new Response(
    JSON.stringify(body),
    { status: 200, headers: { "Content-Type": "application/json", ...CORS_HEADERS } },
  );
}

function requireString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError("invalid-argument", `${fieldName} is required and must be a non-empty string.`);
  }
  return value;
}

function requireNumber(value: unknown, fieldName: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpError("invalid-argument", `${fieldName} is required and must be a number.`);
  }
  return value;
}

// Token privilege lifetime. AgoraCubit refreshes proactively on
// onTokenPrivilegeWillExpire (fired by the Agora SDK before this window
// runs out), so this only needs to comfortably outlast a single ringing
// window + ordinary call duration between refreshes — 1 hour matches
// common Agora reference-app defaults and is short enough that a
// leaked/logged token has a bounded blast radius.
const TOKEN_TTL_SECONDS = 3600;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError("method-not-allowed", "Only POST is supported.");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!accessToken) {
      throw new HttpError("unauthenticated", "Sign-in required.");
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      throw new HttpError("invalid-argument", "Request body must be valid JSON.");
    }
    const { callId, channelName, uid } = (() => {
      const b = body as Record<string, unknown>;
      return {
        callId: requireString(b.callId, "callId"),
        channelName: requireString(b.channelName, "channelName"),
        uid: requireNumber(b.uid, "uid"),
      };
    })();

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnonKey) {
      throw new HttpError("internal", "Server misconfiguration: missing Supabase environment variables.");
    }

    // Scoped to the caller's own JWT (not service-role) so
    // call_sessions_select_participant RLS does the "is this user actually
    // on this call" check for us — a non-participant's select simply
    // returns no row, which we then report as not-found rather than
    // leaking whether the callId exists at all.
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      throw new HttpError("unauthenticated", "Invalid or expired session.");
    }
    const requestingUserId = userData.user.id;

    const { data: session, error: sessionErr } = await userClient
      .from("call_sessions")
      .select("id, caller_id, callee_id, channel_name, status, agora_uid_caller, agora_uid_callee")
      .eq("id", callId)
      .maybeSingle();

    if (sessionErr) {
      throw new HttpError("internal", `Failed to read call session: ${sessionErr.message}`);
    }
    if (!session) {
      throw new HttpError("not-found", "This call no longer exists.");
    }
    if (session.status !== "ringing" && session.status !== "accepted") {
      throw new HttpError("invalid-argument", "This call is no longer active.");
    }
    if (session.channel_name !== channelName) {
      throw new HttpError("invalid-argument", "channelName does not match this call.");
    }

    const expectedUid = requestingUserId === session.caller_id
      ? session.agora_uid_caller
      : requestingUserId === session.callee_id
      ? session.agora_uid_callee
      : null;

    // Unreachable in practice — RLS already guarantees `session` is only
    // returned when requestingUserId is caller_id or callee_id — kept as
    // an explicit, auditable check rather than silently trusting that.
    if (expectedUid === null) {
      throw new HttpError("permission-denied", "You are not a participant on this call.");
    }
    if (expectedUid !== uid) {
      throw new HttpError("invalid-argument", "uid does not match this call session.");
    }

    const appId = Deno.env.get("AGORA_APP_ID");
    const appCertificate = Deno.env.get("AGORA_APP_CERTIFICATE");
    if (!appId || !appCertificate) {
      throw new HttpError("internal", "Server misconfiguration: missing Agora environment variables.");
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    const privilegeExpireSeconds = nowSeconds + TOKEN_TTL_SECONDS;

    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      uid,
      RtcRole.PUBLISHER,
      privilegeExpireSeconds,
      privilegeExpireSeconds,
    );

    return jsonResponse({
      token,
      uid,
      channel: channelName,
      expires_at: new Date(privilegeExpireSeconds * 1000).toISOString(),
      app_id: appId,
    });
  } catch (e) {
    if (e instanceof HttpError) {
      return errorResponse(e.code, e.message);
    }
    return errorResponse("internal", e instanceof Error ? e.message : String(e));
  }
});
