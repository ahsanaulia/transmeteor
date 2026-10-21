import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/storage_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/monitoring_providers.dart';

/// Halaman admin "Monitoring Zona Storage" (9 Oktober 2026, permintaan
/// user eksplisit):
/// "Dipilih Zona maka akan muncul daftar barang yang ada dizona
/// dilengkapi data Nomor Resi, nomor buku, tanggal terima, nama tujuan
/// dan alamat tujuan. Ada Fungsi Cari search: Masukkan nama tujuan, atau
/// nomor resi atau nomor buku ----> maka muncul daftar barang dan di
/// Zona mana barang tersebut. Hanya barang yang belum diloading dan
/// dalam perjalanan."
///
/// Dirancang sebagai SATU daftar + DUA filter yang bisa dipakai
/// bersamaan (pola yang sama dengan filter status di `ReceivingListPage`
/// -- lihat 9 Oktober 2026 #10): chip pilih zona (jawab kebutuhan
/// "dipilih zona -> muncul daftar barang di zona itu") DAN kolom
/// pencarian (jawab kebutuhan "cari nama tujuan/no resi/no buku ->
/// muncul daftar barang + di zona mana"). Kalau user mencari TANPA
/// pilih zona dulu ("Semua Zona"), tiap kartu barang tetap menampilkan
/// badge nama zona-nya -- itulah jawaban "di Zona mana barang tersebut".
///
/// Data sumbernya `unloadedZoneItemsProvider`
/// (`MonitoringService.getUnloadedZoneItems`) -- SUDAH difilter di sisi
/// service supaya CUMA barang yang BELUM PERNAH disentuh scan LOAD sama
/// sekali yang ikut (barang yang sudah mulai dimuat ATAU sedang
/// perjalanan otomatis tidak muncul, sesuai permintaan user "Hanya
/// barang yang belum diloading dan dalam perjalanan" -- begitu barang
/// keluar fisik dari zona gudangnya, dia harus hilang dari daftar ini).
class StorageZoneMonitoringPage extends ConsumerStatefulWidget {
  const StorageZoneMonitoringPage({super.key});

  @override
  ConsumerState<StorageZoneMonitoringPage> createState() =>
      _StorageZoneMonitoringPageState();
}

