import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/services/voice_player_service.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../../chat/data/datasources/chat_local_data_source.dart';
import '../../../chat/domain/entities/voice_message_entity.dart';
import '../../../chat/domain/services/voice_recording_service.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../../domain/usecases/create_friend_alert_sound_usecase.dart';
import '../../domain/usecases/delete_friend_alert_sound_usecase.dart';
import '../../domain/usecases/get_friend_alert_sounds_usecase.dart';
import '../../domain/usecases/rename_friend_alert_sound_usecase.dart';
import '../../domain/usecases/replace_friend_alert_sound_usecase.dart';

const int kMaxAlertSoundDurationMs = 20000;
const int kMinAlertSoundDurationMs = 1000;

enum FriendAlertRecordingPhase { idle, recording, paused, recorded }

class FriendAlertState {
  final bool isLoading;
  final List<FriendAlertSoundEntity> sounds;
  final String? errorMessage;
  final bool isBusy;
  final FriendAlertRecordingPhase recordingPhase;
  final File? recordedFile;
  final int recordedDurationMs;
  final bool isPreviewPlaying;
  final String notificationText;

  const FriendAlertState({
    this.isLoading = false,
    this.sounds = const [],
    this.errorMessage,
    this.isBusy = false,
    this.recordingPhase = FriendAlertRecordingPhase.idle,
    this.recordedFile,
    this.recordedDurationMs = 0,
    this.isPreviewPlaying = false,
    this.notificationText = '',
  });

  String get autoTitle {
    final trimmed = notificationText.trim();
    if (trimmed.isEmpty) return 'Alert';
    final words = trimmed.split(RegExp(r'\s+'));
    return words.length == 1 ? words.first : words.take(2).join(' ');
  }

  FriendAlertState copyWith({
    bool? isLoading,
    List<FriendAlertSoundEntity>? sounds,
    String? errorMessage,
    bool clearError = false,
    bool? isBusy,
    FriendAlertRecordingPhase? recordingPhase,
    File? recordedFile,
    bool clearRecordedFile = false,
    int? recordedDurationMs,
    bool? isPreviewPlaying,
    String? notificationText,
  }) {
    return FriendAlertState(
      isLoading: isLoading ?? this.isLoading,
      sounds: sounds ?? this.sounds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isBusy: isBusy ?? this.isBusy,
      recordingPhase: recordingPhase ?? this.recordingPhase,
      recordedFile: clearRecordedFile ? null : (recordedFile ?? this.recordedFile),
      recordedDurationMs: recordedDurationMs ?? this.recordedDurationMs,
      isPreviewPlaying: isPreviewPlaying ?? this.isPreviewPlaying,
      notificationText: notificationText ?? this.notificationText,
    );
  }
}

class FriendAlertCubit extends Cubit<FriendAlertState> {
  final WatchFriendAlertSoundsUseCase watchFriendAlertSoundsUseCase;
  final CreateFriendAlertSoundUseCase createFriendAlertSoundUseCase;
  final RenameFriendAlertSoundUseCase renameFriendAlertSoundUseCase;
  final ReplaceFriendAlertSoundUseCase replaceFriendAlertSoundUseCase;
  final DeleteFriendAlertSoundUseCase deleteFriendAlertSoundUseCase;
  final VoiceRecordingService recordingService;
  final VoicePlayerService previewPlayer;
  final SupabaseClient supabase;
  final ChatLocalDataSource chatLocalDataSource;

  final String ownerUid;
  final String chatId;
  String? _resolvedFriendUid;
  Timer? _maxDurationTimer;
  StreamSubscription<List<FriendAlertSoundEntity>>? _soundsSubscription;

  FriendAlertCubit({
    required this.watchFriendAlertSoundsUseCase,
    required this.createFriendAlertSoundUseCase,
    required this.renameFriendAlertSoundUseCase,
    required this.replaceFriendAlertSoundUseCase,
    required this.deleteFriendAlertSoundUseCase,
    required this.recordingService,
    required this.previewPlayer,
    required this.supabase,
    required this.chatLocalDataSource,
    required this.ownerUid,
    required this.chatId,
  }) : super(const FriendAlertState());

  String? get resolvedFriendUid => _resolvedFriendUid;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      if (_resolvedFriendUid == null) {
        final remoteChatId = await chatLocalDataSource.getRemoteChatId(chatId) ?? chatId;
        final ownerSupabaseUid = await UserIdBridge.resolve(
          ownerUid,
          currentSupabaseUserId: supabase.auth.currentUser?.id,
        );
        final memberRows = await supabase.from('chat_members').select('user_id').eq('chat_id', remoteChatId);
        final otherSupabaseUid = memberRows
            .map((row) => row['user_id'] as String)
            .firstWhere((uid) => uid != ownerSupabaseUid, orElse: () => '');
        _resolvedFriendUid = otherSupabaseUid.isEmpty
            ? null
            : (await UserIdBridge.reverseResolve(otherSupabaseUid) ?? otherSupabaseUid);
      }

