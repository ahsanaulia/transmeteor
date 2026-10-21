import '../core/services/supabase_service.dart';
import '../models/sender_model.dart';

class SenderService {
  static final _client = SupabaseService.client;

  static Future<List<SenderModel>> getSenders() async {
    final response = await _client
        .from('senders')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => SenderModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<SenderModel?> getSenderById(
    String id,
  ) async {
    final response = await _client
        .from('senders')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return SenderModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<List<SenderModel>> searchSenders(
    String keyword,
  ) async {
    final response = await _client
        .from('senders')
        .select()
        .eq('is_active', true)
        .ilike('name', '%$keyword%')
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => SenderModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<SenderModel> createSender({
    required String name,
    String? phone,
    String? address,
  }) async {
    final response = await _client
        .from('senders')
        .insert({
          'name': name,
          'phone': phone,
          'address': address,
          'is_active': true,
        })
        .select()
        .single();

    return SenderModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<SenderModel> updateSender({
    required String id,
    required String name,
    String? phone,
    String? address,
  }) async {
    final response = await _client
        .from('senders')
        .update({
          'name': name,
          'phone': phone,
          'address': address,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return SenderModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deactivateSender(
    String id,
  ) async {
    await _client
        .from('senders')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// SEMUA pengirim (aktif maupun nonaktif) -- dipakai halaman admin
  /// "Daftar Pengirim Langganan" (permintaan user, 6 Oktober 2026
  /// lanjutan) supaya admin bisa lihat & aktif/nonaktifkan semuanya,
  /// bukan cuma yang aktif. Mengikuti pola PERSIS
  /// `DestinationService.getAllDestinations`. Field pencarian pengirim
  /// di form input resi (Receiving) TIDAK pakai method ini -- dia tetap
  /// pakai [searchSenders] (hanya yang aktif) lewat SearchPickField.
  static Future<List<SenderModel>> getAllSenders() async {
    final response = await _client
        .from('senders')
        .select()
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => SenderModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// Set is_active manual (bisa aktifkan lagi atau nonaktifkan) -- dipakai
  /// admin di "Daftar Pengirim Langganan" lewat tombol switch. Mengikuti
  /// pola PERSIS `DestinationService.setActive`. Menonaktifkan pengirim
  /// TIDAK menghapus riwayat resi lama yang sudah memakainya -- cuma bikin
  /// pengirim itu tidak lagi muncul di pencarian saat input resi baru.
  static Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('senders')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}