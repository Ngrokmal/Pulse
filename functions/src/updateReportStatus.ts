import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAdmin, requireString, logAdminAction } from "./adminAuth";

const VALID_STATUSES = new Set(["pending", "reviewed", "resolved"]);

export const updateReportStatus = onCall(async (request: CallableRequest) => {
  const actorUid = requireAdmin(request);
  const db = admin.firestore();

  const reportId = requireString(request.data?.reportId, "reportId");
  const status = requireString(request.data?.status, "status");

  if (!VALID_STATUSES.has(status)) {
    throw new HttpsError("invalid-argument", "status must be 'pending', 'reviewed', or 'resolved'.");
  }

  const reportRef = db.collection("reports").doc(reportId);
  const reportDoc = await reportRef.get();
  if (!reportDoc.exists) {
    throw new HttpsError("not-found", "Report does not exist.");
  }

  await reportRef.update({ status });

  await logAdminAction(db, {
    action: status === "resolved" ? "report_resolved" : "report_reviewed",
    actorUid,
    reportId,
  });

  return { success: true };
});
