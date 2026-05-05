import 'package:flutter/material.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/services/notification_service.dart';

enum PotatoNotificationType { success, error, info }

class PotatoNotification {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext? context, {
    required String message,
    PotatoNotificationType type = PotatoNotificationType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final effectiveContext = context ?? NotificationService.instance.navigatorKey.currentContext;
    if (effectiveContext == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(effectiveContext);
    
    _currentEntry = OverlayEntry(
      builder: (context) => _TopNotificationWidget(
        message: message,
        type: type,
        onDismiss: () {
          _currentEntry?.remove();
          _currentEntry = null;
        },
        duration: duration,
      ),
    );

    overlay.insert(_currentEntry!);
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final PotatoNotificationType type;
  final VoidCallback onDismiss;
  final Duration duration;

  const _TopNotificationWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    // Auto dismiss
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    IconData icon;
    
    switch (widget.type) {
      case PotatoNotificationType.success:
        bgColor = AppUi.primary;
        icon = Icons.check_circle_outline;
        break;
      case PotatoNotificationType.error:
        bgColor = Colors.red.shade800;
        icon = Icons.error_outline;
        break;
      case PotatoNotificationType.info:
        bgColor = const Color(0xFF2F3B45);
        icon = Icons.info_outline;
        break;
    }

    final topPadding = MediaQuery.of(context).padding.top + 10;

    return Positioned(
      top: topPadding,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor.withAlpha(235), // Slight transparency for premium feel
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.white24, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => _controller.reverse().then((_) => widget.onDismiss()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
