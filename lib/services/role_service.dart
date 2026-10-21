import '../core/services/supabase_service.dart';
import '../models/employee_role_model.dart';

class RoleService {
  static final _client = SupabaseService.client;

  static Future<List<EmployeeRoleModel>> getRoles() async {
    final response = await _client
        .from('employee_roles')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (response as List)
        .map(
          (data) => EmployeeRoleModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<EmployeeRoleModel?> getRoleById(
    String id,
  ) async {
    final response = await _client
        .from('employee_roles')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return EmployeeRoleModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<EmployeeRoleModel?> getRoleByCode(
    String code,
  ) async {
    final response = await _client
        .from('employee_roles')
        .select()
        .eq('code', code)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return EmployeeRoleModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }
}