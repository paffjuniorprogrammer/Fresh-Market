import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:potato_app/models/business_profile.dart';
import 'package:potato_app/utils/constants.dart';

enum LiveLocationTrackingStatus {
  idle,
  tracking,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  error,
  loading,
}

class LiveLocationTrackingState {
  final LiveLocationTrackingStatus status;
  final String message;
  final DateTime? lastUpdatedAt;

  const LiveLocationTrackingState({
    required this.status,
    required this.message,
    this.lastUpdatedAt,
  });

  bool get isTracking => status == LiveLocationTrackingStatus.tracking;

  static const idle = LiveLocationTrackingState(
    status: LiveLocationTrackingStatus.idle,
    message: 'Live tracking is not active.',
  );
}

class LiveLocationService {
  LiveLocationService._();

  static final LiveLocationService instance = LiveLocationService._();

  final ValueNotifier<LiveLocationTrackingState> trackingState =
      ValueNotifier<LiveLocationTrackingState>(LiveLocationTrackingState.idle);
  final ValueNotifier<Position?> currentPosition = ValueNotifier<Position?>(
    null,
  );
  final ValueNotifier<String?> currentReadableLocation = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<BusinessProfile?> businessProfile =
      ValueNotifier<BusinessProfile?>(null);

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSubscription;
  String? _userId;
  String _customerName = '';
  String _phone = '';
  String _locationLabel = '';
  String? _lastResolvedLocationKey;

  Future<void> startTracking({
    required String userId,
    required String customerName,
    required String phone,
    required String locationLabel,
  }) async {
    _userId = userId;
    _customerName = customerName;
    _phone = phone;
    _locationLabel = locationLabel;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      trackingState.value = const LiveLocationTrackingState(
        status: LiveLocationTrackingStatus.serviceDisabled,
        message:
            'Location service is off. Turn on GPS to share your live delivery position.',
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      trackingState.value = const LiveLocationTrackingState(
        status: LiveLocationTrackingStatus.permissionDenied,
        message: 'Location permission was denied.',
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      trackingState.value = const LiveLocationTrackingState(
        status: LiveLocationTrackingStatus.permissionDeniedForever,
        message:
            'Location permission is permanently denied. Enable it from app settings.',
      );
      return;
    }

    await _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          _sendLocation,
          onError: (Object error) {
            trackingState.value = LiveLocationTrackingState(
              status: LiveLocationTrackingStatus.error,
              message: 'Live tracking failed: $error',
              lastUpdatedAt: trackingState.value.lastUpdatedAt,
            );
          },
        );

    try {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _sendLocation(currentPosition);
    } catch (_) {
      trackingState.value = const LiveLocationTrackingState(
        status: LiveLocationTrackingStatus.tracking,
        message: 'Waiting for your next live location update...',
      );
    }
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    currentPosition.value = null;
    currentReadableLocation.value = null;
    _lastResolvedLocationKey = null;
    trackingState.value = LiveLocationTrackingState.idle;
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  void _setupBusinessProfileListener() {
    _profileSubscription?.cancel();
    _profileSubscription = Supabase.instance.client
        .from(AppConstants.businessProfileTable)
        .stream(primaryKey: ['id'])
        .eq('id', 1)
        .listen((data) {
          if (data.isNotEmpty) {
            final nextProfile = BusinessProfile.fromJson(data.first);
            businessProfile.value = nextProfile;
          }
        });
  }

  Future<BusinessProfile> loadBusinessProfile({
    bool forceRefresh = false,
  }) async {
    if (_profileSubscription == null) {
      _setupBusinessProfileListener();
    }
    if (!forceRefresh && businessProfile.value != null) {
      return businessProfile.value!;
    }

    try {
      final response = await Supabase.instance.client
          .from(AppConstants.businessProfileTable)
          .select()
          .eq('id', 1)
          .maybeSingle();

      final nextProfile = response == null
          ? BusinessProfile.fallback()
          : BusinessProfile.fromJson(Map<String, dynamic>.from(response));
      businessProfile.value = nextProfile;
      return nextProfile;
    } catch (_) {
      final fallback = BusinessProfile.fallback();
      businessProfile.value = fallback;
      return fallback;
    }
  }

  Future<double?> getDistanceToStoreKm() async {
    try {
      final profile = await loadBusinessProfile(forceRefresh: false);
      return getDistanceToCoordinates(
        latitude: profile.latitude ?? AppConstants.paflyLatitude,
        longitude: profile.longitude ?? AppConstants.paflyLongitude,
      );
    } catch (_) {
      return null;
    }
  }

  Future<double?> getDistanceToCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    try {
      Position? position = currentPosition.value;
      if (position == null) {
        position = await Geolocator.getLastKnownPosition();
        position ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        currentPosition.value = position;
      }

      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        latitude,
        longitude,
      );
      return distanceMeters / 1000;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistLocation(
    Position position, {
    required String locationLabel,
  }) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    await Supabase.instance.client.from(AppConstants.locationsTable).upsert({
      'user_id': userId,
      'customer_name': _customerName,
      'phone': _phone,
      'location_label': locationLabel,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<void> _sendLocation(Position position) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    currentPosition.value = position;
    currentReadableLocation.value = null; // Trigger "Locating..." state in UI
    await _persistLocation(position, locationLabel: _locationLabel);
    unawaited(_resolveReadableLocation(position));

    trackingState.value = LiveLocationTrackingState(
      status: LiveLocationTrackingStatus.tracking,
      message:
          'Your live position is being shared with '
          '${businessProfile.value?.businessName ?? AppConstants.defaultBusinessName} admin.',
      lastUpdatedAt: DateTime.now(),
    );
  }

  Future<void> _resolveReadableLocation(Position position) async {
    final locationKey =
        '${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)}';
    if (_lastResolvedLocationKey == locationKey &&
        currentReadableLocation.value != null &&
        currentReadableLocation.value!.isNotEmpty) {
      return;
    }

    _lastResolvedLocationKey = locationKey;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });

      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'PAFLY/1.0',
        },
      );

      if (response.statusCode != 200) {
        currentReadableLocation.value =
            'Live GPS ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        await _persistLocation(
          position,
          locationLabel: currentReadableLocation.value ?? _locationLabel,
        );
        return;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final address = (payload['address'] as Map?)?.cast<String, dynamic>();
      final displayName = _buildReadableAddress(payload, address);
      currentReadableLocation.value = displayName.isNotEmpty
          ? displayName
          : 'Live GPS ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      await _persistLocation(
        position,
        locationLabel: currentReadableLocation.value ?? _locationLabel,
      );
    } catch (_) {
      currentReadableLocation.value =
          'Live GPS ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      await _persistLocation(
        position,
        locationLabel: currentReadableLocation.value ?? _locationLabel,
      );
    }
  }

  String _buildReadableAddress(
    Map<String, dynamic> payload,
    Map<String, dynamic>? address,
  ) {
    final parts = <String>[
      _pick(address, const ['house_number', 'road', 'pedestrian', 'footway']),
      _pick(address, const ['suburb', 'quarter', 'neighbourhood']),
      _pick(address, const ['city', 'town', 'village', 'municipality']),
      _pick(address, const ['state', 'province']),
      _pick(address, const ['country']),
    ].where((part) => part.isNotEmpty).toList();

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    return payload['display_name']?.toString().trim() ?? '';
  }

  String _pick(Map<String, dynamic>? address, List<String> keys) {
    if (address == null) return '';
    for (final key in keys) {
      final value = address[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }
}
