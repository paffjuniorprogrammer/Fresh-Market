import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/screens/auth_router.dart';
import 'package:potato_app/screens/confirm_account_screen.dart';
import 'package:potato_app/services/ui_service.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/utils/input_rules.dart';
import 'package:potato_app/utils/supabase_errors.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _clientAccountType = 'client';

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final emailInput = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final location = _locationController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty ||
        emailInput.isEmpty ||
        phone.isEmpty ||
        location.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      PotatoNotification.show(
        context,
        message: 'Please fill name, email, phone, location, and password.',
        type: PotatoNotificationType.error,
      );
      return;
    }

    if (!emailInput.contains('@')) {
      PotatoNotification.show(
        context,
        message: 'Enter a valid email address.',
        type: PotatoNotificationType.error,
      );
      return;
    }

    final passwordError = InputRules.validateStrongPassword(password);
    if (passwordError != null) {
      PotatoNotification.show(
        context,
        message: passwordError,
        type: PotatoNotificationType.error,
      );
      return;
    }

    if (password != confirmPassword) {
      PotatoNotification.show(
        context,
        message: 'Passwords do not match',
        type: PotatoNotificationType.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = emailInput;
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        emailRedirectTo: AppConstants.authConfirmationRedirectUrl,
        password: password,
        data: {
          'name': name,
          'phone': phone,
          'email': email,
          'location': location,
          'requested_role': _clientAccountType,
          'account_type': _clientAccountType,
        },
      );

      if (!mounted) return;

      final createdUser = res.user;
      final identities = createdUser?.identities ?? [];
      debugPrint('Registration successful. User ID: ${createdUser?.id}');
      debugPrint('Identities found: ${identities.length}');
      final isEmailConfirmed = createdUser?.emailConfirmedAt != null;

      if (createdUser != null && !isEmailConfirmed) {
        if (res.session != null) {
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConfirmAccountScreen(email: email, phone: phone),
          ),
        );
      } else if (res.session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AppBootstrapScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConfirmAccountScreen(email: email, phone: phone),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        PotatoNotification.show(
          context,
          message: friendlyAuthErrorMessage(
            e,
            fallbackMessage:
                'We could not create your account. Please check your details and try again.',
          ),
          type: PotatoNotificationType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        PotatoNotification.show(
          context,
          message: 'We could not create your account. Please try again.',
          type: PotatoNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();

    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                      width: 450,
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
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 420;
                              if (isCompact) {
                                return Column(
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFF0F4FF,
                                          ),
                                          foregroundColor: AppUi.dark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/logo.png',
                                          width: 54,
                                          height: 54,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 8),
                                        const Flexible(
                                          child: Text(
                                            'PAFLY',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: AppUi.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFF0F4FF),
                                      foregroundColor: AppUi.dark,
                                    ),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      Image.asset(
                                        'assets/logo.png',
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.contain,
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'PAFLY',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: AppUi.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  const SizedBox(width: 48),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Create an Account',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: AppUi.dark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _nameController,
                            inputFormatters: [InputRules.textOnly],
                            decoration: _fieldDecoration(
                              hint: 'Full Name',
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _fieldDecoration(
                              hint: 'Email address',
                              icon: Icons.email_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _fieldDecoration(
                              hint: 'Phone number for delivery',
                              icon: Icons.phone_rounded,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _locationController,
                            decoration: _fieldDecoration(
                              hint: 'Delivery Location',
                              icon: Icons.location_on_outlined,
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
                          TextField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: _fieldDecoration(
                              hint: 'Confirm Password',
                              icon: Icons.lock_reset_rounded,
                              suffix: IconButton(
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _register,
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
                                      'Sign Up',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text.rich(
                              TextSpan(
                                text: 'Already have an account? ',
                                style: TextStyle(color: Colors.grey.shade600),
                                children: const [
                                  TextSpan(
                                    text: 'Login',
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
