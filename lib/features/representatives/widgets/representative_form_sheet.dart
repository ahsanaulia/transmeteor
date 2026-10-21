import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/representative_model.dart';
import '../../../services/representative_service.dart';

/// Bottom sheet "Tambah/Edit Perwakilan" -- dipakai admin di halaman
/// "Daftar Perwakilan", DAN dipakai sopir di `RepresentativeHandoffPage`
/// lewat dialog ringkas yang sama datanya (lihat
/// `_showCreateRepresentativeDialog` di halaman itu -- dialog itu
/// sengaja bentuk `AlertDialog` ringkas, bukan bottom sheet ini, supaya
/// konsisten dengan pola `_showCreateSenderDialog`/
/// `_showCreateDestinationDialog` di alur input resi; sheet ini KHUSUS
/// dipakai admin).
///
/// Mengikuti pola PERSIS `DestinationFormSheet` TAPI tanpa titik peta --
/// perwakilan tidak punya lat/long di tabelnya (permintaan user cuma
/// "menulis nama perwakilan dan alamatnya").
///
/// [existing] null -> mode tambah baru. [existing] terisi -> mode edit,
/// form di-prefill dari data itu dan simpan memanggil
/// updateRepresentative (bukan createRepresentative).
class RepresentativeFormSheet extends ConsumerStatefulWidget {
  final RepresentativeModel? existing;

  const RepresentativeFormSheet({super.key, this.existing});

  @override
  ConsumerState<RepresentativeFormSheet> createState() =>
      _RepresentativeFormSheetState();
}

class _RepresentativeFormSheetState
    extends ConsumerState<RepresentativeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  String? _errorMessage;
  bool _isSaving = false;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _nameController = TextEditingController(text: existing?.name ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _addressController = TextEditingController(text: existing?.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim();
      final phoneText = _phoneController.text.trim();
      final addressText = _addressController.text.trim();

      if (_isEditMode) {
        await RepresentativeService.updateRepresentative(
          id: widget.existing!.id,
          name: name,
          phone: phoneText.isEmpty ? null : phoneText,
          address: addressText.isEmpty ? null : addressText,
        );
      } else {
        await RepresentativeService.createRepresentative(
          name: name,
          phone: phoneText.isEmpty ? null : phoneText,
          address: addressText.isEmpty ? null : addressText,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = _isEditMode
            ? 'Gagal menyimpan perubahan: $e'
            : 'Gagal menambahkan perwakilan: $e';
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
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
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
                    _isEditMode ? 'Edit Perwakilan' : 'Tambah Perwakilan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Daftarkan perwakilan/agen titipan barang di sini -- '
                    'dipakai sopir saat tujuan asli tutup/tidak bisa '
                    'dijangkau sehingga barang dititip dulu di sini, '
                    'bukan langsung di tujuan.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Perwakilan',
                      hintText: 'Contoh: Toko Agen Jaya - Blitar',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Nama perwakilan wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'No. HP (opsional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Alamat',
                      hintText: 'Alamat lengkap tempat barang dititip',
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isEditMode ? 'Simpan Perubahan' : 'Simpan Perwakilan',
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
