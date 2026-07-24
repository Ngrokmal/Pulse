import 'dart:io';
import '../../domain/entities/voice_draft_entity.dart';
import '../../domain/services/voice_recording_service.dart';
import 'voice_draft_store.dart';

/// Thin orchestration layer sitting on top of the existing
/// [VoiceRecordingService] singleton (unchanged pipeline, reused as-is) and
/// [VoiceDraftStore]. This is what the chat UI talks to for the WhatsApp-style
/// record → pause/resume → delete/send flow (Bugs 1-4 of the Voice Message
/// audit). It intentionally does not touch Firestore, the repository, or the
/// bloc — sending still goes through the existing `SendMediaMessageEvent`
/// pipeline, dispatched by the caller (ChatScreen) exactly as before.
///
/// [VoiceRecordingService] is a shared singleton also used by
/// FriendAlertCubit (custom_alert feature) for alert-sound recording — see
/// that cubit's doc comment. To avoid that unrelated feature's recordings
/// ever surfacing as a "Voice Draft" bar in a chat screen, this coordinator
/// only publishes a draft to [VoiceDraftStore] for sessions *it* started
/// (tracked via [_ownsCurrentSession]). [autoPauseIfInterrupted] still pauses
/// the underlying recorder unconditionally when the app is backgrounded,
/// since silently continuing to record in the background is undesirable
/// for either feature — it just only turns that into a visible chat draft
/// when the session belongs to a voice message.
///
/// Drafts are scoped per [chatId] (see [VoiceDraftEntity.chatId]) so a
/// recording paused in one chat never leaks into a different chat's
/// composer if the user navigates between chats while it's paused.
class VoiceRecordingCoordinator {
  VoiceRecordingCoordinator(this._recordingService, this._draftStore);

  final VoiceRecordingService _recordingService;
  final VoiceDraftStore _draftStore;

  bool _ownsCurrentSession = false;

  VoiceRecordingService get recordingService => _recordingService;
  VoiceDraftStore get draftStore => _draftStore;

  /// Called once at app startup (see main.dart) to recover a draft left
  /// behind by a killed process, if any — scoped to whoever is signed in
  /// right now.
  Future<void> restoreFromDisk(String? currentUserId) => _draftStore.restoreFromDisk(currentUserId);

  /// Call whenever the signed-in user changes (login/logout). Discards any
  /// draft that doesn't belong to [currentUserId] — including cancelling a
  /// still-live recording session, so a stale session never blocks the
  /// next account from starting a fresh recording.
  Future<void> discardIfUserMismatch(String? currentUserId) async {
    final draft = _draftStore.current;
    if (draft == null || draft.userId == currentUserId) return;
    if (!draft.recoveredAfterRestart && _ownsCurrentSession && _recordingService.isRecording) {
      try {
        await _recordingService.cancelRecording();
      } catch (_) {
        // best-effort — draft is discarded below regardless
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

  /// User explicitly tapped Pause.
  Future<void> pauseRecording() async {
    if (!_ownsCurrentSession || !_recordingService.isRecording) return;
    await _recordingService.pauseRecording();
    _publishPausedDraft();
  }

  /// Called from app-lifecycle/navigation hooks (Bug 3: backgrounding,
  /// screen lock, incoming call, notification, navigating to another
  /// in-app page). Safe to call unconditionally — a no-op unless a
  /// recording is actively in progress.
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

  /// Resumes the SAME recording — never starts a second one. Only possible
  /// for a draft whose native recorder session is still alive (i.e. not
  /// [VoiceDraftEntity.recoveredAfterRestart]).
  Future<void> resumeRecording() async {
    final draft = _draftStore.current;
    if (draft == null || draft.recoveredAfterRestart) return;
    _ownsCurrentSession = true;
    await _recordingService.resumeRecording();
    _draftStore.setDraft(draft.copyWith(isPaused: false, elapsedMs: _recordingService.elapsedMs));
  }

  /// Deletes the draft entirely — cancels the live session if there is one,
  /// otherwise just removes the recovered file from disk.
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
        // best-effort cleanup only
      }
    }
    _ownsCurrentSession = false;
    _draftStore.setDraft(null);
    await _draftStore.clearSidecar();
  }

  /// Finalizes the draft for sending. Returns the file/duration/waveform to
  /// hand off to the existing `SendMediaMessageEvent` pipeline — this
  /// coordinator never uploads anything itself.
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
      // Recovered-after-restart draft: no live session to stop, send the
      // partial audio exactly as it was left on disk.
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
