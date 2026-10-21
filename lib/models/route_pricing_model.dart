class RoutePricingModel {
  final String id;
  final String routeCode;
  final String routeName;
  final double price;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  RoutePricingModel({
    required this.id,
    required this.routeCode,
    required this.routeName,
    required this.price,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoutePricingModel.fromMap(Map<String, dynamic> map) {
    return RoutePricingModel(
      id: map['id'],
      routeCode: map['route_code'],
      routeName: map['route_name'],
      price: (map['price'] as num?)?.toDouble() ?? 0,
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'route_code': routeCode,
      'route_name': routeName,
      'price': price,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}