import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/destination_model.dart';
import '../../../services/destination_service.dart';
import '../../receiving/pages/destination_picker_map_page.dart';

/// Bottom sheet "Tambah/Edit Tujuan" -- dipakai admin di halaman
/// "Daftar Langganan Tujuan" untuk mendaftarkan tujuan langganan baru
/// (sebelum dipakai staff Receiving di lapangan) atau mengubah data
/// tujuan yang sudah ada.
///
/// [existing] null -> mode tambah baru. [existing] terisi -> mode edit,
/// form di-prefill dari data itu dan simpan memanggil updateDestination
/// (bukan createDestination).
///
/// Titik lokasi (lat/long) OPSIONAL -- admin bisa langsung tentukan lewat
/// peta (reuse `DestinationPickerMapPage` yang sama dipakai di alur
/// Receiving) supaya nanti staff yang menerima barang ke tujuan ini tidak
/// perlu menandai titiknya lagi dari nol. Kalau tidak diisi di sini,
/// tetap bisa ditentukan belakangan lewat form input resi seperti biasa.
class DestinationFormSheet extends ConsumerStatefulWidget {
  final DestinationModel? existing;

  const DestinationFormSheet({super.key, this.existing});

  @override
  ConsumerState<DestinationFormSheet> createState() =>
      _DestinationFormSheetState();
}

class _DestinationFormSheetState extends ConsumerState<DestinationFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  double? _latitude;
  double? _longitude;

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
    _latitude = existing?.latitude;
    _longitude = existing?.longitude;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => DestinationPickerMapPage(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _latitude = picked.latitude;
        _longitude = picked.longitude;
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
    });
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
        await DestinationService.updateDestination(
          id: widget.existing!.id,
          name: name,
          phone: phoneText.isEmpty ? null : phoneText,
          address: addressText.isEmpty ? null : addressText,
          latitude: _latitude,
          longitude: _longitude,
        );
      } else {
        await DestinationService.createDestination(
          name: name,
          phone: phoneText.isEmpty ? null : phoneText,
          address: addressText.isEmpty ? null : addressText,
          latitude: _latitude,
          longitude: _longitude,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = _isEditMode
            ? 'Gagal menyimpan perubahan: $e'
            : 'Gagal menambahkan tujuan: $e';
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
    final hasLocation = _latitude != null && _longitude != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
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
                    _isEditMode ? 'Edit Tujuan' : 'Tambah Tujuan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Daftarkan tujuan langganan di sini supaya staff '
                    'Receiving tinggal cari & pilih saat input resi -- '
                    'tidak perlu ketik ulang dari nol tiap kali ada '
                    'kiriman ke tujuan yang sama.',
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
                      labelText: 'Nama Tujuan',
                      hintText: 'Contoh: Toko Makmur Jaya - Surabaya',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Nama tujuan wajib diisi'
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
                      labelText: 'Alamat (opsional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (hasLocation)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: AppColors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_latitude!.toStringAsFixed(6)}, '
                              '${_longitude!.toStringAsFixed(6)}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _isSaving ? null : _clearLocation,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Hapus titik lokasi',
                          ),
                        ],
                      ),
                    ),
                  if (hasLocation) const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickOnMap,
                    icon: const Icon(Icons.map_rounded),
                    label: Text(hasLocation ? 'Ubah Titik di Peta' : 'Pilih Titik di Peta (opsional)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.blue,
                      side: BorderSide(color: AppColors.blue.withOpacity(0.25)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isEditMode ? 'Simpan Perubahan' : 'Simpan Tujuan',
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
