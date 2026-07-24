import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/config/cloudinary_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/services/voice_local_cache_service.dart';
import '../../domain/entities/media_upload_result.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/message_type.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/media_repository.dart';
import '../../domain/usecases/send_message_usecase.dart';
import '../../domain/usecases/send_media_message_usecase.dart';
import '../../domain/usecases/send_message_with_alert_usecase.dart';
import '../../../custom_alert/domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/usecases/reset_unread_count_usecase.dart';
import '../../domain/usecases/stream_messages_usecase.dart';
import '../../domain/usecases/set_typing_status_usecase.dart';
import '../../domain/usecases/stream_typing_status_usecase.dart';
import '../../domain/usecases/mark_message_as_delivered_usecase.dart';
import '../../domain/usecases/mark_message_as_read_usecase.dart';

// Stability + Loading + Error Handling মাইলস্টোন: message-stream প্রথম
// snapshot না আসা পর্যন্ত ChatLoading state-এ আটকে থাকতে পারত অনির্দিষ্টকাল
// (Firestore permission/index সমস্যা বা permanently-offline অবস্থায় stream
// কখনো প্রথম event/error emit না করলে) — "infinite loading"। এই সময়সীমা
// পার হলে (স্ট্রিম এখনো চালু/listening থাকা অবস্থাতেই) একটি retry-able
// ErrorState emit করা হয়; পরে ডেটা এলে normal ChatLoadedState-এ self-heal
// করে (নিচে LoadMessagesEvent handler দেখুন)।
const _kLoadTimeout = Duration(seconds: 15);
// send/mark-জাতীয় one-shot Firestore write অপারেশনের জন্য bounded wait —
// OfflineQueueManager স্থায়ী নেটওয়ার্ক-ডাউন অবস্থায় টাস্ক queue-তে রেখে দেয়
// (ইচ্ছাকৃত অফলাইন-রেজিলিয়েন্স), তাই caller-সাইড টাইমআউট ছাড়া এই await
// অনির্দিষ্টকাল আটকে থাকতে পারত।
const _kActionTimeout = Duration(seconds: 15);

abstract class ChatEvent {}
class LoadMessagesEvent extends ChatEvent {
  final String chatId;
  // Day 5 Milestone 6: nullable/optional — পুরনো কোনো call-site থাকলে ভাঙবে না।
  // দেওয়া হলে chat open হওয়ার সাথে সাথে current user-এর unreadCount 0-এ রিসেট হয়
  // (LoadGroupMessagesEvent-এর currentUserId, Day 5 M4-এর সাথে সামঞ্জস্যপূর্ণ)।
  final String? currentUserId;
  LoadMessagesEvent(this.chatId, {this.currentUserId});
}
class OnMessagesReceivedEvent extends ChatEvent {
  final List<MessageEntity> messages;
  OnMessagesReceivedEvent(this.messages);
}
class SendMessageEvent extends ChatEvent {
  final String chatId;
  final String senderId;
  final String text;
  // Day 6 M1 composer-fix: messageId param সরানো হয়েছে — এখন
  // SendMessageUseCase internally generateMessageId দিয়ে জেনারেট করে
  // (SendGroupMessageEvent-এর হুবহু সমতুল্য, যেখানে messageId কখনোই
  // caller-supplied ছিল না)।
  SendMessageEvent({
    required this.chatId,
    required this.senderId,
    required this.text,
  });
}
// Friend Alert Sounds (Premium Social Feature) — additive sibling of
// SendMessageEvent. `text` empty => alert-only send mode; non-empty =>
// message+alert. Dispatched from ChatScreen after the user picks/records a
// sound in the FriendAlertBottomSheet.
class SendMessageWithAlertEvent extends ChatEvent {
  final String chatId;
  final String senderId;
  final String text;
  final AlertAudioMetadata alert;
  SendMessageWithAlertEvent({
    required this.chatId,
    required this.senderId,
    this.text = '',
    required this.alert,
  });
}

