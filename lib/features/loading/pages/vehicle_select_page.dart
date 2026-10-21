import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/shipment_service.dart';
import 'loading_scan_page.dart';

/// Halaman "Pilih Kendaraan" -- menampilkan kendaraan yang SUDAH
/// DISIAPKAN Admin (lihat `VehicleService.getVehicles`), masing-masing
/// dengan status "Dalam Perjalanan" atau "Siap Dimuat" (lihat
/// `_VehicleTile`, dihitung LIVE dari ada/tidaknya shipment aktif).
///
/// **DIKEMBALIKAN (13 Oktober 2026, permintaan user eksplisit:
/// "Kembalikan perubahan, bahwa kendaraan harus disiapkan oleh admin
/// baru muncul di loading")** -- fitur 10 Oktober 2026 yang membuat
/// kendaraan langsung tampil begitu didata (tanpa perlu disiapkan)
/// DIBATALKAN. Kendaraan baru (lewat "Pendataan Armada") TIDAK muncul
/// di sini sampai Admin menentukan sopirnya lewat "Siapkan Kendaraan"
/// (`VehicleService.prepareVehicle`) -- begitu juga kendaraan yang baru
/// selesai 1 perjalanan (ARRIVED), otomatis hilang lagi dari sini
/// sampai disiapkan ulang (lihat `ShipmentService.returnToOffice`/
/// `forceCompleteByAdmin`).
///
/// Kendaraan yang statusnya masih LOADING (sudah mulai discan tapi belum
/// diberangkatkan) TETAP muncul di sini -- supaya bisa dibuka lagi kalau
/// ada tambahan muatan. Loading TIDAK memberangkatkan kendaraan; itu
/// wewenang Admin lewat halaman "Daftar Muatan" (yang sekarang juga
/// reachable dari Aplikasi Loading lewat menu "Berangkatkan Kendaraan").
///
/// **DIPAKAI ULANG untuk Admin (7 Oktober 2026 lanjutan)**: menu Admin
/// "Loading Barang" (standalone, lihat `dashboard_home_page.dart`) SEKARANG
/// buka halaman INI JUGA (bukan file terpisah/duplikat) lewat [title] &
/// [destinationPageBuilder] -- supaya daftar kendaraan "siap muat" dan
/// logic lanjutkan/buat-shipment-baru (`ShipmentService.
/// resolveOrCreateShipmentForVehicle`) TIDAK dobel-maintain. Perbedaan
/// Admin vs staff Loading HANYA di halaman tujuan setelah shipment
/// didapat: staff -> `LoadingScanPage` (scan kamera + checklist manual),
/// Admin -> `AdminManualLoadPage` (checklist manual saja, tanpa kamera --
/// sesuai sifatnya sebagai intervensi/koreksi, bukan alur kerja utama).
class VehicleSelectPage extends ConsumerStatefulWidget {
  /// Judul AppBar -- default utk staff Loading, diisi beda utk Admin.
  final String title;

  /// Halaman yang dibuka setelah shipment (baru/lanjutan) didapat --
  /// default (`null`) berarti `LoadingScanPage` (perilaku staff Loading,
  /// TIDAK berubah). Admin mengisi ini dengan `AdminManualLoadPage`.
  final Widget Function(VehicleModel vehicle, ShipmentModel shipment)?
      destinationPageBuilder;

  /// Pesan empty-state saat belum ada kendaraan yang SUDAH DISIAPKAN
  /// (DIKEMBALIKAN 13 Oktober 2026 -- lihat doc comment class di atas).
  /// Admin (yang membuka halaman ini SENDIRI dari menu "Loading Barang")
  /// mengisi pesan versi dirinya sendiri.
  final String emptyStateMessage;

  const VehicleSelectPage({
    super.key,
    this.title = 'Pilih Kendaraan',
    this.destinationPageBuilder,
    this.emptyStateMessage = 'Belum ada kendaraan yang disiapkan. Siapkan '
        'dulu lewat menu "Siapkan Kendaraan" (tentukan sopirnya).',
  });