      _soundsSubscription?.cancel();
      _soundsSubscription = watchFriendAlertSoundsUseCase(
        ownerUid: ownerUid,
        friendUid: _resolvedFriendUid ?? '',
      ).listen(
        (sounds) {
          if (!isClosed) emit(state.copyWith(isLoading: false, sounds: sounds));
        },
        onError: (e) {
          if (!isClosed) emit(state.copyWith(isLoading: false, errorMessage: friendlyErrorMessage(e)));
        },
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: friendlyErrorMessage(e)));
    }
  }


  Future<void> startRecording() async {
    if (recordingService.isRecording) {
      emit(state.copyWith(
        errorMessage: 'Finish or discard your voice message recording first, then try the alert sound again.',
      ));
      return;
    }
    try {
      await recordingService.startRecording();
      emit(state.copyWith(recordingPhase: FriendAlertRecordingPhase.recording, clearRecordedFile: true));
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(const Duration(milliseconds: kMaxAlertSoundDurationMs), stopRecording);
    } catch (e) {
      emit(state.copyWith(errorMessage: friendlyErrorMessage(e)));
    }
  }

  Future<void> pauseRecording() async {
    if (state.recordingPhase != FriendAlertRecordingPhase.recording) return;
    _maxDurationTimer?.cancel();
    try {
      await recordingService.pauseRecording();
      emit(state.copyWith(recordingPhase: FriendAlertRecordingPhase.paused));
    } catch (e) {
      emit(state.copyWith(errorMessage: friendlyErrorMessage(e)));
    }
  }

  Future<void> resumeRecording() async {
    if (state.recordingPhase != FriendAlertRecordingPhase.paused) return;
    try {
      await recordingService.resumeRecording();
      emit(state.copyWith(recordingPhase: FriendAlertRecordingPhase.recording));
      final remainingMs = kMaxAlertSoundDurationMs - recordingService.elapsedMs;
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(
        Duration(milliseconds: remainingMs > 0 ? remainingMs : 0),
        stopRecording,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: friendlyErrorMessage(e)));
    }
  }

  void setNotificationText(String text) {
    emit(state.copyWith(notificationText: text));
  }

  Future<void> stopRecording() async {
    _maxDurationTimer?.cancel();
    try {
      final VoiceMessageEntity result = await recordingService.stopRecording();
      final localPath = result.localPath;
      if (localPath == null) {
        emit(state.copyWith(
          recordingPhase: FriendAlertRecordingPhase.idle,
          errorMessage: 'Recording failed. Please try again.',
        ));
        return;
      }
      final clampedDuration = result.durationMs.clamp(0, kMaxAlertSoundDurationMs);
      emit(state.copyWith(
        recordingPhase: FriendAlertRecordingPhase.recorded,
        recordedFile: File(localPath),
        recordedDurationMs: clampedDuration,
      ));
    } catch (e) {
      emit(state.copyWith(
        recordingPhase: FriendAlertRecordingPhase.idle,
        errorMessage: friendlyErrorMessage(e),
      ));
    }
  }

  Future<void> discardRecording() async {
    await cancelRecordingIfAny();
  }

  Future<void> cancelRecordingIfAny() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    if (state.recordingPhase == FriendAlertRecordingPhase.recording ||
        state.recordingPhase == FriendAlertRecordingPhase.paused) {
      try {
        await recordingService.cancelRecording();
      } catch (_) {}
    }
    final file = state.recordedFile;
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (!isClosed) {
      emit(state.copyWith(
        recordingPhase: FriendAlertRecordingPhase.idle,
        clearRecordedFile: true,
        notificationText: '',
      ));
    }
  }

  Future<FriendAlertSoundEntity?> send() async {
    final file = state.recordedFile;
    if (file == null) return null;
    if (_resolvedFriendUid == null) {
      emit(state.copyWith(errorMessage: 'Could not identify this chat\'s friend. Please reopen the chat and try again.'));
      return null;
    }

    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      final sound = await createFriendAlertSoundUseCase(
        ownerUid: ownerUid,
        audioFile: file,
        displayName: state.autoTitle,
        durationMs: state.recordedDurationMs,
        friendUid: _resolvedFriendUid,
      );
      emit(state.copyWith(
        isBusy: false,
        sounds: [...state.sounds, sound],
        recordingPhase: FriendAlertRecordingPhase.idle,
        clearRecordedFile: true,
        notificationText: '',
      ));
      return sound;
    } catch (e) {
      emit(state.copyWith(isBusy: false, errorMessage: friendlyErrorMessage(e)));
      return null;
    }
  }

  Future<void> previewRecordedFile() async {
    final file = state.recordedFile;
    if (file == null) return;
    try {
      await previewPlayer.setFilePath(file.path);
      await previewPlayer.play();
      emit(state.copyWith(isPreviewPlaying: true));
    } catch (e) {
      emit(state.copyWith(errorMessage: friendlyErrorMessage(e)));
    }
  }

  Future<void> previewExistingSound(FriendAlertSoundEntity sound) async {
    try {
      await previewPlayer.setUrl(sound.metadata.audioUrl);
      await previewPlayer.play();
      emit(state.copyWith(isPreviewPlaying: true));
    } catch (e) {
      emit(state.copyWith(errorMessage: friendlyErrorMessage(e)));
    }
  }

  Future<void> stopPreview() async {
    try {
      await previewPlayer.stop();
    } catch (_) {}
    emit(state.copyWith(isPreviewPlaying: false));
  }


  Future<FriendAlertSoundEntity?> saveRecordedAs({
    required String displayName,
    required bool asGlobal,
  }) async {
    final file = state.recordedFile;
    if (file == null) return null;

    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      final sound = await createFriendAlertSoundUseCase(
        ownerUid: ownerUid,
        audioFile: file,
        displayName: displayName,
        durationMs: state.recordedDurationMs,
        friendUid: asGlobal ? null : _resolvedFriendUid,
      );
      emit(state.copyWith(
        isBusy: false,
        sounds: [...state.sounds, sound],
        recordingPhase: FriendAlertRecordingPhase.idle,
        clearRecordedFile: true,
      ));
      return sound;
    } catch (e) {
      emit(state.copyWith(isBusy: false, errorMessage: friendlyErrorMessage(e)));
      return null;
    }
  }

  Future<void> rename(FriendAlertSoundEntity sound, String newName) async {
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      final updated = await renameFriendAlertSoundUseCase(sound: sound, newDisplayName: newName);
      emit(state.copyWith(isBusy: false, sounds: _replace(sound, updated)));
    } catch (e) {
      emit(state.copyWith(isBusy: false, errorMessage: friendlyErrorMessage(e)));
    }
  }

  Future<void> replaceAudio(FriendAlertSoundEntity sound) async {
    final file = state.recordedFile;
    if (file == null) return;
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      final updated = await replaceFriendAlertSoundUseCase(
        sound: sound,
        audioFile: file,
        durationMs: state.recordedDurationMs,
      );
      emit(state.copyWith(
        isBusy: false,
        sounds: _replace(sound, updated),
        recordingPhase: FriendAlertRecordingPhase.idle,
        clearRecordedFile: true,
      ));
    } catch (e) {
      emit(state.copyWith(isBusy: false, errorMessage: friendlyErrorMessage(e)));
    }
  }

  Future<void> delete(FriendAlertSoundEntity sound) async {
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      await deleteFriendAlertSoundUseCase(sound);
      emit(state.copyWith(
        isBusy: false,
        sounds: state.sounds.where((s) => s.alertId != sound.alertId).toList(),
      ));
    } catch (e) {
      emit(state.copyWith(isBusy: false, errorMessage: friendlyErrorMessage(e)));
    }
  }

  List<FriendAlertSoundEntity> _replace(FriendAlertSoundEntity oldSound, FriendAlertSoundEntity newSound) {
    return state.sounds.map((s) => s.alertId == oldSound.alertId ? newSound : s).toList();
  }

  AlertAudioMetadata metadataOf(FriendAlertSoundEntity sound) => sound.metadata;

  @override
  Future<void> close() async {
    _soundsSubscription?.cancel();
    _maxDurationTimer?.cancel();
    if (state.recordingPhase == FriendAlertRecordingPhase.recording ||
        state.recordingPhase == FriendAlertRecordingPhase.paused) {
      try {
        await recordingService.cancelRecording();
      } catch (_) {}
    }
    final leftoverFile = state.recordedFile;
    if (leftoverFile != null) {
      try {
        if (await leftoverFile.exists()) await leftoverFile.delete();
      } catch (_) {}
    }
    try {
      await previewPlayer.stop();
      await previewPlayer.dispose();
    } catch (_) {}
    return super.close();
  }
}
