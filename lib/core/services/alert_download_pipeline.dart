import 'dart:async';

import '../../features/custom_alert/domain/entities/alert_audio_metadata_entity.dart';
import '../../features/custom_alert/domain/usecases/ensure_alert_audio_cached_usecase.dart';
import 'alert_autoplay_service.dart';
import 'alert_foreground_service_bridge.dart';

class AlertDownloadPipeline {
  final EnsureAlertAudioCachedUseCase ensureAlertAudioCachedUseCase;
  final AlertAutoplayService autoplayService;
  final AlertForegroundServiceBridge foregroundServiceBridge;

  AlertDownloadPipeline({
    required this.ensureAlertAudioCachedUseCase,
    required this.autoplayService,
    required this.foregroundServiceBridge,
  });

  Future<void> _queue = Future.value();

  Future<void> run(
    AlertAudioMetadata metadata, {
    Duration perAttemptTimeout = const Duration(seconds: 45),
  }) {
    final Future<void> previous = _queue;
    final Completer<void> completer = Completer<void>();
    _queue = completer.future;

    previous.whenComplete(() async {
      try {
        await _runOnce(metadata).timeout(perAttemptTimeout, onTimeout: () {});
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  Future<void> _runOnce(AlertAudioMetadata metadata) async {
    try {
      await foregroundServiceBridge.start();
      final String path = await ensureAlertAudioCachedUseCase.call(metadata);
      await autoplayService.playAndAwaitCompletion(path);
    } catch (_) {
    } finally {
      await foregroundServiceBridge.stop();
    }
  }
}
