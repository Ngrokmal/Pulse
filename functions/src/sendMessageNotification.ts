import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Missing link identified by the notification-delivery audit: no Cloud
 * Function anywhere in this repo ever called admin.messaging().send(). The
 * receiver side (fcm_message_handler.dart, notification_service.dart,
 * AlertAudioMetadataModel.fromPushData, the whole Custom Alert Audio System)
 * was already fully built and is left completely untouched here — this
 * function only produces the push that receiver already knows how to
 * consume.
 *
 * Triggers on every new doc under chats/{chatId}/messages/{messageId} —
 * covers text, media, voice, and Friend Alert Sounds messages uniformly,
 * since they're all written through the same MessageModel/_persistMessage
 * path client-side and therefore land in the same collection with the same
 * shape (alert-only/message+alert messages simply have the extra alert*
 * fields populated).
 *
 * Payload contract is NOT invented here — every data field sent below is a
 * field AlertAudioMetadataModel.fromPushData (lib/features/custom_alert/
 * data/models/alert_audio_metadata_model.dart) and fcm_message_handler.dart
 * already read: title, body, chatId, and — only when present on the message
 * — alertId/alertDisplayName/alertAudioUrl/alertAudioChecksum/
 * alertAudioFormat/alertAudioSizeBytes/alertAudioDurationMs. FCM data
 * payloads must be flat string maps, so numeric fields are stringified
 * exactly the way fromPushData already expects to parse them
 * (int.tryParse / no parsing for strings).
 */
export const sendMessageNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const message = snap.data();
    const { chatId } = event.params;
    const db = admin.firestore();

    const senderId: string | undefined = message.senderId;
    if (!senderId) return;

    // Recipient(s): every chat participant except the sender. 1:1 chat docs
    // store members under participantIds (ChatRepositoryImpl); group chat
    // docs store members under memberUids instead (GroupRepositoryImpl,
    // ChatListItemModel.isGroup) and never have participantIds. A chat doc
    // only ever has one of the two fields, so this can't double-count.
    const chatDoc = await db.collection("chats").doc(chatId).get();
    const chatData = chatDoc.data();
    const participantIds: string[] = chatData?.participantIds ?? chatData?.memberUids ?? [];
    const recipientIds = participantIds.filter((uid) => uid !== senderId);
    if (recipientIds.length === 0) return;

    // Tokens: reuses the existing users/{uid}.fcmToken field, now populated
    // by FcmTokenSyncService (lib/core/services/fcm_token_sync_service.dart)
    // — the client-side half of this same missing-link fix.
    const userDocs = await db.getAll(
      ...recipientIds.map((uid) => db.collection("users").doc(uid))
    );
    const tokenPairs = recipientIds
      .map((uid, i) => ({ uid, token: userDocs[i].data()?.fcmToken as string | undefined }))
      .filter((pair): pair is { uid: string; token: string } => !!pair.token);
    const tokens = tokenPairs.map((pair) => pair.token);
    if (tokens.length === 0) {
      logger.info(`sendMessageNotification: no FCM tokens for chat ${chatId}, skipping.`);
      return;
    }

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName: string = senderDoc.data()?.displayName ?? senderDoc.data()?.username ?? "Someone";

    const hasAlert = !!message.alertId && !!message.alertAudioUrl;
    const hasText = typeof message.text === "string" && message.text.trim().length > 0;

    // Same three send modes as the client's send flow (message-only /
    // message+alert / alert-only) — this only decides notification title
    // and body text, not delivery mechanics, which are identical either way.
    let title = senderName;
    let body: string;
    if (hasAlert && hasText) {
      body = message.text;
    } else if (hasAlert) {
      body = `🔔 sent you a "${message.alertDisplayName ?? "custom"}" alert`;
    } else if (hasText) {
      body = message.text;
    } else {
      body = message.type === "voice" ? "🎤 Voice message" : "Sent a message";
    }

    const data: Record<string, string> = {
      title,
      body,
      chatId,
    };
    if (hasAlert) {
      data.alertId = String(message.alertId);
      data.alertDisplayName = String(message.alertDisplayName ?? message.alertId);
      data.alertAudioUrl = String(message.alertAudioUrl);
      data.alertAudioChecksum = String(message.alertAudioChecksum ?? "");
      data.alertAudioFormat = String(message.alertAudioFormat ?? "");
      data.alertAudioSizeBytes = String(message.alertAudioSizeBytes ?? "0");
      if (message.alertAudioDurationMs != null) {
        data.alertAudioDurationMs = String(message.alertAudioDurationMs);
      }
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      data,
      // No `notification` block: the client (NotificationService, existing,
      // untouched) builds and displays its own local notification from
      // `data` for every app state — this avoids the OS auto-displaying a
      // second, duplicate notification alongside the custom-sound one.
      android: { priority: "high" },
      apns: { headers: { "apns-priority": "10" }, payload: { aps: { contentAvailable: true } } },
    });

    // Best-effort cleanup of dead tokens — does not block/redesign anything
    // else, just keeps users/{uid}.fcmToken from going stale forever.
    response.responses.forEach((r, i) => {
      if (!r.success && r.error?.code === "messaging/registration-token-not-registered") {
        const uid = tokenPairs[i].uid;
        db.collection("users").doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() }).catch(() => {});
      }
    });

    logger.info(
      `sendMessageNotification: chat ${chatId}, ${response.successCount}/${tokens.length} delivered.`
    );
  }
);
