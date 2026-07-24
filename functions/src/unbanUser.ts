import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, requireUserExists, requireNotSelf, logAdminAction } from "./adminAuth";

export const unbanUser = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const targetUid = requireString(request.data?.targetUid, "targetUid");
  requireNotSelf(actorUid, targetUid);

  const targetDoc = await requireUserExists(db, targetUid);
  if (targetDoc.get("isBanned") !== true) {
    throw new HttpsError("failed-precondition", "User is not currently banned.");
  }

  const activeBans = await db
    .collection("bans")
    .where("targetUid", "==", targetUid)
    .where("status", "==", "active")
    .get();

  const userRef = db.collection("users").doc(targetUid);

  await db.runTransaction(async (tx) => {
    for (const doc of activeBans.docs) {
      tx.update(doc.ref, { status: "lifted" });
    }
    tx.update(userRef, {
      isBanned: false,
      bannedAt: admin.firestore.FieldValue.delete(),
      banType: admin.firestore.FieldValue.delete(),
      banExpiresAt: admin.firestore.FieldValue.delete(),
    });
  });

  await logAdminAction(db, { action: "unban", actorUid, targetUid });

  return { success: true };
});
