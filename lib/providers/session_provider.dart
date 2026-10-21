import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee_model.dart';
import '../models/employee_role_model.dart';
import '../services/employee_service.dart';
import '../services/role_service.dart';

/// Data employee yang sedang login.
///
/// Riverpod meng-cache hasilnya secara otomatis, jadi halaman mana pun
/// yang butuh tahu "siapa yang sedang login" cukup
/// `ref.watch(currentEmployeeProvider)` -- tidak perlu fetch sendiri
/// seperti sebelumnya (SplashPage & ReceivingHomePage dulu masing-masing
/// memanggil EmployeeService.getCurrentEmployee() sendiri-sendiri).
final currentEmployeeProvider = FutureProvider<EmployeeModel?>((ref) {
  return EmployeeService.getCurrentEmployee();
});

/// Role dari employee yang sedang login.
///
/// Otomatis mengikuti [currentEmployeeProvider]: kalau employee-nya
/// null, role juga null tanpa perlu fetch tambahan.
final currentRoleProvider = FutureProvider<EmployeeRoleModel?>((ref) async {
  final employee = await ref.watch(currentEmployeeProvider.future);

  if (employee == null) {
    return null;
  }

  return RoleService.getRoleById(employee.roleId);
});

/// Panggil ini setelah login atau logout supaya provider session di atas
/// mengambil data baru pada kunjungan berikutnya, bukan memakai cache
/// dari akun sebelumnya.
void invalidateSession(WidgetRef ref) {
  ref.invalidate(currentEmployeeProvider);
  ref.invalidate(currentRoleProvider);
}
