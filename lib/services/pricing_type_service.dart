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

  /// FITUR (21 Oktober 2026, permintaan user eksplisit): "Perlu ada
  /// pengisian jenis tarif pada bagian penerimaan juga. Jika jenis tarif
  /// barang belum ada maka mereka boleh menambah jenis tarif baru."
  /// Dipakai staff/admin Penerimaan lewat tombol "Tambah Jenis Tarif
  /// Baru" di `PickerField` (lihat `receiving_detail_form_sheet.dart`/
  /// `admin_receiving_detail_dialog.dart`) -- BEDA dari
  /// [createPricingType] (dipakai admin "Kelola Jenis Harga") yang minta
  /// `code` diisi manual, staff Penerimaan TIDAK disuruh mengisi `code`
  /// (field internal, cuma dipakai pencarian di "Kelola Jenis Harga",
  /// tidak tampil ke pelanggan) -- di-generate OTOMATIS dari nama lewat
  /// [_generateAutoCode].
  static Future<PricingTypeModel> createPricingTypeWithAutoCode({
    required String name,
    required double price,
  }) async {
    return createPricingType(
      code: _generateAutoCode(name),
      name: name,
      price: price,
    );
  }

  /// Slug dari nama + 5 digit terakhir epoch ms supaya cukup unik tanpa
  /// perlu query cek bentrok dulu (frekuensi pembuatan jenis tarif di
  /// app ini rendah -- 1 kantor, bukan ribuan transaksi per detik).
  static String _generateAutoCode(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = slug.isEmpty ? 'tarif' : slug;
    final millis = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = millis.substring(millis.length - 5);
    return '${base}_$suffix';
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