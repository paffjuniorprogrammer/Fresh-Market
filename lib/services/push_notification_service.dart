import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/services/notification_service.dart';

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

    try {
      if (kIsWeb) {
        if (AppConstants.firebaseApiKey.isEmpty) {
          debugPrint('Firebase Web API Key is missing. Skipping Push Notifications initialization.');
          _firebaseReady = false;
          return;
        }
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: AppConstants.firebaseApiKey,
            appId: AppConstants.firebaseAppId,
            messagingSenderId: AppConstants.firebaseMessagingSenderId,
            projectId: AppConstants.firebaseProjectId,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }

      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Listen for messages while the app is in the foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? message.data['title'] ?? 'New Notification';
        final body = message.notification?.body ?? message.data['body'] ?? '';
        
        NotificationService.instance.messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('$title\n$body'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });

      _firebaseReady = true;
    } catch (error) {
      debugPrint('Firebase push init skipped: $error');
      _firebaseReady = false;
    }
  }

  Future<bool> isPermissionGranted() async {
    if (kIsWeb) {
      final status = await FirebaseMessaging.instance.requestPermission();
      return status.authorizationStatus == AuthorizationStatus.authorized;
    }
    
    final status = await FirebaseMessaging.instance.requestPermission();
    return status.authorizationStatus == AuthorizationStatus.authorized;
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

    String? token;
    if (kIsWeb) {
      token = await FirebaseMessaging.instance.getToken(
        vapidKey: AppConstants.firebaseVapidKey,
      );
    } else {
      token = await FirebaseMessaging.instance.getToken();
    }

    if (token != null && token.isNotEmpty) {
      await _upsertDeviceToken(tokenTable, userId, token);
      await _removeTokenFromOtherTable(tokenTable, token);
    } else {
      debugPrint('Push token is empty for $userId on $tokenTable.');
    }

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((token) async {
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
  }) => notifyAdminsOfOrderEvent(
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
