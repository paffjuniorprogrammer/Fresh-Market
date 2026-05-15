import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/screens/auth_router.dart';
import 'package:potato_app/screens/confirm_account_screen.dart';
import 'package:potato_app/screens/register_screen.dart';
import 'package:potato_app/services/ui_service.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/utils/supabase_errors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _showAuthMessage(String message) {
    if (!mounted) return;
    PotatoNotification.show(
      context,
      message: message,
      type: PotatoNotificationType.error,
    );
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      _showAuthMessage('Enter your email and password to continue.');
      return;
    }

    if (!identifier.contains('@')) {
      _showAuthMessage('Enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: identifier,
        password: password,
      );

      final signedInUser = res.user;
      if (signedInUser != null && signedInUser.emailConfirmedAt == null) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ConfirmAccountScreen(email: identifier, phone: null),
          ),
        );
        return;
      }

      if (signedInUser != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AppBootstrapScreen()),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        if (isEmailNotConfirmedAuthError(e)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ConfirmAccountScreen(email: identifier, phone: null),
            ),
          );
          return;
        }
        _showAuthMessage(_describeAuthError(e));
      }
    } catch (_) {
      if (mounted) {
        _showAuthMessage('Login could not be completed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(
      text: _identifierController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'you@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, emailController.text.trim()),
            child: const Text('Send reset link'),
          ),
        ],
      ),
    );

    emailController.dispose();

    if (!mounted || email == null || email.isEmpty) {
      return;
    }

    if (!email.contains('@')) {
      _showAuthMessage('Enter a valid email address.');
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: AppConstants.authRecoveryRedirectUrl,
      );
      if (!mounted) return;
      PotatoNotification.show(
        context,
        message: 'Password reset email sent. Check your inbox.',
        type: PotatoNotificationType.success,
      );
    } on AuthException catch (e) {
      if (mounted) {
        _showAuthMessage(_describeAuthError(e));
      }
    } catch (_) {
      if (mounted) {
        _showAuthMessage(
          'Password reset could not be completed. Please try again.',
        );
      }
    }
  }

  String _describeAuthError(AuthException e) {
    return friendlyAuthErrorMessage(
      e,
      fallbackMessage:
          'We could not sign you in. Check your email and password, then try again.',
    );
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppUi.primary),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.88),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppUi.primary, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0F4FF), Color(0xFFE0E7FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: 0.10,
                    child: Image.asset(
                      'assets/logo.png',
                      width: 430,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/logo.png',
                                width: 64,
                                height: 64,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'PAFLY',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppUi.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: AppUi.dark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Login to continue shopping fresh groceries.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _identifierController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _fieldDecoration(
                              hint: 'Email address',
                              icon: Icons.email_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: _fieldDecoration(
                              hint: 'Password',
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _forgotPassword,
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppUi.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppUi.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _openRegister,
                            child: Text.rich(
                              TextSpan(
                                text: 'Don\'t have an account? ',
                                style: TextStyle(color: Colors.grey.shade600),
                                children: const [
                                  TextSpan(
                                    text: 'Sign Up',
                                    style: TextStyle(
                                      color: AppUi.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
