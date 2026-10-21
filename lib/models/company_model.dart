class CompanyModel {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final String? logoUrl;

  /// Interval kirim ping lokasi GPS (dalam DETIK) buat tracking sopir --
  /// dipakai [GpsForegroundService]. Default 900 detik (15 menit, nilai
  /// produksi). Sengaja dibuat kolom yang bisa diubah admin lewat halaman
  /// "Profil Perusahaan" (bukan konstanta di kode) supaya waktu uji coba
  /// lapangan bisa diisi angka kecil (mis. 1 atau 10 detik) tanpa perlu
  /// ubah kode & build ulang -- balikin ke 900 lagi kalau sudah selesai
  /// uji coba, supaya baterai HP sopir & kuota data tidak boros.
  final int gpsPingIntervalSeconds;

  /// URL publik website "Cek Resi" SAAT INI (8 Oktober 2026, DIGANTI NAMA
  /// 13 Oktober 2026 dari `companyTrack` -> `companyPublicUrl`) --
  /// sengaja disimpan sebagai data yang bisa diubah admin lewat "Profil
  /// Perusahaan", BUKAN konstanta di kode, supaya kalau nanti domain
  /// hosting website itu berubah, admin tinggal update field ini TANPA
  /// perlu build ulang APK/web app ini sama sekali.
  ///
  /// **DIUBAH ARSITEKTUR (13 Oktober 2026, permintaan user eksplisit:
  /// "Saya memilih untuk menggunakan website lain. Link berbeda...
  /// Sehingga tidak ada kemungkinan diluar perusahaan bisa memiliki
  /// akses pada aplikasi")**: field ini SEKARANG menunjuk ke WEBSITE
  /// STATIS TERPISAH (bukan Flutter, bukan bagian dari app ini) --
  /// SEBELUMNYA menunjuk ke halaman "Telusuri Kiriman" yang EMBEDDED di
  /// app Flutter ini sendiri (`TrackShipmentPage`, dibuka dari tombol di
  /// `LoginPage`) -- tombol itu SUDAH DIHAPUS (lihat doc comment
  /// `LoginPage`) supaya publik TIDAK PERNAH menyentuh domain/build app
  /// utama sama sekali. Website barunya panggil RPC publik yang SAMA
  /// (`track_shipment`, `get_public_company_info`) lewat Supabase anon
  /// key -- lihat paket terpisah di luar project Flutter ini.
  ///
  /// Dipakai sebagai teks link yang disisipkan di footer WA ke tujuan &
  /// footer cetakan Resi (lihat
  /// `pdf_templates.dart`/`receipt_preview_page.dart`), supaya customer
  /// tahu ke mana harus buka untuk lacak kiriman mereka sendiri. Null/
  /// kosong -> baris link ini TIDAK ditampilkan sama sekali (tidak ada
  /// link rusak/kosong yang nongol di cetakan).
  final String? companyPublicUrl;

  /// Ambang hari "resi terlambat" (16 Oktober 2026, permintaan user
  /// eksplisit): dipakai Monitoring Resi Admin & Supervisor untuk
  /// menandai KOTAK MERAH pada resi yang SUDAH LEWAT dari sekian hari
  /// dari HARI INI, dihitung dari `ReceivingModel.receivedAt` (tanggal
  /// resi diterima) -- HANYA berlaku untuk resi yang statusnya masih
  /// "Penerimaan" (BELUM pernah dimuat/di-loading sama sekali, lihat
  /// `ReceivingComputedStatus.penerimaan`), sesuai klarifikasi user:
  /// "hanya resi yang statusnya belum loading atau penerimaan". Resi
  /// yang sudah "Masih Perjalanan"/"Selesai" TIDAK PERNAH ditandai
  /// merah lewat field ini, berapa pun lama usianya.
  ///
  /// Sengaja dibuat kolom yang bisa diubah admin lewat halaman "Profil
  /// Perusahaan" (bukan konstanta di kode), supaya ambang harinya bisa
  /// disesuaikan tanpa build ulang app. Default 3 hari kalau belum
  /// pernah diisi (resi lama sebelum migrasi kolom ini).
  final int resiOverdueDays;

  final DateTime createdAt;
  final DateTime updatedAt;

  CompanyModel({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.logoUrl,
    this.gpsPingIntervalSeconds = 900,
    this.companyPublicUrl,
    this.resiOverdueDays = 3,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CompanyModel.fromMap(Map<String, dynamic> map) {
    return CompanyModel(
      id: map['id'],
      name: map['name'],
      address: map['address'],
      phone: map['phone'],
      logoUrl: map['logo_url'],
      gpsPingIntervalSeconds:
          (map['gps_ping_interval_seconds'] as num?)?.toInt() ?? 900,
      companyPublicUrl: map['company_public_url'],
      resiOverdueDays: (map['resi_overdue_days'] as num?)?.toInt() ?? 3,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'logo_url': logoUrl,
      'gps_ping_interval_seconds': gpsPingIntervalSeconds,
      'company_public_url': companyPublicUrl,
      'resi_overdue_days': resiOverdueDays,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
