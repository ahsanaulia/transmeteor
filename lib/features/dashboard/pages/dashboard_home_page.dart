import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/employee_role_model.dart';
import '../../../providers/dashboard_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/auth_service.dart';
import '../../admin/pages/administrasi_page.dart';
import '../../auth/pages/login_page.dart';
import '../../company/pages/company_profile_page.dart';
import '../../destinations/pages/destination_manage_page.dart';
import '../../employees/pages/employee_create_page.dart';
import '../../employees/pages/employee_manage_page.dart';
import '../../item_types/pages/item_type_manage_page.dart';
import '../../loading/pages/admin_manual_load_page.dart';
import '../../loading/pages/shipment_dispatch_page.dart';
import '../../loading/pages/shipment_list_page.dart';
import '../../loading/pages/vehicle_select_page.dart';
import '../../pricing/pages/pricing_type_manage_page.dart';
import '../../receiving/pages/admin_receiving_entry_page.dart';
import '../../representatives/pages/representative_manage_page.dart';
import '../../senders/pages/sender_manage_page.dart';
import '../../storages/pages/storage_manage_page.dart';
import '../../storages/pages/storage_zone_monitoring_page.dart';
import '../../vehicles/pages/prepare_vehicle_page.dart';
import 'fleet_monitoring_page.dart';
import 'resi_delivery_monitoring_page.dart';
import 'trip_performance_page.dart';
import 'receiving_list_page.dart';

class DashboardHomePage extends ConsumerStatefulWidget {
  const DashboardHomePage({super.key});

