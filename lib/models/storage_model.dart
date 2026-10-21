/// Zona Storage -- lokasi/area penyimpanan barang di gudang (8 Oktober
/// 2026, permintaan user: "Tambahkan tabel storages. isinya adalah id,
/// nama_zona, deskripsi"). Dipakai 2 arah:
/// 1. Receiving -- saat input detail barang, staff pilih zona TEMPAT
///    barang itu diletakkan (`receiving_details.storage_id`).
/// 2. Loading -- saat checklist centang barang yang mau dimuat, zona ini
///    ditampilkan supaya staff tahu ke mana harus mengambil barangnya
///    secara fisik di gudang.
///
/// Struktur mirip `RepresentativeModel`/`DestinationModel` (CRUD admin
/// sederhana: nama + deskripsi + aktif/nonaktif), TANPA lat/long -- tidak
/// ada kebutuhan titik peta untuk zona di dalam gudang.
class StorageModel {
  final String id;
  final String namaZona;
  final String? deskripsi;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  StorageModel({
    required this.id,
    required this.namaZona,
    this.deskripsi,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StorageModel.fromMap(Map<String, dynamic> map) {
    return StorageModel(
      id: map['id'],
      namaZona: map['nama_zona'],
      deskripsi: map['deskripsi'],
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nama_zona': namaZona,
      'deskripsi': deskripsi,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
