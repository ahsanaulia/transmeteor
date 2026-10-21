import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/storage_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/storage_service.dart';
import '../widgets/storage_form_sheet.dart';

/// Halaman admin "Zona Storage" (8 Oktober 2026, permintaan user poin
/// 10) -- daftar semua zona storage, tambah/edit, aktif/nonaktifkan.
/// Mirror pola `DestinationManagePage`/`PricingTypeManagePage`, lengkap
/// dengan search.
///
/// Menonaktifkan zona TIDAK menghapusnya -- cuma bikin zona itu tidak
/// lagi muncul di picker saat input detail barang baru. Riwayat barang
/// lama yang sudah memakai zona itu (`receiving_details.storage_id`)
/// tetap utuh.
class StorageManagePage extends ConsumerStatefulWidget {
  const StorageManagePage({super.key});

  @override
  ConsumerState<StorageManagePage> createState() => _StorageManagePageState();
}

class _StorageManagePageState extends ConsumerState<StorageManagePage> {
  String? _busyStorageId;

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
      ref.invalidate(allStoragesProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StorageModel> _filterStorages(List<StorageModel> storages) {
    if (_searchQuery.isEmpty) return storages;

    return storages.where((storage) {
      final nama = storage.namaZona.toLowerCase();
      final deskripsi = storage.deskripsi?.toLowerCase() ?? '';
      return nama.contains(_searchQuery) || deskripsi.contains(_searchQuery);
    }).toList();
  }

  void _refreshAll() {
    ref.invalidate(allStoragesProvider);
    // Picker zona di form input detail barang (Penerimaan) & tampilan
    // zona di checklist Loading juga harus langsung melihat perubahan.
    ref.invalidate(storagesProvider);
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StorageFormSheet(),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _openEditSheet(StorageModel storage) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StorageFormSheet(existing: storage),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _toggleActive(StorageModel storage) async {
    setState(() => _busyStorageId = storage.id);

    try {
      await StorageService.setActive(storage.id, !storage.isActive);
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status zona: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyStorageId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storagesAsync = ref.watch(allStoragesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Zona Storage'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Zona'),
        backgroundColor: AppColors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Zona',
                hint: 'Cari nama atau deskripsi zona...',
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
              child: storagesAsync.when(
                data: (storages) {
                  if (storages.isEmpty) {
                    return ErrorStateView(
                      title: 'Belum ada zona storage.',
                      message: 'Tambahkan zona baru lewat tombol di bawah.',
                      icon: Icons.warehouse_outlined,
                      onRetry: _openAddSheet,
                    );
                  }

                  final filtered = _filterStorages(storages);

                  if (filtered.isEmpty) {
                    return ErrorStateView(
                      title: 'Zona tidak ditemukan.',
                      message: 'Tidak ada zona yang cocok dengan "${_searchController.text}".',
                      icon: Icons.search_off_rounded,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final storage = filtered[index];

                      return _StorageTile(
                        storage: storage,
                        isBusy: _busyStorageId == storage.id,
                        onTap: () => _openEditSheet(storage),
                        onToggleActive: () => _toggleActive(storage),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar zona.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allStoragesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageTile extends StatelessWidget {
  final StorageModel storage;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _StorageTile({
    required this.storage,
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
          color: (storage.isActive ? AppColors.green : AppColors.textSecondary)
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
                  child: const Icon(Icons.warehouse_rounded, color: AppColors.lightBlue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storage.namaZona,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        storage.deskripsi?.isNotEmpty == true
                            ? storage.deskripsi!
                            : 'Belum ada deskripsi',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (storage.isActive ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          storage.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: storage.isActive ? AppColors.green : AppColors.textSecondary,
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
                    value: storage.isActive,
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
