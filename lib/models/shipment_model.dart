class ShipmentModel {
  final String id;
  final String shipmentNumber;
  final String vehicleId;
  final String? routePricingId;
  final String? destination;
  final String status;
  final String loadedBy;
  final String? driverEmployeeId;
  final DateTime? loadedAt;
  final DateTime? tripStartedAt;
  final DateTime? departedAt;
  final DateTime? arrivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Diisi kalau shipment ini diselesaikan lewat "Intervensi Admin"
  // (bukan lewat tombol "Sudah Kembali ke Kantor" sopir sendiri) --
  // lihat ShipmentService.forceCompleteByAdmin. Dipakai buat jejak audit
  // (badge "Diselesaikan Admin" di Monitoring Kinerja Perjalanan).
  final bool completedByAdmin;
  final String? adminCompletionNote;
  // Diisi kalau trip_started_at ini di-set lewat "Intervensi Admin: Mulai
  // Paksa Perjalanan" (bukan sopir menekan "Mulai Perjalanan" sendiri) --
  // lihat ShipmentService.forceStartTripByAdmin. Mirror pola
  // completedByAdmin/adminCompletionNote di atas, tapi untuk ujung AWAL
  // perjalanan. Dipakai buat jejak audit (badge "Diberangkatkan Admin" di
  // Monitoring Kinerja Perjalanan).
  final bool tripStartedByAdmin;
  final String? adminStartTripNote;

  ShipmentModel({
    required this.id,
    required this.shipmentNumber,
    required this.vehicleId,
    this.routePricingId,
    this.destination,
    required this.status,
    required this.loadedBy,
    this.driverEmployeeId,
    this.loadedAt,
    this.tripStartedAt,
    this.departedAt,
    this.arrivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.completedByAdmin = false,
    this.adminCompletionNote,
    this.tripStartedByAdmin = false,
    this.adminStartTripNote,
  });

  factory ShipmentModel.fromMap(Map<String, dynamic> map) {
    return ShipmentModel(
      id: map['id'],
      shipmentNumber: map['shipment_number'],
      vehicleId: map['vehicle_id'],
      routePricingId: map['route_pricing_id'],
      destination: map['destination'],
      status: map['status'],
      loadedBy: map['loaded_by'],
      driverEmployeeId: map['driver_employee_id'],
      loadedAt: map['loaded_at'] != null
          ? DateTime.parse(map['loaded_at'])
          : null,
      tripStartedAt: map['trip_started_at'] != null
          ? DateTime.parse(map['trip_started_at'])
          : null,
      departedAt: map['departed_at'] != null
          ? DateTime.parse(map['departed_at'])
          : null,
      arrivedAt: map['arrived_at'] != null
          ? DateTime.parse(map['arrived_at'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      // `?? false`/nullable -- aman kalau kolomnya belum sempat
      // dimigrasi di Supabase (lihat add_admin_force_complete_shipment.sql).
      completedByAdmin: (map['completed_by_admin'] as bool?) ?? false,
      adminCompletionNote: map['admin_completion_note'],
      // `?? false`/nullable -- aman kalau kolomnya belum sempat dimigrasi
      // di Supabase (lihat add_admin_force_start_trip.sql).
      tripStartedByAdmin: (map['trip_started_by_admin'] as bool?) ?? false,
      adminStartTripNote: map['admin_start_trip_note'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipment_number': shipmentNumber,
      'vehicle_id': vehicleId,
      'route_pricing_id': routePricingId,
      'destination': destination,
      'status': status,
      'loaded_by': loadedBy,
      'driver_employee_id': driverEmployeeId,
      'loaded_at': loadedAt?.toIso8601String(),
      'trip_started_at': tripStartedAt?.toIso8601String(),
      'departed_at': departedAt?.toIso8601String(),
      'arrived_at': arrivedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_by_admin': completedByAdmin,
      'admin_completion_note': adminCompletionNote,
      'trip_started_by_admin': tripStartedByAdmin,
      'admin_start_trip_note': adminStartTripNote,
    };
  }
}