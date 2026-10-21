import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/sender_model.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../supervisor_ui_kit.dart';

/// Halaman READ-ONLY "barang apa saja" di 1 shipment (mobil) -- dibuka
/// dari Tab 2 Dashboard Supervisor (16 Oktober 2026, permintaan user:
/// "Daftar shipment muatan yang sudah tiba di tujuan. Jika diklik mobil
/// shipmentnya muncul barang2 apa apa saja"). SENGAJA dipakai juga untuk
/// shipment yang MASIH "Sedang Dimuat" (bukan cuma yang sudah tiba) --
/// supervisor tetap boleh lihat isi muatan kapan saja, lihat doc comment
/// `SupervisorLoadingTab`.
///
/// BUKAN `ManifestPage` admin (yang punya tombol bagikan PDF & tap-ke-
/// edit) -- halaman BARU, murni tampilan, dibangun dari
/// `shipmentScansProvider` (SUDAH DIPERLUAS field-nya khusus kebutuhan
/// ini, lihat doc comment `ShipmentService.getShipmentScanFeed`)
/// dikelompokkan per barang (`receiving_detail_id`), masing-masing
/// menampilkan 12 field kelengkapan informasi (permintaan user):
///   1. Pengirim, 2. Diterima, 3. Diterima oleh (tujuan), 4+5. Barang +
///   jumlah, 6. Diperbarui, 7+8. Loading kapan+siapa, 9+10. Mobil+sopir
///   (dari [vehicle], sama untuk semua barang di 1 shipment), 11. Tanggal
///   penyelesaian, 12. Diselesaikan paksa -- 11 & 12 diambil per-RESI
///   dari `receivingProgressSummaryProvider` (sama seperti Tab 1), bukan
///   per-barang (penyelesaian memang tercatat di level resi).
class SupervisorShipmentItemsPage extends ConsumerWidget {
  final ShipmentModel shipment;
  final VehicleModel vehicle;

