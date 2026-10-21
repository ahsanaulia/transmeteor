class VehicleModel {
  final String id;
  final String vehicleCode;
  final String plateNumber;
  final String? vehicleType;
  final String? driverEmployeeId;
  final String? driverName;
  final String? driverPhone;
  final String? helper1EmployeeId;
  final String? helper2EmployeeId;
  final String? helper3EmployeeId;
  final double? capacityKg;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  VehicleModel({
    required this.id,
    required this.vehicleCode,
    required this.plateNumber,
    this.vehicleType,
    this.driverEmployeeId,
    this.driverName,
    this.driverPhone,
    this.helper1EmployeeId,
    this.helper2EmployeeId,
    this.helper3EmployeeId,
    this.capacityKg,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleModel.fromMap(Map<String, dynamic> map) {
    return VehicleModel(
      id: map['id'],
      vehicleCode: map['vehicle_code'],
      plateNumber: map['plate_number'],
      vehicleType: map['vehicle_type'],
      driverEmployeeId: map['driver_employee_id'],
      driverName: map['driver_name'],
      driverPhone: map['driver_phone'],
      helper1EmployeeId: map['helper1_employee_id'],
      helper2EmployeeId: map['helper2_employee_id'],
      helper3EmployeeId: map['helper3_employee_id'],
      capacityKg: (map['capacity_kg'] as num?)?.toDouble(),
      isActive: map['is_active'] ?? false,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicle_code': vehicleCode,
      'plate_number': plateNumber,
      'vehicle_type': vehicleType,
      'driver_employee_id': driverEmployeeId,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'helper1_employee_id': helper1EmployeeId,
      'helper2_employee_id': helper2EmployeeId,
      'helper3_employee_id': helper3EmployeeId,
      'capacity_kg': capacityKg,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}