class ItemTypeModel {
  final String id;
  final String code;
  final String name;
  final String? handling;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ItemTypeModel({
    required this.id,
    required this.code,
    required this.name,
    this.handling,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ItemTypeModel.fromMap(Map<String, dynamic> map) {
    return ItemTypeModel(
      id: map['id'],
      code: map['code'],
      name: map['name'],
      handling: map['handling'],
      description: map['description'],
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'handling': handling,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}