  const SupervisorShipmentItemsPage({
    super.key,
    required this.shipment,
    required this.vehicle,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'LOADING':
        return 'Sedang Dimuat';
      case 'DEPARTED':
        return 'Berangkat';
      case 'ARRIVED':
        return 'Tiba';
      case 'CANCELLED':
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  List<Map<String, dynamic>> _groupByDetail(List<Map<String, dynamic>> scans) {
    final order = <String>[];
    final groups = <String, Map<String, dynamic>>{};

    for (final scan in scans) {
      final detail = scan['receiving_details'] as Map?;
      final detailId = detail?['id'] as String?;
      final key = detailId ?? 'scan-${scan['id']}';

      final group = groups.putIfAbsent(key, () {
        order.add(key);
        final receiving = detail?['receiving'] as Map?;
        return {
          'detailId': detailId,
          'detail': detail,
          'receiving': receiving,
          'firstScannedAt': scan['scanned_at'],
          'scannedBy': scan['scanned_by'],
          'count': 0,
        };
      });

      group['count'] = (group['count'] as int) + 1;
    }

    return order.map((key) => groups[key]!).toList();
  }

  String _employeeName(List<EmployeeModel>? employees, String? employeeId) {
    if (employeeId == null) return '-';
    if (employees == null) return 'Memuat...';
    for (final e in employees) {
      if (e.id == employeeId) return e.fullName;
    }
    return '-';
  }

  String _senderName(List<SenderModel>? senders, String? senderId) {
    if (senderId == null) return '-';
    if (senders == null) return 'Memuat...';
    for (final s in senders) {
      if (s.id == senderId) return s.name;
    }
    return '-';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scansAsync = ref.watch(shipmentScansProvider(shipment.id));
    final employeesAsync = ref.watch(allEmployeesProvider);
    final sendersAsync = ref.watch(allSendersProvider);
    final progressAsync = ref.watch(receivingProgressSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          shipment.shipmentNumber,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
      ),
      body: scansAsync.when(
        data: (scans) {
          final groups = _groupByDetail(scans);
          final progress = progressAsync.value;

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.blue.withOpacity(0.14)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_rounded,
                        color: AppColors.blue, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mobil: ${vehicle.plateNumber}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sopir: ${vehicle.driverName ?? '-'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _statusLabel(shipment.status),
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'Belum ada barang yang discan untuk shipment ini.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                for (final group in groups)
                  _ItemCard(
                    group: group,
                    senderName: _senderName(
                      sendersAsync.value,
                      (group['receiving'] as Map?)?['sender_id'] as String?,
                    ),
                    scannedByName: _employeeName(
                      employeesAsync.value,
                      group['scannedBy'] as String?,
                    ),
                    updatedByName: _employeeName(
                      employeesAsync.value,
                      (group['receiving'] as Map?)?['updated_by'] as String?,
                    ),
                    progressEntry: () {
                      final receivingId =
                          (group['detail'] as Map?)?['receiving_id'] as String?;
                      if (receivingId == null) return null;
                      return progress?[receivingId];
                    }(),
                  ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat isi muatan.',
          message: error.toString(),
          onRetry: () => ref.invalidate(shipmentScansProvider(shipment.id)),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final String senderName;
  final String scannedByName;
  final String updatedByName;
  final Map<String, dynamic>? progressEntry;

  const _ItemCard({
    required this.group,
    required this.senderName,
    required this.scannedByName,
    required this.updatedByName,
    required this.progressEntry,
  });

  @override
  Widget build(BuildContext context) {
    final detail = group['detail'] as Map?;
    final receiving = group['receiving'] as Map?;
    final count = group['count'] as int;

    final itemName = detail?['item_name']?.toString() ?? '-';
    final quantityUnit = detail?['quantity_unit']?.toString() ?? '';
    final receiptNumber = receiving?['receipt_number']?.toString() ?? '-';
    final nomorBuku = receiving?['nomor_buku']?.toString();
    final destination = receiving?['destination']?.toString() ?? '-';
    final destinationAddress = receiving?['destination_address']?.toString();

    final receivedAtRaw = receiving?['received_at'] as String?;
    final receivedAt = receivedAtRaw != null ? DateTime.tryParse(receivedAtRaw) : null;

    final updatedAtRaw = receiving?['updated_at'] as String?;
    final updatedAt = updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) : null;
    final updatedBy = receiving?['updated_by'] as String?;

    final scannedAtRaw = group['firstScannedAt'] as String?;
    final scannedAt = scannedAtRaw != null ? DateTime.tryParse(scannedAtRaw) : null;

    final deliveredAt = progressEntry?['deliveredAt'] as DateTime?;
    final isBypassAdmin = progressEntry?['isBypassAdmin'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      // FITUR (16 Oktober 2026 -- "dipercantik" + konsistensi dengan Tab
      // 1/3): `SupervisorAccentCard` + `SupervisorField` + chip pastel
      // hitam-bold, lihat `supervisor_ui_kit.dart`.
      child: SupervisorAccentCard(
        color: AppColors.cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    itemName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                ),
                SupervisorPastelChip(
                  label: '$count $quantityUnit',
                  pastelColor: AppColors.cyan,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              nomorBuku != null && nomorBuku.isNotEmpty
                  ? 'Resi $receiptNumber / $nomorBuku'
                  : 'Resi $receiptNumber',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
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
                  label: 'Diterima Oleh (Tujuan)',
                  value: destinationAddress != null &&
                          destinationAddress.isNotEmpty
                      ? '$destination • $destinationAddress'
                      : destination,
                ),
                SupervisorField(
                  label: 'Diperbarui',
                  value: updatedBy != null && updatedAt != null
                      ? '${formatDateId(updatedAt)}, ${formatTimeId(updatedAt)} • $updatedByName'
                      : 'Belum pernah diedit',
                ),
                SupervisorField(
                  label: 'Loading',
                  value: scannedAt != null
                      ? '${formatDateId(scannedAt)}, ${formatTimeId(scannedAt)} • $scannedByName'
                      : '-',
                ),
                SupervisorField(
                  label: 'Tanggal Penyelesaian',
                  value: deliveredAt != null
                      ? '${formatDateId(deliveredAt)}, ${formatTimeId(deliveredAt)}'
                      : 'Belum selesai',
                ),
                SupervisorField(
                  label: 'Diselesaikan Paksa?',
                  value: isBypassAdmin ? 'Ya' : 'Tidak',
                  valueColor: isBypassAdmin ? AppColors.red : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
