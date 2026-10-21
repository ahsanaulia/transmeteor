import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/vehicle_service.dart';
import '../pages/supervisor_shipment_items_page.dart';
import '../supervisor_ui_kit.dart';

enum _LoadingSection { daftarMuatan, sudahTiba }

/// Tab 2 "Monitoring Pemuatan & Penyelesaian" -- Dashboard Supervisor (16
/// Oktober 2026, permintaan user):
/// "Daftar muatan (sebagaimana di admin) tetapi tanpa crud. Daftar
/// shipment muatan yang sudah tiba di tujuan. Jika diklik mobil
/// shipmentnya muncul barang2 apa apa saja."
///
/// Dua bagian dipilih lewat chip (bukan TabBar bersarang, supaya tetap 1
/// layar tanpa gesture tab-di-dalam-tab yang membingungkan):
///   - "Daftar Muatan" -> shipment status LOADING (`shipmentsLoadingProvider`,
///     SAMA dengan sumber data `ShipmentDispatchPage` admin), TANPA tombol
///     Berangkatkan/cetak.
///   - "Sudah Tiba" -> shipment status ARRIVED, dari `shipmentsProvider`
///     (riwayat semua shipment) disaring di Dart.
///
/// Tap kartu mana pun (kedua bagian) membuka `SupervisorShipmentItemsPage`
/// (read-only, lihat doc comment di sana) -- SENGAJA tap juga diaktifkan
/// untuk "Daftar Muatan" (bukan cuma "Sudah Tiba"), supaya supervisor bisa
/// pantau isi muatan SEJAK masih di gudang, bukan baru setelah tiba.
class SupervisorLoadingTab extends ConsumerStatefulWidget {
  const SupervisorLoadingTab({super.key});

  @override
  ConsumerState<SupervisorLoadingTab> createState() =>
      _SupervisorLoadingTabState();
}

class _SupervisorLoadingTabState extends ConsumerState<SupervisorLoadingTab> {
  _LoadingSection _section = _LoadingSection.daftarMuatan;

  String _employeeName(List<EmployeeModel>? employees, String employeeId) {
    if (employees == null) return 'Memuat...';
    for (final e in employees) {
      if (e.id == employeeId) return e.fullName;
    }
    return '-';
  }

