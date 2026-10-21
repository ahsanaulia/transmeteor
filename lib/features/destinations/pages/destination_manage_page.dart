import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/destination_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/destination_service.dart';
import '../widgets/destination_form_sheet.dart';

/// Halaman admin "Daftar Langganan Tujuan" -- daftar semua tujuan
/// (destinations), tombol tambah tujuan baru, edit tujuan yang sudah
/// ada, dan aktif/nonaktifkan.
///
/// Sebelumnya tujuan cuma bisa didaftarkan "numpang" lewat form input
/// resi di Receiving (tombol "Tambah Tujuan Baru" saat mencari tujuan
/// yang belum ada). Halaman ini menambah jalur admin supaya tujuan-
/// tujuan langganan (yang sudah pasti akan dipakai berulang) bisa
/// didaftarkan lebih dulu dari sini -- staff Receiving di lapangan
/// tinggal cari & pilih, mempercepat proses input resi.
///
/// Menonaktifkan tujuan TIDAK menghapusnya -- cuma bikin tujuan itu
/// tidak lagi muncul di pencarian saat input resi baru. Riwayat resi
/// lama yang sudah memakai tujuan itu tetap utuh.
class DestinationManagePage extends ConsumerStatefulWidget {
  const DestinationManagePage({super.key});

  @override
  ConsumerState<DestinationManagePage> createState() =>
      _DestinationManagePageState();
}

class _DestinationManagePageState extends ConsumerState<DestinationManagePage> {
  String? _busyDestinationId;

  // Search (permintaan user, 6 Oktober 2026): filter dilakukan di sisi
  // aplikasi (bukan query baru ke server) karena halaman ini SUDAH
  // ambil SEMUA tujuan sekaligus (aktif maupun nonaktif) lewat
  // `allDestinationsProvider` -- beda dari `DestinationService
  // .searchDestinations` yang dipakai di alur input resi (HANYA cari
  // yang aktif). Kalau dipaksa pakai itu di sini, tujuan nonaktif jadi
  // tidak bisa dicari sama sekali oleh admin -- jadi SENGAJA filter
  // manual di sini supaya tetap bisa cari tujuan aktif & nonaktif.
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
      ref.invalidate(allDestinationsProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Cocokkan keyword ke nama, nomor HP, ATAU alamat tujuan -- supaya
  /// admin bisa cari "0812..." atau sepotong alamat, tidak cuma nama.
  List<DestinationModel> _filterDestinations(
    List<DestinationModel> destinations,
  ) {
    if (_searchQuery.isEmpty) return destinations;

    return destinations.where((destination) {
      final name = destination.name.toLowerCase();
      final phone = destination.phone?.toLowerCase() ?? '';
      final address = destination.address?.toLowerCase() ?? '';
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          address.contains(_searchQuery);
    }).toList();
  }

  void _refreshAll() {
    ref.invalidate(allDestinationsProvider);
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DestinationFormSheet(),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _openEditSheet(DestinationModel destination) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DestinationFormSheet(existing: destination),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _toggleActive(DestinationModel destination) async {
    setState(() => _busyDestinationId = destination.id);

    try {
      await DestinationService.setActive(destination.id, !destination.isActive);
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status tujuan: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyDestinationId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinationsAsync = ref.watch(allDestinationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Daftar Langganan Tujuan'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tujuan'),
        backgroundColor: AppColors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Tujuan',
                hint: 'Cari nama, nomor HP, atau alamat tujuan...',
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
              child: destinationsAsync.when(
                data: (destinations) {
                  if (destinations.isEmpty) {
                    return ErrorStateView(
                      title: 'Belum ada tujuan langganan.',
                      message: 'Tambahkan tujuan baru lewat tombol di bawah.',
                      icon: Icons.place_outlined,
                      onRetry: _openAddSheet,
                    );
                  }

                  final filtered = _filterDestinations(destinations);

                  if (filtered.isEmpty) {
                    // Tanpa `onRetry` SENGAJA -- tombol bawaan
                    // `ErrorStateView` selalu berlabel "Coba Lagi" (cocok
                    // untuk retry fetch, BUKAN untuk "hapus pencarian").
                    return ErrorStateView(
                      title: 'Tujuan tidak ditemukan.',
                      message: 'Tidak ada tujuan yang cocok dengan "${_searchController.text}".',
                      icon: Icons.search_off_rounded,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final destination = filtered[index];

                      return _DestinationTile(
                        destination: destination,
                        isBusy: _busyDestinationId == destination.id,
                        onTap: () => _openEditSheet(destination),
                        onToggleActive: () => _toggleActive(destination),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar tujuan.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allDestinationsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ringkasan detail tujuan buat subtitle di tile -- gabungkan telepon/
/// alamat/status titik peta yang terisi saja, dipisah "•". Kalau semua
/// kosong (tujuan cuma didaftarkan namanya saja), tampilkan placeholder
/// supaya baris subtitle tidak kosong melompong.
String _buildSubtitle(DestinationModel destination, bool hasLocation) {
  final parts = [
    if (destination.phone != null && destination.phone!.isNotEmpty) destination.phone!,
    if (destination.address != null && destination.address!.isNotEmpty) destination.address!,
    if (hasLocation) 'Titik peta tersimpan',
  ];

  return parts.isEmpty ? 'Belum ada detail tambahan' : parts.join(' • ');
}

class _DestinationTile extends StatelessWidget {
  final DestinationModel destination;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _DestinationTile({
    required this.destination,
    required this.isBusy,
    required this.onTap,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = destination.latitude != null && destination.longitude != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (destination.isActive ? AppColors.green : AppColors.textSecondary)
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
                    color: AppColors.lightBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.place_rounded, color: AppColors.lightBlue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _buildSubtitle(destination, hasLocation),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (destination.isActive ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          destination.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: destination.isActive ? AppColors.green : AppColors.textSecondary,
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
                    value: destination.isActive,
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