  @override
  ConsumerState<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends ConsumerState<DashboardHomePage> {
  // ============================================================
  // SESSION / LOGOUT
  // ============================================================

  Future<void> _refresh() async {
    ref.invalidate(currentEmployeeProvider);
    ref.invalidate(dashboardSummaryProvider);
    await ref.read(currentEmployeeProvider.future);
  }

  Future<void> _logout() async {
    try {
      await AuthService.signOut();

      invalidateSession(ref);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal logout: $e')));
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _logout();
    }
  }

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);
    final roleAsync = ref.watch(currentRoleProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _buildBody(employeeAsync, roleAsync)),
    );
  }

  Widget _buildBody(
    AsyncValue<EmployeeModel?> employeeAsync,
    AsyncValue<EmployeeRoleModel?> roleAsync,
  ) {
    if (employeeAsync.isLoading || roleAsync.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    final error = employeeAsync.hasError
        ? employeeAsync.error
        : (roleAsync.hasError ? roleAsync.error : null);

    if (error != null) {
      return ErrorStateView(
        title: 'Data pengguna tidak dapat dimuat.',
        message: error.toString(),
        onRetry: () => ref.invalidate(currentEmployeeProvider),
      );
    }

    final employee = employeeAsync.value;

    if (employee == null) {
      return const ErrorStateView(
        title: 'Data employee untuk akun ini tidak ditemukan.',
      );
    }

    final roleName = roleAsync.value?.name ?? 'Supervisor';

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWide ? 900 : double.infinity,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 24 : 16,
                    16,
                    isWide ? 24 : 16,
                    32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(
                        employeeName: employee.fullName,
                        roleName: roleName,
                      ),
                      const SizedBox(height: 18),
                      _buildSummarySection(constraints.maxWidth),
                      const SizedBox(height: 20),
                      _buildMenuSection(),
                      const SizedBox(height: 20),
                      _buildRecentSection(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader({required String employeeName, required String roleName}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F9FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.blue.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.navy, AppColors.blue],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.space_dashboard_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRANS',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.navy.withOpacity(0.12),
                        AppColors.blue.withOpacity(0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    roleName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showLogoutConfirmation,
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY (KPI CARDS)
  // ============================================================

  Widget _buildSummarySection(double maxWidth) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return summaryAsync.when(
      data: (summary) {
        final cards = [
          _SummaryCardData(
            icon: Icons.receipt_long_rounded,
            label: 'Resi Hari Ini',
            value: summary.receivingCountToday.toString(),
            color: AppColors.blue,
          ),
          _SummaryCardData(
            icon: Icons.inventory_2_rounded,
            label: 'Volume Hari Ini',
            value: _formatQuantity(summary.totalQuantityToday),
            color: AppColors.violet,
          ),
          _SummaryCardData(
            icon: Icons.payments_rounded,
            label: 'Nilai Hari Ini',
            value: formatRupiah(summary.totalValueToday),
            color: AppColors.cyan,
          ),
          _SummaryCardData(
            icon: Icons.local_shipping_rounded,
            label: 'Shipment Aktif',
            value: summary.activeShipmentCount.toString(),
            color: AppColors.orange,
          ),
          _SummaryCardData(
            icon: Icons.directions_car_filled_rounded,
            label: 'Kendaraan Terpakai',
            value: summary.vehiclesInUseCount.toString(),
            color: AppColors.green,
          ),
        ];

        final columns = maxWidth >= 700 ? 5 : (maxWidth >= 420 ? 3 : 2);

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [for (final data in cards) _SummaryCard(data: data)],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: AppColors.blue)),
      ),
      error: (error, stackTrace) => Text(
        'Gagal memuat ringkasan: $error',
        style: const TextStyle(color: AppColors.red),
      ),
    );
  }

  // ============================================================
  // MENU
  // ============================================================

  Widget _buildMenuSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.blue.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Operasional',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.assignment_turned_in_rounded,
                title: 'Siapkan Kendaraan',
                subtitle: 'Tambah kendaraan baru & tentukan sopir/helper',
                accentColor: AppColors.navy,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PrepareVehiclePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              // "Loading Barang" (Intervensi Admin) -- MENU BERDIRI
              // SENDIRI (7 Oktober 2026 lanjutan lagi, permintaan user
              // eksplisit), TERPISAH dari "Daftar Muatan" di bawah.
              // SEBELUMNYA fitur ini cuma bisa diakses lewat tile
              // shipment yang SUDAH ADA di Daftar Muatan -- artinya admin
              // baru bisa intervensi SETELAH staff loading sendiri lebih
              // dulu membuka kendaraan itu di app. User eksplisit minta
              // admin bisa TOTAL INDEPENDEN: pilih sendiri kendaraan yang
              // sudah disiapkan, lalu app otomatis membuat/melanjutkan
              // shipment-nya (`ShipmentService.resolveOrCreateShipmentForVehicle`,
              // SAMA PERSIS logic yang dipakai staff Loading lewat
              // `VehicleSelectPage` -- dipakai ulang di sini, BUKAN
              // halaman pilih-kendaraan terpisah/dobel), baru masuk ke
              // checklist `AdminManualLoadPage`.
              MenuActionCard(
                icon: Icons.checklist_rtl_rounded,
                title: 'Loading Barang (Intervensi Admin)',
                subtitle: 'Catat barang yang sudah dimuat buruh tapi belum tercatat di app',
                accentColor: AppColors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VehicleSelectPage(
                        title: 'Loading Barang (Admin)',
                        emptyStateMessage:
                            'Belum ada kendaraan terdata. Tambahkan dulu '
                            'lewat menu "Siapkan Kendaraan" di atas.',
                        destinationPageBuilder: (vehicle, shipment) =>
                            AdminManualLoadPage(
                          shipment: shipment,
                          vehicle: vehicle,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // "Penerimaan Barang" (Intervensi Admin) -- (8 Oktober 2026,
              // permintaan user eksplisit) -- cara LAIN mencatat resi +
              // detail barangnya, KHUSUS admin yang kerja dari komputer/
              // Chrome (satu halaman tabular master-detail, tanpa
              // keharusan foto, cuma 2 aksi cetak). DI SAMPING alur mobile
              // yang sudah ada (ReceivingCreatePage), bukan menggantikan.
              // Lihat doc comment lengkap di AdminReceivingEntryPage.
              MenuActionCard(
                icon: Icons.edit_document,
                title: 'Penerimaan Barang (Intervensi Admin)',
                subtitle: 'Input resi & barang dari komputer -- tabel, tanpa wajib foto',
                accentColor: AppColors.cyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminReceivingEntryPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // "Buat User Pegawai" (8 Oktober 2026, permintaan user poin
              // 8) -- MENGGANTIKAN self-register publik yang DIHAPUS dari
              // halaman login (lihat `login_page.dart`). Admin yang
              // sekarang membuatkan akun pegawai + password-nya, lalu
              // password itu dibagikan manual ke pegawai bersangkutan.
              MenuActionCard(
                icon: Icons.person_add_rounded,
                title: 'Buat User Pegawai',
                subtitle: 'Buat akun login + password baru untuk pegawai',
                accentColor: AppColors.violet,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmployeeCreatePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.people_alt_rounded,
                title: 'Kelola Pegawai',
                subtitle: 'Lihat semua pegawai & aktif/nonaktifkan akun',
                accentColor: AppColors.violet,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmployeeManagePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.inventory_2_rounded,
                title: 'Daftar Muatan',
                subtitle: 'Lihat mobil yang sedang dimuat & berangkatkan',
                accentColor: AppColors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShipmentDispatchPage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.business_rounded,
                title: 'Profil Perusahaan',
                subtitle: 'Nama, alamat & logo -- kop semua cetakan',
                accentColor: AppColors.cyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CompanyProfilePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.sell_rounded,
                title: 'Kelola Jenis Harga',
                subtitle: 'Tambah/edit jenis harga untuk kiriman baru',
                accentColor: AppColors.pink,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PricingTypeManagePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.category_rounded,
                title: 'Kelola Jenis Barang',
                subtitle: 'Tambah/edit jenis barang (8 Oktober 2026)',
                accentColor: AppColors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ItemTypeManagePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.warehouse_rounded,
                title: 'Zona Storage',
                subtitle: 'Kelola zona/lokasi penyimpanan barang di gudang',
                accentColor: AppColors.lightBlue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StorageManagePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.place_rounded,
                title: 'Daftar Langganan Tujuan',
                subtitle: 'Daftarkan tujuan langganan supaya Receiving tinggal pilih',
                accentColor: AppColors.lightBlue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DestinationManagePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.person_rounded,
                title: 'Daftar Pengirim Langganan',
                subtitle: 'Daftarkan pengirim langganan supaya Receiving tinggal pilih',
                accentColor: AppColors.green,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SenderManagePage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.storefront_rounded,
                title: 'Daftar Perwakilan',
                subtitle: 'Agen titipan barang kalau tujuan asli tidak bisa dijangkau',
                accentColor: AppColors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RepresentativeManagePage()),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.blue.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monitoring',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.receipt_long_rounded,
                title: 'Monitoring Resi',
                subtitle: 'Lihat semua resi penerimaan barang',
                accentColor: AppColors.blue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReceivingListPage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.local_shipping_rounded,
                title: 'Monitoring Shipment',
                subtitle: 'Lihat semua shipment & manifest muatan',
                accentColor: AppColors.violet,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShipmentListPage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.map_rounded,
                title: 'Monitoring Kendaraan & Sopir',
                subtitle: 'Peta posisi terakhir semua kendaraan & sopir',
                accentColor: AppColors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FleetMonitoringPage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.check_circle_outline_rounded,
                title: 'Monitoring Resi Sampai',
                subtitle: 'Status pengiriman & lokasi turun tiap resi',
                accentColor: AppColors.green,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ResiDeliveryMonitoringPage()),
                  );
                },
              ),
              const SizedBox(height: 12),
              // FITUR (9 Oktober 2026 -- permintaan user eksplisit):
              // "Monitoring Zona Storage. Dipilih Zona maka akan muncul
              // daftar barang yang ada dizona ... Hanya barang yang
              // belum diloading dan dalam perjalanan." Beda dari "Zona
              // Storage" di bagian "Kelola" di atas (CRUD nama/deskripsi
              // zona) -- ini murni MELIHAT barang apa saja yang lagi
              // tersimpan di tiap zona, lengkap pencarian.
              MenuActionCard(
                icon: Icons.inventory_2_rounded,
                title: 'Monitoring Zona Storage',
                subtitle: 'Barang per zona gudang yang belum dimuat/berangkat',
                accentColor: AppColors.lightBlue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StorageZoneMonitoringPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              MenuActionCard(
                icon: Icons.insights_rounded,
                title: 'Monitoring Kinerja Perjalanan',
                subtitle: 'Durasi, progress resi & biaya per shipment/sopir/kendaraan',
                accentColor: AppColors.cyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TripPerformancePage()),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.blue.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Administrasi',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              // FITUR (10 Oktober 2026, permintaan user eksplisit): menu
              // terpisah untuk tugas administratif berkala -- DIBUAT
              // sebagai halaman daftar menu sendiri (AdministrasiPage,
              // bukan 1 tombol langsung di sini) supaya menu administratif
              // lain yang mungkin ditambahkan nanti punya tempat jelas,
              // tidak campur dengan menu operasional/monitoring di atas.
              MenuActionCard(
                icon: Icons.admin_panel_settings_rounded,
                title: 'Administrasi',
                subtitle: 'Unduh & bersihkan foto Barang Sampai dari Supabase',
                accentColor: AppColors.red,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdministrasiPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RECENT ACTIVITY
  // ============================================================

  Widget _buildRecentSection() {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return summaryAsync.when(
      data: (summary) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecentReceivingCard(summary.recentReceiving),
          const SizedBox(height: 16),
          _buildRecentShipmentCard(summary.recentShipments),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentReceivingCard(List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.blue),
              SizedBox(width: 8),
              Text(
                'Resi Terbaru',
                style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Belum ada resi.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['receipt_number']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${item['destination']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatRupiah((item['total_price'] as num?)?.toDouble() ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildRecentShipmentCard(List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.violet.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_shipping_rounded, size: 18, color: AppColors.violet),
              SizedBox(width: 8),
              Text(
                'Shipment Terbaru',
                style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Belum ada shipment.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['shipment_number']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            ((item['vehicles'] as Map?)?['plate_number'] ?? '-')
                                .toString(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge('${item['status']}'),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = switch (status) {
      'LOADING' => AppColors.orange,
      'DEPARTED' => AppColors.blue,
      'ARRIVED' => AppColors.green,
      'CANCELLED' => AppColors.red,
      _ => AppColors.textSecondary,
    };

    final label = switch (status) {
      'LOADING' => 'Sedang Dimuat',
      'DEPARTED' => 'Berangkat',
      'ARRIVED' => 'Tiba',
      'CANCELLED' => 'Dibatalkan',
      _ => status,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }
}

class _SummaryCardData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  _SummaryCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _SummaryCard extends StatelessWidget {
  final _SummaryCardData data;

  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: data.color.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: data.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const Spacer(),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}