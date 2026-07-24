// TASK 2 migration — run ONCE before/at rollout of the local-first chat
// architecture. Backfills `updatedAt` on every existing message document
// that doesn't have one yet (set equal to its `createdAt`), across every
// chat's `messages` subcollection.
//
// Why this is required: ChatRepositoryImpl.streamMessages /
// GroupRepositoryImpl.streamGroupMessages now query
// `where('updatedAt', isGreaterThan: cursor)`. Firestore excludes any
// document that doesn't have the filtered field at all from that query —
// so without this backfill, every message sent before this deploy would
// become permanently invisible to any device that doesn't already have it
// cached locally (fresh installs, new devices, cleared app storage).
//
// Usage: node scripts/backfillMessageUpdatedAt.js
const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();
const BATCH_SIZE = 400;

async function backfillChat(chatDoc) {
  const messagesRef = chatDoc.ref.collection("messages");
  let migrated = 0;
  let lastDoc = null;

  while (true) {
    let query = messagesRef.orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let batchHasWrites = false;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      if (data.updatedAt === undefined && data.createdAt !== undefined) {
        batch.update(doc.ref, { updatedAt: data.createdAt });
        batchHasWrites = true;
        migrated++;
      }
    }

    if (batchHasWrites) await batch.commit();
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < BATCH_SIZE) break;
  }

  return migrated;
}

async function run() {
  const chatsSnapshot = await db.collection("chats").get();
  let totalMigrated = 0;

  for (const chatDoc of chatsSnapshot.docs) {
    const migrated = await backfillChat(chatDoc);
    totalMigrated += migrated;
    if (migrated > 0) {
      console.log(`chats/${chatDoc.id}: backfilled updatedAt on ${migrated} message(s)`);
    }
  }

  console.log(`Done. Total messages backfilled: ${totalMigrated}`);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
