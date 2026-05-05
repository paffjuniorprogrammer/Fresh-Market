import 'package:potato_app/utils/constants.dart';

class BusinessProfile {
  final int id;
  final String businessName;
  final String email;
  final String phone;
  final String location;
  final String addressLine;
  final double? latitude;
  final double? longitude;
  final String momoPayMerchantCode;
  final double deliveryBaseFee;
  final double deliveryDistanceThresholdKm;
  final double deliveryExtraKmFee;
  final double deliveryOrderThreshold;
  final double deliveryExtraOrderPercent;
  final DateTime? updatedAt;

  const BusinessProfile({
    required this.id,
    required this.businessName,
    required this.email,
    required this.phone,
    required this.location,
    required this.addressLine,
    this.latitude,
    this.longitude,
    this.momoPayMerchantCode = '',
    this.deliveryBaseFee = 500,
    this.deliveryDistanceThresholdKm = 4,
    this.deliveryExtraKmFee = 200,
    this.deliveryOrderThreshold = 20000,
    this.deliveryExtraOrderPercent = 0.20,
    this.updatedAt,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    final latitudeValue = json['latitude'];
    final longitudeValue = json['longitude'];
    return BusinessProfile(
      id: (json['id'] as num?)?.toInt() ?? 1,
      businessName: json['business_name']?.toString().trim().isNotEmpty == true
          ? json['business_name'].toString().trim()
          : AppConstants.defaultBusinessName,
      email: json['email']?.toString().trim() ?? '',
      phone: json['phone']?.toString().trim() ?? '',
      location: json['location']?.toString().trim() ?? '',
      addressLine: json['address_line']?.toString().trim() ?? '',
      latitude: latitudeValue == null
          ? null
          : (latitudeValue as num?)?.toDouble(),
      longitude: longitudeValue == null
          ? null
          : (longitudeValue as num?)?.toDouble(),
      momoPayMerchantCode: json['momo_pay_merchant_code']?.toString().trim() ?? '',
      deliveryBaseFee: (json['delivery_base_fee'] as num?)?.toDouble() ?? 500,
      deliveryDistanceThresholdKm:
          (json['delivery_distance_threshold'] as num?)?.toDouble() ?? 4,
      deliveryExtraKmFee:
          (json['delivery_extra_km_fee'] as num?)?.toDouble() ?? 200,
      deliveryOrderThreshold:
          (json['delivery_order_threshold'] as num?)?.toDouble() ??
          AppConstants.deliveryOrderThreshold,
      deliveryExtraOrderPercent:
          (json['delivery_extra_order_percent'] as num?)?.toDouble() ??
          AppConstants.deliveryExtraOrderPercent,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse('${json['updated_at']}')
          : null,
    );
  }

  factory BusinessProfile.fallback() {
    return const BusinessProfile(
      id: 1,
      businessName: AppConstants.defaultBusinessName,
      email: '',
      phone: '',
      location: '',
      addressLine: '',
      latitude: AppConstants.freshMarketLatitude,
      longitude: AppConstants.freshMarketLongitude,
      momoPayMerchantCode: '',
      deliveryBaseFee: 500,
      deliveryDistanceThresholdKm: 4,
      deliveryExtraKmFee: 200,
      deliveryOrderThreshold: AppConstants.deliveryOrderThreshold,
      deliveryExtraOrderPercent: AppConstants.deliveryExtraOrderPercent,
    );
  }

  bool get hasCoordinates => latitude != null && longitude != null;

  String get contactSummary {
    final parts = [phone.trim(), email.trim()].where((item) => item.isNotEmpty);
    return parts.join(' | ');
  }

  String get addressSummary {
    final parts = [
      addressLine.trim(),
      location.trim(),
    ].where((item) => item.isNotEmpty);
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_name': businessName.trim().isEmpty
          ? AppConstants.defaultBusinessName
          : businessName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'location': location.trim(),
      'address_line': addressLine.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'momo_pay_merchant_code': momoPayMerchantCode,
      'delivery_base_fee': deliveryBaseFee,
      'delivery_distance_threshold': deliveryDistanceThresholdKm,
      'delivery_extra_km_fee': deliveryExtraKmFee,
      'delivery_order_threshold': deliveryOrderThreshold,
      'delivery_extra_order_percent': deliveryExtraOrderPercent,
    };
  }
}
