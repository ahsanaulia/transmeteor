import '../core/services/supabase_service.dart';

/// Service untuk fitur PUBLIK "Telusuri Kiriman" (8 Oktober 2026 --
/// permintaan user poin 11). Dipanggil dari `TrackShipmentPage` yang
/// dibuka LANGSUNG dari halaman Login (TIDAK perlu login dulu) -- jadi
/// `SupabaseService.client` di sini SELALU dalam kondisi anon/tanpa
/// sesi, berbeda dari semua service lain di app ini.
///
/// SENGAJA TIDAK query tabel manapun secara langsung dari sini (beda dari
/// pola service lain di app ini yang biasa `_client.from('...').select()`)
/// -- semua logic lookup & agregasi dilakukan di sisi database lewat
/// function `public.track_shipment` (SECURITY DEFINER, lihat
/// `add_track_shipment_rpc.sql`), supaya:
///   1. Customer anonim tidak pernah diberi akses baca langsung ke tabel
///      internal (harga, HP pengirim, dll) -- cuma field yang di-whitelist
///      di function itu yang keluar.
///   2. Tetap jalan konsisten berapa pun kondisi RLS tabel-tabel itu.
class TrackShipmentService {
  static final _client = SupabaseService.client;

  /// Cari status kiriman berdasarkan Nomor Resi ATAU Nomor Buku.
  ///
  /// Balikin Map hasil decode `jsonb` dari function `track_shipment`.
  /// `result['found']` SELALU ada (true/false) -- cek ini DULU sebelum
  /// baca field lain, karena kalau `false` field lainnya tidak dikirim
  /// sama sekali.
  static Future<Map<String, dynamic>> trackShipment(String search) async {
    final response = await _client.rpc(
      'track_shipment',
      params: {'p_search': search.trim()},
    );

    if (response == null) {
      return {'found': false};
    }

    return Map<String, dynamic>.from(response as Map);
  }

  /// Info perusahaan (nama/alamat/telepon) untuk HEADER halaman ini (8
  /// Oktober 2026, lanjutan lagi -- permintaan user eksplisit) -- lewat
  /// RPC publik `get_public_company_info` (SECURITY DEFINER), BUKAN
  /// query langsung ke tabel `company` (alasan SAMA PERSIS dengan
  /// [trackShipment] -- lihat doc comment kelas di atas & doc comment
  /// `add_public_company_info_rpc.sql`).
  ///
  /// Balikin `null` kalau belum ada baris `company` SAMA SEKALI atau
  /// kalau panggilannya gagal -- header SENGAJA cukup disembunyikan diam-
  /// diam di kasus itu (lihat pemanggil di `TrackShipmentPage`), bukan
  /// menampilkan error yang mengganggu customer yang cuma mau lacak
  /// kiriman.
  static Future<Map<String, dynamic>?> getPublicCompanyInfo() async {
    final response = await _client.rpc('get_public_company_info');

    if (response == null) return null;

    final map = Map<String, dynamic>.from(response as Map);
    if (map['found'] != true) return null;

    return map;
  }
}
