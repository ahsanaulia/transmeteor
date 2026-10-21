class EmployeeModel {
  final String id;
  final String employeeNumber;
  final String fullName;
  final String? phone;
  final String roleId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmployeeModel({
    required this.id,
    required this.employeeNumber,
    required this.fullName,
    this.phone,
    required this.roleId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    return EmployeeModel(
      id: map['id'],
      employeeNumber: map['employee_number'],
      fullName: map['full_name'],
      phone: map['phone'],
      roleId: map['role_id'],
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employee_number': employeeNumber,
      'full_name': fullName,
      'phone': phone,
      'role_id': roleId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}