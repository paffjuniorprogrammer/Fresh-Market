import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:potato_app/services/live_location_service.dart';
import 'package:potato_app/widgets/branded_loading_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationGuard extends StatefulWidget {
  final Widget child;

  const LocationGuard({super.key, required this.child});

  @override
  State<LocationGuard> createState() => _LocationGuardState();
}

class _LocationGuardState extends State<LocationGuard> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isChecking = true);
    
    // Attempt to start tracking immediately if we have permissions
    await LiveLocationService.instance.startTracking(
      userId: user.id,
      customerName: user.userMetadata?['name'] ?? 'User',
      phone: user.userMetadata?['phone'] ?? '',
      locationLabel: 'Live Location',
    );

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveLocationTrackingState>(
      valueListenable: LiveLocationService.instance.trackingState,
      builder: (context, state, _) {
        if (_isChecking) {
          return const Scaffold(
            body: Center(
              child: BrandedLoadingIndicator(
                size: 80,
                label: 'Checking location access...',
              ),
            ),
          );
        }

        if (state.status == LiveLocationTrackingStatus.tracking) {
          return widget.child;
        }

        return _LocationRequiredScreen(
          state: state,
          onRetry: _initLocation,
        );
      },
    );
  }
}

class _LocationRequiredScreen extends StatelessWidget {
  final LiveLocationTrackingState state;
  final VoidCallback onRetry;

  const _LocationRequiredScreen({
    required this.state,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPermanentlyDenied =
        state.status == LiveLocationTrackingStatus.permissionDeniedForever;
    final bool isServiceDisabled =
        state.status == LiveLocationTrackingStatus.serviceDisabled;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8EF),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13), // ~0.05 opacity
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 64,
                  color: Color(0xFF0052CC),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Location Access Required',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1C1E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'To continue using PAFLY, we need your real-time location to ensure accurate delivery and service in your area.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (state.message.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.message,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: isPermanentlyDenied
                      ? () => Geolocator.openAppSettings()
                      : isServiceDisabled
                          ? () => Geolocator.openLocationSettings()
                          : onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0052CC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    isPermanentlyDenied || isServiceDisabled
                        ? Icons.settings_rounded
                        : Icons.my_location_rounded,
                  ),
                  label: Text(
                    isPermanentlyDenied
                        ? 'Open App Settings'
                        : isServiceDisabled
                            ? 'Enable Location Service'
                            : 'Share My Location',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (isPermanentlyDenied || isServiceDisabled) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('I have enabled it, try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
