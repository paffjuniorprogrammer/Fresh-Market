import 'package:flutter/material.dart';
import '../utils/app_ui.dart';
import '../widgets/state_message_card.dart';
import '../widgets/branded_loading_indicator.dart';

class StartupLoadingScreen extends StatelessWidget {
  const StartupLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F8EF),
      body: Center(
        child: BrandedLoadingIndicator(
          size: 94,
          logoSize: 48,
          label: 'Welcome to PAFLY...',
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  final String message;
  final bool isNetworkError;
  final VoidCallback onRetry;

  const StartupErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
    this.isNetworkError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNetworkError ? 'No Internet' : 'Connection Error'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNetworkError ? Icons.wifi_off : Icons.error_outline,
                size: 64,
                color: isNetworkError ? Colors.orange : Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                isNetworkError
                    ? 'No Internet Connection'
                    : 'Supabase failed to initialize:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supabase Setup')),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_input_component, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Invalid Supabase Key',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The Supabase Anon Key provided is too short. '
                  'Please find the "anon public" key in your Supabase '
                  'Settings -> API dashboard. It should be a long string (JWT).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Currently using: sb_publishable_... (This looks like a placeholder)',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DatabaseSetupRequiredScreen extends StatelessWidget {
  const DatabaseSetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PAFLY Setup')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: StateMessageCard(
              icon: Icons.storage_rounded,
              title: 'Database setup required',
              message:
                  'Supabase initialized successfully, but the app database has '
                  'not been created yet. The customer, order, and stock tables '
                  'required by the app are still missing.',
              details: const [
                'Open Supabase -> SQL Editor.',
                'Run the SQL in `supabase/schema.sql` from this project.',
                'That script creates the products, customers, orders, debt view, order RPC, starter rows, the products image bucket, and the required access policies.',
                'Restart the app after the SQL finishes.',
              ],
            ),
          ),
        ),
      ),
    );
  }
}
