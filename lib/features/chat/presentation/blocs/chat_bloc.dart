import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/config/cloudinary_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/services/voice_local_cache_service.dart';
import '../../../../core/services/local_unread_reset_bus.dart';
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
import '../../domain/usecases/get_cached_messages_usecase.dart';
import '../../domain/usecases/set_typing_status_usecase.dart';
import '../../domain/usecases/stream_typing_status_usecase.dart';
import '../../domain/usecases/mark_message_as_delivered_usecase.dart';
import '../../domain/usecases/mark_message_as_read_usecase.dart';

const _kLoadTimeout = Duration(seconds: 15);
const _kActionTimeout = Duration(seconds: 15);

abstract class ChatEvent {}
class LoadMessagesEvent extends ChatEvent {
  final String chatId;
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
  SendMessageEvent({
    required this.chatId,
    required this.senderId,
    required this.text,
  });
}
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
  final GetCachedMessagesUseCase getCachedMessagesUseCase;
  final ResetUnreadCountUseCase resetUnreadCountUseCase;
  final SetTypingStatusUseCase setTypingStatusUseCase;
  final StreamTypingStatusUseCase streamTypingStatusUseCase;
  final MarkMessageAsDeliveredUseCase markMessageAsDeliveredUseCase;
  final MarkMessageAsReadUseCase markMessageAsReadUseCase;
  final MediaRepository mediaRepository;
  final SendMediaMessageUseCase sendMediaMessageUseCase;
  final SendMessageWithAlertUseCase sendMessageWithAlertUseCase;
  final Map<String, MessageEntity> _messagesCache = {};
  final Map<String, PendingMediaUpload> _pendingUploads = {};
  final Set<String> _cancelledUploads = {};
  
  StreamSubscription<List<String>>? _typingSubscription;
  Timer? _loadTimeoutTimer;
  String? _chatId;
  String? _selfUid;
  bool _isLoadingOlder = false;
  DateTime? _loadingOlderBoundary;

  ChatBloc({
    required this.chatRepository,
    required this.sendMessageUseCase,
    required this.streamMessagesUseCase,
    required this.getCachedMessagesUseCase,
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
      final cachedMessages = await getCachedMessagesUseCase(event.chatId);
      if (cachedMessages.isNotEmpty) {
        for (final message in cachedMessages) {
          _messagesCache[message.messageId] = message;
        }
        emit(ChatLoadedState(
          messages: _sortedMessages(),
          typingUserIds: _currentTypingUserIds,
          pendingUploads: _pendingUploads.values.toList(),
        ));
      } else {
        emit(ChatLoading());
      }

      if (event.currentUserId != null) {
        LocalUnreadResetBus.instance.emit(uid: event.currentUserId!, chatId: event.chatId);
        resetUnreadCountUseCase(
          chatId: event.chatId,
          uid: event.currentUserId!,
        ).catchError((Object e) {
          debugPrint('ChatBloc: resetUnreadCount failed — ${friendlyErrorMessage(e)}');
        });
      }

      _chatId = event.chatId;
      _selfUid = event.currentUserId;

      await _typingSubscription?.cancel();
      _typingSubscription = streamTypingStatusUseCase(event.chatId).listen(
        (typingUserIds) {
          final filtered = event.currentUserId == null
              ? typingUserIds
              : typingUserIds.where((uid) => uid != event.currentUserId).toList();
          add(TypingUsersUpdatedEvent(filtered));
        },
        onError: (Object e) {
          debugPrint('ChatBloc: typing stream error — ${friendlyErrorMessage(e)}');
        },
      );

      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (firstSnapshotReceived || emit.isDone) return;
        if (state is ChatLoadedState) return;
        emit(ChatErrorState(
          message: 'লোড হতে সময় বেশি লাগছে। আবার চেষ্টা করুন।',
        ));
      });

      await emit.forEach<List<MessageEntity>>(
        streamMessagesUseCase(event.chatId),
        onData: (messages) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          final deliveredIds = <String>[];
          final readIds = <String>[];
          for (final message in messages) {
            _messagesCache[message.messageId] = message;
            if (event.currentUserId != null &&
                message.senderId != event.currentUserId &&
                message.status == 'sent') {
              deliveredIds.add(message.messageId);
            }
            if (event.currentUserId != null &&
                message.senderId != event.currentUserId &&
                message.status != 'read') {
              readIds.add(message.messageId);
            }
          }

          if (deliveredIds.isNotEmpty) {
            markMessageAsDeliveredUseCase(
              chatId: event.chatId,
              messageIds: deliveredIds,
              uid: event.currentUserId!,
            ).catchError((Object e) {
              debugPrint('ChatBloc: markMessageAsDelivered (batch) failed — ${friendlyErrorMessage(e)}');
            });
          }
          if (readIds.isNotEmpty) {
            markMessageAsReadUseCase(
              chatId: event.chatId,
              messageIds: readIds,
              uid: event.currentUserId!,
            ).catchError((Object e) {
              debugPrint('ChatBloc: markMessageAsRead (batch) failed — ${friendlyErrorMessage(e)}');
            });
          }
          return ChatLoadedState(
            messages: _sortedMessages(),
            typingUserIds: _currentTypingUserIds,
            pendingUploads: _pendingUploads.values.toList(),
          );
        },
        onError: (error, stackTrace) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          if (state is ChatLoadedState) return state;
          return ChatErrorState(message: friendlyErrorMessage(error));
        },
      );
      _loadTimeoutTimer?.cancel();
    });

    on<SendMessageEvent>((event, emit) async {
      try {
        await sendMessageUseCase(
          chatId: event.chatId,
          senderId: event.senderId,
          text: event.text,
        ).timeout(_kActionTimeout);
        setTypingStatusUseCase(chatId: event.chatId, uid: event.senderId, isTyping: false).catchError((Object e) {
          debugPrint('ChatBloc: setTypingStatus failed — ${friendlyErrorMessage(e)}');
        });
      } catch (e) {
        emit(ChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    on<SendMessageWithAlertEvent>((event, emit) async {
      try {
        await sendMessageWithAlertUseCase(
          chatId: event.chatId,
          senderId: event.senderId,
          text: event.text,
          alert: event.alert,
        ).timeout(_kActionTimeout);
        setTypingStatusUseCase(chatId: event.chatId, uid: event.senderId, isTyping: false).catchError((Object e) {
          debugPrint('ChatBloc: setTypingStatus failed — ${friendlyErrorMessage(e)}');
        });
      } catch (e) {
        emit(ChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    on<LoadOlderMessagesEvent>((event, emit) async {
      if (_isLoadingOlder && _loadingOlderBoundary == event.beforeCreatedAt) {
        return;
      }
      _isLoadingOlder = true;
      _loadingOlderBoundary = event.beforeCreatedAt;
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
      } finally {
        _isLoadingOlder = false;
      }
    });

    on<TypingStartedEvent>((event, emit) {
      setTypingStatusUseCase(chatId: event.chatId, uid: event.uid, isTyping: true).catchError((Object e) {
        debugPrint('ChatBloc: setTypingStatus(true) failed — ${friendlyErrorMessage(e)}');
      });
    });
    on<TypingStoppedEvent>((event, emit) {
      setTypingStatusUseCase(chatId: event.chatId, uid: event.uid, isTyping: false).catchError((Object e) {
        debugPrint('ChatBloc: setTypingStatus(false) failed — ${friendlyErrorMessage(e)}');
      });
    });

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
    if (_chatId != null && _selfUid != null) {
      setTypingStatusUseCase(chatId: _chatId!, uid: _selfUid!, isTyping: false).catchError((Object e) {
        debugPrint('ChatBloc: cleanup setTypingStatus failed — ${friendlyErrorMessage(e)}');
      });
    }
    _loadTimeoutTimer?.cancel();
    await _typingSubscription?.cancel();
    return super.close();
  }
}