import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/services/voice_player_service.dart';
import '../../../chat/domain/entities/voice_message_entity.dart';
import '../../../chat/domain/services/voice_recording_service.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../../domain/usecases/create_friend_alert_sound_usecase.dart';
import '../../domain/usecases/delete_friend_alert_sound_usecase.dart';
import '../../domain/usecases/get_friend_alert_sounds_usecase.dart';
import '../../domain/usecases/rename_friend_alert_sound_usecase.dart';
import '../../domain/usecases/replace_friend_alert_sound_usecase.dart';

/// Friend Alert Sounds (Premium Social Feature).
///
/// Deliberately reuses, rather than reimplements:
///  - [VoiceRecordingService] (chat feature, existing) for record/stop —
///    same interface MicRecordButton already uses for voice messages. The
///    Voice Message system itself is completely untouched; this is a second,
///    independent caller of the same recording abstraction.
///  - [VoicePlayerService] (core, existing) for local-file + remote-url
///    preview playback — same player class VoicePlaybackControllerImpl uses.
///  - The 5 usecases from custom_alert/domain/usecases for all persistence.
const int kMaxAlertSoundDurationMs = 5000;
const int kMinAlertSoundDurationMs = 1000;

enum FriendAlertRecordingPhase { idle, recording, recorded }

class FriendAlertState {
  final bool isLoading;
  final List<FriendAlertSoundEntity> sounds;
  final String? errorMessage;
  final bool isBusy; // create/rename/replace/delete in flight
  final FriendAlertRecordingPhase recordingPhase;
  final File? recordedFile;
  final int recordedDurationMs;
  final bool isPreviewPlaying;

  const FriendAlertState({
    this.isLoading = false,
    this.sounds = const [],
    this.errorMessage,
    this.isBusy = false,
    this.recordingPhase = FriendAlertRecordingPhase.idle,
    this.recordedFile,
    this.recordedDurationMs = 0,
    this.isPreviewPlaying = false,
  });

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
    );
  }
}

class FriendAlertCubit extends Cubit<FriendAlertState> {
  final GetFriendAlertSoundsUseCase getFriendAlertSoundsUseCase;
  final CreateFriendAlertSoundUseCase createFriendAlertSoundUseCase;
  final RenameFriendAlertSoundUseCase renameFriendAlertSoundUseCase;
  final ReplaceFriendAlertSoundUseCase replaceFriendAlertSoundUseCase;
  final DeleteFriendAlertSoundUseCase deleteFriendAlertSoundUseCase;
  final VoiceRecordingService recordingService;
  final VoicePlayerService previewPlayer;
  final FirebaseFirestore firestore;

  final String ownerUid;
  final String chatId;
  String? _resolvedFriendUid;
  Timer? _maxDurationTimer;

  FriendAlertCubit({
    required this.getFriendAlertSoundsUseCase,
    required this.createFriendAlertSoundUseCase,
    required this.renameFriendAlertSoundUseCase,
    required this.replaceFriendAlertSoundUseCase,
    required this.deleteFriendAlertSoundUseCase,
    required this.recordingService,
    required this.previewPlayer,
    required this.firestore,
    required this.ownerUid,
    required this.chatId,
  }) : super(const FriendAlertState());

  String? get resolvedFriendUid => _resolvedFriendUid;

  /// Resolves the other participant's uid from the existing `chats/{chatId}`
  /// doc (`participantIds`, same field ChatRepositoryImpl already reads/
  /// writes) — no new Firestore field, no new collection for this lookup.
  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      if (_resolvedFriendUid == null) {
        final chatDoc = await firestore.collection('chats').doc(chatId).get();
        final participantIds = List<String>.from(chatDoc.data()?['participantIds'] as List? ?? const []);
        _resolvedFriendUid = participantIds.firstWhere(
          (uid) => uid != ownerUid,
          orElse: () => '',
        );
        if (_resolvedFriendUid!.isEmpty) _resolvedFriendUid = null;
      }

      final sounds = await getFriendAlertSoundsUseCase(
        ownerUid: ownerUid,
        friendUid: _resolvedFriendUid ?? '',
      );
      emit(state.copyWith(isLoading: false, sounds: sounds));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: friendlyErrorMessage(e)));
    }
  }

  // ---- Record → Preview flow -------------------------------------------

  Future<void> startRecording() async {
    try {
      await recordingService.startRecording();
      emit(state.copyWith(recordingPhase: FriendAlertRecordingPhase.recording, clearRecordedFile: true));
      // Spec: "Record 1-5 seconds" — hard-stop at the 5s ceiling so the
      // user never has to manually enforce it.
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(const Duration(milliseconds: kMaxAlertSoundDurationMs), stopRecording);
    } catch (e) {
      emit(state.copyWith(errorMessage: friendlyErrorMessage(e)));
    }
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
      // Enforce the 1–5 second rule at the UI boundary (repository also
      // validates on createSound/replaceSoundAudio — belt and suspenders).
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
    _maxDurationTimer?.cancel();
    try {
      await recordingService.cancelRecording();
    } catch (_) {}
    emit(state.copyWith(recordingPhase: FriendAlertRecordingPhase.idle, clearRecordedFile: true));
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

  // ---- Create / manage ---------------------------------------------------

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
    _maxDurationTimer?.cancel();
    try {
      await previewPlayer.stop();
      await previewPlayer.dispose();
    } catch (_) {}
    return super.close();
  }
}
