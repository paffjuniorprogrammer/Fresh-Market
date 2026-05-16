import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/services/background_service.dart';
import 'package:potato_app/services/auth_flow_state.dart';
import 'package:potato_app/services/notification_service.dart';
import 'package:potato_app/services/push_notification_service.dart';
import 'package:potato_app/screens/auth_router.dart';
import 'package:potato_app/services/pwa_service.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  PwaService.instance.init();
  runApp(const PotatoApp());
}

Future<void> _initializeDeferredServices() async {
  await NotificationService.instance.init();
  await PushNotificationService.instance.initialize();
  await PotatoBackgroundService.initializeService();
}

class PotatoApp extends StatefulWidget {
  const PotatoApp({super.key});

  @override
  State<PotatoApp> createState() => _PotatoAppState();
}

class _PotatoAppState extends State<PotatoApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<void>? _updateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeDeferredServices());
    });
    unawaited(_initializeDeepLinkHandling());
    
    _updateSubscription = PwaService.instance.updateStream.listen((_) {
      _showUpdateDialog();
    });
  }

  void _showUpdateDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = NotificationService.instance.navigatorKey.currentContext;
      if (context == null) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.system_update_rounded, color: AppUi.primary, size: 28),
              SizedBox(width: 12),
              Text('Update Available', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'A new version of PAFLY is available. Please update to get the latest features and improvements.',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('LATER', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                PwaService.instance.reloadApp();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppUi.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('UPDATE NOW', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _initializeDeepLinkHandling() async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        await _handleIncomingLink(initialLink);
      }
    } catch (error) {
      debugPrint('Initial deep link handling skipped: $error');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleIncomingLink(uri)),
      onError: (error) => debugPrint('Deep link stream error: $error'),
    );
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    final isPaflyScheme = uri.scheme == 'pafly';
    final isPaflyWebDomain = (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'www.pafly.rw' || uri.host == 'pafly.rw');

    if (!isPaflyScheme && !isPaflyWebDomain) {
      return;
    }

    try {
      if (_isPasswordRecoveryLink(uri)) {
        AuthFlowState.instance.markPasswordRecoveryPending();
      }
      if (_isSignupConfirmationLink(uri)) {
        AuthFlowState.instance.markSignupConfirmationPending();
      }
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
    } catch (error) {
      debugPrint('Auth deep link handling error: $error');
      
      // Clear pending states if error occurs
      AuthFlowState.instance.clearPasswordRecoveryPending();
      AuthFlowState.instance.clearSignupConfirmationPending();

      // If we already have a session, maybe the link was just a duplicate click
      if (Supabase.instance.client.auth.currentSession != null) {
        debugPrint('Session already exists, ignoring deep link error.');
        return;
      }

      final errorStr = error.toString().toLowerCase();
      String userMessage = 'The link is invalid or has expired.';
      
      if (errorStr.contains('expired')) {
        userMessage = 'This email link has already been used or has expired. Please request a new one.';
      } else if (errorStr.contains('pkce')) {
        userMessage = 'Authentication session mismatch. Please try again from the login screen.';
      } else if (errorStr.contains('already been used')) {
        userMessage = 'This link has already been used. Please log in normally.';
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.instance.messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(userMessage)),
              ],
            ),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to login or home
              },
            ),
          ),
        );
      });
    }
  }

  bool _isPasswordRecoveryLink(Uri uri) {
    final normalized = uri.toString().toLowerCase();
    return uri.host == 'reset-password' ||
        uri.path.contains('reset-password') ||
        uri.fragment.contains('reset-password') ||
        uri.queryParameters['type']?.toLowerCase() == 'recovery' ||
        normalized.contains('type=recovery');
  }

  bool _isSignupConfirmationLink(Uri uri) {
    final normalized = uri.toString().toLowerCase();
    return uri.host == 'auth-confirmation' ||
        uri.path.contains('auth-confirmation') ||
        uri.fragment.contains('auth-confirmation') ||
        uri.queryParameters['type']?.toLowerCase() == 'signup' ||
        normalized.contains('type=signup');
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(_updateSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PAFLY',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppUi.primary,
          primary: AppUi.primary,
          secondary: AppUi.secondary,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Outfit',
      ),
      navigatorKey: NotificationService.instance.navigatorKey,
      scaffoldMessengerKey: NotificationService.instance.messengerKey,
      home: const AppBootstrapScreen(),
    );
  }
}
