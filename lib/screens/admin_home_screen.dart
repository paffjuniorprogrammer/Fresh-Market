import 'package:flutter/material.dart';

import 'package:potato_app/screens/admin_control_screen.dart';

/// Legacy compatibility entry point.
///
/// The app routes admins to [AdminControlScreen]. Keep this wrapper so any
/// older imports still land on the real dashboard.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminControlScreen();
  }
}
