class PackageTypeModel {
  final String id;
  final String code;
  final String name;
  final int durationDays;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double price;

  PackageTypeModel({
    required this.id,
    required this.code,
    required this.name,
    required this.durationDays,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.price,
  });

  factory PackageTypeModel.fromMap(Map<String, dynamic> map) {
    return PackageTypeModel(
      id: map['id'],
      code: map['code'],
      name: map['name'],
      durationDays: map['duration_days'],
      description: map['description'],
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      price: (map['price'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'duration_days': durationDays,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'price': price,
    };
  }
}