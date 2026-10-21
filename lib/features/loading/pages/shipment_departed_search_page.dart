import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import 'destination_receipt_preview_page.dart';
import 'manifest_page.dart';

/// Cari muatan yang SUDAH BERANGKAT (status DEPARTED/ARRIVED) -- diakses
/// dari tombol pencarian di AppBar "Daftar Muatan" (`ShipmentDispatchPage`,
/// yang cuma menampilkan muatan berstatus LOADING). Permintaan user
/// (22 Sep 2026): supaya kalau ada komplain dari pelanggan setelah truk
/// berangkat, admin bisa cari lagi shipment-nya dari sini (nomor
/// shipment/plat kendaraan/nama sopir), lalu buka kembali Manifest-nya
/// ATAU cetak ulang Tanda Terima Tujuan-nya untuk dicek/dicetak ulang --
/// TANPA harus bolak-balik ke menu "Monitoring Shipment" yang terpisah.
///
/// SENGAJA hanya DEPARTED & ARRIVED yang muncul di sini (LOADING sudah
/// ada di layar utama Daftar Muatan, tidak perlu diulang).
///
/// PENTING soal konsistensi template cetakan untuk komplain: halaman ini
/// TIDAK punya template PDF sendiri. Tombol "Manifest" navigasi ke
/// `ManifestPage` yang SAMA PERSIS dipakai dari Daftar Muatan (bukan
/// halaman/varian lain), dan tombol "Tanda Terima Tujuan" navigasi ke
/// `DestinationReceiptPreviewPage` yang SAMA PERSIS dipakai dari Daftar
/// Muatan (`ShipmentDispatchPage`) -- halaman preview itu sendiri yang
/// memanggil `ShipmentService.getManifestSummaryByDestination` +
/// `PdfTemplates.buildDestinationReceiptDocument`.
/// Jadi cetak ulang shipment lama dari sini dijamin identik dengan
/// cetakan yang dihasilkan waktu shipment itu masih aktif di Daftar
/// Muatan, HARI INI. Catatan realistis (bukan bug, karakteristik sistem
/// sejak awal): PDF TIDAK PERNAH disimpan/diarsipkan di mana pun --
/// setiap cetak SELALU generate ulang dari data live memakai kode
/// template yang berlaku SAAT ITU. Kalau nanti `buildManifestDocument`/
/// `buildDestinationReceiptDocument` diubah lagi, cetak ulang shipment
/// lama akan ikut memakai template BARU (bukan template yang berlaku
/// waktu shipment itu pertama kali berangkat) -- ini berlaku sama untuk
/// SEMUA jalur cetak di app ini, bukan cuma halaman ini. Kalau nanti ada
/// permintaan reprint yang harus persis sama seperti versi lama (misal
/// setelah template berubah lagi), itu perlu fitur arsip PDF terpisah,
/// BUKAN sekadar menjamin halaman ini memanggil fungsi yang sama --
/// tandai kalau user minta ini secara eksplisit di sesi mendatang.
class ShipmentDepartedSearchPage extends ConsumerStatefulWidget {
  const ShipmentDepartedSearchPage({super.key});

  @override
  ConsumerState<ShipmentDepartedSearchPage> createState() =>
      _ShipmentDepartedSearchPageState();
}

