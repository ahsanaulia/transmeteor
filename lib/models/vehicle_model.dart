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
  // FITUR (21 Oktober 2026, permintaan user eksplisit): "tambahkan kolom
  // is_loading. Artinya: admin saat menyiapkan kendaraan sekaligus
  // is_loading jadi true. Jika admin berangkatkan kendaraan is_loading
  // jadi false." BERBEDA dari [isActive] (gate kemunculan di "Pilih
  // Kendaraan" Loading, 13 Oktober 2026) -- field ini menjawab pertanyaan
  // lain: kendaraan ini SEDANG dimuat (belum berangkat) atau SUDAH
  // berangkat? Dipakai Monitoring Resi (Admin+Supervisor) untuk membedakan
  // status "Sedang Dimuat" vs "Dalam Perjalanan". Dijaga di 2 titik:
  // `VehicleService.prepareVehicle` (true) & "Berangkatkan Kendaraan"
  // (`shipment_dispatch_page.dart`)/`ShipmentService.forceStartTripByAdmin`
  // (false) -- lihat `migrasi_sedang_dimuat_dan_fix_selesai.sql`.
  final bool isLoading;
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
    this.isLoading = false,
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
      isLoading: map['is_loading'] as bool? ?? false,
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
      'is_loading': isLoading,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}