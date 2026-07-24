import 'dart:async';
import 'dart:io';
import '../../../../core/services/voice_recorder_service.dart';
import '../../domain/entities/voice_message_entity.dart';
import '../../domain/services/voice_recording_service.dart';

class VoiceRecordingServiceImpl implements VoiceRecordingService {
  final VoiceRecorderService _recorder;
  VoiceRecordingServiceImpl(this._recorder);

  final List<double> _capturedAmplitudes = [];
  StreamSubscription<double>? _amplitudeSubscription;

  // BUG FIX (WhatsApp-style pause/resume): duration used to be computed as
  // a straight `DateTime.now().difference(startedAt)`, which keeps ticking
  // across a pause — so a 3s recording paused for 30s and then resumed
  // would report ~33s instead of ~3s. Tracked instead as the sum of
  // completed active segments (_accumulatedMs) plus the current running
  // segment, if any (_segmentStartedAt).
  int _accumulatedMs = 0;
  DateTime? _segmentStartedAt;

  @override
  bool get isRecording => _recorder.isRecording;

  @override
  bool get isPaused => _recorder.isPaused;

  @override
  int get elapsedMs {
    if (_segmentStartedAt == null) return _accumulatedMs;
    return _accumulatedMs + DateTime.now().difference(_segmentStartedAt!).inMilliseconds;
  }

  @override
  List<double> get liveWaveform => List<double>.unmodifiable(_capturedAmplitudes);

  @override
  String? get currentFilePath => _recorder.currentPath;

  @override
  Future<void> startRecording() async {
    _capturedAmplitudes.clear();
    _accumulatedMs = 0;
    _segmentStartedAt = DateTime.now();
    try {
      await _recorder.start();
    } catch (e) {
      _segmentStartedAt = null;
      rethrow;
    }
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder.amplitudeStream.listen(
      _capturedAmplitudes.add,
      onError: (_) {},
    );
  }

  @override
  Future<void> pauseRecording() async {
    if (!_recorder.isRecording || _recorder.isPaused) return;
    await _recorder.pause();
    if (_segmentStartedAt != null) {
      _accumulatedMs += DateTime.now().difference(_segmentStartedAt!).inMilliseconds;
      _segmentStartedAt = null;
    }
  }

  @override
  Future<void> resumeRecording() async {
    if (!_recorder.isRecording || !_recorder.isPaused) return;
    await _recorder.resume();
    _segmentStartedAt = DateTime.now();
  }

  @override
  Future<VoiceMessageEntity> stopRecording() async {
    File? file;
    try {
      file = await _recorder.stop();
    } catch (_) {
      file = null;
    }
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (_segmentStartedAt != null) {
      _accumulatedMs += DateTime.now().difference(_segmentStartedAt!).inMilliseconds;
      _segmentStartedAt = null;
    }
    final durationMs = _accumulatedMs;
    _accumulatedMs = 0;
    final waveform = List<double>.from(_capturedAmplitudes);
    _capturedAmplitudes.clear();
    return VoiceMessageEntity(
      localPath: file?.path,
      durationMs: durationMs,
      waveform: waveform,
    );
  }

  @override
  Future<void> cancelRecording() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _accumulatedMs = 0;
    _segmentStartedAt = null;
    _capturedAmplitudes.clear();
    try {
      await _recorder.cancel();
    } catch (_) {
      // already stopped/disposed — local state is already reset above
    }
  }

  @override
  Stream<double> get amplitudeStream => _recorder.amplitudeStream;
}
