class Product {
  String id;
  String name;
  String description;
  String imageUrl;
  String? shopId;
  String? categoryId;
  double? purchasePrice;
  double? sellingPrice;
  double price;
  double? discountPrice;
  double? discountThresholdKg;
  double quantity;
  String unit;
  bool isAvailable;
  DateTime? createdAt;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    this.shopId,
    this.categoryId,
    this.purchasePrice,
    this.sellingPrice,
    required this.price,
    this.discountPrice,
    this.discountThresholdKg,
    required this.quantity,
    this.unit = 'kg',
    this.isAvailable = true,
    this.createdAt,
  });

  Product copy() => Product(
    id: id,
    name: name,
    description: description,
    imageUrl: imageUrl,
    shopId: shopId,
    categoryId: categoryId,
    purchasePrice: purchasePrice,
    sellingPrice: sellingPrice,
    price: price,
    discountPrice: discountPrice,
    discountThresholdKg: discountThresholdKg,
    quantity: quantity,
    unit: unit,
    isAvailable: isAvailable,
    createdAt: createdAt,
  );

  bool get hasDiscount =>
      discountPrice != null &&
      discountThresholdKg != null &&
      discountThresholdKg! > 0 &&
      discountPrice! < price;

  double effectivePriceFor(double quantityKg) {
    if (hasDiscount && quantityKg >= discountThresholdKg!) {
      return discountPrice!;
    }
    return price;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawSellingPrice = (json['selling_price'] as num?)?.toDouble();
    final rawPrice =
        (json['price'] as num?)?.toDouble() ?? rawSellingPrice ?? 0;
    return Product(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      imageUrl: '${json['image_url'] ?? ''}',
      shopId: json['shop_id'] as String?,
      categoryId: json['category_id'] as String?,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble(),
      sellingPrice: rawSellingPrice ?? rawPrice,
      price: rawPrice,
      discountPrice: (json['discount_price'] as num?)?.toDouble(),
      discountThresholdKg: (json['discount_threshold_kg'] as num?)?.toDouble(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unit: '${json['unit'] ?? 'kg'}',
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'image_url': imageUrl,
      'shop_id': shopId,
      'category_id': categoryId,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice ?? price,
      'price': price,
      'discount_price': discountPrice,
      'discount_threshold_kg': discountThresholdKg,
      'quantity': quantity,
      'unit': unit,
      'is_available': isAvailable,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
