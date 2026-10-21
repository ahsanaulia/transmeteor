import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/vehicle_service.dart';
import 'manifest_page.dart';

/// Daftar semua shipment (riwayat loading) -- tap salah satu untuk buka
/// lagi manifest muatannya kapan saja.
///
/// NOTE: pakai [allVehiclesProvider] (bukan [vehiclesProvider]) supaya
/// shipment yang kendaraannya sudah tidak "aktif" (mis. sudah lama
/// ARRIVED) tetap bisa ditemukan datanya dan baris manifest-nya tetap
/// bisa dibuka -- kalau pakai vehiclesProvider (yang cuma kendaraan
/// aktif), baris shipment lama jadi tidak bisa di-tap sama sekali.
class ShipmentListPage extends ConsumerWidget {
  const ShipmentListPage({super.key});

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

  Color _statusColor(String status) {
    switch (status) {
      case 'LOADING':
        return AppColors.orange;
      case 'DEPARTED':
        return AppColors.blue;
      case 'ARRIVED':
        return AppColors.green;
      case 'CANCELLED':
        return AppColors.red;
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

  // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
  // "Masukkan data Siapa Nama Pegawai Yang menginput atau scan ... Untuk
  // track pelaksana". `ShipmentModel.loadedBy` sudah ada sejak awal (id
  // employee yang membuka/memulai loading shipment ini, diisi di
  // `VehicleSelectPage` saat shipment dibuat), TAPI belum pernah
  // ditampilkan sebagai nama di mana pun. Resolusi id -> nama lewat
  // `allEmployeesProvider` (SUDAH ADA, dipakai halaman admin "Kelola
  // Pegawai") -- SAMA PERSIS pola yang dipakai `ReceivingListPage`
  // ("Monitoring Resi") untuk `receivedBy`, SENGAJA pakai yang "ALL"
  // (bukan cuma aktif) supaya pegawai yang sudah dinonaktifkan tetap
  // kelihatan namanya di riwayat lama.
  String _employeeName(List<EmployeeModel>? employees, String employeeId) {
    if (employees == null) return 'Memuat...';
    for (final e in employees) {
      if (e.id == employeeId) return e.fullName;
    }
    return '-';
  }

  Widget _buildStatChip(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipmentsAsync = ref.watch(shipmentsProvider);
    final vehiclesAsync = ref.watch(allVehiclesProvider);
    final employeesAsync = ref.watch(allEmployeesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Riwayat Shipment'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: shipmentsAsync.when(
        data: (allShipments) {
          // FITUR (16 Oktober 2026 -- permintaan user eksplisit: "admin
          // juga jangan muncul SHIPMENT yang diselesaikan paksa melalui
          // penyelesaian RESI" -- lihat project doc Tambahan #48):
          // shipment placeholder hasil tombol "Selesaikan" PER-RESI
          // (Monitoring Resi -- `ShipmentService.
          // forceCompleteReceivingByAdmin`) BUKAN muatan kendaraan
          // sungguhan, disembunyikan juga dari "Riwayat Shipment" Admin
          // ini -- lewat `VehicleService.isBypassPlaceholder` (identitas
          // KENDARAANnya), SAMA seperti filter di dashboard Supervisor
          // (`SupervisorLoadingTab`).
          //
          // SENGAJA BUKAN `completedByAdmin`: flag itu JUGA dipakai oleh
          // `ShipmentService.forceCompleteByAdmin` ("Intervensi Admin"
          // pada shipment yang BENAR-BENAR loading pakai kendaraan &
          // sopir asli) -- shipment jenis itu HARUS TETAP tampil di
          // sini, nama sopirnya tetap ada.
          final shipments = allShipments.where((s) {
            final vehicle = _findVehicle(vehiclesAsync.value, s.vehicleId);
            return !VehicleService.isBypassPlaceholder(vehicle);
          }).toList();

          if (shipments.isEmpty) {
            return const ErrorStateView(
              title: 'Belum ada shipment.',
              message:
                  'Shipment akan muncul di sini setelah proses muat barang dimulai.',
              icon: Icons.local_shipping_outlined,
            );
          }

          final loadingCount = shipments.where((s) => s.status == 'LOADING').length;
          final departedCount = shipments.where((s) => s.status == 'DEPARTED').length;
          final arrivedCount = shipments.where((s) => s.status == 'ARRIVED').length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        'Total',
                        '${shipments.length}',
                        AppColors.navy,
                        Icons.local_shipping_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        'Dimuat',
                        '$loadingCount',
                        AppColors.orange,
                        Icons.inventory_2_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        'Berangkat',
                        '$departedCount',
                        AppColors.blue,
                        Icons.north_east_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        'Tiba',
                        '$arrivedCount',
                        AppColors.green,
                        Icons.check_circle_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: shipments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final shipment = shipments[index];
                    final vehicle = _findVehicle(vehiclesAsync.value, shipment.vehicleId);

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: vehicle == null
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
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.local_shipping_rounded,
                                    color: AppColors.blue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shipment.shipmentNumber,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        vehicle?.plateNumber ?? 'Memuat data kendaraan...',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      // FITUR (8 Oktober 2026, lanjutan
                                      // lagi -- permintaan user eksplisit):
                                      // nama pegawai yang membuka/memuat
                                      // shipment ini, "untuk track
                                      // pelaksana".
                                      Text(
                                        'Dimuat oleh: ${_employeeName(employeesAsync.value, shipment.loadedBy)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(shipment.status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _statusLabel(shipment.status),
                                    style: TextStyle(
                                      color: _statusColor(shipment.status),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat daftar shipment.',
          message: error.toString(),
          onRetry: () => ref.invalidate(shipmentsProvider),
        ),
      ),
    );
  }
}
