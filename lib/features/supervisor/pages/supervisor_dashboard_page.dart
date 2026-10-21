import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/auth_service.dart';
import '../../auth/pages/login_page.dart';
import '../widgets/supervisor_resi_tab.dart';
import '../widgets/supervisor_loading_tab.dart';
import '../widgets/supervisor_zone_tab.dart';

/// FITUR (16 Oktober 2026, permintaan user eksplisit): dashboard BARU
/// khusus role "Supervisor" -- "Dashboard ini hanya monitoring di Admin
/// yang dapat dijalankan. Tidak boleh ada editing disitu. Hanya View
/// saja." Beda total dari `DashboardHomePage` (dashboard Admin biasa,
/// penuh CRUD/aksi): halaman ini & SEMUA widget tab di bawahnya SENGAJA
/// TIDAK PERNAH memanggil service yang menulis data (insert/update/
/// delete) -- cuma membaca provider yang sudah ada (read-only by
/// construction, bukan cuma "disembunyikan tombolnya").
///
/// Dirancang untuk monitor BESAR (32 inch, permintaan user eksplisit):
/// - Header ala website: identitas aplikasi + nama/role pegawai + logout,
///   SELALU terlihat (bukan AppBar standar kecil).
/// - Tab di bawah header (bukan di AppBar) supaya bisa dibuat besar/jelas.
/// - SEMUA teks informasi di 3 tab di bawah ini dibuat BOLD & lebih besar
///   dari halaman admin biasa, sesuai permintaan user "Huruf harus agak
///   besar ... keterbacaan tinggi BOLD dan Besar untuk semua informasi".
///
/// 3 tab (sesuai permintaan user, urutan & isi SAMA):
///   1. Monitoring Resi -- `SupervisorResiTab`.
///   2. Monitoring Pemuatan & Penyelesaian (Manifest + Tanda Terima
///      Tujuan) -- `SupervisorLoadingTab`.
///   3. Monitoring Barang (per Zona) -- `SupervisorZoneTab`.
///
/// Kelengkapan informasi (12 poin permintaan user: siapa pengirim,
/// tanggal+jam terima, siapa menerima, apa barangnya, berapa jumlahnya,
/// kapan+siapa yang mengedit, kapan+siapa yang loading, mobil+sopir yang
/// loading, tanggal penyelesaian, apakah diselesaikan paksa+siapa)
/// SENGAJA dikumpulkan LENGKAP di kartu/detail tiap tab (bukan tersebar
/// perlu buka banyak halaman) -- lihat doc comment masing-masing widget
/// tab untuk field mana yang relevan di tab itu (Tab 3 "Monitoring
/// Barang" misalnya TIDAK punya field loading/penyelesaian karena barang
/// di tab itu, menurut definisinya, memang belum pernah dimuat).
class SupervisorDashboardPage extends ConsumerStatefulWidget {
  const SupervisorDashboardPage({super.key});

  @override
  ConsumerState<SupervisorDashboardPage> createState() =>
      _SupervisorDashboardPageState();
}

class _SupervisorDashboardPageState
    extends ConsumerState<SupervisorDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      builder: (context) => AlertDialog(
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
      ),
    );

    if (result == true) await _logout();
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);
    final roleAsync = ref.watch(currentRoleProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(employeeAsync, roleAsync),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  SupervisorResiTab(),
                  SupervisorLoadingTab(),
                  SupervisorZoneTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER (ala website -- identitas app + pegawai + logout)
  // ============================================================

  // FITUR (16 Oktober 2026 -- permintaan user "Logo ganti dengan logo
  // perusahaan"): logo bulat dari `companyProvider` (SAMA sumber dengan
  // kop semua cetakan PDF, lihat `PdfTemplates`), fallback ke ikon kalau
  // perusahaan belum punya logo / masih memuat / gagal load jaringan.
  Widget _buildLogo(String? logoUrl) {
    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: (logoUrl != null && logoUrl.isNotEmpty)
          ? Image.network(
              logoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.local_shipping_rounded,
                color: Colors.white,
                size: 26,
              ),
            )
          : const Icon(
              Icons.local_shipping_rounded,
              color: Colors.white,
              size: 26,
            ),
    );
  }

  Widget _buildHeader(
    AsyncValue<dynamic> employeeAsync,
    AsyncValue<dynamic> roleAsync,
  ) {
    final employeeName = employeeAsync.value?.fullName as String?;
    final roleName = roleAsync.value?.name as String? ?? 'Supervisor';
    final companyAsync = ref.watch(companyProvider);
    final logoUrl = companyAsync.value?.logoUrl as String?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: const BoxDecoration(
        color: AppColors.navy,
      ),
      child: Row(
        children: [
          _buildLogo(logoUrl),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // FITUR (16 Oktober 2026 -- "Judul Tebal dan Cantik"):
                // label kecil berwarna di atas judul utama, supaya ada
                // aksen warna & hierarki yang lebih "cantik" dibanding
                // 1 baris teks putih polos sebelumnya.
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TRANS • LIVE MONITORING',
                      style: TextStyle(
                        color: AppColors.lightBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'DASHBOARD SUPERVISOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 25,
                    letterSpacing: 0.4,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  color: AppColors.lightBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${employeeName ?? 'Memuat...'} • $roleName (Hanya Lihat)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: _showLogoutConfirmation,
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TAB BAR (besar, di bawah header, bukan di AppBar)
  // ============================================================

  // FITUR (16 Oktober 2026 -- "Berwarna warni antar data"): tiap tab
  // punya warna ikon sendiri (violet/orange/lightBlue -- SAMA dengan
  // warna aksen yang dipakai di kartu tab tsb, lihat `SupervisorAccentCard`
  // di masing-masing widget tab) supaya langsung terasa beda kategori
  // sejak di tab bar, bukan cuma pas sudah masuk ke dalam tab.
  static const _tabAccentColors = [
    AppColors.violet,
    AppColors.orange,
    AppColors.lightBlue,
  ];

  Widget _buildTabBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: AppColors.navy,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: const BoxDecoration(),
        indicatorColor: Colors.transparent,
        dividerColor: AppColors.border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        tabs: [
          for (var i = 0; i < 3; i++)
            Tab(
              height: 64,
              child: AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  final selected = _tabController.index == i;
                  final color = _tabAccentColors[i];
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? color.withOpacity(0.14) : null,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(
                        bottom: BorderSide(
                          color: selected ? color : Colors.transparent,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          [
                            Icons.receipt_long_rounded,
                            Icons.local_shipping_rounded,
                            Icons.warehouse_rounded,
                          ][i],
                          color: color,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          [
                            'Monitoring Resi',
                            'Monitoring Pemuatan & Penyelesaian',
                            'Monitoring Barang',
                          ][i],
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: selected ? AppColors.navy : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
