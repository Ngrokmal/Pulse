import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/voice_draft_entity.dart';

/// Local-only store for the "Voice Draft" concept (Bug 3/4 of the Voice
/// Message audit). Deliberately has NO Firestore/cloud component — a draft
/// only ever exists as a file on this device plus a small JSON sidecar used
/// purely to recover from the app process being killed outright.
///
/// A singleton (like [VoiceRecorderService]/[VoiceRecordingServiceImpl]) so
/// the draft survives the ChatScreen widget being torn down and rebuilt
/// (user navigates to another in-app page and back) without any special
/// wiring — the in-memory [draftNotifier] value simply keeps existing.
///
/// Scoped by BOTH chatId and userId (see [VoiceDraftEntity]) — a draft must
/// never surface in a different chat, and must never surface for a
/// different logged-in account on the same device (logout/login
/// mid-session, or a crash-recovered draft left behind by a previous
/// session's user). [discardIfUserMismatch] is the enforcement point for
/// the latter — call it whenever the signed-in user changes.
class VoiceDraftStore {
  VoiceDraftStore._privateConstructor();
  static final VoiceDraftStore instance = VoiceDraftStore._privateConstructor();

  static const String _sidecarFileName = 'voice_draft_meta.json';

  final ValueNotifier<VoiceDraftEntity?> draftNotifier = ValueNotifier<VoiceDraftEntity?>(null);

  VoiceDraftEntity? get current => draftNotifier.value;

  void setDraft(VoiceDraftEntity? draft) {
    draftNotifier.value = draft;
  }

  /// If a draft is currently held (in memory or restored from disk) that
  /// belongs to a different account than [currentUserId], discard it
  /// entirely — not just hide it — including deleting its local audio file
  /// and clearing the crash-recovery sidecar. Call this whenever the
  /// signed-in user changes (login/logout), so a previous account's
  /// recording can never surface for the next account on the same device.
  /// No-op if there's no draft, or it already belongs to [currentUserId].
  Future<void> discardIfUserMismatch(String? currentUserId) async {
    final draft = current;
    if (draft == null || draft.userId == currentUserId) return;
    try {
      final file = File(draft.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // best-effort cleanup only
    }
    draftNotifier.value = null;
    await clearSidecar();
  }

  /// Writes/updates the crash-recovery sidecar next to the recording. Safe
  /// to call frequently — failures are swallowed since this is a
  /// best-effort recovery aid, never the source of truth while the app is
  /// alive (the in-memory recorder/service singletons are).
  Future<void> persistSidecar({
    required String chatId,
    required String userId,
    required String filePath,
    required int elapsedMs,
  }) async {
    try {
      final sidecar = await _sidecarFile();
      await sidecar.writeAsString(jsonEncode({
        'chatId': chatId,
        'userId': userId,
        'path': filePath,
        'elapsedMs': elapsedMs,
      }));
    } catch (_) {
      // Best-effort only — an in-app pause/resume still works from the live
      // singleton even if we fail to write the recovery sidecar.
    }
  }

  Future<void> clearSidecar() async {
    try {
      final sidecar = await _sidecarFile();
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    } catch (_) {
      // nothing else to do — worst case a stale sidecar is cleaned up
      // (or simply ignored, since it also validates the audio file still
      // exists) the next time restoreFromDisk() runs.
    }
  }

  /// Called once at app startup (see main.dart) with whoever is signed in
  /// at that moment. If the process was previously killed while a voice
  /// message was mid-recording, this reconstructs a best-effort draft from
  /// whatever partial audio survived on disk so it is never silently lost
  /// — surfaced with [VoiceDraftEntity.recoveredAfterRestart] set, since
  /// there is no live native recorder session left to resume.
  ///
  /// If the sidecar belongs to a DIFFERENT account than [currentUserId]
  /// (or no one is signed in yet), it is discarded outright rather than
  /// restored — a leftover recording must never surface for the wrong
  /// account.
  Future<void> restoreFromDisk(String? currentUserId) async {
    try {
      final sidecar = await _sidecarFile();
      if (!await sidecar.exists()) return;
      final raw = await sidecar.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final chatId = map['chatId'] as String?;
      final userId = map['userId'] as String?;
      final path = map['path'] as String?;
      final elapsedMs = (map['elapsedMs'] as num?)?.toInt() ?? 0;
      if (chatId == null || path == null) {
        await sidecar.delete();
        return;
      }
      final audioFile = File(path);
      if (!await audioFile.exists() || await audioFile.length() <= 0) {
        await sidecar.delete();
        return;
      }
      // Old sidecar written before userId scoping existed, or it belongs
      // to a different/no-longer-signed-in account — never restore it.
      if (userId == null || currentUserId == null || userId != currentUserId) {
        try {
          await audioFile.delete();
        } catch (_) {
          // best-effort
        }
        await sidecar.delete();
        return;
      }
      draftNotifier.value = VoiceDraftEntity(
        chatId: chatId,
        userId: userId,
        filePath: path,
        elapsedMs: elapsedMs,
        isPaused: true,
        recoveredAfterRestart: true,
      );
    } catch (_) {
      // Corrupt/unreadable sidecar — nothing recoverable, fail silently
      // rather than block app startup.
    }
  }

  Future<File> _sidecarFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$_sidecarFileName');
  }
}
