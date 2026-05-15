import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_flow_state.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import 'login_screen.dart';
import 'password_reset_screen.dart';
import 'client_dashboard.dart';
import 'guest_browse_screen.dart';
import 'package:potato_app/screens/admin_control_screen.dart';
import 'setup_screens.dart';
import '../widgets/branded_loading_indicator.dart';
import '../widgets/location_guard.dart';

enum AppLaunchState {
  ready,
  setupRequired,
  databaseSetupRequired,
  initializationError,
  noInternet,
}

class AppBootstrapScreen extends StatefulWidget {
  const AppBootstrapScreen({super.key});

  @override
  State<AppBootstrapScreen> createState() => _AppBootstrapScreenState();
}

class _AppBootstrapScreenState extends State<AppBootstrapScreen> {
  late final Future<AppLaunchState> _launchFuture = _initializeApp();
  String? _initErrorMessage;

  bool _isMissingSchemaError(PostgrestException error) {
    return error.code == '42P01';
  }

  Future<AppLaunchState> _initializeApp() async {
    final isSupabaseConfigured =
        AppConstants.supabaseUrl.isNotEmpty &&
        AppConstants.supabaseUrl.contains('supabase.co') &&
        AppConstants.supabaseAnonKey.length > 40;

    if (!isSupabaseConfigured) {
      return AppLaunchState.setupRequired;
    }

    try {
      NotificationService.instance.init();
      await Supabase.instance.client
          .from(AppConstants.productsTable)
          .select('id')
          .limit(1);
      return AppLaunchState.ready;
    } on PostgrestException catch (error) {
      if (_isMissingSchemaError(error)) {
        return AppLaunchState.databaseSetupRequired;
      }
      _initErrorMessage = error.message;
      return AppLaunchState.initializationError;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socketexception') ||
          errorStr.contains('host lookup') ||
          errorStr.contains('connection failed') ||
          errorStr.contains('network_error')) {
        return AppLaunchState.noInternet;
      }

      debugPrint('Supabase Initialization Error: $e');
      _initErrorMessage = e.toString();
      return AppLaunchState.initializationError;
    }
  }

  void _handleRetry() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AppBootstrapScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppLaunchState>(
      future: _launchFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StartupErrorScreen(
            message: snapshot.error.toString(),
            onRetry: _handleRetry,
          );
        }

        if (!snapshot.hasData) {
          return const StartupLoadingScreen();
        }

        final state = snapshot.data!;
        if (state == AppLaunchState.ready) return const AuthRouter();

        if (state == AppLaunchState.noInternet) {
          return StartupErrorScreen(
            message:
                'No internet available. Please connect to the internet to use the app.',
            isNetworkError: true,
            onRetry: _handleRetry,
          );
        }

        if (state == AppLaunchState.initializationError) {
          return StartupErrorScreen(
            message: _initErrorMessage ?? 'Unknown connection error',
            onRetry: _handleRetry,
          );
        }

        return state == AppLaunchState.setupRequired
            ? const SetupRequiredScreen()
            : const DatabaseSetupRequiredScreen();
      },
    );
  }
}

class _RoleLookupFailureScreen extends StatelessWidget {
  final Future<void> Function() onSignOut;

