import 'dart:io';
import '../../domain/entities/voice_draft_entity.dart';
import '../../domain/services/voice_recording_service.dart';
import 'voice_draft_store.dart';

class VoiceRecordingCoordinator {
  VoiceRecordingCoordinator(this._recordingService, this._draftStore);

  final VoiceRecordingService _recordingService;
  final VoiceDraftStore _draftStore;

  bool _ownsCurrentSession = false;

  VoiceRecordingService get recordingService => _recordingService;
  VoiceDraftStore get draftStore => _draftStore;

  Future<void> restoreFromDisk(String? currentUserId) => _draftStore.restoreFromDisk(currentUserId);

  Future<void> discardIfUserMismatch(String? currentUserId) async {
    final draft = _draftStore.current;
    if (draft == null || draft.userId == currentUserId) return;
    if (!draft.recoveredAfterRestart && _ownsCurrentSession && _recordingService.isRecording) {
      try {
        await _recordingService.cancelRecording();
      } catch (_) {
      }
    }
    _ownsCurrentSession = false;
    await _draftStore.discardIfUserMismatch(currentUserId);
  }

  Future<void> startRecording(String chatId, String userId) async {
    await _recordingService.startRecording();
    _ownsCurrentSession = true;
    _draftStore.setDraft(VoiceDraftEntity(
      chatId: chatId,
      userId: userId,
      filePath: _recordingService.currentFilePath ?? '',
      elapsedMs: 0,
      isPaused: false,
    ));
  }

  Future<void> pauseRecording() async {
    if (!_ownsCurrentSession || !_recordingService.isRecording) return;
    await _recordingService.pauseRecording();
    _publishPausedDraft();
  }

  Future<void> autoPauseIfInterrupted() async {
    if (!_recordingService.isRecording || _recordingService.isPaused) return;
    await _recordingService.pauseRecording();
    if (_ownsCurrentSession) _publishPausedDraft();
  }

  void _publishPausedDraft() {
    final current = _draftStore.current;
    if (current == null) return;
    final path = _recordingService.currentFilePath ?? current.filePath;
    final elapsedMs = _recordingService.elapsedMs;
    _draftStore.setDraft(current.copyWith(filePath: path, elapsedMs: elapsedMs, isPaused: true));
    _draftStore.persistSidecar(chatId: current.chatId, userId: current.userId, filePath: path, elapsedMs: elapsedMs);
  }

  Future<void> resumeRecording() async {
    final draft = _draftStore.current;
    if (draft == null || draft.recoveredAfterRestart) return;
    _ownsCurrentSession = true;
    await _recordingService.resumeRecording();
    _draftStore.setDraft(draft.copyWith(isPaused: false, elapsedMs: _recordingService.elapsedMs));
  }

  Future<void> deleteDraft() async {
    final draft = _draftStore.current;
    if (draft == null) return;
    if (!draft.recoveredAfterRestart && _ownsCurrentSession) {
      await _recordingService.cancelRecording();
    } else {
      try {
        final file = File(draft.filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {
      }
    }
    _ownsCurrentSession = false;
    _draftStore.setDraft(null);
    await _draftStore.clearSidecar();
  }

  Future<({File file, Duration duration, List<double> waveform})?> finalizeForSend() async {
    final draft = _draftStore.current;
    if (draft == null) return null;

    File? file;
    Duration duration;
    List<double> waveform;

    if (!draft.recoveredAfterRestart && _ownsCurrentSession) {
      final entity = await _recordingService.stopRecording();
      final path = entity.localPath ?? draft.filePath;
      file = path.isEmpty ? null : File(path);
      duration = Duration(milliseconds: entity.durationMs);
      waveform = entity.waveform;
    } else {
      file = File(draft.filePath);
      duration = draft.elapsedDuration;
      waveform = const [];
    }

    _ownsCurrentSession = false;
    _draftStore.setDraft(null);
    await _draftStore.clearSidecar();

    if (file == null || !await file.exists() || duration <= Duration.zero) return null;
    return (file: file, duration: duration, waveform: waveform);
  }
}
