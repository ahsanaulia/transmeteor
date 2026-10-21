class ShipmentScanModel {
  final String id;
  final String shipmentId;
  final String receivingDetailId;
  final String unitCode;
  final int unitIndex;
  final String scanType;
  final String scannedBy;
  final DateTime scannedAt;
  final String? notes;
  final double? latitude;
  final double? longitude;
  // Diisi kalau scan DELIVER ini sebenarnya "dititip di PERWAKILAN"
  // (tujuan asli tutup/tidak bisa dijangkau sopir), BUKAN langsung di
  // tujuan -- lihat `RepresentativeService` &
  // `ShipmentService.recordRepresentativeHandoffForReceiving`. null
  // untuk semua scan LOAD dan scan DELIVER normal (langsung ke tujuan).
  final String? representativeId;
  // URL foto bukti penyelesaian barang TANPA SCAN KAMERA (checklist manual
  // "Tanpa Label QR" di Aplikasi Sopir, diperluas 10 Oktober 2026 supaya
  // juga bisa menyelesaikan barang BERLABEL -- antisipasi kamera sopir
  // rusak/label rusak). WAJIB diisi di sisi UX sebelum submit checklist
  // manual, tapi kolom database-nya SENGAJA DIBUAT BOLEH NULL (permintaan
  // user eksplisit: "tetapi boleh Null") -- null untuk SEMUA scan lewat
  // kamera QR (baik LOAD maupun DELIVER), karena scan kamera tidak pernah
  // memfoto.
  final String? urlFotoSelesai;

  ShipmentScanModel({
    required this.id,
    required this.shipmentId,
    required this.receivingDetailId,
    required this.unitCode,
    required this.unitIndex,
    required this.scanType,
    required this.scannedBy,
    required this.scannedAt,
    this.notes,
    this.latitude,
    this.longitude,
    this.representativeId,
    this.urlFotoSelesai,
  });

  factory ShipmentScanModel.fromMap(Map<String, dynamic> map) {
    return ShipmentScanModel(
      id: map['id'],
      shipmentId: map['shipment_id'],
      receivingDetailId: map['receiving_detail_id'],
      unitCode: map['unit_code'],
      unitIndex: map['unit_index'],
      scanType: map['scan_type'],
      scannedBy: map['scanned_by'],
      scannedAt: DateTime.parse(map['scanned_at']),
      notes: map['notes'],
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      representativeId: map['representative_id'],
      urlFotoSelesai: map['url_foto_selesai'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shipment_id': shipmentId,
      'receiving_detail_id': receivingDetailId,
      'unit_code': unitCode,
      'unit_index': unitIndex,
      'scan_type': scanType,
      'scanned_by': scannedBy,
      'scanned_at': scannedAt.toIso8601String(),
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'representative_id': representativeId,
      'url_foto_selesai': urlFotoSelesai,
    };
  }
}