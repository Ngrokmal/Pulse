import { onCall, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, requireUserExists, requireNotSelf, logAdminAction } from "./adminAuth";

export const issueWarning = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const targetUid = requireString(request.data?.targetUid, "targetUid");
  const reason = requireString(request.data?.reason, "reason");
  requireNotSelf(actorUid, targetUid);

  await requireUserExists(db, targetUid);

  await db.collection("warnings").add({
    userUid: targetUid,
    reason,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    issuedBy: actorUid,
  });

  await logAdminAction(db, { action: "warning_issued", actorUid, targetUid, details: reason });

  return { success: true };
});
