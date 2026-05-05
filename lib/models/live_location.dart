class LiveLocation {
  final String userId;
  final String customerName;
  final String phone;
  final String locationLabel;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  const LiveLocation({
    required this.userId,
    required this.customerName,
    required this.phone,
    required this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  bool get isFresh => DateTime.now().difference(updatedAt).inMinutes < 5;

  factory LiveLocation.fromJson(Map<String, dynamic> json) {
    return LiveLocation(
      userId: '${json['user_id'] ?? ''}',
      customerName: '${json['customer_name'] ?? 'Client'}',
      phone: '${json['phone'] ?? ''}',
      locationLabel: '${json['location_label'] ?? ''}',
      latitude: (json['latitude'] as num? ?? 0).toDouble(),
      longitude: (json['longitude'] as num? ?? 0).toDouble(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse('${json['updated_at']}')
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
