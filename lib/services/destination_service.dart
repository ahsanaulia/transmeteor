import '../core/services/supabase_service.dart';
import '../models/destination_model.dart';
import '../models/receiving_model.dart';

class DestinationService {
  static final _client = SupabaseService.client;

  static Future<List<DestinationModel>> getDestinations() async {
    final response = await _client
        .from('destinations')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => DestinationModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// SEMUA tujuan (aktif maupun nonaktif) -- dipakai di halaman admin
  /// "Kelola Daftar Tujuan" supaya admin bisa lihat & aktif/nonaktifkan
  /// semuanya, bukan cuma yang aktif. Tujuan baru bisa didaftarkan lebih
  /// dulu dari sini sebelum dipakai staff Receiving di lapangan -- tidak
  /// harus menunggu numpang dibuat lewat form input resi.
  static Future<List<DestinationModel>> getAllDestinations() async {
    final response = await _client
        .from('destinations')
        .select()
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => DestinationModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<DestinationModel?> getDestinationById(
    String id,
  ) async {
    final response = await _client
        .from('destinations')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return DestinationModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<List<DestinationModel>> searchDestinations(
    String keyword,
  ) async {
    final response = await _client
        .from('destinations')
        .select()
        .eq('is_active', true)
        .ilike('name', '%$keyword%')
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => DestinationModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<DestinationModel> createDestination({
    required String name,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _client
        .from('destinations')
        .insert({
          'name': name,
          'phone': phone,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'is_active': true,
        })
        .select()
        .single();

    return DestinationModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<DestinationModel> updateDestination({
    required String id,
    required String name,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _client
        .from('destinations')
        .update({
          'name': name,
          'phone': phone,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return DestinationModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deactivateDestination(
    String id,
  ) async {
    await _client
        .from('destinations')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// Set is_active manual (bisa aktifkan lagi atau nonaktifkan) -- dipakai
  /// admin di "Kelola Daftar Tujuan" lewat tombol switch. Nonaktifkan
  /// tujuan TIDAK menghapus riwayat resi lama yang sudah memakainya
  /// (destination_id di receiving tetap ada) -- cuma bikin tujuan itu
  /// tidak lagi muncul di pencarian saat input resi baru.
  static Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('destinations')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// Semua resi yang tujuannya sama (destination_id yang sama) --
  /// dipakai buat halaman "Daftar Resi per Tujuan" supaya driver tidak
  /// perlu bolak-balik ke tujuan yang sama beberapa kali kalau ada
  /// beberapa pengirim berbeda mengirim ke tujuan yang sama.
  static Future<List<ReceivingModel>> getReceivingsByDestination(
    String destinationId,
  ) async {
    // '*, destinations:destination_id(phone)' -- nomor HP live dari tabel
    // destinations (fix 5 Oktober 2026, lihat catatan panjang di
    // `ReceivingService._receivingSelectWithLiveDestination` &
    // `ReceivingModel.destinationPhone`).
    final response = await _client
        .from('receiving')
        .select('*, destinations:destination_id(phone)')
        .eq('destination_id', destinationId)
        .order('created_at', ascending: false);

    return (response as List)
        .map(
          (data) => ReceivingModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }
}
