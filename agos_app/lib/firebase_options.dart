// File generated manually from google-services.json and GoogleService-Info.plist.
// ignore_for_file: type=lint
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
        return ios;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAd5QWfd1vH1R74etvfv_nvKBkVTIBjtwo',
    appId: '1:804926916850:web:1ae24dc72f5f19fec8286b',
    messagingSenderId: '804926916850',
    projectId: 'agos-prod',
    storageBucket: 'agos-prod.firebasestorage.app',
    authDomain: 'agos-prod.firebaseapp.com',
    measurementId: 'G-GRXS877ELR',
  );

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

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAEGzg2FPnaOIAu6JjukO45A-VQ3UDb6FM',
    appId: '1:804926916850:android:da7420fc9a612d67c8286b',
    messagingSenderId: '804926916850',
    projectId: 'agos-prod',
    storageBucket: 'agos-prod.firebasestorage.app',
  );
}
