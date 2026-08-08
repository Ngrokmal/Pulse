class VoiceDraftEntity {
  final String chatId;

  final String userId;

  final String filePath;

  final int elapsedMs;

  final bool isPaused;

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
