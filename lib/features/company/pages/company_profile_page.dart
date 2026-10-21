import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/company_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/company_service.dart';

/// Halaman Admin untuk isi/ubah profil perusahaan (nama, alamat, logo).
///
/// Cuma 1 baris data (bukan tabel master multi-row) -- dipakai sebagai
/// kop di semua cetakan (resi, manifest, daftar resi per tujuan). Diisi
/// sekali, tinggal diubah lagi kalau memang ada perubahan.
class CompanyProfilePage extends ConsumerStatefulWidget {
  const CompanyProfilePage({super.key});

  @override
  ConsumerState<CompanyProfilePage> createState() => _CompanyProfilePageState();
}

class _CompanyProfilePageState extends ConsumerState<CompanyProfilePage> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _gpsIntervalController = TextEditingController(text: '900');
  final _companyPublicUrlController = TextEditingController();
  final _resiOverdueDaysController = TextEditingController(text: '3');

  String? _companyId;
  String? _logoUrl;
  XFile? _pickedLogo;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _gpsIntervalController.dispose();
    _companyPublicUrlController.dispose();
    _resiOverdueDaysController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final company = await CompanyService.getCompany();

      if (!mounted) return;

      setState(() {
        if (company != null) {
          _companyId = company.id;
          _nameController.text = company.name;
          _addressController.text = company.address ?? '';
          _phoneController.text = company.phone ?? '';
          _gpsIntervalController.text = company.gpsPingIntervalSeconds.toString();
          _companyPublicUrlController.text = company.companyPublicUrl ?? '';
          _resiOverdueDaysController.text = company.resiOverdueDays.toString();
          _logoUrl = company.logoUrl;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _pickLogo() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (photo == null) return;

    setState(() {
      _pickedLogo = photo;
      _isUploadingLogo = true;
    });

    try {
      final bytes = await photo.readAsBytes();
      final url = await CompanyService.uploadLogo(bytes);

      if (!mounted) return;

      setState(() {
        _logoUrl = url;
        _isUploadingLogo = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isUploadingLogo = false;
        _errorMessage = 'Gagal upload logo: $e';
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Nama perusahaan wajib diisi.');
      return;
    }

    final gpsIntervalSeconds = int.tryParse(_gpsIntervalController.text.trim());

    if (gpsIntervalSeconds == null || gpsIntervalSeconds < 1) {
      setState(() => _errorMessage =
          'Interval kirim lokasi GPS harus diisi angka detik, minimal 1.');
      return;
    }

    final resiOverdueDays = int.tryParse(_resiOverdueDaysController.text.trim());

    if (resiOverdueDays == null || resiOverdueDays < 1) {
      setState(() => _errorMessage =
          'Batas hari resi terlambat harus diisi angka hari, minimal 1.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final company = await CompanyService.saveCompany(
        id: _companyId,
        name: name,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        logoUrl: _logoUrl,
        gpsPingIntervalSeconds: gpsIntervalSeconds,
        companyPublicUrl: _companyPublicUrlController.text.trim().isEmpty
            ? null
            : _companyPublicUrlController.text.trim(),
        resiOverdueDays: resiOverdueDays,
      );

      _companyId = company.id;

      ref.invalidate(companyProvider);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil perusahaan tersimpan.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profil Perusahaan',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Dipakai sebagai kop semua cetakan',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.blue),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                children: [
                  _buildLogoSection(),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      children: [
                        AppTextField(
                          controller: _nameController,
                          label: 'Nama Perusahaan',
                          hint: 'Contoh: PT. TRANS',
                          icon: Icons.business_rounded,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _addressController,
                          label: 'Alamat',
                          hint: 'Alamat kantor pusat',
                          icon: Icons.location_on_outlined,
                          maxLines: 2,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _phoneController,
                          label: 'No. HP / Telepon',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          enabled: !_isSaving,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tracking GPS Sopir',
                          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _gpsIntervalController,
                          label: 'Interval Kirim Lokasi (detik)',
                          hint: 'Contoh: 900 (15 menit) untuk produksi',
                          icon: Icons.timer_outlined,
                          keyboardType: TextInputType.number,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 10),
                        const InfoBanner(
                          variant: InfoBannerVariant.info,
                          message: 'Untuk pemakaian sehari-hari, biarkan 900 (15 menit) supaya '
                              'baterai HP sopir & kuota data tidak boros. Untuk UJI COBA saja, '
                              'boleh diisi angka kecil (mis. 1 atau 10 detik) supaya tidak perlu '
                              'nunggu lama lihat titik lokasi baru masuk -- ingat balikin lagi ke '
                              '900 setelah selesai uji coba. Perubahan ini kepakai untuk '
                              'PERJALANAN BERIKUTNYA (tekan "Mulai Perjalanan" lagi), bukan '
                              'perjalanan yang sedang berlangsung saat ini.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cek Resi (Website Terpisah)',
                          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _companyPublicUrlController,
                          label: 'Link Website Cek Resi',
                          hint: 'Contoh: https://cek-resi-trans.netlify.app',
                          icon: Icons.link_rounded,
                          keyboardType: TextInputType.url,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 10),
                        const InfoBanner(
                          variant: InfoBannerVariant.info,
                          message: 'Isi dengan link WEBSITE TERPISAH (bukan bagian dari app ini) '
                              'yang khusus untuk pelanggan cek status resi sendiri -- lihat '
                              'paket website & panduan deploy-nya yang dikirim terpisah dari '
                              'project app ini. Link ini ditampilkan di footer teks WhatsApp ke '
                              'tujuan & footer cetakan Resi. Kosongkan kalau website itu belum '
                              'di-deploy -- baris link TIDAK akan muncul di cetakan. Kalau nanti '
                              'domain hosting website itu berubah, cukup update link ini saja, '
                              'TIDAK perlu build ulang APK/web app ini.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monitoring Resi Terlambat',
                          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _resiOverdueDaysController,
                          label: 'Batas Hari Resi Terlambat',
                          hint: 'Contoh: 3 (hari)',
                          icon: Icons.warning_amber_rounded,
                          keyboardType: TextInputType.number,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 10),
                        const InfoBanner(
                          variant: InfoBannerVariant.info,
                          message: 'Resi yang statusnya MASIH "Penerimaan" (belum pernah '
                              'dimuat/di-loading sama sekali) akan ditandai KOTAK MERAH di '
                              'Monitoring Resi Admin & Supervisor begitu sudah lewat dari '
                              'jumlah hari ini, dihitung dari tanggal resi diterima. Resi '
                              'yang sudah "Masih Perjalanan" atau "Selesai" TIDAK ditandai '
                              'merah, berapa pun lama usianya.',
                        ),
                      ],
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    InfoBanner(
                      variant: InfoBannerVariant.error,
                      message: _errorMessage!,
                      onDismiss: () => setState(() => _errorMessage = null),
                    ),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Simpan Profil',
                    loadingLabel: 'Menyimpan...',
                    isLoading: _isSaving,
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: _save,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: _isUploadingLogo
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.blue),
                  )
                : (_logoUrl != null
                    ? Image.network(
                        _logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.business_rounded,
                          size: 44,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : const Icon(
                        Icons.business_rounded,
                        size: 44,
                        color: AppColors.textSecondary,
                      )),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isUploadingLogo ? null : _pickLogo,
            icon: const Icon(Icons.image_outlined),
            label: Text(_logoUrl == null ? 'Pilih Logo' : 'Ganti Logo'),
          ),
        ],
      ),
    );
  }
}
