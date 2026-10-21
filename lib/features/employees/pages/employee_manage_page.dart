import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/employee_role_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/employee_service.dart';

/// Halaman admin "Kelola Pegawai" -- daftar semua pegawai & tombol
/// aktif/nonaktifkan. BUKAN antrian approval: pegawai baru yang register
/// tetap langsung aktif seperti biasa. Ini murni supaya admin bisa
/// menonaktifkan pegawai yang sudah tidak bekerja lagi (mis. resign),
/// sehingga dia tidak bisa login lagi.
class EmployeeManagePage extends ConsumerStatefulWidget {
  const EmployeeManagePage({super.key});

  @override
  ConsumerState<EmployeeManagePage> createState() =>
      _EmployeeManagePageState();
}

class _EmployeeManagePageState extends ConsumerState<EmployeeManagePage> {
  String? _busyEmployeeId;

  @override
  void initState() {
    super.initState();

    // Selalu tampilkan data terbaru tiap halaman ini dibuka -- pegawai
    // yang baru saja register mungkin belum tercermin di cache Riverpod
    // dari sesi sebelumnya.
    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(allEmployeesProvider);
    });
  }

  String _roleName(List<EmployeeRoleModel>? roles, String roleId) {
    if (roles == null) return '';

    for (final role in roles) {
      if (role.id == roleId) return role.name;
    }

    return '';
  }

  Future<void> _toggleActive(EmployeeModel employee) async {
    setState(() => _busyEmployeeId = employee.id);

    try {
      await EmployeeService.setActive(employee.id, !employee.isActive);
      ref.invalidate(allEmployeesProvider);
      ref.invalidate(driverEmployeesProvider);
      ref.invalidate(helperEmployeesProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status pegawai: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyEmployeeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(allEmployeesProvider);
    final rolesAsync = ref.watch(employeeRolesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kelola Pegawai'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: employeesAsync.when(
        data: (employees) {
          if (employees.isEmpty) {
            return const ErrorStateView(
              title: 'Belum ada pegawai.',
              message: 'Pegawai akan muncul di sini setelah register.',
              icon: Icons.people_outline_rounded,
            );
          }

          final roles = rolesAsync.value;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: employees.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final employee = employees[index];

              return _EmployeeTile(
                employee: employee,
                roleName: _roleName(roles, employee.roleId),
                isBusy: _busyEmployeeId == employee.id,
                onToggleActive: () => _toggleActive(employee),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.blue),
        ),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat daftar pegawai.',
          message: error.toString(),
          onRetry: () => ref.invalidate(allEmployeesProvider),
        ),
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final EmployeeModel employee;
  final String roleName;
  final bool isBusy;
  final VoidCallback onToggleActive;

  const _EmployeeTile({
    required this.employee,
    required this.roleName,
    required this.isBusy,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (employee.isActive ? AppColors.green : AppColors.textSecondary)
              .withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person_rounded, color: AppColors.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (roleName.isNotEmpty) roleName,
                      if (employee.phone != null) employee.phone!,
                    ].join(' • '),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (employee.isActive ? AppColors.green : AppColors.textSecondary)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      employee.isActive ? 'Aktif' : 'Nonaktif',
                      style: TextStyle(
                        color: employee.isActive ? AppColors.green : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isBusy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: employee.isActive,
                activeColor: AppColors.green,
                onChanged: (_) => onToggleActive(),
              ),
          ],
        ),
      ),
    );
  }
}
