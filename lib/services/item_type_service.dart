import '../core/services/supabase_service.dart';
import '../models/item_type_model.dart';

class ItemTypeService {
  static final _client = SupabaseService.client;

  static Future<List<ItemTypeModel>> getItemTypes() async {
    final response = await _client
        .from('item_types')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => ItemTypeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// SEMUA jenis barang (aktif maupun nonaktif) -- dipakai halaman admin
  /// "Kelola Jenis Barang" (8 Oktober 2026), mirror pola
  /// `PricingTypeService.getAllPricingTypes()`.
  static Future<List<ItemTypeModel>> getAllItemTypes() async {
    final response = await _client
        .from('item_types')
        .select()
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => ItemTypeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<ItemTypeModel?> getItemTypeById(
    String id,
  ) async {
    final response = await _client
        .from('item_types')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ItemTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<ItemTypeModel?> getItemTypeByCode(
    String code,
  ) async {
    final response = await _client
        .from('item_types')
        .select()
        .eq('code', code)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ItemTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<ItemTypeModel> createItemType({
    required String code,
    required String name,
    String? handling,
    String? description,
  }) async {
    final response = await _client
        .from('item_types')
        .insert({
          'code': code,
          'name': name,
          'handling': handling,
          'description': description,
          'is_active': true,
        })
        .select()
        .single();

    return ItemTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<ItemTypeModel> updateItemType({
    required String id,
    required String code,
    required String name,
    String? handling,
    String? description,
  }) async {
    final response = await _client
        .from('item_types')
        .update({
          'code': code,
          'name': name,
          'handling': handling,
          'description': description,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return ItemTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deactivateItemType(
    String id,
  ) async {
    await _client
        .from('item_types')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// Toggle aktif/nonaktif generic (bisa aktifkan lagi) -- melengkapi
  /// [deactivateItemType] yang HANYA bisa menonaktifkan. Dipakai switch
  /// di halaman admin "Kelola Jenis Barang" (mirror
  /// `PricingTypeService.setActive`).
  static Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('item_types')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}