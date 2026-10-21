import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/widgets/widgets.dart';
import '../../../services/expense_service.dart';

const _expenseTypes = [
  {'code': 'BBM', 'label': 'BBM', 'icon': Icons.local_gas_station_rounded},
  {'code': 'PENGINAPAN', 'label': 'Penginapan', 'icon': Icons.hotel_rounded},
  {'code': 'MAKAN', 'label': 'Makan', 'icon': Icons.restaurant_rounded},
];

/// Bottom sheet isi laporan pengeluaran perjalanan (BBM/Penginapan/Makan).
/// Lokasi selalu otomatis kerekam saat submit, foto struk opsional.
class ExpenseFormSheet extends StatefulWidget {
  final String shipmentId;
  final String employeeId;

  const ExpenseFormSheet({
    super.key,
    required this.shipmentId,
    required this.employeeId,
  });

  @override
  State<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<ExpenseFormSheet> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedType = 'BBM';
  XFile? _photo;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (photo != null) {
      setState(() => _photo = photo);
    }
  }

  Future<void> _save() async {
    final amount =
        double.tryParse(_amountController.text.trim().replaceAll(',', '.'));

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Nominal wajib diisi dengan angka yang benar.');
      return;
    }

    if (_notesController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Catatan wajib diisi.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final position = await LocationHelper.getCurrentPosition(context);

      if (position == null) {
        setState(() => _isSaving = false);
        return;
      }

      String? photoUrl;

      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        photoUrl = await ExpenseService.uploadReceiptPhoto(
          shipmentId: widget.shipmentId,
          bytes: bytes,
        );
      }

      await ExpenseService.createExpense(
        shipmentId: widget.shipmentId,
        employeeId: widget.employeeId,
        expenseType: _selectedType,
        amount: amount,
        notes: _notesController.text.trim(),
        photoUrl: photoUrl,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Gagal menyimpan laporan: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              'Laporan Pengeluaran',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: _expenseTypes.map((type) {
                final selected = _selectedType == type['code'];

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () =>
                          setState(() => _selectedType = type['code'] as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.blue.withOpacity(0.12)
                              : AppColors.fieldFill,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? AppColors.blue : AppColors.border,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              type['icon'] as IconData,
                              color: selected ? AppColors.blue : AppColors.textSecondary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              type['label'] as String,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: selected ? AppColors.blue : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Nominal (Rp)',
              icon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _notesController,
              label: 'Catatan',
              hint: 'Contoh: Isi solar di SPBU Cikampek',
              icon: Icons.notes_rounded,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_photo == null ? 'Foto Struk (opsional)' : 'Ganti Foto Struk'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Simpan Laporan',
              loadingLabel: 'Menyimpan...',
              isLoading: _isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}