class LoadOlderMessagesEvent extends ChatEvent {
  final String chatId;
  final DateTime beforeCreatedAt;
  LoadOlderMessagesEvent({required this.chatId, required this.beforeCreatedAt});
}

class SendMediaMessageEvent extends ChatEvent {
  final String chatId;
  final String senderId;
  final String type;
  final File file;
  final String fileName;
  final int fileSizeBytes;
  final String? mimeType;
  final int? durationMs;
  final String caption;
  final List<double>? waveform;
  SendMediaMessageEvent({
    required this.chatId,
    required this.senderId,
    required this.type,
    required this.file,
    required this.fileName,
    required this.fileSizeBytes,
    this.mimeType,
    this.durationMs,
    this.caption = '',
    this.waveform,
  });
}

class RetryMediaUploadEvent extends ChatEvent {
  final String localId;
  RetryMediaUploadEvent(this.localId);
}

class CancelMediaUploadEvent extends ChatEvent {
  final String localId;
  CancelMediaUploadEvent(this.localId);
}

class _MediaUploadProgressEvent extends ChatEvent {
  final String localId;
  final double progress;
  _MediaUploadProgressEvent(this.localId, this.progress);
}

class _MediaUploadedEvent extends ChatEvent {
  final String localId;
  final String chatId;
  final String senderId;
  final String secureUrl;
  _MediaUploadedEvent(this.localId, this.chatId, this.senderId, this.secureUrl);
}

class _MediaUploadFailedEvent extends ChatEvent {
  final String localId;
  final String errorMessage;
  _MediaUploadFailedEvent(this.localId, this.errorMessage);
}

// Day 6 Milestone 1 (Typing Indicator): UI (ভবিষ্যতে composer widget)
// থেকে dispatch করা হবে — keystroke-এ TypingStartedEvent, ইনঅ্যাক্টিভিটি
// টাইমআউটে TypingStoppedEvent। LoadGroupMessagesEvent/SendGroupMessageEvent-এর
// প্যাটার্নের সাথে সামঞ্জস্যপূর্ণ সাধারণ event class।
class TypingStartedEvent extends ChatEvent {
  final String chatId;
  final String uid;
  TypingStartedEvent({required this.chatId, required this.uid});
}
class TypingStoppedEvent extends ChatEvent {
  final String chatId;
  final String uid;
  TypingStoppedEvent({required this.chatId, required this.uid});
}
// Internal — streamTypingStatusUseCase থেকে আসা প্রতিটি Firestore snapshot-এ
// fire হয়, UI dispatch করে না।
class TypingUsersUpdatedEvent extends ChatEvent {
  final List<String> typingUserIds;
  TypingUsersUpdatedEvent(this.typingUserIds);
}

enum MediaUploadStage { uploading, failed, cancelled }

class PendingMediaUpload {
  final String localId;
  final String type;
  final File file;
  final String fileName;
  final int fileSizeBytes;
  final String? mimeType;
  final int? durationMs;
  final String caption;
  final List<double>? waveform;
  final double progress;
  final MediaUploadStage stage;
  final String? errorMessage;

  const PendingMediaUpload({
    required this.localId,
    required this.type,
    required this.file,
    required this.fileName,
    required this.fileSizeBytes,
    this.mimeType,
    this.durationMs,
    this.caption = '',
    this.waveform,
    this.progress = 0,
    this.stage = MediaUploadStage.uploading,
    this.errorMessage,
  });

  PendingMediaUpload copyWith({
    double? progress,
    MediaUploadStage? stage,
    String? errorMessage,
  }) {
    return PendingMediaUpload(
      localId: localId,
      type: type,
      file: file,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      durationMs: durationMs,
      caption: caption,
      progress: progress ?? this.progress,
      stage: stage ?? this.stage,
      errorMessage: errorMessage,
    );
  }
}

