import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart' show appFlavor;

/// Firebase settings for the two Android apps (from `android/app/src/<flavor>/google-services.json`).
/// These identify the project; they are not secrets. Access is controlled by firestore.rules.
class AppFirebaseOptions {
  static FirebaseOptions get current => appFlavor == 'capture' ? capture : daily;

  static const daily = FirebaseOptions(
    apiKey: 'AIzaSyCd6ARNc0E22p0RlfTwPYPVUV3dqPenHi8',
    appId: '1:399136486751:android:c96eed4b2ec253c6d5b2ea',
    messagingSenderId: '399136486751',
    projectId: 'finance-tracker-c9664',
    storageBucket: 'finance-tracker-c9664.firebasestorage.app',
  );

  static const capture = FirebaseOptions(
    apiKey: 'AIzaSyCd6ARNc0E22p0RlfTwPYPVUV3dqPenHi8',
    appId: '1:399136486751:android:2df7eb3d6e644452d5b2ea',
    messagingSenderId: '399136486751',
    projectId: 'finance-tracker-c9664',
    storageBucket: 'finance-tracker-c9664.firebasestorage.app',
  );
}
