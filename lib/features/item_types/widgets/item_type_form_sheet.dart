import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/item_type_model.dart';
import '../../../services/item_type_service.dart';

/// Bottom sheet "Tambah/Edit Jenis Barang" -- dipakai admin di halaman
/// "Kelola Jenis Barang" (8 Oktober 2026). Mirror PERSIS
/// `PricingTypeFormSheet`, TANPA field harga (jenis barang tidak punya
/// harga -- itu urusan Jenis Tarif, lihat `pricing_type_form_sheet.dart`).
///
/// [existing] null -> mode tambah baru. [existing] terisi -> mode edit.
class ItemTypeFormSheet extends ConsumerStatefulWidget {
  final ItemTypeModel? existing;

  const ItemTypeFormSheet({super.key, this.existing});

  @override
  ConsumerState<ItemTypeFormSheet> createState() => _ItemTypeFormSheetState();
}

class _ItemTypeFormSheetState extends ConsumerState<ItemTypeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _handlingController;
  late final TextEditingController _descriptionController;

  String? _errorMessage;
  bool _isSaving = false;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _codeController = TextEditingController(text: existing?.code ?? '');
    _nameController = TextEditingController(text: existing?.name ?? '');
    _handlingController = TextEditingController(text: existing?.handling ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _handlingController.dispose();
    _descriptionController.dispose();
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
      final handlingText = _handlingController.text.trim();
      final descriptionText = _descriptionController.text.trim();

      if (_isEditMode) {
        await ItemTypeService.updateItemType(
          id: widget.existing!.id,
          code: code,
          name: name,
          handling: handlingText.isEmpty ? null : handlingText,
          description: descriptionText.isEmpty ? null : descriptionText,
        );
      } else {
        await ItemTypeService.createItemType(
          code: code,
          name: name,
          handling: handlingText.isEmpty ? null : handlingText,
          description: descriptionText.isEmpty ? null : descriptionText,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = _isEditMode
            ? 'Gagal menyimpan perubahan: $e'
            : 'Gagal menambahkan jenis barang: $e';
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
                    _isEditMode ? 'Edit Jenis Barang' : 'Tambah Jenis Barang',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Jenis barang dipakai saat input resi (Penerimaan) untuk '
                    'menentukan kategori barang. Tambahkan jenis baru di sini '
                    'setiap kali ada jenis barang baru.',
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
                      hintText: 'Contoh: item006',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Kode wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Jenis Barang',
                      hintText: 'Contoh: Sparepart Motor',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Nama wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _handlingController,
                    decoration: const InputDecoration(
                      labelText: 'Penanganan Khusus (opsional)',
                      hintText: 'Contoh: Mudah pecah, Jangan ditumpuk',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan (opsional)',
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isEditMode ? 'Simpan Perubahan' : 'Simpan Jenis Barang',
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
