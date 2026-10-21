import '../core/services/supabase_service.dart';
import '../models/employee_model.dart';
import 'role_service.dart';

class EmployeeService {
  static final _client = SupabaseService.client;

  static Future<EmployeeModel?> getCurrentEmployee() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    final response = await _client
        .from('employees')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return EmployeeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<EmployeeModel?> getEmployeeById(
    String id,
  ) async {
    final response = await _client
        .from('employees')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return EmployeeModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<List<EmployeeModel>> getEmployees() async {
    final response = await _client
        .from('employees')
        .select()
        .eq('is_active', true)
        .order('full_name', ascending: true);

    return (response as List)
        .map(
          (data) => EmployeeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// SEMUA employee (aktif maupun dinonaktifkan) -- dipakai di halaman
  /// admin "Kelola Pegawai" supaya admin bisa lihat & aktif/nonaktifkan
  /// siapa saja, bukan cuma yang aktif.
  static Future<List<EmployeeModel>> getAllEmployees() async {
    final response = await _client
        .from('employees')
        .select()
        .order('full_name', ascending: true);

    return (response as List)
        .map(
          (data) => EmployeeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// Daftar employee aktif dengan role tertentu (dicari lewat kode role,
  /// misal 'DRIVER' / 'HELPER') -- dipakai buat picker sopir & helper.
  static Future<List<EmployeeModel>> getEmployeesByRoleCode(
    String roleCode,
  ) async {
    final role = await RoleService.getRoleByCode(roleCode);

    if (role == null) {
      return [];
    }

    final response = await _client
        .from('employees')
        .select()
        .eq('role_id', role.id)
        .eq('is_active', true)
        .order('full_name', ascending: true);

    return (response as List)
        .map(
          (data) => EmployeeModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// Set is_active manual -- dipakai admin di "Kelola Pegawai" untuk
  /// menonaktifkan pegawai yang sudah tidak bekerja lagi (mis. resign),
  /// supaya dia tidak bisa login lagi. Bukan approval-gate: pegawai baru
  /// tetap langsung aktif saat register, ini murni tombol nonaktifkan.
  static Future<void> setActive(String employeeId, bool isActive) async {
    await _client.from('employees').update({
      'is_active': isActive,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', employeeId);
  }
}
