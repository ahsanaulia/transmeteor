/// Satu baris di tabel `shipment_helpers` -- helper yang ditugaskan ikut
/// perjalanan satu shipment (opsional, cuma diisi kalau helper itu benar
/// ikut naik & perlu dilacak lokasinya, bukan sekadar bantu angkat barang
/// di titik muat).
class ShipmentHelperModel {
  final String id;
  final String shipmentId;
  final String employeeId;
  final DateTime createdAt;

  ShipmentHelperModel({
    required this.id,
    required this.shipmentId,
    required this.employeeId,
    required this.createdAt,
  });

  factory ShipmentHelperModel.fromMap(Map<String, dynamic> map) {
    return ShipmentHelperModel(
      id: map['id'],
      shipmentId: map['shipment_id'],
      employeeId: map['employee_id'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipment_id': shipmentId,
      'employee_id': employeeId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}