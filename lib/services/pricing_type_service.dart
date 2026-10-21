import '../core/services/supabase_service.dart';
import '../models/pricing_type_model.dart';

class PricingTypeService {
  static final _client = SupabaseService.client;

  static Future<List<PricingTypeModel>>
      getPricingTypes() async {
    final response = await _client
        .from('pricing_types')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => PricingTypeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// SEMUA jenis harga (aktif maupun nonaktif) -- dipakai di halaman
  /// admin "Kelola Jenis Harga" supaya admin bisa lihat & aktif/
  /// nonaktifkan semuanya, bukan cuma yang aktif. Jenis harga baru untuk
  /// jenis kiriman baru ditambahkan lewat halaman ini (tidak perlu lagi
  /// insert manual lewat SQL Supabase).
  static Future<List<PricingTypeModel>> getAllPricingTypes() async {
    final response = await _client
        .from('pricing_types')
        .select()
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => PricingTypeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<PricingTypeModel?> getPricingTypeById(
    String id,
  ) async {
    final response = await _client
        .from('pricing_types')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return PricingTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<PricingTypeModel?> getPricingTypeByCode(
    String code,
  ) async {
    final response = await _client
        .from('pricing_types')
        .select()
        .eq('code', code)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return PricingTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<PricingTypeModel> createPricingType({
    required String code,
    required String name,
    String? description,
    required double price,
  }) async {
    final response = await _client
        .from('pricing_types')
        .insert({
          'code': code,
          'name': name,
          'description': description,
          'price': price,
          'is_active': true,
        })
        .select()
        .single();

    return PricingTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<PricingTypeModel> updatePricingType({
    required String id,
    required String code,
    required String name,
    String? description,
    required double price,
  }) async {
    final response = await _client
        .from('pricing_types')
        .update({
          'code': code,
          'name': name,
          'description': description,
          'price': price,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return PricingTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deactivatePricingType(
    String id,
  ) async {
    await _client
        .from('pricing_types')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// Set is_active manual (bisa aktifkan lagi atau nonaktifkan) -- dipakai
  /// admin di "Kelola Jenis Harga" lewat tombol switch. Nonaktifkan jenis
  /// harga TIDAK menghapus riwayat resi lama yang sudah memakainya
  /// (pricingTypeId di receiving_details tetap ada) -- cuma bikin jenis
  /// harga itu tidak lagi muncul di picker saat input resi baru.
  static Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('pricing_types')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}