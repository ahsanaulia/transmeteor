import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/representative_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/representative_service.dart';
import '../widgets/representative_form_sheet.dart';

/// Halaman admin "Daftar Perwakilan" -- daftar semua perwakilan/agen
/// titipan barang (representatives), tombol tambah perwakilan baru,
/// edit perwakilan yang sudah ada, dan aktif/nonaktifkan. Mengikuti pola
/// PERSIS `DestinationManagePage` (permintaan user, 6 Oktober 2026
/// lanjutan: "Tambahkan di aplikasi admin : CRUD : Daftar Perwakilan").
///
/// Tabel `representatives` ini juga dipakai sopir di
/// `RepresentativeHandoffPage` (fitur "Selesaikan di Perwakilan") --
/// perwakilan bisa didaftarkan lebih dulu dari sini oleh admin, ATAU
/// langsung di lapangan oleh sopir lewat dialog ringkas kalau belum ada
/// (keduanya menulis ke tabel yang sama, saling melihat data terbaru
/// masing-masing).
///
/// Menonaktifkan perwakilan TIDAK menghapusnya -- cuma bikin perwakilan
/// itu tidak lagi muncul di pencarian sopir saat menitip barang baru.
/// Riwayat handoff lama yang sudah memakai perwakilan itu tetap utuh.
class RepresentativeManagePage extends ConsumerStatefulWidget {
  const RepresentativeManagePage({super.key});

  @override
  ConsumerState<RepresentativeManagePage> createState() =>
      _RepresentativeManagePageState();
}

class _RepresentativeManagePageState
    extends ConsumerState<RepresentativeManagePage> {
  String? _busyRepresentativeId;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });

    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(allRepresentativesProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Cocokkan keyword ke nama, nomor HP, ATAU alamat perwakilan -- supaya
  /// admin bisa cari "0812..." atau sepotong alamat, tidak cuma nama.
  List<RepresentativeModel> _filterRepresentatives(
    List<RepresentativeModel> representatives,
  ) {
    if (_searchQuery.isEmpty) return representatives;

    return representatives.where((representative) {
      final name = representative.name.toLowerCase();
      final phone = representative.phone?.toLowerCase() ?? '';
      final address = representative.address?.toLowerCase() ?? '';
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          address.contains(_searchQuery);
    }).toList();
  }

  void _refreshAll() {
    ref.invalidate(allRepresentativesProvider);
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RepresentativeFormSheet(),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _openEditSheet(RepresentativeModel representative) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RepresentativeFormSheet(existing: representative),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _toggleActive(RepresentativeModel representative) async {
    setState(() => _busyRepresentativeId = representative.id);

    try {
      await RepresentativeService.setActive(
        representative.id,
        !representative.isActive,
      );
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status perwakilan: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyRepresentativeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final representativesAsync = ref.watch(allRepresentativesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Daftar Perwakilan'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Perwakilan'),
        backgroundColor: AppColors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Perwakilan',
                hint: 'Cari nama, nomor HP, atau alamat perwakilan...',
                icon: Icons.search_rounded,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Hapus pencarian',
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
            Expanded(
              child: representativesAsync.when(
                data: (representatives) {
                  if (representatives.isEmpty) {
                    return ErrorStateView(
                      title: 'Belum ada perwakilan.',
                      message: 'Tambahkan perwakilan baru lewat tombol di bawah.',
                      icon: Icons.storefront_outlined,
                      onRetry: _openAddSheet,
                    );
                  }

                  final filtered = _filterRepresentatives(representatives);

                  if (filtered.isEmpty) {
                    // Tanpa `onRetry` SENGAJA -- tombol bawaan
                    // `ErrorStateView` selalu berlabel "Coba Lagi" (cocok
                    // untuk retry fetch, BUKAN untuk "hapus pencarian").
                    return ErrorStateView(
                      title: 'Perwakilan tidak ditemukan.',
                      message: 'Tidak ada perwakilan yang cocok dengan "${_searchController.text}".',
                      icon: Icons.search_off_rounded,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final representative = filtered[index];

                      return _RepresentativeTile(
                        representative: representative,
                        isBusy: _busyRepresentativeId == representative.id,
                        onTap: () => _openEditSheet(representative),
                        onToggleActive: () => _toggleActive(representative),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar perwakilan.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allRepresentativesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ringkasan detail perwakilan buat subtitle di tile -- gabungkan
/// telepon/alamat yang terisi saja, dipisah "•".
String _buildSubtitle(RepresentativeModel representative) {
  final parts = [
    if (representative.phone != null && representative.phone!.isNotEmpty)
      representative.phone!,
    if (representative.address != null && representative.address!.isNotEmpty)
      representative.address!,
  ];

  return parts.isEmpty ? 'Belum ada detail tambahan' : parts.join(' • ');
}

class _RepresentativeTile extends StatelessWidget {
  final RepresentativeModel representative;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _RepresentativeTile({
    required this.representative,
    required this.isBusy,
    required this.onTap,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (representative.isActive ? AppColors.green : AppColors.textSecondary)
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: AppColors.orange),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        representative.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _buildSubtitle(representative),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (representative.isActive ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          representative.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: representative.isActive
                                ? AppColors.green
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBusy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: representative.isActive,
                    activeColor: AppColors.green,
                    onChanged: (_) => onToggleActive(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
