import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/item_type_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/item_type_service.dart';
import '../widgets/item_type_form_sheet.dart';

/// Halaman admin "Kelola Jenis Barang" (8 Oktober 2026, permintaan user
/// poin 9) -- SEBELUMNYA jenis barang (`item_types`) cuma bisa
/// didaftarkan "numpang" lewat form input resi (Receiving), BELUM ADA
/// halaman CRUD admin terpusat sama sekali (beda dari Jenis Harga/
/// Tujuan/Pengirim yang sudah punya). Halaman ini mirror PERSIS pola
/// `PricingTypeManagePage`/`DestinationManagePage`, LENGKAP dengan search
/// dari awal (bukan ditambah belakangan).
///
/// Menonaktifkan jenis barang TIDAK menghapusnya -- cuma bikin jenis itu
/// tidak lagi muncul di picker saat input resi baru.
class ItemTypeManagePage extends ConsumerStatefulWidget {
  const ItemTypeManagePage({super.key});

  @override
  ConsumerState<ItemTypeManagePage> createState() => _ItemTypeManagePageState();
}

class _ItemTypeManagePageState extends ConsumerState<ItemTypeManagePage> {
  String? _busyItemTypeId;

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
      ref.invalidate(allItemTypesProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Cocokkan keyword ke kode ATAU nama jenis barang.
  List<ItemTypeModel> _filterItemTypes(List<ItemTypeModel> itemTypes) {
    if (_searchQuery.isEmpty) return itemTypes;

    return itemTypes.where((itemType) {
      final code = itemType.code.toLowerCase();
      final name = itemType.name.toLowerCase();
      return code.contains(_searchQuery) || name.contains(_searchQuery);
    }).toList();
  }

  void _refreshAll() {
    ref.invalidate(allItemTypesProvider);
    // Picker jenis barang di form input resi (Penerimaan) juga harus
    // langsung melihat jenis baru / perubahan / nonaktif.
    ref.invalidate(itemTypesProvider);
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ItemTypeFormSheet(),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _openEditSheet(ItemTypeModel itemType) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemTypeFormSheet(existing: itemType),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _toggleActive(ItemTypeModel itemType) async {
    setState(() => _busyItemTypeId = itemType.id);

    try {
      await ItemTypeService.setActive(itemType.id, !itemType.isActive);
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status jenis barang: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyItemTypeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemTypesAsync = ref.watch(allItemTypesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kelola Jenis Barang'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Jenis Barang'),
        backgroundColor: AppColors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Jenis Barang',
                hint: 'Cari kode atau nama jenis barang...',
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
              child: itemTypesAsync.when(
                data: (itemTypes) {
                  if (itemTypes.isEmpty) {
                    return ErrorStateView(
                      title: 'Belum ada jenis barang.',
                      message: 'Tambahkan jenis barang baru lewat tombol di bawah.',
                      icon: Icons.category_outlined,
                      onRetry: _openAddSheet,
                    );
                  }

                  final filtered = _filterItemTypes(itemTypes);

                  if (filtered.isEmpty) {
                    return ErrorStateView(
                      title: 'Jenis barang tidak ditemukan.',
                      message: 'Tidak ada jenis barang yang cocok dengan "${_searchController.text}".',
                      icon: Icons.search_off_rounded,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final itemType = filtered[index];

                      return _ItemTypeTile(
                        itemType: itemType,
                        isBusy: _busyItemTypeId == itemType.id,
                        onTap: () => _openEditSheet(itemType),
                        onToggleActive: () => _toggleActive(itemType),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar jenis barang.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allItemTypesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTypeTile extends StatelessWidget {
  final ItemTypeModel itemType;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _ItemTypeTile({
    required this.itemType,
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
          color: (itemType.isActive ? AppColors.green : AppColors.textSecondary)
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
                    color: AppColors.orange.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.category_rounded, color: AppColors.orange),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemType.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        itemType.handling != null && itemType.handling!.isNotEmpty
                            ? '${itemType.code} • ${itemType.handling}'
                            : itemType.code,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (itemType.isActive ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          itemType.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: itemType.isActive ? AppColors.green : AppColors.textSecondary,
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
                    value: itemType.isActive,
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
