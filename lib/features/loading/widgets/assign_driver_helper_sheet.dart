import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../providers/master_data_providers.dart';

/// Hasil pilihan dari [AssignDriverHelperSheet].
class DriverHelperAssignment {
  final String driverEmployeeId;
  final List<String> helperEmployeeIds;

  const DriverHelperAssignment({
    required this.driverEmployeeId,
    required this.helperEmployeeIds,
  });
}

/// Bottom sheet pilih sopir (wajib) & helper (opsional, boleh lebih dari
/// satu) sebelum shipment baru dibuat -- dipanggil sekali per shipment,
/// saat staff Loading mulai muat barang.
///
/// Helper HANYA dipilih kalau dia memang ikut naik ke kendaraan & perlu
/// dilacak lokasinya. Kalau perannya cuma bantu angkat barang di titik
/// muat (tidak ikut jalan), jangan dipilih di sini.
class AssignDriverHelperSheet extends ConsumerStatefulWidget {
  final String? initialDriverEmployeeId;

  const AssignDriverHelperSheet({super.key, this.initialDriverEmployeeId});

  @override
  ConsumerState<AssignDriverHelperSheet> createState() =>
      _AssignDriverHelperSheetState();
}

class _AssignDriverHelperSheetState
    extends ConsumerState<AssignDriverHelperSheet> {
  EmployeeModel? _selectedDriver;
  final Set<String> _selectedHelperIds = {};
  String? _errorMessage;

  EmployeeModel? _resolveSelectedDriver(List<EmployeeModel>? drivers) {
    if (_selectedDriver != null) return _selectedDriver;
    if (widget.initialDriverEmployeeId == null || drivers == null) return null;

    for (final driver in drivers) {
      if (driver.id == widget.initialDriverEmployeeId) return driver;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driverEmployeesProvider);
    final helpersAsync = ref.watch(helperEmployeesProvider);
    final currentDriver = _resolveSelectedDriver(driversAsync.value);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E4EC),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sopir & Helper Perjalanan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sopir wajib dipilih supaya lokasinya bisa dilacak selama '
                  'perjalanan. Helper cukup dipilih kalau memang ikut naik '
                  'ke kendaraan.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                PickerField<EmployeeModel>(
                  label: 'Sopir',
                  hint: 'Pilih sopir',
                  sheetTitle: 'Pilih Sopir',
                  icon: Icons.person_pin_circle_outlined,
                  itemsAsync: driversAsync,
                  itemsProvider: driverEmployeesProvider,
                  itemLabel: (e) => e.fullName,
                  itemSubtitle: (e) => e.phone,
                  selected: currentDriver,
                  onSelected: (e) => setState(() => _selectedDriver = e),
                  onClear: () => setState(() {
                    _selectedDriver = null;
                  }),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Helper (opsional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                helpersAsync.when(
                  data: (helpers) {
                    if (helpers.isEmpty) {
                      return const Text(
                        'Belum ada employee dengan role Helper.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      );
                    }

                    return Column(
                      children: helpers.map((helper) {
                        final checked = _selectedHelperIds.contains(helper.id);

                        return CheckboxListTile(
                          value: checked,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            helper.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle:
                              helper.phone != null ? Text(helper.phone!) : null,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedHelperIds.add(helper.id);
                              } else {
                                _selectedHelperIds.remove(helper.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Text(
                    'Gagal memuat daftar helper: $error',
                    style: const TextStyle(color: AppColors.red, fontSize: 12.5),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Lanjut Muat Barang',
                  onPressed: () {
                    final driver = _resolveSelectedDriver(driversAsync.value);

                    if (driver == null) {
                      setState(() => _errorMessage = 'Sopir wajib dipilih.');
                      return;
                    }

                    Navigator.of(context).pop(
                      DriverHelperAssignment(
                        driverEmployeeId: driver.id,
                        helperEmployeeIds: _selectedHelperIds.toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}