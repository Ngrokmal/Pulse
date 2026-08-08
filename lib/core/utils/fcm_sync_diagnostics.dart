import 'dart:developer' as developer;

class FcmSyncLog {
  FcmSyncLog._();

  static const String _name = 'FCM_SYNC';

  static void step(String step, String message) {
    developer.log('[$step] $message', name: _name);
  }

  static void error(String step, String message, Object error, [StackTrace? stackTrace]) {
    final buffer = StringBuffer('[$step] $message :: ${error.runtimeType}: $error');
    try {
      final dynamic e = error;
      final code = e.code;
      final details = e.details;
      final hint = e.hint;
      buffer.write(' | code=$code details=$details hint=$hint');
    } catch (_) {
    }
    developer.log(buffer.toString(), name: _name, level: 1000 , error: error, stackTrace: stackTrace);
  }
}