  VehicleModel? _findVehicle(List<VehicleModel>? vehicles, String vehicleId) {
    if (vehicles == null) return null;
    for (final v in vehicles) {
      if (v.id == vehicleId) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(allVehiclesProvider);
    final employeesAsync = ref.watch(allEmployeesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: Row(
            children: [
              _sectionChip('Daftar Muatan (Sedang Dimuat)',
                  _LoadingSection.daftarMuatan, AppColors.orange),
              const SizedBox(width: 12),
              _sectionChip('Sudah Tiba di Tujuan', _LoadingSection.sudahTiba,
                  AppColors.green),
            ],
          ),
        ),
        Expanded(
          child: _section == _LoadingSection.daftarMuatan
              ? _buildDaftarMuatan(vehiclesAsync.value, employeesAsync.value)
              : _buildSudahTiba(vehiclesAsync.value, employeesAsync.value),
        ),
      ],
    );
  }

  Widget _sectionChip(String label, _LoadingSection value, Color color) {
    final selected = _section == value;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => _section = value),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: selected ? Colors.white : color,
      ),
      selectedColor: color,
      backgroundColor: color.withOpacity(0.10),
      side: BorderSide(color: color.withOpacity(selected ? 0 : 0.25)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      showCheckmark: false,
    );
  }

  Widget _buildDaftarMuatan(
    List<VehicleModel>? vehicles,
    List<EmployeeModel>? employees,
  ) {
    final shipmentsAsync = ref.watch(shipmentsLoadingProvider);

    return shipmentsAsync.when(
      data: (shipments) {
        if (shipments.isEmpty) {
          return const Center(
            child: Text(
              'Tidak ada kendaraan yang sedang dimuat saat ini.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return _buildShipmentGrid([
          for (final shipment in shipments)
            _ShipmentTile(
              shipment: shipment,
              vehicle: _findVehicle(vehicles, shipment.vehicleId),
              statusLabel: 'Sedang Dimuat',
              statusColor: AppColors.orange,
              loadedByLabel: 'Dimuat oleh: '
                  '${_employeeName(employees, shipment.loadedBy)}',
            ),
        ]);
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.blue)),
      error: (error, stackTrace) => ErrorStateView(
        title: 'Gagal memuat daftar muatan.',
        message: error.toString(),
        onRetry: () => ref.invalidate(shipmentsLoadingProvider),
      ),
    );
  }

  Widget _buildSudahTiba(
    List<VehicleModel>? vehicles,
    List<EmployeeModel>? employees,
  ) {
    final shipmentsAsync = ref.watch(shipmentsProvider);

    return shipmentsAsync.when(
      data: (allShipments) {
        // FITUR (16 Oktober 2026 -- permintaan user eksplisit: "data
        // yang sudah terlanjur membuat shipment baru akibat
        // penyelesaian RESI jangan muncul" di sini, LALU diperjelas lagi
        // lewat pesan susulan yang membedakan 2 jenis "diselesaikan
        // paksa admin" -- lihat project doc Tambahan #48):
        // shipment hasil tombol "Selesaikan" PER-RESI (bypass admin,
        // Monitoring Resi -- lihat
        // `ShipmentService.forceCompleteReceivingByAdmin`) BUKAN muatan
        // kendaraan sungguhan -- disaring keluar dari "Sudah Tiba di
        // Tujuan" lewat `VehicleService.isBypassPlaceholder` (identitas
        // KENDARAANnya, bukan `completedByAdmin`).
        //
        // PENTING: TIDAK pakai `completedByAdmin` sebagai filter (lihat
        // percobaan PERTAMA yang SALAH, Tambahan #47) -- flag itu JUGA
        // di-set true oleh `ShipmentService.forceCompleteByAdmin`
        // ("Intervensi Admin" di shipment yang BENAR-BENAR loading pakai
        // kendaraan & sopir asli, cuma dipaksa selesai krn sopir tidak
        // bisa menekan sendiri) -- shipment jenis itu HARUS TETAP
        // tampil di sini (nama sopirnya tetap ada), dan filter
        // `completedByAdmin` lama JUSTRU ikut menyembunyikannya, salah.
        final shipments = allShipments.where((s) {
          if (s.status != 'ARRIVED') return false;
          final vehicle = _findVehicle(vehicles, s.vehicleId);
          return !VehicleService.isBypassPlaceholder(vehicle);
        }).toList();

        if (shipments.isEmpty) {
          return const Center(
            child: Text(
              'Belum ada shipment yang sudah tiba di tujuan.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return _buildShipmentGrid([
          for (final shipment in shipments)
            _ShipmentTile(
              shipment: shipment,
              vehicle: _findVehicle(vehicles, shipment.vehicleId),
              statusLabel: 'Tiba',
              statusColor: AppColors.green,
              loadedByLabel: 'Dimuat oleh: '
                  '${_employeeName(employees, shipment.loadedBy)}',
            ),
        ]);
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.blue)),
      error: (error, stackTrace) => ErrorStateView(
        title: 'Gagal memuat riwayat shipment.',
        message: error.toString(),
        onRetry: () => ref.invalidate(shipmentsProvider),
      ),
    );
  }

  // FITUR (16 Oktober 2026 -- permintaan user eksplisit: "3 kolom untuk
  // Resi dan shipment dan tinggi ditambah"): grid 3 kolom, SAMA pola
  // dengan `SupervisorResiTab` (`Wrap` + `LayoutBuilder`, BUKAN
  // `GridView`, supaya tinggi tiap kartu tetap bebas beda-beda).
  Widget _buildShipmentGrid(List<Widget> tiles) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 16.0;
          const columns = 3;
          final cardWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final tile in tiles)
                SizedBox(width: cardWidth, child: tile),
            ],
          );
        },
      ),
    );
  }
}

class _ShipmentTile extends StatelessWidget {
  final ShipmentModel shipment;
  final VehicleModel? vehicle;
  final String statusLabel;
  final Color statusColor;
  final String loadedByLabel;

  const _ShipmentTile({
    required this.shipment,
    required this.vehicle,
    required this.statusLabel,
    required this.statusColor,
    required this.loadedByLabel,
  });

  // FITUR (16 Oktober 2026 -- "UI Tab Shipment juga perlu dipercantik" +
  // "3 kolom ... dan tinggi ditambah"): `SupervisorAccentCard` (strip
  // warna di atas + badan pastel tipis) menggantikan Container putih
  // polos, konsisten dengan Tab 1 & Tab 3. Layout diubah dari Row
  // (ikon+teks+chip+chevron 1 baris) jadi Column vertikal supaya tetap
  // nyaman dibaca di kartu yang sekarang 1/3 lebar layar (grid 3 kolom),
  // dengan padding dilonggarkan supaya kartu terasa lebih tinggi/lega.
  @override
  Widget build(BuildContext context) {
    return SupervisorAccentCard(
      color: statusColor,
      padding: const EdgeInsets.all(20),
      onTap: vehicle == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SupervisorShipmentItemsPage(
                    shipment: shipment,
                    vehicle: vehicle!,
                  ),
                ),
              );
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.local_shipping_rounded,
                    color: statusColor, size: 28),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 26),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            shipment.shipmentNumber,
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: 0.2),
          ),
          const SizedBox(height: 6),
          Text(
            vehicle != null
                ? '${vehicle!.plateNumber}'
                    '${vehicle!.driverName != null ? ' • ${vehicle!.driverName}' : ''}'
                : 'Memuat data kendaraan...',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loadedByLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 14),
          SupervisorPastelChip(label: statusLabel, pastelColor: statusColor),
        ],
      ),
    );
  }
}
