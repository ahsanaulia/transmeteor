import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../services/shipment_service.dart';
import '../../loading/pages/manifest_page.dart';
import 'destination_receipt_preview_page.dart';
import 'shipment_departed_search_page.dart';

/// Halaman admin "Daftar Muatan" -- daftar semua kendaraan yang sedang
/// dimuat (status LOADING, belum diberangkatkan). Admin yang memutuskan
/// kapan kendaraan diberangkatkan (bukan staff Loading), supaya masih
/// ada kesempatan menambah muatan sebelum benar-benar jalan.
///
/// **CATATAN (7 Oktober 2026 lanjutan lagi)**: tombol "Loading Barang
/// (Intervensi Admin)" yang SEBELUMNYA ada di tiap tile halaman ini SUDAH
/// DIPINDAHKAN total jadi menu standalone "Loading Barang" di Dashboard
/// (`dashboard_home_page.dart`, section Operasional) -- permintaan user
/// eksplisit supaya admin bisa intervensi TANPA tergantung staff loading
/// sudah lebih dulu membuka kendaraan (shipment) itu di app. Halaman ini
/// TIDAK lagi punya akses apa pun ke `AdminManualLoadPage`.
class ShipmentDispatchPage extends ConsumerStatefulWidget {
  const ShipmentDispatchPage({super.key});

  @override
  ConsumerState<ShipmentDispatchPage> createState() => _ShipmentDispatchPageState();
}

class _ShipmentDispatchPageState extends ConsumerState<ShipmentDispatchPage> {
  String? _busyShipmentId;

  /// Buka preview "Tanda Terima Tujuan" -- tombol ke-3 di tile Daftar
  /// Muatan, permintaan user (22 Sep 2026). Beda dari "Manifest" (rekap
  /// per resi buat arsip), dokumen ini 1 halaman PER TUJUAN untuk
  /// diserahkan & ditandatangani di lokasi tujuan masing-masing.
  ///
  /// SEBELUMNYA tombol ini langsung generate & share PDF tanpa preview
  /// -- diubah (22 Sep 2026, permintaan susulan user: "sebelum kirim pdf
  /// sebaiknya memang ada preview disitu") jadi navigasi ke
  /// `DestinationReceiptPreviewPage` dulu, konsisten dengan pola
  /// preview-dulu yang dipakai fitur cetak lain di app ini. Generate PDF
  /// & tombol bagikan/cetak sekarang sepenuhnya ditangani halaman preview
  /// itu (lewat widget `PdfPreview`), jadi tidak perlu logic
  /// async/busy-state di sini lagi.
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

  Future<void> _confirmDispatch(ShipmentModel shipment, VehicleModel? vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Berangkatkan Kendaraan?'),
        content: Text(
          'Kendaraan ${vehicle?.plateNumber ?? ''} (${shipment.shipmentNumber}) akan '
          'ditandai berangkat. Pastikan semua muatan yang perlu sudah discan naik.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Berangkatkan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyShipmentId = shipment.id);

    try {
      await ShipmentService.updateShipmentStatus(
        shipmentId: shipment.id,
        status: 'DEPARTED',
        departedAt: DateTime.now(),
      );

      ref.invalidate(shipmentsLoadingProvider);
      ref.invalidate(activeShipmentForVehicleProvider(shipment.vehicleId));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendaraan ditandai berangkat.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memberangkatkan: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyShipmentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipmentsAsync = ref.watch(shipmentsLoadingProvider);
    final vehiclesAsync = ref.watch(allVehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Daftar Muatan'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Pencarian muatan yang SUDAH BERANGKAT (status DEPARTED/ARRIVED)
          // -- beda dari daftar utama di halaman ini yang cuma nampilin
          // status LOADING. Dipakai buat cari ulang manifes/tanda terima
          // tujuan saat ada komplain dari tujuan setelah kendaraan jalan.
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Cari Muatan Berangkat',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ShipmentDepartedSearchPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: () async {
          ref.invalidate(shipmentsLoadingProvider);
          await ref.read(shipmentsLoadingProvider.future);
        },
        child: shipmentsAsync.when(
          data: (shipments) {
            if (shipments.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Tidak ada kendaraan yang sedang dimuat saat ini.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              );
            }

            final vehicles = vehiclesAsync.value;

            VehicleModel? findVehicle(String vehicleId) {
              if (vehicles == null) return null;
              for (final v in vehicles) {
                if (v.id == vehicleId) return v;
              }
              return null;
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: shipments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final shipment = shipments[index];
                final vehicle = findVehicle(shipment.vehicleId);
                final isBusy = _busyShipmentId == shipment.id;

                return _DispatchTile(
                  shipment: shipment,
                  vehicle: vehicle,
                  isBusy: isBusy,
                  onDispatch: () => _confirmDispatch(shipment, vehicle),
                  onViewManifest: vehicle == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ManifestPage(shipment: shipment, vehicle: vehicle),
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
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
          error: (error, _) => ErrorStateView(
            title: 'Gagal memuat daftar muatan.',
            message: error.toString(),
            onRetry: () => ref.invalidate(shipmentsLoadingProvider),
          ),
        ),
      ),
    );
  }
}

class _DispatchTile extends StatelessWidget {
  final ShipmentModel shipment;
  final VehicleModel? vehicle;
  final bool isBusy;
  final VoidCallback onDispatch;
  final VoidCallback? onViewManifest;
  final VoidCallback? onPrintDestinationReceipt;

  const _DispatchTile({
    required this.shipment,
    required this.vehicle,
    required this.isBusy,
    required this.onDispatch,
    required this.onViewManifest,
    required this.onPrintDestinationReceipt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orange.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
                  color: AppColors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: AppColors.orange),
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
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Sedang Dimuat',
                  style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: 11),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isBusy ? null : onDispatch,
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              icon: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.north_east_rounded),
              label: Text(isBusy ? 'Memproses...' : 'Berangkatkan'),
            ),
          ),
        ],
      ),
    );
  }
}
