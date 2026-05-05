import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potato_app/screens/setup_screens.dart';

void main() {
  testWidgets('Setup screen shows Supabase guidance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SetupRequiredScreen()),
    );

    expect(find.text('Supabase Setup'), findsOneWidget);
    expect(find.text('Invalid Supabase Key'), findsOneWidget);
  });
}
