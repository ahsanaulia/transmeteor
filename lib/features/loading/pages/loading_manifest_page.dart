import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';

/// Halaman "Lihat Manifest" (Loading) -- FITUR BARU (21 Oktober 2026,
/// permintaan user eksplisit): "Pada loading Tambahkan menu Lihat
/// Manifest (pilih mobil (yang sedang loading) ----> daftar manifest)
/// dalam bentuk tabular mobile: Tujuan, No Resi, Nama Barang, Jumlah ...
/// Total Resi : ... Total Barang : ...."
///
/// SENGAJA view-only di dalam app, TIDAK ADA tombol cetak/bagikan PDF di
/// sini -- beda dari `ManifestPage` (yang justru dipakai utk "Bagikan
/// PDF" Manifest Muatan) maupun fitur "Cetak Manifest" yang SUDAH
/// DIHAPUS dari Loading 7 Oktober 2026 (lihat `arsitektur-tambahan.md`).
/// Staff Loading cuma butuh lihat ringkasan muatan kendaraan yang sedang
/// dia kerjakan, bukan cetak dokumen apapun.
///
/// Dibuka dari [VehicleSelectPage] lewat `destinationPageBuilder` (SAMA
/// seperti "Muat Barang"), jadi langkah "pilih mobil (yang sedang
/// loading)" TIDAK perlu bikin halaman baru -- lihat
/// `loading_home_page.dart` utk menu barunya.
///
/// Data diambil dari [manifestByDestinationProvider], yang MURNI
/// membungkus `ShipmentService.getManifestSummaryByDestination` -- SATU
/// SUMBER KEBENARAN yang sama dipakai cetakan PDF "Tanda Terima Tujuan",
/// supaya angka yang dilihat staff Loading di sini SELALU konsisten
/// dengan dokumen resmi (tidak ada logic hitung baru di halaman ini).
class LoadingManifestPage extends ConsumerWidget {
  final VehicleModel vehicle;
  final ShipmentModel shipment;

  const LoadingManifestPage({
    super.key,
    required this.vehicle,
    required this.shipment,
  });

  /// Meratakan data yang per-tujuan (`destinationName` -> `rows`) jadi
  /// 1 list flat baris tabel {tujuan, noResi, namaBarang, jumlah} --
  /// tabel yang diminta user TIDAK digroup per tujuan dengan header
  /// terpisah, cukup 1 tabel panjang dengan kolom Tujuan di tiap baris.
  List<Map<String, dynamic>> _flattenRows(
    List<Map<String, dynamic>> destinationGroups,
  ) {
    final flat = <Map<String, dynamic>>[];

    for (final group in destinationGroups) {
      final destinationName = group['destinationName']?.toString() ?? '-';
      final rows = (group['rows'] as List?) ?? const [];

      for (final row in rows) {
        final map = row as Map<String, dynamic>;
        flat.add({
          'destinationName': destinationName,
          'receiptNumber': map['receiptNumber']?.toString() ?? '-',
          'itemName': map['itemName']?.toString() ?? '-',
          'totalQuantity': (map['totalQuantity'] as num?)?.toInt() ?? 0,
          'quantityUnit': map['quantityUnit']?.toString() ?? '',
        });
      }
    }

    return flat;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync =
        ref.watch(manifestByDestinationProvider(shipment.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'Lihat Manifest',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: manifestAsync.when(
          data: (destinationGroups) {
            final rows = _flattenRows(destinationGroups);
            return _buildBody(rows);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.blue),
          ),
          error: (error, stackTrace) => ErrorStateView(
            title: 'Gagal memuat manifest.',
            message: error.toString(),
            onRetry: () =>
                ref.invalidate(manifestByDestinationProvider(shipment.id)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> rows) {
    final totalResi =
        rows.map((row) => row['receiptNumber']).toSet().length;
    final totalBarang = rows.fold<int>(
      0,
      (sum, row) => sum + (row['totalQuantity'] as int),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _VehicleInfoCard(vehicle: vehicle, shipment: shipment),
        ),
        Expanded(
          child: rows.isEmpty
              ? const ErrorStateView(
                  title: 'Belum ada barang dimuat.',
                  message: 'Manifest akan muncul begitu ada barang yang '
                      'discan naik ke kendaraan ini.',
                  icon: Icons.inventory_2_outlined,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  children: [
                    _ManifestTable(rows: rows),
                  ],
                ),
        ),
        _buildTotalsFooter(totalResi: totalResi, totalBarang: totalBarang),
      ],
    );
  }

  Widget _buildTotalsFooter({required int totalResi, required int totalBarang}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _TotalTile(
              label: 'Total Resi',
              value: '$totalResi',
              icon: Icons.receipt_long_rounded,
              color: AppColors.violet,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TotalTile(
              label: 'Total Barang',
              value: '$totalBarang',
              icon: Icons.inventory_2_rounded,
              color: AppColors.cyan,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleInfoCard extends StatelessWidget {
  final VehicleModel vehicle;
  final ShipmentModel shipment;

  const _VehicleInfoCard({required this.vehicle, required this.shipment});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.violet.withOpacity(0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.local_shipping_rounded, color: AppColors.violet),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.plateNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Shipment ${shipment.shipmentNumber}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tabel manifest mobile -- kolom: Tujuan, No Resi, Nama Barang, Jumlah
/// (sesuai permintaan user, persis urutan itu). Dibuat pakai `Table`
/// biasa (bukan `DataTable`) supaya gampang diatur lebar kolomnya untuk
/// layar sempit HP dan teks bisa wrap multi-baris tanpa overflow.
class _ManifestTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _ManifestTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.4), // Tujuan
          1: FlexColumnWidth(1.6), // No Resi
          2: FlexColumnWidth(2.6), // Nama Barang
          3: FlexColumnWidth(1.1), // Jumlah
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: AppColors.border),
          verticalInside: BorderSide(color: AppColors.border),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.08)),
            children: const [
              _HeaderCell('Tujuan'),
              _HeaderCell('No Resi'),
              _HeaderCell('Nama Barang'),
              _HeaderCell('Jumlah'),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                _DataCell(row['destinationName'].toString()),
                _DataCell(row['receiptNumber'].toString()),
                _DataCell(row['itemName'].toString()),
                _DataCell(
                  '${row['totalQuantity']}'
                  '${(row['quantityUnit'] as String).isNotEmpty ? ' ${row['quantityUnit']}' : ''}',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;

  const _DataCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TotalTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
