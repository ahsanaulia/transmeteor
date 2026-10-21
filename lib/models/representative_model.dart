/// Perwakilan (agen/titik titipan barang) -- dipakai sopir saat tujuan
/// asli tutup/tidak bisa dijangkau sehingga barang diturunkan di sini
/// dulu, BUKAN langsung di tujuan. Lihat dokumentasi panjang di
/// `RepresentativeService` & project doc `arsitektur-flutter.md`.
///
/// Struktur sama persis `DestinationModel` TAPI tanpa latitude/longitude
/// -- permintaan user cuma "menulis nama perwakilan dan alamatnya".
class RepresentativeModel {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  RepresentativeModel({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RepresentativeModel.fromMap(Map<String, dynamic> map) {
    return RepresentativeModel(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      address: map['address'],
      isActive: map['is_active'] ?? true,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
