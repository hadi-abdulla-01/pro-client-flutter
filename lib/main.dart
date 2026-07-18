import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'core/notification_service.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();

  final service = NotificationService.instance;
  print('Handling a background message ${message.messageId}');

  // If message is a notification, use its details.
  if (message.notification != null) {
    final notification = message.notification!;
    service.showLocalNotification(
      id: service.idFromUuid(message.messageId ?? ''),
      title: notification.title ?? 'New Message',
      body: notification.body ?? '',
    );
  }
  // If it's a data message, extract details from data field.
  else if (message.data.isNotEmpty) {
    service.showLocalNotification(
      id: service.idFromUuid(message.messageId ?? ''),
      title: message.data['title'] ?? 'New Message',
      body: message.data['body'] ?? '',
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseConfig.init();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications (permission prompt happens inside)
  await NotificationService.instance.init();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'PRO Portal Client',
      theme: TerraTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
