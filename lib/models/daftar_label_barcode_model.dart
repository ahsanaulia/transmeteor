/// FITUR (21 Oktober 2026 -- Section A, "Label Barcode"). Lihat doc
/// comment lengkap di `migrasi_label_barcode.sql` untuk latar belakang &
/// keputusan arsitektur -- model ini 1:1 dengan tabel `daftar_label_barcode`.
class LabelBarcodeStatus {
  static const belumDipakai = 'BELUM_DIPAKAI';
  static const terpakai = 'TERPAKAI';
}

class DaftarLabelBarcodeModel {
  final String id;
  final int sequenceNo;
  final String barcodeCode;
  final String status;
  final String? noResi;
  final String? kodeBarang;
  final String? receivingDetailId;
  final DateTime? assignedAt;
  final String? assignedBy;
  final DateTime createdAt;
  final String? createdBy;

  DaftarLabelBarcodeModel({
    required this.id,
    required this.sequenceNo,
    required this.barcodeCode,
    this.status = LabelBarcodeStatus.belumDipakai,
    this.noResi,
    this.kodeBarang,
    this.receivingDetailId,
    this.assignedAt,
    this.assignedBy,
    required this.createdAt,
    this.createdBy,
  });

  bool get isUsed => status == LabelBarcodeStatus.terpakai;

  factory DaftarLabelBarcodeModel.fromMap(Map<String, dynamic> map) {
    return DaftarLabelBarcodeModel(
      id: map['id'] as String,
      sequenceNo: (map['sequence_no'] as num).toInt(),
      barcodeCode: map['barcode_code'] as String,
      status: map['status'] as String? ?? LabelBarcodeStatus.belumDipakai,
      noResi: map['no_resi'] as String?,
      kodeBarang: map['kode_barang'] as String?,
      receivingDetailId: map['receiving_detail_id'] as String?,
      assignedAt: map['assigned_at'] != null
          ? DateTime.parse(map['assigned_at'] as String)
          : null,
      assignedBy: map['assigned_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      createdBy: map['created_by'] as String?,
    );
  }
}