abstract class ChatState {}
class ChatInitial extends ChatState {}
class ChatLoading extends ChatState {}
class ChatLoadedState extends ChatState {
  final List<MessageEntity> messages;
  // Day 6 Milestone 1: self-uid বাদে বর্তমানে টাইপ করছে এমন uid-দের তালিকা।
  // ডিফল্ট খালি লিস্ট — বিদ্যমান কোনো call-site (শুধু messages পাস করা)
  // ভাঙবে না।
  final List<String> typingUserIds;
  final List<PendingMediaUpload> pendingUploads;
  ChatLoadedState({
    required this.messages,
    this.typingUserIds = const [],
    this.pendingUploads = const [],
  });
}
class ChatErrorState extends ChatState {
  final String message;
  ChatErrorState({required this.message});
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository chatRepository;
  final SendMessageUseCase sendMessageUseCase;
  final StreamMessagesUseCase streamMessagesUseCase;
  // Day 5 Milestone 6
  final ResetUnreadCountUseCase resetUnreadCountUseCase;
  // Day 6 Milestone 1 (Typing Indicator)
  final SetTypingStatusUseCase setTypingStatusUseCase;
  final StreamTypingStatusUseCase streamTypingStatusUseCase;
  // Day 6 Milestone 2 (Delivery Status)
  final MarkMessageAsDeliveredUseCase markMessageAsDeliveredUseCase;
  // Day 6 Milestone 3 (Read Receipts)
  final MarkMessageAsReadUseCase markMessageAsReadUseCase;
  // Phase 8.2 (Media Messaging)
  final MediaRepository mediaRepository;
  final SendMediaMessageUseCase sendMediaMessageUseCase;
  // Friend Alert Sounds (Premium Social Feature)
  final SendMessageWithAlertUseCase sendMessageWithAlertUseCase;
  final Map<String, MessageEntity> _messagesCache = {};
  final Map<String, PendingMediaUpload> _pendingUploads = {};
  final Set<String> _cancelledUploads = {};
  // Day 6 Milestone 1: টাইপিং স্ট্রিম আলাদাভাবে সাবস্ক্রাইব করা হয় (emit.forEach
  // messages স্ট্রিমে আটকে থাকে বলে একই handler-এ দুটো স্ট্রিম merge করা যায় না)
  // — প্রতিটি snapshot TypingUsersUpdatedEvent হিসেবে bloc-এর event queue-তে
  // add হয়, যা flutter_bloc-এর normal sequential event processing-এর মধ্যেই থাকে।
  StreamSubscription<List<String>>? _typingSubscription;
  // Stability fix: LoadMessagesEvent-এর "প্রথম snapshot না এলে timeout" গার্ড
  // (নিচে দেখুন) — instance field রাখা হয়েছে যাতে close()-এ cancel করা যায়
  // (dangling Timer এড়াতে, _typingSubscription-এর মতোই প্যাটার্ন)।
  Timer? _loadTimeoutTimer;
  String? _chatId;
  String? _selfUid;

