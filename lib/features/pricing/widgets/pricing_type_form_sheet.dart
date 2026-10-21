import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/pricing_type_model.dart';
import '../../../services/pricing_type_service.dart';

/// Bottom sheet "Tambah/Edit Jenis Harga" -- dipakai admin di halaman
/// "Kelola Jenis Harga" untuk menambah jenis harga baru (mis. saat ada
/// jenis kiriman baru) atau mengubah kode/nama/harga yang sudah ada.
///
/// [existing] null -> mode tambah baru. [existing] terisi -> mode edit,
/// form di-prefill dari data itu dan simpan memanggil updatePricingType
/// (bukan createPricingType).
class PricingTypeFormSheet extends ConsumerStatefulWidget {
  final PricingTypeModel? existing;

  const PricingTypeFormSheet({super.key, this.existing});

  @override
  ConsumerState<PricingTypeFormSheet> createState() =>
      _PricingTypeFormSheetState();
}

class _PricingTypeFormSheetState extends ConsumerState<PricingTypeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;

  String? _errorMessage;
  bool _isSaving = false;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _codeController = TextEditingController(text: existing?.code ?? '');
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _priceController = TextEditingController(
      text: existing == null ? '' : _trimNumber(existing.price),
    );
  }

  String _trimNumber(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final code = _codeController.text.trim();
      final name = _nameController.text.trim();
      final descriptionText = _descriptionController.text.trim();
      final price = double.parse(_priceController.text.trim());

      if (_isEditMode) {
        await PricingTypeService.updatePricingType(
          id: widget.existing!.id,
          code: code,
          name: name,
          description: descriptionText.isEmpty ? null : descriptionText,
          price: price,
        );
      } else {
        await PricingTypeService.createPricingType(
          code: code,
          name: name,
          description: descriptionText.isEmpty ? null : descriptionText,
          price: price,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = _isEditMode
            ? 'Gagal menyimpan perubahan: $e'
            : 'Gagal menambahkan jenis harga: $e';
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Form(
              key: _formKey,
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
                    _isEditMode ? 'Edit Jenis Harga' : 'Tambah Jenis Harga',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Jenis harga dipakai saat input resi (Penerimaan) untuk '
                    'menentukan harga per unit barang. Tambahkan jenis baru '
                    'di sini setiap kali ada jenis kiriman baru.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Kode',
                      hintText: 'Contoh: price006',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Kode wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Jenis Harga',
                      hintText: 'Contoh: Ban Motor / pieces',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Nama wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan (opsional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Harga (Rp)',
                      hintText: 'Contoh: 25000',
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';

                      if (trimmed.isEmpty) return 'Harga wajib diisi';

                      final parsed = double.tryParse(trimmed);

                      if (parsed == null || parsed < 0) {
                        return 'Harga tidak valid';
                      }

                      return null;
                    },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isEditMode ? 'Simpan Perubahan' : 'Simpan Jenis Harga',
                    loadingLabel: 'Menyimpan...',
                    isLoading: _isSaving,
                    icon: Icons.check_circle_rounded,
                    backgroundColor: AppColors.green,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
