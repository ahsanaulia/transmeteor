import '../core/services/supabase_service.dart';

class AuthService {
  static final _auth = SupabaseService.client.auth;

  static bool get isLoggedIn {
    return _auth.currentSession != null;
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> register({
    required String employeeNumber,
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String roleId,
  }) async {
    // 1. Buat akun Auth
    final response = await _auth.signUp(
      email: email,
      password: password,
    );

    final user = response.user;

    if (user == null) {
      throw Exception(
        'User Auth gagal dibuat.',
      );
    }

    // 2. Buat data employee
    //    employees.id = auth.users.id
    await SupabaseService.client
        .from('employees')
        .insert({
      'id': user.id,
      'employee_number': employeeNumber,
      'full_name': fullName,
      'phone': phone.isEmpty ? null : phone,
      'role_id': roleId,
      'is_active': true,
    });
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }
}
