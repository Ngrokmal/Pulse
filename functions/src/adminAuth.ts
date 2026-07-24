import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export function requireAdmin(request: CallableRequest): string {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admin privileges required.");
  }
  return auth.uid;
}

export function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

export async function requireUserExists(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<admin.firestore.DocumentSnapshot> {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists) {
    throw new HttpsError("not-found", "Target user does not exist.");
  }
  return doc;
}

export function requireNotSelf(actorUid: string, targetUid: string): void {
  if (actorUid === targetUid) {
    throw new HttpsError("invalid-argument", "Actor cannot target themselves.");
  }
}

export async function logAdminAction(
  db: admin.firestore.Firestore,
  entry: {
    action: string;
    actorUid: string;
    targetUid?: string | null;
    reportId?: string | null;
    details?: string | null;
  },
): Promise<void> {
  await db.collection("adminActionLog").add({
    action: entry.action,
    actorUid: entry.actorUid,
    targetUid: entry.targetUid ?? null,
    reportId: entry.reportId ?? null,
    details: entry.details ?? null,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}
