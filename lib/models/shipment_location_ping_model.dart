/// Satu titik lokasi driver/helper, direkam tiap 15 menit selama
/// shipment berjalan (foreground-only, selagi app dibuka).
class ShipmentLocationPingModel {
  final String id;
  final String shipmentId;
  final String employeeId;
  final String roleAtPing; // 'DRIVER' atau 'HELPER'
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final DateTime recordedAt;

  ShipmentLocationPingModel({
    required this.id,
    required this.shipmentId,
    required this.employeeId,
    required this.roleAtPing,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    required this.recordedAt,
  });

  factory ShipmentLocationPingModel.fromMap(Map<String, dynamic> map) {
    return ShipmentLocationPingModel(
      id: map['id'],
      shipmentId: map['shipment_id'],
      employeeId: map['employee_id'],
      roleAtPing: map['role_at_ping'],
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(map['recorded_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipment_id': shipmentId,
      'employee_id': employeeId,
      'role_at_ping': roleAtPing,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_m': accuracyM,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}