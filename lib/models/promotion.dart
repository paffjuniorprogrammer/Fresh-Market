class Promotion {
  final String id;
  final String title;
  final String imageUrl;
  final bool isActive;
  final DateTime? createdAt;

  const Promotion({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.isActive = true,
    this.createdAt,
  });

  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: '${json['id']}',
      title: '${json['title'] ?? ''}',
      imageUrl: '${json['image_url'] ?? ''}',
      isActive: json['is_active'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse('${json['created_at']}')
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'image_url': imageUrl,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String()
    };
  }
}
