import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  VoiceRecorderService._privateConstructor();
  static final VoiceRecorderService instance = VoiceRecorderService._privateConstructor();

  AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  bool _isRecording = false;
  bool _isPaused = false;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  String? get currentPath => _currentPath;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (_isRecording) {
      throw StateError('Recorder is already recording');
    }
    bool granted;
    try {
      granted = await _recorder.hasPermission();
    } catch (_) {
      throw StateError('Microphone permission denied');
    }
    if (!granted) {
      throw StateError('Microphone permission denied');
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      _currentPath = path;
      _isRecording = true;
      _isPaused = false;
    } catch (e) {
      _isRecording = false;
      _isPaused = false;
      _currentPath = null;
      throw StateError('Recorder unavailable');
    }
  }

  Future<void> pause() async {
    if (!_isRecording || _isPaused) return;
    try {
      await _recorder.pause();
      _isPaused = true;
    } catch (_) {
      throw StateError('Recorder unavailable');
    }
  }

  Future<void> resume() async {
    if (!_isRecording || !_isPaused) return;
    try {
      await _recorder.resume();
      _isPaused = false;
    } catch (_) {
      throw StateError('Recorder unavailable');
    }
  }

  Future<File?> stop() async {
    if (!_isRecording) return null;
    String? stoppedPath;
    try {
      stoppedPath = await _recorder.stop();
    } catch (_) {
      stoppedPath = null;
    } finally {
      _isRecording = false;
      _isPaused = false;
    }
    final resolvedPath = stoppedPath ?? _currentPath;
    _currentPath = null;
    await _releaseAndRecreate();
    if (resolvedPath == null) return null;
    final file = File(resolvedPath);
    return file.existsSync() ? file : null;
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {
    } finally {
      _isRecording = false;
      _isPaused = false;
      _currentPath = null;
    }
    await _releaseAndRecreate();
  }

  Future<void> _releaseAndRecreate() async {
    final old = _recorder;
    _recorder = AudioRecorder();
    _amplitudeStream = null;
    // ignore: avoid_print
    print('[QA][amp-cache] recorder recreated, cached amplitude stream invalidated');
    try {
      await old.dispose();
    } catch (_) {
    }
  }

  Stream<double>? _amplitudeStream;

  Stream<double> get amplitudeStream {
    final isCached = _amplitudeStream != null;
    _amplitudeStream ??= _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .map((amp) => _normalize(amp.current))
        .asBroadcastStream();
    // ignore: avoid_print
    print('[QA][amp-cache] amplitudeStream access -> '
        '${isCached ? "reused cached" : "created new"} '
        'hash=${identityHashCode(_amplitudeStream)}');
    return _amplitudeStream!;
  }

  double _normalize(double db) {
    const minDb = -45.0;
    const maxDb = 0.0;
    final clamped = db.clamp(minDb, maxDb);
    return ((clamped - minDb) / (maxDb - minDb)).clamp(0.05, 1.0);
  }

  Future<void> dispose() async {
    _amplitudeStream = null;
    try {
      await _recorder.dispose();
    } catch (_) {
    } finally {
      _isRecording = false;
      _isPaused = false;
      _currentPath = null;
    }
  }
}
