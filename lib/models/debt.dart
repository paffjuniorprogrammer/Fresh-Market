class Debt {
  final String clientName;
  final String phone;
  final String location;
  final String? productId;
  final String productName;
  final double quantityKg;
  final double totalAmount;
  final double paid;
  final double balance;
  final DateTime? createdAt;

  Debt({
    required this.clientName,
    required this.phone,
    required this.location,
    this.productId,
    required this.productName,
    required this.quantityKg,
    required this.totalAmount,
    required this.paid,
    required this.balance,
    this.createdAt,
  });

  factory Debt.fromJson(Map<String, dynamic> json) {
    return Debt(
      clientName: '${json['customer_name'] ?? json['client_name'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      location: '${json['location'] ?? ''}',
      productId: json['product_id']?.toString(),
      productName: '${json['product_name'] ?? ''}',
      quantityKg: (json['quantity_kg'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paid: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }
}
