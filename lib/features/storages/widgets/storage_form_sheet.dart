import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/storage_model.dart';
import '../../../services/storage_service.dart';

/// Bottom sheet "Tambah/Edit Zona Storage" -- dipakai admin di halaman
/// "Zona Storage" (8 Oktober 2026, permintaan user poin 10). Paling
/// sederhana dari semua form sheet master data di app ini -- cuma 2
/// field (nama_zona, deskripsi), TANPA kode/harga/telepon/titik peta.
///
/// [existing] null -> mode tambah baru. [existing] terisi -> mode edit.
class StorageFormSheet extends ConsumerStatefulWidget {
  final StorageModel? existing;

  const StorageFormSheet({super.key, this.existing});

  @override
  ConsumerState<StorageFormSheet> createState() => _StorageFormSheetState();
}

class _StorageFormSheetState extends ConsumerState<StorageFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _namaZonaController;
  late final TextEditingController _deskripsiController;

  String? _errorMessage;
  bool _isSaving = false;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _namaZonaController = TextEditingController(text: existing?.namaZona ?? '');
    _deskripsiController = TextEditingController(text: existing?.deskripsi ?? '');
  }

  @override
  void dispose() {
    _namaZonaController.dispose();
    _deskripsiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final namaZona = _namaZonaController.text.trim();
      final deskripsiText = _deskripsiController.text.trim();

      if (_isEditMode) {
        await StorageService.updateStorage(
          id: widget.existing!.id,
          namaZona: namaZona,
          deskripsi: deskripsiText.isEmpty ? null : deskripsiText,
        );
      } else {
        await StorageService.createStorage(
          namaZona: namaZona,
          deskripsi: deskripsiText.isEmpty ? null : deskripsiText,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = _isEditMode
            ? 'Gagal menyimpan perubahan: $e'
            : 'Gagal menambahkan zona storage: $e';
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
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.8,
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
                    _isEditMode ? 'Edit Zona Storage' : 'Tambah Zona Storage',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Zona dipakai saat input detail barang (Penerimaan) '
                    'untuk menandai di mana barang diletakkan di gudang, '
                    'supaya staff Loading tahu ke mana harus mengambilnya.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _namaZonaController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Zona',
                      hintText: 'Contoh: Zona A, Rak 1, Gudang Belakang',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Nama zona wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _deskripsiController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi (opsional)',
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isEditMode ? 'Simpan Perubahan' : 'Simpan Zona',
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
