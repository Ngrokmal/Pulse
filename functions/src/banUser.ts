import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, requireUserExists, requireNotSelf, logAdminAction } from "./adminAuth";

const VALID_TYPES = new Set(["permanent", "temporary"]);

export const banUser = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const targetUid = requireString(request.data?.targetUid, "targetUid");
  const reason = requireString(request.data?.reason, "reason");
  const type = requireString(request.data?.type, "type");
  const expiresAtRaw = request.data?.expiresAt;

  if (!VALID_TYPES.has(type)) {
    throw new HttpsError("invalid-argument", "type must be 'permanent' or 'temporary'.");
  }
  requireNotSelf(actorUid, targetUid);

  const targetDoc = await requireUserExists(db, targetUid);
  if (targetDoc.get("isBanned") === true) {
    throw new HttpsError("failed-precondition", "User is already banned.");
  }

  let expiresAt: admin.firestore.Timestamp | null = null;
  if (type === "temporary") {
    if (typeof expiresAtRaw !== "string") {
      throw new HttpsError("invalid-argument", "expiresAt is required for a temporary ban.");
    }
    const parsed = new Date(expiresAtRaw);
    if (Number.isNaN(parsed.getTime()) || parsed.getTime() <= Date.now()) {
      throw new HttpsError("invalid-argument", "expiresAt must be a valid future date.");
    }
    expiresAt = admin.firestore.Timestamp.fromDate(parsed);
  }

  const banRef = db.collection("bans").doc();
  const userRef = db.collection("users").doc(targetUid);

  await db.runTransaction(async (tx) => {
    tx.set(banRef, {
      targetUid,
      reason,
      issuedBy: actorUid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "active",
      type,
      expiresAt,
    });
    tx.update(userRef, {
      isBanned: true,
      bannedAt: admin.firestore.FieldValue.serverTimestamp(),
      banType: type,
      banExpiresAt: expiresAt ?? admin.firestore.FieldValue.delete(),
    });
  });

  await admin.auth().revokeRefreshTokens(targetUid);

  await logAdminAction(db, { action: "ban", actorUid, targetUid, details: reason });

  return { success: true };
});
