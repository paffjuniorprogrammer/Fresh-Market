import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/screens/login_screen.dart';
import 'package:potato_app/services/ui_service.dart';
import 'package:potato_app/utils/supabase_errors.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';

class ConfirmAccountScreen extends StatefulWidget {
  final String email;
  final String? phone;
  final String title;
  final String message;
  final String instruction;
  final String buttonLabel;

  const ConfirmAccountScreen({
    super.key,
    required this.email,
    this.phone,
    this.title = 'Confirm Your Email',
    this.message =
        'Confirm your email first before you can log in or reset your password.',
    this.instruction =
        'Open the confirmation email, tap the link, then come back and log in. If nothing arrives, check spam and use the resend button below.',
    this.buttonLabel = 'Back to Login',
  });

  @override
  State<ConfirmAccountScreen> createState() => _ConfirmAccountScreenState();
}

class _ConfirmAccountScreenState extends State<ConfirmAccountScreen> {
  bool _isResending = false;

  Future<void> _resendConfirmationEmail() async {
    if (_isResending) return;

    setState(() => _isResending = true);
    try {
      await Supabase.instance.client.auth.resend(
        email: widget.email,
        type: OtpType.signup,
        emailRedirectTo: AppConstants.authConfirmationRedirectUrl,
      );

      if (!mounted) return;
      PotatoNotification.show(
        context,
        message:
            'Confirmation email sent again. Check your inbox and spam folder.',
        type: PotatoNotificationType.success,
      );
    } on AuthException catch (e) {
      if (mounted) {
        PotatoNotification.show(
          context,
          message: friendlyAuthErrorMessage(
            e,
            fallbackMessage:
                'We could not resend the confirmation email. Please try again.',
          ),
          type: PotatoNotificationType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        PotatoNotification.show(
          context,
          message:
              'We could not resend the confirmation email. Please try again.',
          type: PotatoNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone?.trim() ?? '';
    final showPhone = phone.isNotEmpty;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0F4FF), Color(0xFFE0E7FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
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
                      const Icon(
                        Icons.mark_email_read_rounded,
                        size: 64,
                        color: AppUi.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppUi.dark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.message,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      _InfoTile(label: 'Email', value: widget.email),
                      if (showPhone) ...[
                        const SizedBox(height: 10),
                        _InfoTile(label: 'Phone', value: phone),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppUi.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          widget.instruction,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 24),
                      const Text(
                        'Did not get the email?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppUi.dark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1. Check your spam/junk folder.\n'
                        '2. Verify your email address is correct.\n'
                        '3. Wait 5 minutes before resending.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _isResending
                              ? null
                              : _resendConfirmationEmail,
                          icon: _isResending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.mark_email_unread_outlined),
                          label: Text(
                            _isResending
                                ? 'Resending...'
                                : 'Resend confirmation email',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppUi.primary,
                            side: const BorderSide(color: AppUi.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppUi.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: Text(
                            widget.buttonLabel,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
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
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

