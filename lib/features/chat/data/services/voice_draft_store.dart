import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/voice_draft_entity.dart';

class VoiceDraftStore {
  VoiceDraftStore._privateConstructor();
  static final VoiceDraftStore instance = VoiceDraftStore._privateConstructor();

  static const String _sidecarFileName = 'voice_draft_meta.json';

  final ValueNotifier<VoiceDraftEntity?> draftNotifier = ValueNotifier<VoiceDraftEntity?>(null);

  VoiceDraftEntity? get current => draftNotifier.value;

  void setDraft(VoiceDraftEntity? draft) {
    draftNotifier.value = draft;
  }

  Future<void> discardIfUserMismatch(String? currentUserId) async {
    final draft = current;
    if (draft == null || draft.userId == currentUserId) return;
    try {
      final file = File(draft.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
    }
    draftNotifier.value = null;
    await clearSidecar();
  }

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
    }
  }

  Future<void> clearSidecar() async {
    try {
      final sidecar = await _sidecarFile();
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    } catch (_) {
    }
  }

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
      if (userId == null || currentUserId == null || userId != currentUserId) {
        try {
          await audioFile.delete();
        } catch (_) {
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
    }
  }

  Future<File> _sidecarFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$_sidecarFileName');
  }
}
