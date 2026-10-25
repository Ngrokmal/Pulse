// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'this project currently only targets Android. Run '
        '`flutterfire configure` after adding a web Firebase app.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS - '
          'this project currently only targets Android. Run '
          '`flutterfire configure` after adding an iOS Firebase app.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDG8ZGcCdBOFHuox7f5ox1nLFYMxVEtu0A',
    appId: '1:260839823539:android:4fff8938f83ce00f7bf8c6',
    messagingSenderId: '260839823539',
    projectId: 'messengerclone-d7f43',
    storageBucket: 'messengerclone-d7f43.firebasestorage.app',
  );
}