  const _RoleLookupFailureScreen({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8EF),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.security_rounded,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Account verification failed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'We could not verify your role in the database. Sign out and sign in again after the backend is restored.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => unawaited(onSignOut()),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Sign out and retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthRouter extends StatefulWidget {
  const AuthRouter({super.key});

  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  String? _loadedUserId;
  Future<Map<String, dynamic>?>? _roleFuture;
  bool _recoveringFromRoleLookupFailure = false;
  bool _announcedSignupConfirmation = false;
  bool _showedUnconfirmedSessionWarning = false;

  Future<void> _ensureCurrentUserProfile() async {
    try {
      await Supabase.instance.client.rpc(
        AppConstants.ensureCurrentUserProfileRpc,
      );
    } catch (error) {
      debugPrint('User profile sync skipped: $error');
    }
  }

  Future<Map<String, dynamic>?> _loadRole(String userId) async {
    await _ensureCurrentUserProfile();

    try {
      final value = await Supabase.instance.client
          .from(AppConstants.usersTable)
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (value == null) {
        final currentEmail = Supabase.instance.client.auth.currentUser?.email
            ?.trim()
            .toLowerCase();
        if (currentEmail == 'paffpro01@gmail.com') {
          return <String, dynamic>{'role': 'admin'};
        }
        return <String, dynamic>{'role': 'client'};
      }

      return Map<String, dynamic>.from(value as Map);
    } catch (e) {
      debugPrint('Error loading role: $e');
      final currentEmail = Supabase.instance.client.auth.currentUser?.email
          ?.trim()
          .toLowerCase();
      if (currentEmail == 'paffpro01@gmail.com') {
        return <String, dynamic>{'role': 'admin'};
      }
      return <String, dynamic>{'role': 'client'};
    }
  }

  void _ensureRoleFuture(String userId) {
    if (_loadedUserId == userId && _roleFuture != null) {
      return;
    }

    _loadedUserId = userId;
    _roleFuture = _loadRole(userId);
  }

  void _resetRoleLookupState() {
    if (!mounted) return;
    setState(() {
      _loadedUserId = null;
      _roleFuture = null;
      _recoveringFromRoleLookupFailure = false;
    });
  }

  Future<void> _signOutAndResetRoleLookupState() async {
    if (_recoveringFromRoleLookupFailure) {
      return;
    }

    _recoveringFromRoleLookupFailure = true;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('Role lookup sign-out skipped: $error');
    }

    _resetRoleLookupState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final authEvent = snapshot.data?.event;
        if (authEvent == AuthChangeEvent.passwordRecovery ||
            AuthFlowState.instance.isPasswordRecoveryPending) {
          return const PasswordResetScreen();
        }

        final session = Supabase.instance.client.auth.currentSession;
        final currentUser = session?.user;
        if (currentUser != null && currentUser.emailConfirmedAt == null) {
          if (!_showedUnconfirmedSessionWarning) {
            _showedUnconfirmedSessionWarning = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              NotificationService.instance.messengerKey.currentState
                  ?.showSnackBar(
                    const SnackBar(
                      content: Text('Confirm your email first, then log in.'),
                    ),
                  );
            });
            unawaited(Supabase.instance.client.auth.signOut());
          }
          return const LoginScreen();
        }

        if (AuthFlowState.instance.isSignupConfirmationPending &&
            !_announcedSignupConfirmation) {
          _announcedSignupConfirmation = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            NotificationService.instance.messengerKey.currentState
                ?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Email confirmed successfully. You can log in now.',
                    ),
                  ),
                );
            AuthFlowState.instance.clearSignupConfirmationPending();
          });
        }

        if (session == null) {
          _loadedUserId = null;
          _roleFuture = null;
          _recoveringFromRoleLookupFailure = false;
          _announcedSignupConfirmation = false;
          _showedUnconfirmedSessionWarning = false;
          return GuestBrowseScreen(
            onLoginTapped: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          );
        }

        _ensureRoleFuture(session.user.id);

        return FutureBuilder<Map<String, dynamic>?>(
          future: _roleFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFFF5F8EF),
                body: Center(
                  child: BrandedLoadingIndicator(
                    size: 86,
                    logoSize: 42,
                    label: 'Loading your PAFLY account...',
                  ),
                ),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              return _RoleLookupFailureScreen(
                onSignOut: _signOutAndResetRoleLookupState,
              );
            }

            final role = snapshot.data?['role'];

            if (role == 'admin') {
              unawaited(
                PushNotificationService.instance.registerAdminDevice(
                  session.user.id,
                ),
              );
              return const LocationGuard(child: AdminControlScreen());
            } else {
              unawaited(
                PushNotificationService.instance.registerClientDevice(
                  session.user.id,
                ),
              );
              return const LocationGuard(child: ClientDashboard());
            }
          },
        );
      },
    );
  }
}
