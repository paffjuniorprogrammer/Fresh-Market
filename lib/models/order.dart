class OrderItem {
  final int id;
  final String productId;
  final String productName;
  final double quantityKg;
  final double pricePerKg;
  final String unit;
  final String? productImageUrl;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantityKg,
    required this.pricePerKg,
    this.unit = 'kg',
    this.productImageUrl,
  });

  // alias for admin UI compatibility
  double get quantity => quantityKg;
  double get priceAtOrder => pricePerKg;

  double get totalPrice => quantityKg * pricePerKg;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    // The `products` key may be present when the query joins products(image_url)
    final productData = json['products'] as Map<String, dynamic>?;
    return OrderItem(
      id: (json['id'] ?? 0) as int,
      productId: '${json['product_id'] ?? ''}',
      productName: '${json['product_name'] ?? ''}',
      quantityKg: ((json['quantity_kg'] ?? 0) as num?)?.toDouble() ?? 0,
      pricePerKg: ((json['price_per_kg'] ?? 0) as num?)?.toDouble() ?? 0,
      unit: json['unit'] ?? 'kg',
      productImageUrl: productData?['image_url'] as String?,
    );
  }
}

class Order {
  final int id;
  final String? clientId;
  final String clientName;
  final String phone;
  final String location;
  final String? deliveryLocationLabel;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final DateTime? deliveryPositionUpdatedAt;
  final List<OrderItem> items;
  final String? productId;
  final String? productName;
  final double? quantityKg;
  final double? pricePerKg;
  final String? unit;
  /// After-discount total stored in DB (total_price column)
  final double totalPrice;
  /// Original delivery fee (unchanged even when free_delivery promo applied)
  final double deliveryFee;
  final double paidAmount;
  final bool isCredit;
  final String? paymentMethod;
  final String? cancelReason;
  final String status;
  final DateTime? createdAt;
  /// Amount discounted by promo code (0 if no promo applied)
  final double discountAmount;
  /// Promo code UUID if applied
  final String? promoCodeId;

  Order({
    required this.id,
    this.clientId,
    required this.clientName,
    required this.phone,
    required this.location,
    this.deliveryLocationLabel,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryPositionUpdatedAt,
    required this.items,
    this.productId,
    this.productName,
    this.quantityKg,
    this.pricePerKg,
    this.unit,
    required this.totalPrice,
    required this.deliveryFee,
    required this.paidAmount,
    required this.isCredit,
    this.paymentMethod,
    this.cancelReason,
    this.status = 'Pending',
    this.createdAt,
    this.discountAmount = 0,
    this.promoCodeId,
  });

  /// Balance owed = after-discount total - amount paid
  double get balance {
    final b = totalPrice - paidAmount;
    if (b <= 0) return 0;
    return double.parse(b.toStringAsFixed(2));
  }

  bool get isPaid => paidAmount >= totalPrice;

  String get idStr => id.toString();

  /// Product subtotal before delivery and discount
  double get itemsSubtotal {
    if (items.isNotEmpty) {
      return items.fold(0, (sum, item) => sum + item.totalPrice);
    }
    if (quantityKg != null && pricePerKg != null) {
      return quantityKg! * pricePerKg!;
    }
    // totalPrice is after discount; add discount back then subtract delivery
    return (totalPrice + discountAmount - deliveryFee).clamp(0, double.infinity);
  }

  String get displayProductName {
    if (items.isNotEmpty) {
      if (items.length == 1) return items.first.productName;
      return '${items.first.productName} + ${items.length - 1} more';
    }
    return productName ?? 'Unknown Product';
  }

  double get displayTotalQuantity {
    if (items.isNotEmpty) {
      return items.fold(0, (sum, item) => sum + item.quantityKg);
    }
    return quantityKg ?? 0;
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final List<OrderItem> items = [];
    if (json['order_items'] != null) {
      final List<dynamic> itemsJson = json['order_items'];
      items.addAll(itemsJson.map((i) => OrderItem.fromJson(i)));
    }
    final deliveryLatitudeValue =
        json['o_delivery_latitude'] ?? json['delivery_latitude'];
    final deliveryLongitudeValue =
        json['o_delivery_longitude'] ?? json['delivery_longitude'];
    final deliveryPositionUpdatedAtValue =
        json['o_delivery_position_updated_at'] ??
        json['delivery_position_updated_at'];
    final quantityKgValue = json['o_quantity_kg'] ?? json['quantity_kg'];
    final pricePerKgValue = json['o_price_per_kg'] ?? json['price_per_kg'];

    return Order(
      id: (json['o_id'] ?? json['id'] ?? 0) as int,
      clientId: json['o_client_id'] ?? json['client_id']?.toString(),
      clientName:
          '${json['o_customer_name'] ?? json['customer_name'] ?? json['client_name'] ?? ''}',
      phone: '${json['o_phone'] ?? json['phone'] ?? ''}',
      location: '${json['o_location'] ?? json['location'] ?? ''}',
      deliveryLocationLabel:
          json['o_delivery_location_label'] ?? json['delivery_location_label'],
      deliveryLatitude: deliveryLatitudeValue == null
          ? null
          : (deliveryLatitudeValue as num?)?.toDouble(),
      deliveryLongitude: deliveryLongitudeValue == null
          ? null
          : (deliveryLongitudeValue as num?)?.toDouble(),
      deliveryPositionUpdatedAt: deliveryPositionUpdatedAtValue != null
          ? DateTime.parse('$deliveryPositionUpdatedAtValue')
          : null,
      items: items,
      productId: json['o_product_id'] ?? json['product_id']?.toString(),
      productName: json['o_product_name'] ?? json['product_name'],
      quantityKg: quantityKgValue == null
          ? null
          : (quantityKgValue as num?)?.toDouble(),
      pricePerKg: pricePerKgValue == null
          ? null
          : (pricePerKgValue as num?)?.toDouble(),
      unit: json['o_unit'] ?? json['unit'],
      totalPrice:
          ((json['o_total_price'] ?? json['total_price'] ?? 0) as num?)
              ?.toDouble() ??
          0,
      deliveryFee:
          ((json['o_delivery_fee'] ?? json['delivery_fee'] ?? 0) as num?)
              ?.toDouble() ??
          0,
      paidAmount:
          ((json['o_paid_amount'] ?? json['paid_amount'] ?? 0) as num?)
              ?.toDouble() ??
          0,
      isCredit: (json['o_is_credit'] ?? json['is_credit']) as bool? ?? false,
      paymentMethod: json['o_payment_method'] ?? json['payment_method'],
      cancelReason:
          json['o_cancel_reason'] ?? json['cancel_reason']?.toString(),
      status: '${json['o_status'] ?? json['status'] ?? 'Pending'}',
      createdAt: (json['o_created_at'] ?? json['created_at']) != null
          ? DateTime.parse('${json['o_created_at'] ?? json['created_at']}')
          : null,
      discountAmount:
          ((json['discount_amount'] ?? 0) as num?)?.toDouble() ?? 0,
      promoCodeId: json['promo_code_id']?.toString(),
    );
  }
}
