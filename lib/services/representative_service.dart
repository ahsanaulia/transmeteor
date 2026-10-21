import '../core/services/supabase_service.dart';
import '../models/representative_model.dart';

/// CRUD tabel `representatives` -- mengikuti pola PERSIS
/// `DestinationService` (lihat file itu untuk komentar lebih lengkap
/// soal kenapa ada getXxx vs getAllXxx vs searchXxx).
///
/// Dipakai di 2 tempat:
/// 1. Aplikasi sopir -- "Selesaikan di Perwakilan" (lihat
///    `RepresentativeHandoffPage`): cari perwakilan yang sudah ada lewat
///    [searchRepresentatives] (SearchPickField), atau daftarkan baru di
///    tempat lewat [createRepresentative] kalau belum ada.
/// 2. Aplikasi admin -- halaman "Daftar Perwakilan"
///    (`RepresentativeManagePage`): lihat SEMUA perwakilan (aktif/
///    nonaktif) lewat [getAllRepresentatives], tambah/edit/aktifkan-
///    nonaktifkan.
class RepresentativeService {
  static final _client = SupabaseService.client;

  static Future<List<RepresentativeModel>> getRepresentatives() async {
    final response = await _client
        .from('representatives')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => RepresentativeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// SEMUA perwakilan (aktif maupun nonaktif) -- dipakai halaman admin
  /// "Daftar Perwakilan" supaya admin bisa lihat & aktif/nonaktifkan
  /// semuanya, bukan cuma yang aktif.
  static Future<List<RepresentativeModel>> getAllRepresentatives() async {
    final response = await _client
        .from('representatives')
        .select()
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => RepresentativeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<RepresentativeModel?> getRepresentativeById(
    String id,
  ) async {
    final response = await _client
        .from('representatives')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return RepresentativeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Dipakai `SearchPickField<RepresentativeModel>` di
  /// `RepresentativeHandoffPage` -- cari perwakilan yang sudah pernah
  /// didaftarkan sebelum sopir mengetik ulang dari nol.
  static Future<List<RepresentativeModel>> searchRepresentatives(
    String keyword,
  ) async {
    final response = await _client
        .from('representatives')
        .select()
        .eq('is_active', true)
        .ilike('name', '%$keyword%')
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => RepresentativeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<RepresentativeModel> createRepresentative({
    required String name,
    String? phone,
    String? address,
  }) async {
    final response = await _client
        .from('representatives')
        .insert({
          'name': name,
          'phone': phone,
          'address': address,
          'is_active': true,
        })
        .select()
        .single();

    return RepresentativeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<RepresentativeModel> updateRepresentative({
    required String id,
    required String name,
    String? phone,
    String? address,
  }) async {
    final response = await _client
        .from('representatives')
        .update({
          'name': name,
          'phone': phone,
          'address': address,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return RepresentativeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Set is_active manual (bisa aktifkan lagi atau nonaktifkan) -- dipakai
  /// admin di "Daftar Perwakilan" lewat tombol switch. Menonaktifkan
  /// perwakilan TIDAK menghapus riwayat handoff lama yang sudah memakainya
  /// (`shipment_scans.representative_id` tetap ada) -- cuma bikin
  /// perwakilan itu tidak lagi muncul di pencarian sopir saat menitip
  /// barang baru.
  static Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('representatives')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}
