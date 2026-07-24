/// Local-only representation of an in-progress or paused voice recording
/// that has not been sent yet (Bug 3 / Bug 4 of the Voice Message audit).
///
/// This is NEVER persisted to Firestore — it only ever lives in memory
/// (via [VoiceDraftStore]) and, for crash/kill recovery, as a small JSON
/// sidecar file next to the recording itself on local disk.
class VoiceDraftEntity {
  /// The chat this draft belongs to — so a draft paused in one chat never
  /// surfaces (or can be accidentally sent into) a different chat's
  /// composer if the user navigates between chats while it's paused.
  final String chatId;

  /// The account that recorded this draft — so it never surfaces after a
  /// different user logs in on the same device (logout/login mid-session,
  /// or a crash-recovered draft from a previous session's user).
  final String userId;

  /// Local path of the (still-growing or finished-but-unsent) .m4a file.
  final String filePath;

  /// How much of the recording is actually audio so far. While a live
  /// native recording session is attached this is a snapshot; once
  /// [isPaused] is true it is the authoritative elapsed time.
  final int elapsedMs;

  /// True whenever the draft is not actively being captured right now
  /// (user tapped pause, the app was backgrounded/interrupted, or the
  /// screen was navigated away from).
  final bool isPaused;

  /// True only when this draft was reconstructed from disk after the
  /// Android process was killed outright — in that case the native
  /// recorder session no longer exists, so "Resume" is not possible;
  /// only "Delete" and "Send" (send-as-is) remain available.
  final bool recoveredAfterRestart;

  const VoiceDraftEntity({
    required this.chatId,
    required this.userId,
    required this.filePath,
    required this.elapsedMs,
    required this.isPaused,
    this.recoveredAfterRestart = false,
  });

  Duration get elapsedDuration => Duration(milliseconds: elapsedMs);

  VoiceDraftEntity copyWith({
    String? chatId,
    String? userId,
    String? filePath,
    int? elapsedMs,
    bool? isPaused,
    bool? recoveredAfterRestart,
  }) {
    return VoiceDraftEntity(
      chatId: chatId ?? this.chatId,
      userId: userId ?? this.userId,
      filePath: filePath ?? this.filePath,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      isPaused: isPaused ?? this.isPaused,
      recoveredAfterRestart: recoveredAfterRestart ?? this.recoveredAfterRestart,
    );
  }
}
