import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/vehicle_service.dart';

/// Bottom sheet "Siapkan Kendaraan" / "Pendataan Armada" -- dipakai
/// untuk menetapkan/mengganti sopir & (maksimal 3) helper sebuah
/// kendaraan.
///
/// **DIUBAH (10 Oktober 2026)**: kendaraan SUDAH tampil di "Pilih
/// Kendaraan" Loading SEBELUM sheet ini dibuka sama sekali (lihat
/// `VehicleService.getVehicles`) -- sheet ini hanya perlu dibuka supaya
/// kendaraan punya sopir, yang baru wajib ada SAAT shipment benar-benar
/// mulai dibuat. Status "Dalam Perjalanan"/"Siap Dimuat" TIDAK lagi
/// terkait dengan disimpan/tidaknya sheet ini -- itu dihitung live dari
/// shipment aktif kendaraan (lihat `VehicleSelectPage`).
class PrepareVehicleSheet extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const PrepareVehicleSheet({super.key, required this.vehicle});

  @override
  ConsumerState<PrepareVehicleSheet> createState() =>
      _PrepareVehicleSheetState();
}

class _PrepareVehicleSheetState extends ConsumerState<PrepareVehicleSheet> {
  static const _maxHelpers = 3;

  EmployeeModel? _selectedDriver;
  final Set<String> _selectedHelperIds = {};
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _selectedHelperIds.addAll(
      [
        widget.vehicle.helper1EmployeeId,
        widget.vehicle.helper2EmployeeId,
        widget.vehicle.helper3EmployeeId,
      ].whereType<String>(),
    );
  }

  EmployeeModel? _resolveSelectedDriver(List<EmployeeModel>? drivers) {
    if (_selectedDriver != null) return _selectedDriver;
    if (widget.vehicle.driverEmployeeId == null || drivers == null) return null;

    for (final driver in drivers) {
      if (driver.id == widget.vehicle.driverEmployeeId) return driver;
    }

    return null;
  }

  Future<void> _save() async {
    final drivers = ref.read(driverEmployeesProvider).value;
    final driver = _resolveSelectedDriver(drivers);

    if (driver == null) {
      setState(() => _errorMessage = 'Sopir wajib dipilih.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await VehicleService.prepareVehicle(
        vehicleId: widget.vehicle.id,
        driverEmployeeId: driver.id,
        driverName: driver.fullName,
        driverPhone: driver.phone,
        helperEmployeeIds: _selectedHelperIds.toList(),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal menyiapkan kendaraan: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deactivate() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await VehicleService.setActive(widget.vehicle.id, false);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal menonaktifkan kendaraan: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driverEmployeesProvider);
    final helpersAsync = ref.watch(helperEmployeesProvider);
    final currentDriver = _resolveSelectedDriver(driversAsync.value);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.68,
        minChildSize: 0.4,
        maxChildSize: 0.94,
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
                Text(
                  'Siapkan ${widget.vehicle.plateNumber}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tentukan sopir & helper kendaraan ini. Kendaraan ini '
                  'sudah muncul di "Pilih Kendaraan" Loading -- sopir wajib '
                  'diisi di sini sebelum bisa dipakai untuk mulai memuat '
                  'barang.',
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
                  onClear: () => setState(() => _selectedDriver = null),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Helper (opsional, maks 3 orang)',
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
                        final reachedLimit =
                            !checked && _selectedHelperIds.length >= _maxHelpers;

                        return CheckboxListTile(
                          value: checked,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            helper.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: helper.phone != null
                              ? Text(helper.phone!)
                              : (reachedLimit
                                  ? const Text(
                                      'Maks 3 helper sudah dipilih',
                                      style: TextStyle(fontSize: 11),
                                    )
                                  : null),
                          onChanged: reachedLimit
                              ? null
                              : (value) {
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
                  label: 'Simpan & Aktifkan',
                  loadingLabel: 'Menyimpan...',
                  isLoading: _isSaving,
                  icon: Icons.check_circle_rounded,
                  backgroundColor: AppColors.green,
                  onPressed: _save,
                ),
                if (widget.vehicle.isActive) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isSaving ? null : _deactivate,
                      child: const Text('Nonaktifkan Kendaraan (Permanen)'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}