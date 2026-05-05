import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:potato_app/utils/constants.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Ignore missing Firebase configuration in background isolate.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _ordersChannelId = 'fresh_market_orders';
  static const _ordersChannelName = 'Fresh Market Orders';
  static const _ordersChannelDescription =
      'Loud admin alerts for new client orders and cancellations.';
  static const _updatesChannelId = 'fresh_market_updates';
  static const _updatesChannelName = 'Fresh Market Updates';
  static const _updatesChannelDescription =
      'Client payment and order status updates from Fresh Market.';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;
  bool _firebaseReady = false;
  Future<void>? _initializationFuture;
  String? _registeredUserId;
  String? _registeredTokenTable;
  StreamSubscription<String>? _tokenRefreshSubscription;

  bool get isFirebaseReady => _firebaseReady;

  Future<void> initialize() async {
    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _initializeInternal();
    return _initializationFuture!;
  }

  Future<void> _initializeInternal() async {
    if (_initialized) return;
    _initialized = true;

    await _initializeLocalNotifications();

    if (kIsWeb) return;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _firebaseReady = true;
    } catch (error) {
      debugPrint('Firebase push init skipped: $error');
      _firebaseReady = false;
    }
  }

  Future<void> registerAdminDevice(String userId) => _registerDevice(
        userId: userId,
        tokenTable: AppConstants.adminTokensTable,
      );

  Future<void> registerClientDevice(String userId) => _registerDevice(
        userId: userId,
        tokenTable: AppConstants.clientTokensTable,
      );

  Future<void> _registerDevice({
    required String userId,
    required String tokenTable,
  }) async {
    await initialize();
    if (!_firebaseReady) return;
    if (_registeredUserId == userId &&
        _registeredTokenTable == tokenTable &&
        _tokenRefreshSubscription != null) {
      return;
    }

    _registeredUserId = userId;
    _registeredTokenTable = tokenTable;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await _upsertDeviceToken(tokenTable, userId, token);
      await _removeTokenFromOtherTable(tokenTable, token);
    } else {
      debugPrint('Push token is empty for $userId on $tokenTable.');
    }

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      if (token.isEmpty) return;
      await _upsertDeviceToken(tokenTable, userId, token);
      await _removeTokenFromOtherTable(tokenTable, token);
    });
  }

  Future<void> notifyAdminsOfOrderEvent({
    required String eventType,
    required int orderId,
    required String customerName,
    required String paymentMethod,
    required double totalPrice,
    String? cancelReason,
    String? orderDetails,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        AppConstants.notifyAdminOrderFunction,
        body: {
          'eventType': eventType,
          'orderId': orderId,
          'customerName': customerName,
          'paymentMethod': paymentMethod,
          'totalPrice': totalPrice,
          'cancelReason': cancelReason,
          'orderDetails': orderDetails,
        },
      );
    } catch (error) {
      debugPrint('Admin push invoke failed: $error');
    }
  }

  Future<void> notifyAdminsOfNewOrder({
    required int orderId,
    required String customerName,
    required String paymentMethod,
    required double totalPrice,
    String? orderDetails,
  }) =>
      notifyAdminsOfOrderEvent(
        eventType: 'new_order',
        orderId: orderId,
        customerName: customerName,
        paymentMethod: paymentMethod,
        totalPrice: totalPrice,
        orderDetails: orderDetails,
      );

  Future<void> notifyClientEvent({
    required String eventType,
    String? userId,
    int? orderId,
    String? orderStatus,
    String? customerName,
    String? productName,
    double? totalPrice,
    double? paymentAmount,
    String? productId,
    double? oldPrice,
    double? newPrice,
    String? unit,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        AppConstants.notifyClientEventFunction,
        body: {
          'eventType': eventType,
          'userId': userId,
          'orderId': orderId,
          'orderStatus': orderStatus,
          'customerName': customerName,
          'productName': productName,
          'totalPrice': totalPrice,
          'paymentAmount': paymentAmount,
          'productId': productId,
          'oldPrice': oldPrice,
          'newPrice': newPrice,
          'unit': unit,
        },
      );
    } catch (error) {
      debugPrint('Client push invoke failed: $error');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        _ordersChannelId,
        _ordersChannelName,
        description: _ordersChannelDescription,
        importance: Importance.max,
      ),
    );

    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        _updatesChannelId,
        _updatesChannelName,
        description: _updatesChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    bool playSound = true,
  }) async {
    await initialize();

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _ordersChannelId,
          _ordersChannelName,
          channelDescription: _ordersChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );

    if (!playSound) return;
    try {
      await _audioPlayer.play(AssetSource('audio/notification.mpeg'));
    } catch (error) {
      debugPrint('Local notification asset sound failed: $error');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ??
        _foregroundTitleFromData(message.data) ??
        'Fresh Market';
    final body =
        notification?.body ??
        _foregroundBodyFromData(message.data) ??
        'You have a new update.';

    await showLocalNotification(title: title, body: body);
  }

  String? _foregroundTitleFromData(Map<String, dynamic> data) {
    final eventType = '${data['eventType'] ?? ''}'.trim().toLowerCase();
    switch (eventType) {
      case 'new_order':
        return 'New customer order';
      case 'order_cancelled':
        return 'Order cancelled by client';
      case 'order_status':
        return 'Order updated';
      case 'payment_received':
        return 'Payment received';
      case 'price_update':
        return 'Product price updated';
      default:
        return null;
    }
  }

  String? _foregroundBodyFromData(Map<String, dynamic> data) {
    final eventType = '${data['eventType'] ?? ''}'.trim().toLowerCase();
    final orderId = '${data['orderId'] ?? ''}'.trim();
    final customerName = '${data['customerName'] ?? ''}'.trim();
    final paymentMethod = '${data['paymentMethod'] ?? ''}'.trim();
    final totalPrice = double.tryParse('${data['totalPrice'] ?? ''}');
    final paymentAmount = double.tryParse('${data['paymentAmount'] ?? ''}');
    final orderStatus = '${data['orderStatus'] ?? ''}'.trim().toLowerCase();
    final cancelReason = '${data['cancelReason'] ?? ''}'.trim();

    switch (eventType) {
      case 'new_order':
        final customerLabel = customerName.isNotEmpty ? customerName : 'A client';
        final orderLabel = orderId.isNotEmpty ? 'Order #$orderId' : 'A new order';
        final paymentLabel = paymentMethod.isNotEmpty
            ? paymentMethod
            : 'Unspecified payment';
        final amountLabel = totalPrice == null || totalPrice <= 0
            ? null
            : '${totalPrice.toStringAsFixed(0)} Frw';
        final body = '$customerLabel placed $orderLabel. - $paymentLabel';
        return amountLabel == null ? body : '$body - $amountLabel';
      case 'order_cancelled':
        final customerLabel = customerName.isNotEmpty ? customerName : 'A client';
        final orderLabel = orderId.isNotEmpty ? 'order #$orderId' : 'an order';
        if (cancelReason.isNotEmpty) {
          return '$customerLabel cancelled $orderLabel: $cancelReason';
        }
        return '$customerLabel cancelled $orderLabel.';
      case 'payment_received':
        final orderLabel = orderId.isNotEmpty ? 'Order #$orderId' : 'Your order';
        final amountLabel = paymentAmount == null || paymentAmount <= 0
            ? 'A payment'
            : '${paymentAmount.toStringAsFixed(0)} Frw';
        if (orderStatus == 'completed') {
          return '$amountLabel was received for $orderLabel. Your order is now fully paid.';
        }
        return '$amountLabel was received for $orderLabel.';
      case 'order_status':
        final orderLabel = orderId.isNotEmpty ? 'Order #$orderId' : 'Your order';
        if (orderStatus == 'completed') {
          return '$orderLabel is now fully paid and completed.';
        }
        return orderStatus.isEmpty
            ? '$orderLabel was updated.'
            : '$orderLabel is now ${data['orderStatus']}.';
      default:
        return null;
    }
  }

  Future<void> _upsertDeviceToken(
    String tokenTable,
    String userId,
    String token,
  ) async {
    await Supabase.instance.client.from(tokenTable).upsert({
      'user_id': userId,
      'fcm_token': token,
      'platform': _platformName(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'fcm_token');
  }

  Future<void> _removeTokenFromOtherTable(
    String tokenTable,
    String token,
  ) async {
    final otherTable = tokenTable == AppConstants.adminTokensTable
        ? AppConstants.clientTokensTable
        : AppConstants.adminTokensTable;

    try {
      await Supabase.instance.client
          .from(otherTable)
          .delete()
          .eq('fcm_token', token);
    } catch (error) {
      debugPrint('Token cleanup skipped for $otherTable: $error');
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
