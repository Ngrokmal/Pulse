const admin = require("firebase-admin");

const targetUid = process.argv[2];

if (!targetUid) {
  console.error("Usage: node scripts/bootstrapFirstAdmin.js <uid>");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

async function run() {
  const user = await admin.auth().getUser(targetUid);
  const existingClaims = user.customClaims || {};
  await admin.auth().setCustomUserClaims(targetUid, { ...existingClaims, admin: true });
  await admin.auth().revokeRefreshTokens(targetUid);
  await admin.firestore().collection("adminActionLog").add({
    action: "admin_granted",
    actorUid: "bootstrap-script",
    targetUid,
    reportId: null,
    details: "Initial admin bootstrap",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`admin claim granted to ${targetUid}`);
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