  @override
  ConsumerState<VehicleSelectPage> createState() => _VehicleSelectPageState();
}

class _VehicleSelectPageState extends ConsumerState<VehicleSelectPage> {
  String? _loadingVehicleId;

  Future<void> _selectVehicle(VehicleModel vehicle) async {
    setState(() {
      _loadingVehicleId = vehicle.id;
    });

    try {
      final employee = await ref.read(currentEmployeeProvider.future);

      if (employee == null) {
        throw Exception(
          'Data employee tidak ditemukan, tidak bisa memulai shipment.',
        );
      }

      // Logic "lanjutkan muat vs buat shipment baru" dipusatkan di
      // service -- dipakai SAMA PERSIS oleh staff Loading & Admin (lihat
      // doc comment class di atas), supaya tidak dobel-maintain.
      final shipment = await ShipmentService.resolveOrCreateShipmentForVehicle(
        vehicleId: vehicle.id,
        vehicleDriverEmployeeId: vehicle.driverEmployeeId,
        loadedBy: employee.id,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => widget.destinationPageBuilder != null
              ? widget.destinationPageBuilder!(vehicle, shipment)
              : LoadingScanPage(vehicle: vehicle, shipment: shipment),
        ),
      );

      ref.invalidate(activeShipmentForVehicleProvider(vehicle.id));
      ref.invalidate(vehiclesProvider);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka shipment: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingVehicleId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: vehiclesAsync.when(
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return ErrorStateView(
              title: 'Belum ada kendaraan siap muat.',
              message: widget.emptyStateMessage,
              icon: Icons.local_shipping_outlined,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final vehicle = vehicles[index];
              final isLoadingThis = _loadingVehicleId == vehicle.id;

              return _VehicleTile(
                vehicle: vehicle,
                isLoading: isLoadingThis,
                onTap: _loadingVehicleId == null
                    ? () => _selectVehicle(vehicle)
                    : null,
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.blue),
        ),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat daftar kendaraan.',
          message: error.toString(),
          onRetry: () => ref.invalidate(vehiclesProvider),
        ),
      ),
    );
  }
}

class _VehicleTile extends ConsumerWidget {
  final VehicleModel vehicle;
  final bool isLoading;
  final VoidCallback? onTap;

  const _VehicleTile({
    required this.vehicle,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeShipmentAsync =
        ref.watch(activeShipmentForVehicleProvider(vehicle.id));

    final activeShipment = activeShipmentAsync.value;
    final hasActiveShipment = activeShipment != null && !activeShipmentAsync.isLoading;

    // **DIUBAH (10 Oktober 2026, permintaan user: "Status hanya 2: Dalam
    // Perjalanan / Siap dimuat")** -- SEBELUMNYA ada 3 badge (dibedakan
    // LOADING vs DEPARTED). Sekarang dikumpulkan jadi 2: kendaraan yang
    // SOPIR & kendaraannya belum menyelesaikan resi barangnya (shipment
    // masih LOADING ATAU DEPARTED, keduanya "belum sampai ARRIVED") selalu
    // "Dalam Perjalanan"; begitu shipment terakhirnya ARRIVED (atau belum
    // pernah ada shipment sama sekali), kendaraan jadi "Siap Dimuat".
    // Catatan: tap ke kendaraan "Dalam Perjalanan" (termasuk yang sudah
    // DEPARTED) TETAP diperbolehkan -- itu artinya "lanjutkan/tambah
    // muatan", perilaku `_selectVehicle` tidak berubah.
    final String badgeLabel;
    final Color badgeColor;

    if (hasActiveShipment) {
      badgeLabel = 'Dalam Perjalanan';
      badgeColor = AppColors.orange;
    } else {
      badgeLabel = 'Siap Dimuat';
      badgeColor = AppColors.green;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
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
                    color: AppColors.blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.local_shipping_rounded, color: AppColors.blue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.plateNumber,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (vehicle.vehicleType != null) vehicle.vehicleType!,
                          if (vehicle.driverName != null) vehicle.driverName!,
                        ].join(' • '),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
