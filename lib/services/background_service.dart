import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PotatoBackgroundService {
  static const notificationChannelId = 'fresh_market_orders';
  static const notificationChannelName = 'PAFLY Orders';
  static const notificationChannelDescription =
      'Local notification channel for PAFLY alerts';

  static Future<void> initializeService() async {
    if (kIsWeb) {
      debugPrint('Local notification channel setup skipped on Web.');
      return;
    }

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      notificationChannelName,
      description: notificationChannelDescription,
      importance: Importance.max,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }
}
