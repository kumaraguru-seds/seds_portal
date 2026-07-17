// File generated from google-services.json
// Project: seds-portal | Package: com.example.frontend_fluttter_app

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS Firebase options not yet configured.',
        );
      case TargetPlatform.windows:
        return windows;
      default:
        // For Linux, macOS, etc — use android config as fallback
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyACbPL0KgAq_ogvrQBVq5j7Cla_kmFol_A',
    appId: '1:138971655632:android:7d319da971e8588ae3ddd5',
    messagingSenderId: '138971655632',
    projectId: 'seds-portal',
    storageBucket: 'seds-portal.firebasestorage.app',
  );

  // Windows uses the same Firebase project — web API key works for desktop SDK
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyACbPL0KgAq_ogvrQBVq5j7Cla_kmFol_A',
    appId: '1:138971655632:windows:seds_portal_desktop',
    messagingSenderId: '138971655632',
    projectId: 'seds-portal',
    storageBucket: 'seds-portal.firebasestorage.app',
  );

  // Web Firebase options — real credentials from Firebase Console
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC2ll09YTyVhJZAlU3eyxQQyAe3oi4fIas',
    appId: '1:138971655632:web:914554399f89bb3be3ddd5',
    messagingSenderId: '138971655632',
    projectId: 'seds-portal',
    storageBucket: 'seds-portal.firebasestorage.app',
    authDomain: 'seds-portal.firebaseapp.com',
    measurementId: 'G-N24KK5EJPG',
  );
}
