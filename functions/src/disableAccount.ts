import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, requireUserExists, requireNotSelf, logAdminAction } from "./adminAuth";

export const disableAccount = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const targetUid = requireString(request.data?.targetUid, "targetUid");
  requireNotSelf(actorUid, targetUid);

  const targetDoc = await requireUserExists(db, targetUid);
  if (targetDoc.get("isDisabled") === true) {
    throw new HttpsError("failed-precondition", "Account is already disabled.");
  }

  await db.collection("users").doc(targetUid).update({
    isDisabled: true,
    disabledAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await admin.auth().revokeRefreshTokens(targetUid);

  await logAdminAction(db, { action: "disable", actorUid, targetUid });

  return { success: true };
});
