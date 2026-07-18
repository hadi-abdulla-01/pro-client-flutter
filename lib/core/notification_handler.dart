import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// This needs to be a top-level function (not a class method)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This handler runs in a separate isolate from your main application,
  // so you cannot update UI state from here. You must initialize Firebase
  // within the handler since it runs in its own context.
  await Firebase.initializeApp();

  if (kDebugMode) {
    print("--- Handling a background message: ${message.messageId}");
    print('Message data: ${message.data}');
  }

  if (message.notification != null) {
    if (kDebugMode) {
      print('Message also contained a notification: ${message.notification}');
    }
  }
}