class _ShipmentDepartedSearchPageState
    extends ConsumerState<ShipmentDepartedSearchPage> {
  String _keyword = '';

  String _statusLabel(String status) {
    switch (status) {
      case 'DEPARTED':
        return 'Berangkat';
      case 'ARRIVED':
        return 'Tiba';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'DEPARTED':
        return AppColors.blue;
      case 'ARRIVED':
        return AppColors.green;
      default:
        return AppColors.textSecondary;
    }
  }

  VehicleModel? _findVehicle(List<VehicleModel>? vehicles, String vehicleId) {
    if (vehicles == null) return null;

    for (final vehicle in vehicles) {
      if (vehicle.id == vehicleId) return vehicle;
    }

    return null;
  }

  /// Buka preview "Tanda Terima Tujuan" -- navigasi ke
  /// `DestinationReceiptPreviewPage` yang SAMA PERSIS dipakai dari Daftar
  /// Muatan (`ShipmentDispatchPage`), BUKAN generate & share langsung
  /// dari sini (diubah 22 Sep 2026, permintaan user: harus ada preview
  /// sebelum PDF dikirim) -- lihat doc comment di
  /// `DestinationReceiptPreviewPage` untuk alasan kenapa preview-nya pakai
  /// `PdfPreview` (bukan UI custom).
  void _openDestinationReceiptPreview(
    ShipmentModel shipment,
    VehicleModel vehicle,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DestinationReceiptPreviewPage(
          shipment: shipment,
          vehicle: vehicle,
        ),
      ),
    );
  }

  List<ShipmentModel> _filterAndSort(
    List<ShipmentModel> shipments,
    List<VehicleModel>? vehicles,
  ) {
    final departed = shipments
        .where((s) => s.status == 'DEPARTED' || s.status == 'ARRIVED')
        .toList();

    // Terbaru duluan berdasarkan waktu berangkat (fallback createdAt kalau
    // entah kenapa departedAt kosong) -- paling relevan buat komplain yang
    // biasanya soal pengiriman baru-baru ini.
    departed.sort((a, b) {
      final aTime = a.departedAt ?? a.createdAt;
      final bTime = b.departedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    final keyword = _keyword.trim().toLowerCase();
    if (keyword.isEmpty) return departed;

    return departed.where((shipment) {
      final vehicle = _findVehicle(vehicles, shipment.vehicleId);

      return shipment.shipmentNumber.toLowerCase().contains(keyword) ||
          (vehicle?.plateNumber.toLowerCase().contains(keyword) ?? false) ||
          (vehicle?.driverName?.toLowerCase().contains(keyword) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final shipmentsAsync = ref.watch(shipmentsProvider);
    final vehiclesAsync = ref.watch(allVehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cari Muatan Berangkat'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: TextField(
                onChanged: (value) => setState(() => _keyword = value),
                decoration: InputDecoration(
                  hintText: 'Nomor shipment / plat kendaraan / nama sopir...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.fieldFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: shipmentsAsync.when(
                data: (shipments) {
                  final filtered = _filterAndSort(shipments, vehiclesAsync.value);

                  if (filtered.isEmpty) {
                    return ErrorStateView(
                      icon: Icons.local_shipping_outlined,
                      title: _keyword.trim().isEmpty
                          ? 'Belum ada muatan yang berangkat'
                          : 'Tidak ditemukan',
                      message: _keyword.trim().isEmpty
                          ? 'Muatan yang sudah diberangkatkan akan muncul di sini.'
                          : 'Coba kata kunci lain -- nomor shipment, plat kendaraan, '
                              'atau nama sopir.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final shipment = filtered[index];
                      final vehicle =
                          _findVehicle(vehiclesAsync.value, shipment.vehicleId);

                      return _DepartedShipmentTile(
                        shipment: shipment,
                        vehicle: vehicle,
                        statusLabel: _statusLabel(shipment.status),
                        statusColor: _statusColor(shipment.status),
                        onViewManifest: vehicle == null
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ManifestPage(
                                      shipment: shipment,
                                      vehicle: vehicle,
                                    ),
                                  ),
                                );
                              },
                        onPrintDestinationReceipt: vehicle == null
                            ? null
                            : () => _openDestinationReceiptPreview(shipment, vehicle),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar muatan.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(shipmentsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartedShipmentTile extends StatelessWidget {
  final ShipmentModel shipment;
  final VehicleModel? vehicle;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onViewManifest;
  final VoidCallback? onPrintDestinationReceipt;

  const _DepartedShipmentTile({
    required this.shipment,
    required this.vehicle,
    required this.statusLabel,
    required this.statusColor,
    required this.onViewManifest,
    required this.onPrintDestinationReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final departedAt = shipment.departedAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_shipping_rounded, color: AppColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shipment.shipmentNumber,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicle != null
                          ? '${vehicle!.plateNumber}${vehicle!.driverName != null ? ' • ${vehicle!.driverName}' : ''}'
                          : 'Memuat data kendaraan...',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (departedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Berangkat: ${_formatDateTime(departedAt)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPrintDestinationReceipt,
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  label: const Text(
                    'Tanda Terima Tujuan',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onViewManifest,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Manifest', overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hh:$mm';
  }
}
