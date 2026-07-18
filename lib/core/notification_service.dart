import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  RealtimeChannel? _channel;
  bool _initialized = false;

  static const String _channelId = 'pro_services_channel';
  static const String _channelName = 'PRO Services Alerts';
  static const String _channelDesc = 'Notifications from your PRO services portal';

  // ── Notification details — no custom icon so Android uses the app icon ───
  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDesc,
    importance: Importance.max,   // MAX ensures heads-up banner appears
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    // No icon: field — uses the default set in AndroidInitializationSettings
  );

  static const NotificationDetails _notifDetails =
      NotificationDetails(android: _androidDetails);

  // ── Init ─────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Use @mipmap/ic_launcher as default icon (must match a drawable/mipmap res)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Explicitly create the notification channel (required Android 8+)
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Request POST_NOTIFICATIONS permission (Android 13+)
      await androidPlugin.requestNotificationsPermission();
    }

    debugPrint('[NotificationService] Initialized');
  }

  // ── Subscribe to realtime for a list of company IDs ──────────────────────
  void subscribe(List<String> companyIds, {VoidCallback? onNotificationChange}) {
    unsubscribe();

    debugPrint('[NotificationService] Subscribing with companyIds: $companyIds');

    _channel = supabase
        .channel('pro_notifications_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            debugPrint('[NotificationService] Change: ${payload.eventType}');
            if (payload.eventType == PostgresChangeEvent.insert) {
              final row = payload.newRecord;
              final rowCompanyId = row['company_id'] as String?;

              final isRelevant =
                  rowCompanyId == null || companyIds.contains(rowCompanyId);

              if (isRelevant) {
                showLocalNotification(
                  id: idFromUuid(row['id']?.toString() ?? ''),
                  title: row['title']?.toString() ?? 'PRO Services',
                  body: row['message']?.toString() ?? '',
                );
              }
            }
            onNotificationChange?.call();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[NotificationService] status=$status error=$error');
        });
  }

  void unsubscribe() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    debugPrint('[NotificationService] Showing banner: $title');
    await _plugin.show(id, title, body, _notifDetails);
  }

  int idFromUuid(String uuid) =>
      uuid.replaceAll('-', '').hashCode.abs() % 2147483647;
}
