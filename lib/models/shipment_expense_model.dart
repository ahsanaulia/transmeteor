/// Laporan pengeluaran perjalanan driver (BBM / Penginapan / Makan).
/// Foto struk opsional, lokasi selalu otomatis kerekam saat submit.
class ShipmentExpenseModel {
  final String id;
  final String shipmentId;
  final String employeeId;
  final String expenseType; // 'BBM' | 'PENGINAPAN' | 'MAKAN'
  final double amount;
  final String? notes;
  final String? photoUrl;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  ShipmentExpenseModel({
    required this.id,
    required this.shipmentId,
    required this.employeeId,
    required this.expenseType,
    required this.amount,
    this.notes,
    this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });

  factory ShipmentExpenseModel.fromMap(Map<String, dynamic> map) {
    return ShipmentExpenseModel(
      id: map['id'],
      shipmentId: map['shipment_id'],
      employeeId: map['employee_id'],
      expenseType: map['expense_type'],
      amount: (map['amount'] as num).toDouble(),
      notes: map['notes'],
      photoUrl: map['photo_url'],
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      recordedAt: DateTime.parse(map['recorded_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipment_id': shipmentId,
      'employee_id': employeeId,
      'expense_type': expenseType,
      'amount': amount,
      'notes': notes,
      'photo_url': photoUrl,
      'latitude': latitude,
      'longitude': longitude,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}