import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/sender_model.dart';
import '../../../models/storage_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../supervisor_ui_kit.dart';

/// Tab 3 "Monitoring Barang" -- Dashboard Supervisor (16 Oktober 2026,
/// permintaan user): "Muncul daftar Zona. Jika diklik maka muncul semua
/// barang yang statusnya belum dalam perjalanan di setiap zona yang
/// dimaksud."
///
/// Adaptasi `StorageZoneMonitoringPage` (admin, SUDAH read-only sejak
/// awal, tidak ada CRUD apa pun) -- dibesarkan huruf/padding untuk
/// monitor 32 inch, dan `unloadedZoneItemsProvider` SUDAH DIPERLUAS
/// (lihat doc comment `MonitoringService.getUnloadedZoneItems`) membawa
/// `senderId`/`receivedByEmployeeId`/`updatedAt`/`updatedBy` sekalian.
///
/// Field kelengkapan (12 poin permintaan user) yang RELEVAN di tab ini
/// HANYA 1,2,3,4,5,6 -- barang di tab ini, menurut definisi query-nya,
/// BELUM PERNAH disentuh scan LOAD sama sekali ("belum dalam
/// perjalanan"), jadi field 7-12 (loading/mobil/sopir/penyelesaian)
/// otomatis TIDAK relevan (barang belum pernah dimuat) dan tidak
/// ditampilkan di sini -- SENGAJA, bukan kelupaan.
class SupervisorZoneTab extends ConsumerStatefulWidget {
  const SupervisorZoneTab({super.key});

  @override
  ConsumerState<SupervisorZoneTab> createState() => _SupervisorZoneTabState();
}

