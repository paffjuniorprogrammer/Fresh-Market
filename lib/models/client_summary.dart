class ClientSummary {
  final String? clientId;
  final String clientName;
  final String phone;
  final String location;
  final double accountDiscountPercentage;
  final int ordersCount;
  final double totalSpent;
  final double totalPaid;
  final double totalDebt;
  final DateTime? lastOrderAt;

  const ClientSummary({
    this.clientId,
    required this.clientName,
    required this.phone,
    required this.location,
    required this.accountDiscountPercentage,
    required this.ordersCount,
    required this.totalSpent,
    required this.totalPaid,
    required this.totalDebt,
    this.lastOrderAt,
  });

  factory ClientSummary.fromJson(Map<String, dynamic> json) {
    final rawClientId = json['client_id'];
    final clientId = rawClientId == null
        ? null
        : '$rawClientId'.trim();
    return ClientSummary(
      clientId: clientId == null || clientId.isEmpty || clientId == 'null'
          ? null
          : clientId,
      clientName: '${json['customer_name'] ?? json['client_name'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      location: '${json['location'] ?? ''}',
      accountDiscountPercentage:
          (json['account_discount_percentage'] as num? ?? 0).toDouble(),
      ordersCount: (json['orders_count'] as num? ?? 0).toInt(),
      totalSpent: (json['total_spent'] as num? ?? 0).toDouble(),
      totalPaid: (json['total_paid'] as num? ?? 0).toDouble(),
      totalDebt: (json['total_debt'] as num? ?? 0).toDouble(),
      lastOrderAt: json['last_order_at'] != null
          ? DateTime.parse('${json['last_order_at']}')
          : null,
    );
  }
}
