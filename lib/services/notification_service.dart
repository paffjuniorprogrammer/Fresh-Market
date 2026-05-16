import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:potato_app/services/ui_service.dart';
import 'package:potato_app/services/push_notification_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final _audioPlayer = AudioPlayer();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  GlobalKey<ScaffoldMessengerState> get messengerKey => _messengerKey;
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  bool _isInitialized = false;
  RealtimeChannel? _adminChannel;
  RealtimeChannel? _clientChannel;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    // Pre-load or prepare audio if needed
  }

  Future<void> checkAndPromptPermissions() async {
    final granted = await PushNotificationService.instance.isPermissionGranted();
    if (!granted) {
      _showSnackBar(
        'Notifications are disabled in your phone settings. Enable them to get order updates.',
        Icons.notifications_off_rounded,
        Colors.orange,
      );
    }
  }

  void _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/notification.mpeg'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  void setupAdminListener() {
    _adminChannel?.unsubscribe();
    _adminChannel = Supabase.instance.client
        .channel('admin-orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final newOrder = payload.newRecord;
            final customerName = '${newOrder['customer_name'] ?? 'Client'}'
                .trim();
            final paymentMethod = '${newOrder['payment_method'] ?? 'Cash'}'
                .trim();
            final totalPrice = num.tryParse('${newOrder['total_price'] ?? ''}');
            final totalLabel = totalPrice == null
                ? ''
                : ' • ${totalPrice.toStringAsFixed(0)} Frw';
            final message =
                '$customerName placed Order #${newOrder['id']} • $paymentMethod$totalLabel';
            _showSnackBar(message, Icons.shopping_cart, Colors.green);
            if (!PushNotificationService.instance.isFirebaseReady) {
              unawaited(
                PushNotificationService.instance.showLocalNotification(
                  title: 'New customer order',
                  body: message,
                  playSound: false,
                ),
              );
            }
            _playNotificationSound();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final updatedOrder = payload.newRecord;
            final oldOrder = payload.oldRecord;
            final newStatus = '${updatedOrder['status'] ?? ''}';
            final oldStatus = '${oldOrder['status'] ?? ''}';
            final cancelReason = '${updatedOrder['cancel_reason'] ?? ''}'
                .trim();

            if (newStatus == oldStatus) {
              return;
            }

            if (newStatus.toLowerCase() == 'cancelled') {
              final customerName =
                  '${updatedOrder['customer_name'] ?? 'Client'}'.trim();
              final reasonSuffix = cancelReason.isNotEmpty
                  ? ': ${cancelReason.length > 60 ? '${cancelReason.substring(0, 57)}...' : cancelReason}'
                  : '';
              final message =
                  '$customerName cancelled Order #${updatedOrder['id']}$reasonSuffix';
              _showSnackBar(message, Icons.cancel_outlined, Colors.red);
              if (!PushNotificationService.instance.isFirebaseReady) {
                unawaited(
                  PushNotificationService.instance.showLocalNotification(
                    title: 'Order cancelled by client',
                    body: message,
                    playSound: false,
                  ),
                );
              }
            } else {
              final message = 'Order #${updatedOrder['id']} status: $newStatus';
              _showSnackBar(message, Icons.info_outline, Colors.blue);
              if (!PushNotificationService.instance.isFirebaseReady) {
                unawaited(
                  PushNotificationService.instance.showLocalNotification(
                    title: 'PAFLY update',
                    body: message,
                    playSound: false,
                  ),
                );
              }
            }
            _playNotificationSound();
          },
        )
        .subscribe();
  }

  void setupClientListener(String userId) {
    _clientChannel?.unsubscribe();
    _clientChannel = Supabase.instance.client
        .channel('client-orders-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_id',
            value: userId,
          ),
          callback: (payload) {
            final updatedOrder = payload.newRecord;
            final oldOrder = payload.oldRecord;

            if (updatedOrder['status'] != oldOrder['status']) {
              _showSnackBar(
                'Order #${updatedOrder['id']} status: ${updatedOrder['status']}',
                Icons.info_outline,
                Colors.blue,
              );
              _playNotificationSound();
            }
          },
        )
        .subscribe();
  }

  void _showSnackBar(String message, IconData icon, Color color) {
    PotatoNotification.show(
      null,
      message: message,
      type: color == Colors.green
          ? PotatoNotificationType.success
          : color == Colors.red
          ? PotatoNotificationType.error
          : PotatoNotificationType.info,
    );
  }

  void dispose() {
    _adminChannel?.unsubscribe();
    _clientChannel?.unsubscribe();
    _audioPlayer.dispose();
  }
}
