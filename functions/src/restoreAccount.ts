import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, requireUserExists, requireNotSelf, logAdminAction } from "./adminAuth";

export const restoreAccount = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const targetUid = requireString(request.data?.targetUid, "targetUid");
  requireNotSelf(actorUid, targetUid);

  const targetDoc = await requireUserExists(db, targetUid);
  if (targetDoc.get("isDisabled") !== true) {
    throw new HttpsError("failed-precondition", "Account is not currently disabled.");
  }

  await db.collection("users").doc(targetUid).update({
    isDisabled: false,
    disabledAt: admin.firestore.FieldValue.delete(),
  });

  await logAdminAction(db, { action: "restore", actorUid, targetUid });

  return { success: true };
});
