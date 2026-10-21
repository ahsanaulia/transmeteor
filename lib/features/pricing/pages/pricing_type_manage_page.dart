import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/pricing_type_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/pricing_type_service.dart';
import '../widgets/pricing_type_form_sheet.dart';

/// Halaman admin "Kelola Jenis Harga" -- daftar semua jenis harga
/// (pricing_types), tombol tambah jenis baru, edit jenis yang sudah ada,
/// dan aktif/nonaktifkan. Ini menggantikan cara lama (insert manual lewat
/// SQL Supabase) supaya jenis harga untuk jenis kiriman baru bisa
/// ditambahkan langsung dari aplikasi.
///
/// Menonaktifkan jenis harga TIDAK menghapusnya -- cuma bikin jenis itu
/// tidak lagi muncul di picker saat input resi baru. Riwayat resi lama
/// yang sudah memakai jenis harga itu tetap utuh.
class PricingTypeManagePage extends ConsumerStatefulWidget {
  const PricingTypeManagePage({super.key});

  @override
  ConsumerState<PricingTypeManagePage> createState() =>
      _PricingTypeManagePageState();
}

class _PricingTypeManagePageState extends ConsumerState<PricingTypeManagePage> {
  String? _busyPricingTypeId;

  // Search (permintaan user, 8 Oktober 2026 -- poin 9a), mirror pola
  // `DestinationManagePage`: filter di sisi aplikasi karena halaman ini
  // SUDAH ambil SEMUA jenis harga sekaligus lewat `allPricingTypesProvider`.
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
      ref.invalidate(allPricingTypesProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Cocokkan keyword ke kode ATAU nama jenis harga.
  List<PricingTypeModel> _filterPricingTypes(List<PricingTypeModel> pricingTypes) {
    if (_searchQuery.isEmpty) return pricingTypes;

    return pricingTypes.where((pricingType) {
      final code = pricingType.code.toLowerCase();
      final name = pricingType.name.toLowerCase();
      return code.contains(_searchQuery) || name.contains(_searchQuery);
    }).toList();
  }

  void _refreshAll() {
    ref.invalidate(allPricingTypesProvider);
    // Picker jenis harga di form input resi (Penerimaan) juga harus
    // langsung melihat jenis baru / perubahan harga / nonaktif.
    ref.invalidate(pricingTypesProvider);
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PricingTypeFormSheet(),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _openEditSheet(PricingTypeModel pricingType) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PricingTypeFormSheet(existing: pricingType),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _toggleActive(PricingTypeModel pricingType) async {
    setState(() => _busyPricingTypeId = pricingType.id);

    try {
      await PricingTypeService.setActive(pricingType.id, !pricingType.isActive);
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status jenis harga: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyPricingTypeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pricingTypesAsync = ref.watch(allPricingTypesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kelola Jenis Harga'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Jenis Harga'),
        backgroundColor: AppColors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Jenis Harga',
                hint: 'Cari kode atau nama jenis harga...',
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
              child: pricingTypesAsync.when(
                data: (pricingTypes) {
                  if (pricingTypes.isEmpty) {
                    return ErrorStateView(
                      title: 'Belum ada jenis harga.',
                      message: 'Tambahkan jenis harga baru lewat tombol di bawah.',
                      icon: Icons.sell_outlined,
                      onRetry: _openAddSheet,
                    );
                  }

                  final filtered = _filterPricingTypes(pricingTypes);

                  if (filtered.isEmpty) {
                    return ErrorStateView(
                      title: 'Jenis harga tidak ditemukan.',
                      message: 'Tidak ada jenis harga yang cocok dengan "${_searchController.text}".',
                      icon: Icons.search_off_rounded,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final pricingType = filtered[index];

                      return _PricingTypeTile(
                        pricingType: pricingType,
                        isBusy: _busyPricingTypeId == pricingType.id,
                        onTap: () => _openEditSheet(pricingType),
                        onToggleActive: () => _toggleActive(pricingType),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar jenis harga.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allPricingTypesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingTypeTile extends StatelessWidget {
  final PricingTypeModel pricingType;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _PricingTypeTile({
    required this.pricingType,
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
          color: (pricingType.isActive ? AppColors.green : AppColors.textSecondary)
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
                    color: AppColors.pink.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.sell_rounded, color: AppColors.pink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pricingType.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${pricingType.code} • ${formatRupiah(pricingType.price)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (pricingType.isActive ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pricingType.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: pricingType.isActive ? AppColors.green : AppColors.textSecondary,
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
                    value: pricingType.isActive,
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
