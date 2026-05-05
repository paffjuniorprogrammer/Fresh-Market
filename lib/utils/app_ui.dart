import 'package:flutter/material.dart';

class AppUi {
  static const primary = Color(0xFF1B5E20); // Deeper green
  static const dark = Color(0xFF1A1C1E);
  static const secondary = Color(0xFF2E7D32);
  static const accent = Color(0xFFD4AF37); // Subtle gold accent
  static const background = Color(0xFFF8F9FA);
  static const surface = Colors.white;
  static const error = Color(0xFFBA1A1A);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF9A825);
  
  static const cardShadow = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];
  
  static final cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(20),
    boxShadow: cardShadow,
    border: Border.all(color: Colors.grey.shade100),
  );
}
