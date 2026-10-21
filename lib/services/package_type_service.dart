import '../core/services/supabase_service.dart';
import '../models/package_type_model.dart';

class PackageTypeService {
  static final _client = SupabaseService.client;

  static Future<List<PackageTypeModel>>
      getPackageTypes() async {
    final response = await _client
        .from('package_types')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => PackageTypeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<PackageTypeModel?> getPackageTypeById(
    String id,
  ) async {
    final response = await _client
        .from('package_types')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return PackageTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<PackageTypeModel?> getPackageTypeByCode(
    String code,
  ) async {
    final response = await _client
        .from('package_types')
        .select()
        .eq('code', code)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return PackageTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<PackageTypeModel> createPackageType({
    required String code,
    required String name,
    required int durationDays,
    String? description,
    required double price,
  }) async {
    final response = await _client
        .from('package_types')
        .insert({
          'code': code,
          'name': name,
          'duration_days': durationDays,
          'description': description,
          'price': price,
          'is_active': true,
        })
        .select()
        .single();

    return PackageTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<PackageTypeModel> updatePackageType({
    required String id,
    required String code,
    required String name,
    required int durationDays,
    String? description,
    required double price,
  }) async {
    final response = await _client
        .from('package_types')
        .update({
          'code': code,
          'name': name,
          'duration_days': durationDays,
          'description': description,
          'price': price,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return PackageTypeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deactivatePackageType(
    String id,
  ) async {
    await _client
        .from('package_types')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}