class _StorageZoneMonitoringPageState
    extends ConsumerState<StorageZoneMonitoringPage> {
  final _searchController = TextEditingController();
  String _keyword = '';

  // null = "Semua Zona" (tidak difilter per zona, cuma lewat pencarian
  // kalau ada kata kuncinya).
  String? _selectedZoneId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _keyword = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  String _zoneName(List<StorageModel> zones, String? zoneId) {
    if (zoneId == null) return '-';
    for (final z in zones) {
      if (z.id == zoneId) return z.namaZona;
    }
    // Zona pernah ada tapi sudah dihapus total dari tabel `storages` --
    // SANGAT jarang (halaman "Zona Storage" cuma punya tombol
    // aktif/nonaktif, BUKAN hapus permanen), tapi dijaga tetap aman.
    return 'Zona tidak dikenal';
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> items) {
    var filtered = items;

    if (_selectedZoneId != null) {
      filtered =
          filtered.where((it) => it['storageId'] == _selectedZoneId).toList();
    }

    if (_keyword.isNotEmpty) {
      filtered = filtered.where((it) {
        final destination = (it['destination'] as String? ?? '').toLowerCase();
        final receiptNumber =
            (it['receiptNumber'] as String? ?? '').toLowerCase();
        final nomorBuku = (it['nomorBuku'] as String? ?? '').toLowerCase();
        return destination.contains(_keyword) ||
            receiptNumber.contains(_keyword) ||
            nomorBuku.contains(_keyword);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(unloadedZoneItemsProvider);
    final zonesAsync = ref.watch(allStoragesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Monitoring Zona Storage'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: itemsAsync.when(
        data: (items) => zonesAsync.when(
          data: (zones) => _buildBody(items, zones),
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.blue),
          ),
          error: (error, stackTrace) => ErrorStateView(
            title: 'Gagal memuat daftar zona.',
            message: error.toString(),
            onRetry: () => ref.invalidate(allStoragesProvider),
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.blue),
        ),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat barang di zona storage.',
          message: error.toString(),
          onRetry: () => ref.invalidate(unloadedZoneItemsProvider),
        ),
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> items,
    List<StorageModel> zones,
  ) {
    // Jumlah barang per zona (dari SEMUA barang belum-dimuat, BUKAN
    // hasil filter kata kunci) -- dipakai angka di tiap chip zona.
    final countsByZone = <String, int>{};
    for (final it in items) {
      final zoneId = it['storageId'] as String?;
      if (zoneId == null) continue;
      countsByZone[zoneId] = (countsByZone[zoneId] ?? 0) + 1;
    }

    final filtered = _applyFilters(items);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AppTextField(
            controller: _searchController,
            label: 'Cari Barang',
            hint: 'Nama tujuan, nomor resi, atau nomor buku...',
            icon: Icons.search_rounded,
            suffixIcon: _keyword.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Hapus pencarian',
                    onPressed: _searchController.clear,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _buildZoneChips(zones, countsByZone, items.length),
        ),
        Expanded(
          child: filtered.isEmpty
              ? ErrorStateView(
                  title: items.isEmpty
                      ? 'Belum ada barang di zona storage.'
                      : 'Barang tidak ditemukan.',
                  message: items.isEmpty
                      ? 'Semua barang sudah dimuat/dalam perjalanan, atau '
                          'belum ada barang yang diberi zona penyimpanan.'
                      : 'Tidak ada barang yang cocok dengan filter saat ini.',
                  icon: Icons.inventory_2_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _ZoneItemTile(
                      item: filtered[index],
                      zoneName: _zoneName(
                        zones,
                        filtered[index]['storageId'] as String?,
                      ),
                      formatQuantity: _formatQuantity,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildZoneChips(
    List<StorageModel> zones,
    Map<String, int> countsByZone,
    int totalCount,
  ) {
    Widget chip(String label, String? zoneId, int count) {
      final selected = _selectedZoneId == zoneId;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) {
            setState(() => _selectedZoneId = selected ? null : zoneId);
          },
          label: Text('$label ($count)'),
          labelStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.lightBlue,
          ),
          avatar: Icon(
            Icons.warehouse_rounded,
            size: 14,
            color: selected ? Colors.white : AppColors.lightBlue,
          ),
          selectedColor: AppColors.lightBlue,
          backgroundColor: AppColors.lightBlue.withOpacity(0.10),
          side: BorderSide(
            color: AppColors.lightBlue.withOpacity(selected ? 0 : 0.25),
          ),
          showCheckmark: false,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Semua Zona', null, totalCount),
          for (final zone in zones)
            chip(
              zone.isActive ? zone.namaZona : '${zone.namaZona} (nonaktif)',
              zone.id,
              countsByZone[zone.id] ?? 0,
            ),
        ],
      ),
    );
  }
}

class _ZoneItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String zoneName;
  final String Function(double) formatQuantity;

  const _ZoneItemTile({
    required this.item,
    required this.zoneName,
    required this.formatQuantity,
  });

  @override
  Widget build(BuildContext context) {
    final itemName = item['itemName'] as String? ?? '-';
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
    final quantityUnit = item['quantityUnit'] as String? ?? '';
    final receiptNumber = item['receiptNumber'] as String? ?? '-';
    final nomorBuku = item['nomorBuku'] as String?;
    final destination = item['destination'] as String? ?? '-';
    final destinationAddress = item['destinationAddress'] as String?;
    final receivedAtRaw = item['receivedAt'] as String?;
    final receivedAt =
        receivedAtRaw != null ? DateTime.tryParse(receivedAtRaw) : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBlue.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    itemName,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${formatQuantity(quantity)} $quantityUnit',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.lightBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warehouse_rounded,
                    size: 12,
                    color: AppColors.lightBlue,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    zoneName,
                    style: const TextStyle(
                      color: AppColors.lightBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            _infoRow(
              Icons.receipt_long_rounded,
              nomorBuku != null && nomorBuku.isNotEmpty
                  ? '$receiptNumber / $nomorBuku'
                  : receiptNumber,
            ),
            const SizedBox(height: 4),
            _infoRow(
              Icons.event_rounded,
              receivedAt != null
                  ? 'Diterima: ${formatDateId(receivedAt)}'
                  : 'Tanggal terima tidak diketahui',
            ),
            const SizedBox(height: 4),
            _infoRow(Icons.flag_rounded, destination),
            if (destinationAddress != null && destinationAddress.isNotEmpty) ...[
              const SizedBox(height: 4),
              _infoRow(Icons.location_on_outlined, destinationAddress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
