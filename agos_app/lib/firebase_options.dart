// File generated manually from google-services.json and GoogleService-Info.plist.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        // Windows desktop uses the same REST-based API as Android.
        // Register a dedicated Windows/Web app in Firebase Console for production.
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAEGzg2FPnaOIAu6JjukO45A-VQ3UDb6FM',
    appId: '1:804926916850:android:da7420fc9a612d67c8286b',
    messagingSenderId: '804926916850',
    projectId: 'agos-prod',
    storageBucket: 'agos-prod.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDx3K1zZSxm4O701uEEZiYY9JJFzKNMOuU',
    appId: '1:804926916850:ios:463fc7c5999c2ee7c8286b',
    messagingSenderId: '804926916850',
    projectId: 'agos-prod',
    storageBucket: 'agos-prod.firebasestorage.app',
    iosBundleId: 'com.agos.agosApp',
  );

  // Windows desktop: register a Web app in Firebase Console for production.
  // For now, reuses the Android project credentials which share the same REST API key.
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAEGzg2FPnaOIAu6JjukO45A-VQ3UDb6FM',
    appId: '1:804926916850:android:da7420fc9a612d67c8286b',
    messagingSenderId: '804926916850',
    projectId: 'agos-prod',
    storageBucket: 'agos-prod.firebasestorage.app',
  );
}