  ChatBloc({
    required this.chatRepository,
    required this.sendMessageUseCase,
    required this.streamMessagesUseCase,
    required this.resetUnreadCountUseCase,
    required this.setTypingStatusUseCase,
    required this.streamTypingStatusUseCase,
    required this.markMessageAsDeliveredUseCase,
    required this.markMessageAsReadUseCase,
    required this.mediaRepository,
    required this.sendMediaMessageUseCase,
    required this.sendMessageWithAlertUseCase,
  }) : super(ChatInitial()) {
    on<LoadMessagesEvent>((event, emit) async {
      emit(ChatLoading());
      // Day 5 Milestone 6: chat open হওয়ার সাথে সাথে unreadCount রিসেট —
      // message stream শুরু হওয়ার আগে fire-and-forget (send/reset-এর মতোই
      // OfflineQueueManager idempotent write, তাই await করে stream block করার
      // দরকার নেই) — GroupChatBloc-এর LoadGroupMessagesEvent handler-এর সাথে
      // হুবহু সামঞ্জস্যপূর্ণ প্যাটার্ন।
      if (event.currentUserId != null) {
        // Stability fix: fire-and-forget কল এখন real Future রিটার্ন করে
        // (OfflineQueueManager fix) — non-network genuine এরর হলে এখন সেই
        // Future reject হয়; এই মার্কগুলো best-effort/self-correcting (ধারা ৪
        // handoff.md), তাই crash/unhandled-zone-spam এড়াতে .catchError দিয়ে
        // log করে রাখা হয়, silently drop করা হয় না।
        resetUnreadCountUseCase(
          chatId: event.chatId,
          uid: event.currentUserId!,
        ).catchError((Object e) {
          debugPrint('ChatBloc: resetUnreadCount failed — ${friendlyErrorMessage(e)}');
        });
      }
      // Day 6 Milestone 1: close()-এ cleanup typing ping পাঠাতে chatId/selfUid
      // মনে রাখা হয় (নিচে ধারা দেখুন)।
      _chatId = event.chatId;
      _selfUid = event.currentUserId;

      // Day 6 Milestone 1: typing স্ট্রিম আলাদাভাবে সাবস্ক্রাইব — নিজের uid
      // ফিল্টার করে বাদ দেওয়া হয় যাতে নিজে টাইপ করলে নিজের কাছেই "typing"
      // না দেখায়।
      // TYPING INDICATOR DISABLED (see chat_screen.dart for UI-side removal):
      // subscription intentionally not started — this removes the recurring
      // Firestore listener on the chat's typing-status field entirely.
      // StreamTypingStatusUseCase/SetTypingStatusUseCase and their Firestore
      // fields are left untouched (schema/repository unchanged), simply
      // unused, so this is reversible by uncommenting if ever needed again.
      // await _typingSubscription?.cancel();
      // _typingSubscription = streamTypingStatusUseCase(event.chatId).listen(
      //   (typingUserIds) {
      //     final filtered = event.currentUserId == null
      //         ? typingUserIds
      //         : typingUserIds.where((uid) => uid != event.currentUserId).toList();
      //     add(TypingUsersUpdatedEvent(filtered));
      //   },
      //   onError: (Object e) {
      //     debugPrint('ChatBloc: typing stream error — ${friendlyErrorMessage(e)}');
      //   },
      // );

      // Stability fix (Prevent infinite loading): প্রথম message snapshot
      // নির্দিষ্ট সময়ের (১৫s) মধ্যে না এলে retry-able ErrorState emit করা
      // হয় — স্ট্রিম নিজে চালু/listening-ই থাকে, তাই পরে ডেটা এলে normal
      // ChatLoadedState-এ স্বয়ংক্রিয়ভাবে সেরে যায় (নিচে onData-তে cancel)।
      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (!firstSnapshotReceived && !emit.isDone) {
          emit(ChatErrorState(message: 'লোড হতে সময় বেশি লাগছে। আবার চেষ্টা করুন।'));
        }
      });

      // রিয়েল-টাইম সাবস্ক্রিপশন সিঙ্ক এবং ব্রডকাস্ট
      await emit.forEach<List<MessageEntity>>(
        streamMessagesUseCase(event.chatId),
        onData: (messages) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          for (final message in messages) {
            _messagesCache[message.messageId] = message;
            // Day 6 Milestone 2 (Delivery Status): নিজের পাঠানো নয় এমন
            // 'sent' status-এর মেসেজ receive হওয়ার সাথে সাথে fire-and-forget
            // markMessageAsDeliveredUseCase কল — resetUnreadCountUseCase-এর
            // মতোই fire-and-forget প্যাটার্ন, message stream/UI block করে না।
            // currentUserId না দেওয়া থাকলে (nullable, ধারা ৫ M6) স্কিপ করা
            // হয় — কার delivery mark করতে হবে জানার উপায় নেই।
            if (event.currentUserId != null &&
                message.senderId != event.currentUserId &&
                message.status == 'sent') {
              markMessageAsDeliveredUseCase(
                chatId: event.chatId,
                messageId: message.messageId,
                uid: event.currentUserId!,
              ).catchError((Object e) {
                debugPrint('ChatBloc: markMessageAsDelivered failed — ${friendlyErrorMessage(e)}');
              });
            }
            // Day 6 Milestone 3 (Read Receipts): নিজের পাঠানো নয় এমন
            // মেসেজ chat screen খোলা অবস্থায় (এই stream সক্রিয় থাকা অবস্থায়)
            // receive হওয়া মানেই ইউজার সেটা দেখছে — fire-and-forget
            // markMessageAsReadUseCase কল, যা status='sent'/'delivered'
            // উভয় ক্ষেত্রেই 'read'-এ আপডেট করে (WhatsApp-এ chat খোলা মানেই
            // সব delivered মেসেজ read হয়ে যাওয়ার সাথে সামঞ্জস্যপূর্ণ)।
            // ইতিমধ্যে 'read' হলে পুনরায় কল করা হয় না (idempotent হলেও
            // অপ্রয়োজনীয় write এড়ানো)।
            if (event.currentUserId != null &&
                message.senderId != event.currentUserId &&
                message.status != 'read') {
              markMessageAsReadUseCase(
                chatId: event.chatId,
                messageId: message.messageId,
                uid: event.currentUserId!,
              ).catchError((Object e) {
                debugPrint('ChatBloc: markMessageAsRead failed — ${friendlyErrorMessage(e)}');
              });
            }
          }
          return ChatLoadedState(
            messages: _sortedMessages(),
            typingUserIds: _currentTypingUserIds,
            pendingUploads: _pendingUploads.values.toList(),
          );
        },
        onError: (error, stackTrace) {
          // TEMPORARY DEBUG (Bug 4 investigation — remove after root cause confirmed)
          print('DEBUG BUG4 STEP F: ChatBloc emit.forEach onError — this is the ONLY path that produces the visible permission-denied ChatErrorState');
          print('DEBUG BUG4 chatId=${event.chatId} t=${DateTime.now().toIso8601String()}');
          print('DEBUG BUG4 mapped message: ${friendlyErrorMessage(error)}');
          print('DEBUG BUG4 STACKTRACE: $stackTrace');
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          return ChatErrorState(message: friendlyErrorMessage(error));
        },
      );
      _loadTimeoutTimer?.cancel();
    });

    on<SendMessageEvent>((event, emit) async {
      try {
        // Stability fix (Add timeout + Prevent infinite loading): sendMessageUseCase
        // এখন OfflineQueueManager-এর real Future propagate করে (ধারা ওপরে) —
        // তাই এখানে .timeout() যোগ করলে স্থায়ী নেটওয়ার্ক-ডাউন অবস্থাতেও এই
        // await অনির্দিষ্টকাল block হবে না (UI-তে কোনো "sending…" state নেই
        // এই স্ক্রিনে, কিন্তু ChatErrorState দিয়ে এখন real ব্যর্থতা UI-তে
        // দেখানো যায়, যা আগে কখনো ঘটতই না — silent failure fix)।
        await sendMessageUseCase(
          chatId: event.chatId,
          senderId: event.senderId,
          text: event.text,
        ).timeout(_kActionTimeout);
        // Day 6 Milestone 1: "Typing stops immediately after sending a message"
        // — bloc-level এ guarantee করা হলো (UI timer cancel করুক বা না করুক)।
        // fire-and-forget, send-এর সাফল্যকে block করে না।
        // TYPING INDICATOR DISABLED: write removed (see LoadMessagesEvent
        // handler above and chat_screen.dart for the rest of the removal).
        // setTypingStatusUseCase(chatId: event.chatId, uid: event.senderId, isTyping: false).catchError((Object e) {
        //   debugPrint('ChatBloc: setTypingStatus failed — ${friendlyErrorMessage(e)}');
        // });
      } catch (e) {
        emit(ChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    // Friend Alert Sounds (Premium Social Feature) — mirrors SendMessageEvent's
    // handler exactly (same timeout/typing-stop/error-mapping pattern), just
    // calling SendMessageWithAlertUseCase instead of SendMessageUseCase.
    on<SendMessageWithAlertEvent>((event, emit) async {
      try {
        await sendMessageWithAlertUseCase(
          chatId: event.chatId,
          senderId: event.senderId,
          text: event.text,
          alert: event.alert,
        ).timeout(_kActionTimeout);
        // TYPING INDICATOR DISABLED: write removed.
        // setTypingStatusUseCase(chatId: event.chatId, uid: event.senderId, isTyping: false).catchError((Object e) {
        //   debugPrint('ChatBloc: setTypingStatus failed — ${friendlyErrorMessage(e)}');
        // });
      } catch (e) {
        emit(ChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    on<LoadOlderMessagesEvent>((event, emit) async {
      try {
        final olderMessages = await chatRepository
            .loadOlderMessages(
              chatId: event.chatId,
              beforeCreatedAt: event.beforeCreatedAt,
            )
            .timeout(_kActionTimeout);
        for (final message in olderMessages) {
          _messagesCache[message.messageId] = message;
        }
        emit(ChatLoadedState(
          messages: _sortedMessages(),
          typingUserIds: _currentTypingUserIds,
          pendingUploads: _pendingUploads.values.toList(),
        ));
      } catch (e) {
        emit(ChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    // Day 6 Milestone 1: UI (composer) keystroke-এ dispatch করবে — fire-and-forget
    // Firestore write, message stream/UI block করে না।
    // TYPING INDICATOR DISABLED: handlers left registered (event classes
    // still exist, see below) but bodies are no-ops — nothing dispatches
    // these events anymore (chat_screen.dart no longer sends them), and
    // even if something did, no Firestore write happens.
    on<TypingStartedEvent>((event, emit) {
      // setTypingStatusUseCase(chatId: event.chatId, uid: event.uid, isTyping: true).catchError((Object e) {
      //   debugPrint('ChatBloc: setTypingStatus(true) failed — ${friendlyErrorMessage(e)}');
      // });
    });
    on<TypingStoppedEvent>((event, emit) {
      // setTypingStatusUseCase(chatId: event.chatId, uid: event.uid, isTyping: false).catchError((Object e) {
      //   debugPrint('ChatBloc: setTypingStatus(false) failed — ${friendlyErrorMessage(e)}');
      // });
    });

    // Day 6 Milestone 1: typing স্ট্রিম snapshot এলে cached messages-এর সাথে
    // মার্জ করে নতুন ChatLoadedState emit করে — বর্তমান state ChatLoadedState
    // না হলে (এখনো loading/error) শুধু cache আপডেট করে, পরের messages emit-এই
    // reflect হবে।
    on<TypingUsersUpdatedEvent>((event, emit) {
      _currentTypingUserIds = event.typingUserIds;
      if (state is ChatLoadedState) {
        emit(_currentLoadedState());
      }
    });

    on<SendMediaMessageEvent>((event, emit) {
      final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
      _pendingUploads[localId] = PendingMediaUpload(
        localId: localId,
        type: event.type,
        file: event.file,
        fileName: event.fileName,
        fileSizeBytes: event.fileSizeBytes,
        mimeType: event.mimeType,
        durationMs: event.durationMs,
        caption: event.caption,
        waveform: event.waveform,
      );
      emit(_currentLoadedState());
      _startUpload(localId: localId, chatId: event.chatId, senderId: event.senderId);
    });

    on<RetryMediaUploadEvent>((event, emit) {
      final pending = _pendingUploads[event.localId];
      if (pending == null) return;
      _cancelledUploads.remove(event.localId);
      _pendingUploads[event.localId] = pending.copyWith(
        stage: MediaUploadStage.uploading,
        progress: 0,
        errorMessage: null,
      );
      emit(_currentLoadedState());
      _startUpload(localId: event.localId, chatId: _chatId ?? '', senderId: _selfUid ?? '');
    });

    on<CancelMediaUploadEvent>((event, emit) {
      _cancelledUploads.add(event.localId);
      _pendingUploads.remove(event.localId);
      emit(_currentLoadedState());
    });

    on<_MediaUploadProgressEvent>((event, emit) {
      final pending = _pendingUploads[event.localId];
      if (pending == null) return;
      _pendingUploads[event.localId] = pending.copyWith(progress: event.progress);
      emit(_currentLoadedState());
    });

    on<_MediaUploadedEvent>((event, emit) async {
      final pending = _pendingUploads[event.localId];
      if (pending == null) return;
      try {
        final messageId = sendMediaMessageUseCase.generateMessageId(event.chatId);
        await sendMediaMessageUseCase(
          chatId: event.chatId,
          messageId: messageId,
          senderId: event.senderId,
          type: pending.type,
          text: pending.caption,
          mediaUrl: event.secureUrl,
          fileName: pending.fileName,
          fileSizeBytes: pending.fileSizeBytes,
          mimeType: pending.mimeType,
          durationMs: pending.durationMs,
          waveform: pending.waveform,
        ).timeout(_kActionTimeout);
        // Bug 4 fix (sender local caching): the file we just uploaded is
        // already sitting locally — seed the voice cache with it under its
        // now-final URL so the sender's own bubble plays it from disk
        // immediately instead of re-downloading what it just sent.
        // Fire-and-forget: never blocks/fails the send itself.
        if (pending.type == MessageType.voice) {
          unawaited(VoiceLocalCacheService.instance.seedFromLocalFile(
            url: event.secureUrl,
            localFile: pending.file,
          ));
        }
        _pendingUploads.remove(event.localId);
        emit(_currentLoadedState());
      } catch (e) {
        _pendingUploads[event.localId] = pending.copyWith(
          stage: MediaUploadStage.failed,
          errorMessage: friendlyErrorMessage(e),
        );
        emit(_currentLoadedState());
      }
    });

    on<_MediaUploadFailedEvent>((event, emit) {
      final pending = _pendingUploads[event.localId];
      if (pending == null) return;
      _pendingUploads[event.localId] = pending.copyWith(
        stage: MediaUploadStage.failed,
        errorMessage: event.errorMessage,
      );
      emit(_currentLoadedState());
    });
  }

  List<String> _currentTypingUserIds = [];

  ChatLoadedState _currentLoadedState() {
    final current = state;
    return ChatLoadedState(
      messages: current is ChatLoadedState ? current.messages : _sortedMessages(),
      typingUserIds: _currentTypingUserIds,
      pendingUploads: _pendingUploads.values.toList(),
    );
  }

  String _folderFor(String type) {
    switch (type) {
      case MessageType.image:
        return CloudinaryConfig.chatImageFolder;
      case MessageType.video:
        return CloudinaryConfig.chatVideoFolder;
      case MessageType.voice:
        return CloudinaryConfig.chatVoiceFolder;
      default:
        return CloudinaryConfig.chatFileFolder;
    }
  }

  Future<MediaUploadResult> _uploadByType(
    String type,
    File file,
    String folder,
    UploadProgressCallback onProgress,
  ) {
    switch (type) {
      case MessageType.image:
        return mediaRepository.uploadImage(file: file, folder: folder, onProgress: onProgress);
      case MessageType.video:
        return mediaRepository.uploadVideo(file: file, folder: folder, onProgress: onProgress);
      case MessageType.voice:
        return mediaRepository.uploadVoice(file: file, folder: folder, onProgress: onProgress);
      default:
        return mediaRepository.uploadFile(file: file, folder: folder, onProgress: onProgress);
    }
  }

  void _startUpload({
    required String localId,
    required String chatId,
    required String senderId,
  }) {
    final pending = _pendingUploads[localId];
    if (pending == null) return;

    Future<void>(() async {
      try {
        final result = await _uploadByType(
          pending.type,
          pending.file,
          _folderFor(pending.type),
          (progress) {
            if (!isClosed) add(_MediaUploadProgressEvent(localId, progress));
          },
        ).timeout(_kActionTimeout);

        if (_cancelledUploads.contains(localId)) {
          _cancelledUploads.remove(localId);
          return;
        }
        if (!isClosed) add(_MediaUploadedEvent(localId, chatId, senderId, result.secureUrl));
      } catch (e) {
        if (_cancelledUploads.contains(localId)) {
          _cancelledUploads.remove(localId);
          return;
        }
        if (!isClosed) add(_MediaUploadFailedEvent(localId, friendlyErrorMessage(e)));
      }
    });
  }

  List<MessageEntity> _sortedMessages() {
    return _messagesCache.values.toList()
      ..sort((a, b) {
        final int cmp = a.createdAt.compareTo(b.createdAt);
        if (cmp != 0) return cmp;
        return a.messageId.compareTo(b.messageId);
      });
  }

  @override
  Future<void> close() async {
    // Day 6 Milestone 1: স্ক্রিন বন্ধ হওয়ার সময় mid-typing অবস্থায় থাকলে stuck
    // "typing..." indicator এড়াতে best-effort cleanup ping — chatId/selfUid
    // দুটোই জানা থাকলেই (LoadMessagesEvent-এ currentUserId দেওয়া হলে) পাঠানো হয়।
    // TYPING INDICATOR DISABLED: cleanup ping removed — nothing ever sets
    // typing=true anymore, so there is nothing to clean up on close().
    // if (_chatId != null && _selfUid != null) {
    //   // ignore: unawaited_futures
    //   setTypingStatusUseCase(chatId: _chatId!, uid: _selfUid!, isTyping: false).catchError((Object e) {
    //     debugPrint('ChatBloc: cleanup setTypingStatus failed — ${friendlyErrorMessage(e)}');
    //   });
    // }
    _loadTimeoutTimer?.cancel();
    await _typingSubscription?.cancel();
    // Stability fix (Shared repository lifecycle): আগে এখানে
    // `await chatRepository.close();` কল হতো — কিন্তু ChatRepository DI-তে
    // lazy singleton (`sl.registerLazySingleton<ChatRepository>()`), এবং
    // `streamMessages`/`streamTypingUserIds` প্রতিটি কল-এ instance-level
    // `_messagesSubscription`/`_typingSubscription` ফিল্ড সর্বশেষ subscription-এ
    // ওভাররাইট হয়। দুটো ChatScreen একই সাথে stack-এ (বা দ্রুত পরপর) খোলা
    // থাকলে একটি ChatBloc.close() অন্য ChatBloc-এর সক্রিয় স্ট্রিম বাতিল করে
    // দিতে পারত (cross-talk) — এটিই "Shared repository lifecycle" bug।
    // GroupInfoBloc-এর ইচ্ছাকৃত non-override প্যাটার্নের (handoff.md ধারা ৪:
    // "কেউ close() override করে shared resource বন্ধ করে না") সাথে সামঞ্জস্যপূর্ণ
    // করা হলো — প্রতিটি streamMessages/streamTypingUserIds কলের নিজস্ব
    // StreamController.onCancel ইতিমধ্যেই bloc বন্ধ হলে (emit.forEach/
    // _typingSubscription.cancel() উভয়ের মাধ্যমে) নিজের Firestore
    // সাবস্ক্রিপশন সঠিকভাবে cleanup করে — repository.close() রিডানড্যান্ট
    // ও বিপজ্জনক ছিল।
    return super.close();
  }
}
