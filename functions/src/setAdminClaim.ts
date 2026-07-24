import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, requireNotSelf, logAdminAction } from "./adminAuth";

export const setAdminClaim = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const targetUid = requireString(request.data?.targetUid, "targetUid");
  const makeAdmin = request.data?.makeAdmin;
  if (typeof makeAdmin !== "boolean") {
    throw new HttpsError("invalid-argument", "makeAdmin must be a boolean.");
  }
  requireNotSelf(actorUid, targetUid);

  const targetUser = await admin.auth().getUser(targetUid).catch(() => {
    throw new HttpsError("not-found", "Target user does not exist.");
  });

  const existingClaims = targetUser.customClaims ?? {};
  await admin.auth().setCustomUserClaims(targetUid, { ...existingClaims, admin: makeAdmin });
  await admin.auth().revokeRefreshTokens(targetUid);

  await logAdminAction(db, {
    action: makeAdmin ? "admin_granted" : "admin_revoked",
    actorUid,
    targetUid,
  });

  return { success: true };
});
