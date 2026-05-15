import 'package:flutter/material.dart';

class AppUi {
  static const primary = Color(0xFF0052CC); // PAFLY vibrant blue
  static const dark = Color(0xFF1A1C1E);
  static const secondary = Color(0xFF3B82F6); // Lighter blue
  static const accent = Color(0xFF00D4FF); // Cyan accent
  static const background = Color(0xFFF0F4FF); // Light blue background
  static const surface = Colors.white;
  static const error = Color(0xFFBA1A1A);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF9A825);

  static const cardShadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, 4)),
  ];

  static final cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(20),
    boxShadow: cardShadow,
    border: Border.all(color: Colors.grey.shade100),
  );
}
