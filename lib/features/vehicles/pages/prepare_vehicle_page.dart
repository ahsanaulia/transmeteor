import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../widgets/add_vehicle_sheet.dart';
import '../widgets/prepare_vehicle_sheet.dart';

/// Halaman "Siapkan Kendaraan" / "Pendataan Armada" -- tambah kendaraan
/// baru, lalu tentukan sopir & helper-nya.
///
/// **DIPAKAI ULANG untuk Aplikasi Loading (10 Oktober 2026, permintaan
/// user: "Tambahkan menu yang sama dari admin: Pendataan Armada")** --
/// halaman INI JUGA (bukan file terpisah/duplikat) yang dibuka lewat
/// menu "Pendataan Armada" di `LoadingHomePage`, sama seperti Admin
/// membukanya lewat "Siapkan Kendaraan" di Dashboard.
///
/// **DIUBAH (13 Oktober 2026)**: `is_active` KEMBALI jadi gate "sudah
/// disiapkan Admin" untuk tampil di "Pilih Kendaraan" Loading (lihat
/// doc comment `VehicleService.getVehicles`) -- halaman INI tetap
/// yang dipakai untuk menentukan/mengganti sopir-helper (`prepareVehicle`)
/// supaya kendaraan itu boleh tampil di sana.
///
/// **DITAMBAHKAN (13 Oktober 2026, permintaan user: "Pencarian
/// kendaraan disiapkan kendaraan bisa menulis nama sopir atau plat
/// kendaraan")** -- search box di atas daftar, filter LOKAL (bukan
/// query baru ke Supabase) terhadap `allVehiclesProvider` yang sudah
/// di-fetch, cocok substring case-insensitive ke `plateNumber` ATAU
/// `driverName` (salah satu cocok sudah cukup).
class PrepareVehiclePage extends ConsumerStatefulWidget {
  const PrepareVehiclePage({super.key});

  @override
  ConsumerState<PrepareVehiclePage> createState() =>
      _PrepareVehiclePageState();
}

class _PrepareVehiclePageState extends ConsumerState<PrepareVehiclePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    // Pegawai (calon sopir/helper) yang baru saja register mungkin belum
    // tercermin di provider driver/helper yang sudah di-cache Riverpod
    // sejak sesi ini dibuka -- refresh tiap kali halaman ini dibuka
    // supaya picker sopir & helper selalu menampilkan data terbaru.
    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(driverEmployeesProvider);
      ref.invalidate(helperEmployeesProvider);
    });

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<VehicleModel> _filterVehicles(List<VehicleModel> vehicles) {
    if (_searchQuery.isEmpty) return vehicles;

    return vehicles.where((vehicle) {
      final plate = vehicle.plateNumber.toLowerCase();
      final driver = (vehicle.driverName ?? '').toLowerCase();
      return plate.contains(_searchQuery) || driver.contains(_searchQuery);
    }).toList();
  }

  Future<void> _openAddSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddVehicleSheet(),
    );

    if (created == true) {
      ref.invalidate(allVehiclesProvider);
      ref.invalidate(vehiclesProvider);
    }
  }

  Future<void> _openPrepareSheet(VehicleModel vehicle) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PrepareVehicleSheet(vehicle: vehicle),
    );

    if (saved == true) {
      ref.invalidate(allVehiclesProvider);
      ref.invalidate(vehiclesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(allVehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Siapkan Kendaraan'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Kendaraan'),
        backgroundColor: AppColors.blue,
      ),
      body: vehiclesAsync.when(
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return ErrorStateView(
              title: 'Belum ada kendaraan.',
              message: 'Tambahkan kendaraan baru lewat tombol di bawah.',
              icon: Icons.local_shipping_outlined,
              onRetry: _openAddSheet,
            );
          }

          final filtered = _filterVehicles(vehicles);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari nama sopir atau plat kendaraan...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => _searchController.clear(),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColors.blue.withOpacity(0.15),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _searchQuery.isEmpty
                        ? '${filtered.length} kendaraan'
                        : '${filtered.length} dari ${vehicles.length} kendaraan',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? ErrorStateView(
                        title: 'Tidak ditemukan.',
                        message: 'Tidak ada kendaraan dengan nama sopir '
                            'atau plat "$_searchQuery".',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final vehicle = filtered[index];

                          return _VehiclePrepTile(
                            vehicle: vehicle,
                            onTap: () => _openPrepareSheet(vehicle),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.blue),
        ),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat daftar kendaraan.',
          message: error.toString(),
          onRetry: () => ref.invalidate(allVehiclesProvider),
        ),
      ),
    );
  }
}

class _VehiclePrepTile extends StatelessWidget {
  final VehicleModel vehicle;
  final VoidCallback onTap;

  const _VehiclePrepTile({required this.vehicle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final helperCount = [
      vehicle.helper1EmployeeId,
      vehicle.helper2EmployeeId,
      vehicle.helper3EmployeeId,
    ].whereType<String>().length;

    // **DIUBAH (10 Oktober 2026)**: badge di tile ini SEBELUMNYA membaca
    // `vehicle.isActive` sebagai penanda "sudah disiapkan/siap dimuat" --
    // sekarang is_active cuma berarti "tidak dinonaktifkan permanen",
    // jadi badge "siap dimuat"/"dalam perjalanan" HARUS dilihat di
    // `VehicleSelectPage` (dihitung live dari shipment aktif). Di sini,
    // yang relevan untuk konteks "Pendataan Armada" adalah APAKAH
    // kendaraan ini sudah punya sopir atau belum.
    final hasDriver = vehicle.driverEmployeeId != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (hasDriver ? AppColors.green : AppColors.blue)
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
                          if (helperCount > 0) '$helperCount helper',
                        ].join(' • '),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (hasDriver ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hasDriver ? 'Ada Sopir' : 'Belum Ada Sopir',
                          style: TextStyle(
                            color: hasDriver ? AppColors.green : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
