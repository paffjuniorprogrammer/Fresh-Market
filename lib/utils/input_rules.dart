import 'package:flutter/services.dart';

class InputRules {
  static final digitsOnly = FilteringTextInputFormatter.digitsOnly;
  static final textOnly = FilteringTextInputFormatter.allow(
    RegExp(r"[A-Za-zÀ-ÿ' -]"),
  );
  static final decimalOnly = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9.]'),
  );

  static String? validateTextOnly(String? value, {required String fieldName}) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return 'Required';
    if (RegExp(r'\d').hasMatch(input)) {
      return '$fieldName cannot contain numbers';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return 'Required';
    if (!RegExp(r'^\d{10,15}$').hasMatch(input)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? validateStrongPassword(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return 'Required';

    final issues = <String>[];

    if (input.length < 8) {
      issues.add('at least 8 characters');
    }
    if (!RegExp(r'[A-Z]').hasMatch(input)) {
      issues.add('one uppercase letter');
    }
    if (!RegExp(r'[a-z]').hasMatch(input)) {
      issues.add('one lowercase letter');
    }
    if (!RegExp(r'\d').hasMatch(input)) {
      issues.add('one number');
    }

    final weakPasswords = <String>{
      '12345678',
      '123456789',
      'password',
      'password123',
      'admin123',
      'qwerty123',
      '11111111',
      '00000000',
    };
    if (weakPasswords.contains(input.toLowerCase())) {
      return 'That password is too common. Use a stronger one.';
    }

    if (issues.isEmpty) {
      return null;
    }

    if (issues.length == 1) {
      return 'Password must include ${issues.first}.';
    }

    final lastIssue = issues.removeLast();
    return 'Password must include ${issues.join(', ')}, and $lastIssue.';
  }
}