class _SupervisorZoneTabState extends ConsumerState<SupervisorZoneTab> {
  final _searchController = TextEditingController();
  String _keyword = '';
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
    return 'Zona tidak dikenal';
  }

  String _senderName(List<SenderModel>? senders, String? senderId) {
    if (senderId == null) return '-';
    if (senders == null) return 'Memuat...';
    for (final s in senders) {
      if (s.id == senderId) return s.name;
    }
    return '-';
  }

  String _employeeName(List<EmployeeModel>? employees, String? employeeId) {
    if (employeeId == null) return '-';
    if (employees == null) return 'Memuat...';
    for (final e in employees) {
      if (e.id == employeeId) return e.fullName;
    }
    return '-';
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
        // FITUR (16 Oktober 2026 -- permintaan user eksplisit): "pencarian
        // barang: bisa nomor resi maka muncul semua barang dan storage
        // mana berada, bisa juga nama barang: muncul semua barang
        // beserta lokasinya." Pencarian nomor resi/nomor buku/tujuan
        // SUDAH ADA sejak awal tab ini -- yang BARU di sini cuma
        // `itemName`, supaya ketik nama barang juga ikut menyaring
        // (hasilnya otomatis "semua barang beserta lokasinya" karena
        // tiap kartu di daftar ini SUDAH menampilkan badge zona-nya).
        final itemName = (it['itemName'] as String? ?? '').toLowerCase();
        return destination.contains(_keyword) ||
            receiptNumber.contains(_keyword) ||
            nomorBuku.contains(_keyword) ||
            itemName.contains(_keyword);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(unloadedZoneItemsProvider);
    final zonesAsync = ref.watch(allStoragesProvider);
    final sendersAsync = ref.watch(allSendersProvider);
    final employeesAsync = ref.watch(allEmployeesProvider);

    return itemsAsync.when(
      data: (items) => zonesAsync.when(
        data: (zones) => _buildBody(
          items,
          zones,
          sendersAsync.value,
          employeesAsync.value,
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat daftar zona.',
          message: error.toString(),
          onRetry: () => ref.invalidate(allStoragesProvider),
        ),
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.blue)),
      error: (error, stackTrace) => ErrorStateView(
        title: 'Gagal memuat barang di zona storage.',
        message: error.toString(),
        onRetry: () => ref.invalidate(unloadedZoneItemsProvider),
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> items,
    List<StorageModel> zones,
    List<SenderModel>? senders,
    List<EmployeeModel>? employees,
  ) {
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
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          child: AppTextField(
            controller: _searchController,
            label: 'Cari Barang',
            hint: 'Nama barang, nomor resi, nomor buku, atau tujuan...',
            icon: Icons.search_rounded,
            suffixIcon: _keyword.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Hapus pencarian',
                    onPressed: _searchController.clear,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _ZoneItemCard(
                      item: item,
                      zoneName: _zoneName(zones, item['storageId'] as String?),
                      formatQuantity: _formatQuantity,
                      senderName: _senderName(senders, item['senderId'] as String?),
                      updatedByName: _employeeName(
                        employees,
                        item['updatedBy'] as String?,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // FITUR (16 Oktober 2026 -- "Perbsar chip storage dan buat 2 row"):
  // chip dibesarkan (font 15->17, padding lebih lega) DAN diganti dari
  // `SingleChildScrollView` horizontal (1 baris, harus discroll) jadi
  // `Wrap` supaya otomatis melipat ke baris ke-2/ke-3 kalau tidak muat --
  // ini yang membuat tampilannya "2 row" sesuai permintaan user (jumlah
  // baris menyesuaikan jumlah zona & lebar layar, bukan dipaksa pas 2).
  Widget _buildZoneChips(
    List<StorageModel> zones,
    Map<String, int> countsByZone,
    int totalCount,
  ) {
    Widget chip(String label, String? zoneId, int count) {
      final selected = _selectedZoneId == zoneId;
      return ChoiceChip(
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedZoneId = selected ? null : zoneId);
        },
        label: Text('$label ($count)'),
        labelStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: selected ? Colors.white : AppColors.lightBlue,
        ),
        avatar: Icon(Icons.warehouse_rounded, size: 20,
            color: selected ? Colors.white : AppColors.lightBlue),
        selectedColor: AppColors.lightBlue,
        backgroundColor: AppColors.lightBlue.withOpacity(0.10),
        side: BorderSide(
          color: AppColors.lightBlue.withOpacity(selected ? 0 : 0.25),
          width: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        showCheckmark: false,
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('Semua Zona', null, totalCount),
        for (final zone in zones)
          chip(
            zone.isActive ? zone.namaZona : '${zone.namaZona} (nonaktif)',
            zone.id,
            countsByZone[zone.id] ?? 0,
          ),
      ],
    );
  }
}

class _ZoneItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String zoneName;
  final String Function(double) formatQuantity;
  final String senderName;
  final String updatedByName;

  const _ZoneItemCard({
    required this.item,
    required this.zoneName,
    required this.formatQuantity,
    required this.senderName,
    required this.updatedByName,
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
    final updatedAtRaw = item['updatedAt'] as String?;
    final updatedAt =
        updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) : null;
    final updatedBy = item['updatedBy'] as String?;

    // FITUR (16 Oktober 2026, permintaan user eksplisit utk tab Storage):
    //   - Nama barang dibesarkan jadi PALING BESAR di kartu (24, di atas
    //     semua ukuran huruf lain termasuk judul chip).
    //   - "Diterima Oleh (Tujuan)" -> cukup "Tujuan" (value tetap
    //     "Tujuan • Alamat Tujuan").
    //   - Semua prefix angka ("1.", "2.", "3.", "6.") dihilangkan.
    //   - Chip koli & chip zona: huruf hitam bold, latar pastel saja
    //     (`SupervisorPastelChip`, diperbesar).
    //   - `SupervisorAccentCard` + `SupervisorField` utk badan kartu &
    //     sekat antar field yang jelas, konsisten dgn Tab 1/2.
    return SupervisorAccentCard(
      color: AppColors.lightBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            itemName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SupervisorPastelChip(
                label: '${formatQuantity(quantity)} $quantityUnit',
                pastelColor: AppColors.cyan,
                fontSize: 16,
              ),
              SupervisorPastelChip(
                label: zoneName,
                pastelColor: AppColors.lightBlue,
                icon: Icons.warehouse_rounded,
                fontSize: 16,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Wrap(
            children: [
              SupervisorField(label: 'Pengirim', value: senderName),
              SupervisorField(
                label: 'Diterima',
                value: receivedAt != null
                    ? '${formatDateId(receivedAt)}, ${formatTimeId(receivedAt)}'
                    : '-',
              ),
              SupervisorField(
                label: 'Tujuan',
                value: destinationAddress != null &&
                        destinationAddress.isNotEmpty
                    ? '$destination • $destinationAddress'
                    : destination,
              ),
              SupervisorField(
                label: 'Nomor Resi',
                value: nomorBuku != null && nomorBuku.isNotEmpty
                    ? '$receiptNumber / $nomorBuku'
                    : receiptNumber,
              ),
              SupervisorField(
                label: 'Diperbarui',
                value: updatedBy != null && updatedAt != null
                    ? '${formatDateId(updatedAt)}, ${formatTimeId(updatedAt)} • $updatedByName'
                    : 'Belum pernah diedit',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
