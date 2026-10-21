import '../core/services/supabase_service.dart';
import '../models/storage_model.dart';

/// CRUD tabel `storages` -- mengikuti pola PERSIS `RepresentativeService`/
/// `DestinationService`.
///
/// Dipakai di 2 tempat:
/// 1. Receiving -- pilih zona lewat `PickerField<StorageModel>` (cuma
///    yang aktif, lewat [getStorages]) saat input detail barang.
/// 2. Admin -- halaman "Zona Storage" (`StorageManagePage`): lihat SEMUA
///    zona (aktif/nonaktif) lewat [getAllStorages], tambah/edit/
///    aktifkan-nonaktifkan.
class StorageService {
  static final _client = SupabaseService.client;

  static Future<List<StorageModel>> getStorages() async {
    final response = await _client
        .from('storages')
        .select()
        .eq('is_active', true)
        .order('nama_zona', ascending: true);

    return (response as List)
        .map((data) => StorageModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }

  /// SEMUA zona (aktif maupun nonaktif) -- dipakai halaman admin "Zona
  /// Storage" supaya admin bisa lihat & aktif/nonaktifkan semuanya.
  static Future<List<StorageModel>> getAllStorages() async {
    final response = await _client
        .from('storages')
        .select()
        .order('nama_zona', ascending: true);

    return (response as List)
        .map((data) => StorageModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }

  static Future<StorageModel?> getStorageById(String id) async {
    final response = await _client
        .from('storages')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;

    return StorageModel.fromMap(Map<String, dynamic>.from(response));
  }

  static Future<StorageModel> createStorage({
    required String namaZona,
    String? deskripsi,
  }) async {
    final response = await _client
        .from('storages')
        .insert({
          'nama_zona': namaZona,
          'deskripsi': deskripsi,
          'is_active': true,
        })
        .select()
        .single();

    return StorageModel.fromMap(Map<String, dynamic>.from(response));
  }

  static Future<StorageModel> updateStorage({
    required String id,
    required String namaZona,
    String? deskripsi,
  }) async {
    final response = await _client
        .from('storages')
        .update({
          'nama_zona': namaZona,
          'deskripsi': deskripsi,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return StorageModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Set is_active manual -- menonaktifkan zona TIDAK menghapus riwayat
  /// `receiving_details.storage_id` lama yang sudah memakainya, cuma
  /// bikin zona itu tidak lagi muncul di picker saat input barang baru.
  static Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('storages')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}
