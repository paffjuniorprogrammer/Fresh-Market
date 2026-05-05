class Shop {
  final String id;
  final String? ownerId;
  final String name;
  final String description;
  final String logoUrl;
  final String coverImageUrl;
  final String phone;
  final String location;
  final String addressLine;
  final double? latitude;
  final double? longitude;
  final String momoPayMerchantCode;
  final String bankAccount;
  final double deliveryBaseFee;
  final double deliveryDistanceThresholdKm;
  final double deliveryExtraKmFee;
  final double deliveryOrderThreshold;
  final double deliveryExtraOrderPercent;
  final double commissionPercent;
  final bool isActive;

  const Shop({
    required this.id,
    this.ownerId,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.coverImageUrl,
    required this.phone,
    required this.location,
    required this.addressLine,
    this.latitude,
    this.longitude,
    required this.momoPayMerchantCode,
    required this.bankAccount,
    required this.deliveryBaseFee,
    required this.deliveryDistanceThresholdKm,
    required this.deliveryExtraKmFee,
    required this.deliveryOrderThreshold,
    required this.deliveryExtraOrderPercent,
    required this.commissionPercent,
    required this.isActive,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: '${json['id']}',
      ownerId: json['owner_id'] as String?,
      name: '${json['name'] ?? 'Fresh Market'}',
      description: '${json['description'] ?? ''}',
      logoUrl: '${json['logo_url'] ?? ''}',
      coverImageUrl: '${json['cover_image_url'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      location: '${json['location'] ?? ''}',
      addressLine: '${json['address_line'] ?? ''}',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      momoPayMerchantCode: '${json['momo_pay_merchant_code'] ?? ''}',
      bankAccount: '${json['bank_account'] ?? ''}',
      deliveryBaseFee: (json['delivery_base_fee'] as num?)?.toDouble() ?? 500,
      deliveryDistanceThresholdKm:
          (json['delivery_distance_threshold'] as num?)?.toDouble() ?? 4,
      deliveryExtraKmFee:
          (json['delivery_extra_km_fee'] as num?)?.toDouble() ?? 200,
      deliveryOrderThreshold:
          (json['delivery_order_threshold'] as num?)?.toDouble() ?? 20000,
      deliveryExtraOrderPercent:
          (json['delivery_extra_order_percent'] as num?)?.toDouble() ?? 0.20,
      commissionPercent: (json['commission_percent'] as num?)?.toDouble() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
