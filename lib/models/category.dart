class Category {
  final String id;
  final String name;
  final String? imageUrl;
  final double profitPercentage;
  final DateTime? createdAt;

  const Category({
    required this.id,
    required this.name,
    this.imageUrl,
    this.profitPercentage = 0,
    this.createdAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
      imageUrl: json['image_url'] as String?,
      profitPercentage: (json['profit_percentage'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse('${json['created_at']}')
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
      'profit_percentage': profitPercentage,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
