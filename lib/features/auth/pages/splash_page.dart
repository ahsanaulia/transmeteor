import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/session_provider.dart';
import '../../../services/auth_service.dart';
import '../../receiving/pages/receiving_home_page.dart';
import '../../loading/pages/loading_home_page.dart';
import '../../dashboard/pages/dashboard_home_page.dart';
import '../../driver/pages/driver_home_page.dart';
import '../../supervisor/pages/supervisor_dashboard_page.dart';
import 'login_page.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _routeUser();
  }

  Future<void> _routeUser() async {
    await Future.delayed(
      const Duration(milliseconds: 500),
    );

    if (!mounted) return;

    // ============================================================
    // AUTH CHECK
    // ============================================================

    if (!AuthService.isLoggedIn) {
      _goToLogin();
      return;
    }

    try {
      // ============================================================
      // CURRENT EMPLOYEE & ROLE
      //
      // Diambil lewat provider (session_provider.dart) supaya hasilnya
      // di-cache dan tidak perlu di-fetch ulang oleh halaman lain
      // (mis. ReceivingHomePage) yang juga butuh data ini.
      // ============================================================

      final employee = await ref.read(currentEmployeeProvider.future);

      if (employee == null) {
        await AuthService.signOut();
        invalidateSession(ref);

        if (!mounted) return;

        _goToLogin();
        return;
      }

      // Pegawai yang dinonaktifkan admin (lewat "Kelola Pegawai") tidak
      // boleh lanjut masuk -- bukan gate baru, ini pelengkap tombol
      // nonaktifkan supaya benar-benar berefek (kalau tidak dicek di
      // sini, pegawai yang dinonaktifkan tetap bisa pakai aplikasi
      // selama sesi login-nya belum habis).
      if (!employee.isActive) {
        await AuthService.signOut();
        invalidateSession(ref);

        if (!mounted) return;

        throw Exception(
          'Akun Anda sudah dinonaktifkan. Hubungi admin jika ini keliru.',
        );
      }

      final role = await ref.read(currentRoleProvider.future);

      if (role == null) {
        throw Exception(
          'Role employee tidak ditemukan.',
        );
      }

      if (!role.isActive) {
        throw Exception(
          'Role employee tidak aktif.',
        );
      }

      // ============================================================
      // ROLE ROUTER
      // ============================================================

      switch (role.code.toUpperCase()) {
        case 'RECEIVING':
          _goToReceiving();
          return;

        case 'LOADING':
          _goToLoading();
          return;

        case 'DRIVER':
          _goToDriver();
          return;

        case 'HELPER':
          // Helper sekarang hanya data (dipilih admin saat "Siapkan
          // Kendaraan" sebagai helper1/2/3 di kendaraan), BUKAN pengguna
          // aplikasi -- tidak boleh login & pakai fitur operasional apa
          // pun. Akun lama yang kadung terdaftar sebagai Helper (dari
          // sebelum perubahan ini) diblokir login-nya di sini, bukan
          // dihapus datanya.
          await AuthService.signOut();
          invalidateSession(ref);

          if (!mounted) return;

          _showRoleNotAvailable(
            'Akun dengan role Helper tidak bisa login ke aplikasi. '
            'Helper hanya data pendamping kendaraan, ditentukan admin '
            'saat menyiapkan kendaraan.',
          );
          return;

        case 'ADMIN':
          _goToDashboard();
          return;

        // FITUR (16 Oktober 2026, permintaan user eksplisit): "Supervisor"
        // SEKARANG punya dashboard SENDIRI (khusus monitoring, tanpa
        // kemampuan edit apa pun) -- BUKAN lagi `DashboardHomePage` admin
        // biasa seperti sebelumnya. Lihat doc comment
        // `SupervisorDashboardPage` untuk detail.
        case 'SUPERVISOR':
          _goToSupervisor();
          return;

        default:
          _showRoleNotAvailable(
            'Halaman untuk role ${role.name} belum tersedia.',
          );
          return;
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        e.toString(),
      );
    }
  }

  // ============================================================
  // ROUTES
  // ============================================================

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
    );
  }

  void _goToReceiving() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ReceivingHomePage(),
      ),
    );
  }

  void _goToLoading() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoadingHomePage(),
      ),
    );
  }

  void _goToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const DashboardHomePage(),
      ),
    );
  }

  void _goToDriver() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const DriverHomePage(),
      ),
    );
  }

  void _goToSupervisor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const SupervisorDashboardPage(),
      ),
    );
  }

  // ============================================================
  // ERROR / UNAVAILABLE ROLE
  // ============================================================

  void _showRoleNotAvailable(String message) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _RouterMessagePage(
          title: 'Role Belum Tersedia',
          message: message,
        ),
      ),
    );
  }

  void _showError(String message) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _RouterMessagePage(
          title: 'Tidak Dapat Membuka Aplikasi',
          message: message,
          showRetry: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

// ================================================================
// ROUTER MESSAGE PAGE
// ================================================================

class _RouterMessagePage extends StatelessWidget {
  final String title;
  final String message;
  final bool showRetry;

  const _RouterMessagePage({
    required this.title,
    required this.message,
    this.showRetry = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 56,
                ),

                const SizedBox(height: 20),

                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  message,
                  textAlign: TextAlign.center,
                ),

                if (showRetry) ...[
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const SplashPage(),
                        ),
                      );
                    },
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}