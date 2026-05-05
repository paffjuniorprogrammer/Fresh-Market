import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/services/background_service.dart';
import 'package:potato_app/services/auth_flow_state.dart';
import 'package:potato_app/services/notification_service.dart';
import 'package:potato_app/services/push_notification_service.dart';
import 'package:potato_app/screens/auth_router.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeDeferredServices());
    });
    unawaited(_initializeDeepLinkHandling());
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
    if (uri.scheme != 'freshmarket') {
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
      debugPrint('Auth deep link handling skipped: $error');
    }
  }

  bool _isPasswordRecoveryLink(Uri uri) {
    final normalized = uri.toString().toLowerCase();
    return uri.host == 'reset-password' ||
        uri.path.contains('reset-password') ||
        uri.queryParameters['type']?.toLowerCase() == 'recovery' ||
        normalized.contains('type=recovery');
  }

  bool _isSignupConfirmationLink(Uri uri) {
    final normalized = uri.toString().toLowerCase();
    return uri.host == 'auth-confirmation' ||
        uri.path.contains('auth-confirmation') ||
        uri.queryParameters['type']?.toLowerCase() == 'signup' ||
        normalized.contains('type=signup');
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fresh Market',
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




