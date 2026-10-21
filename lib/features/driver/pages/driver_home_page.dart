import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/shipment_expense_model.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/driver_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/gps_foreground_service.dart';
import '../../../services/gps_tracking_task_handler.dart'
    show kGpsLastPingErrorKey, kGpsLastPingErrorAtKey;
import '../../../services/shipment_service.dart';
import '../../auth/pages/login_page.dart';
import '../../loading/pages/manifest_page.dart';
import '../widgets/expense_form_sheet.dart';
import 'delivery_manifest_page.dart';

class DriverHomePage extends ConsumerStatefulWidget {
  const DriverHomePage({super.key});

  @override
  ConsumerState<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends ConsumerState<DriverHomePage> {
  // Tracking GPS sekarang jalan lewat Android Foreground Service
  // (GpsForegroundService), BUKAN Timer.periodic biasa lagi -- lihat
  // penjelasan lengkap di lib/services/gps_tracking_task_handler.dart
  // soal kenapa (Timer.periodic dibunuh Android begitu app di-minimize/
  // layar dikunci, itu akar masalah GPS baru update sampai 12 jam dari
  // hasil uji coba lapangan).
  bool _trackingActive = false;
  DateTime? _lastPingAt;
  bool _isStarting = false;
  bool _isReturning = false;
  String? _trackingError;

  // Error PENGIRIMAN PING terakhir (beda dari _trackingError yang khusus
  // buat error saat menekan "Mulai Perjalanan"). Ditemukan kasus nyata:
  // tracking kelihatan "aktif" tapi tidak ada titik lokasi yang sampai ke
  // server -- sebelumnya errornya ditelan diam-diam di
  // GpsTrackingTaskHandler._sendPing, jadi sopir/admin tidak pernah tahu
  // kenapa. Dibaca dari data persisten (saveData) supaya tetap kelihatan
  // walau error terjadi selagi halaman ini tidak dibuka, PLUS didengar
  // real-time lewat _onTrackingData selama halaman ini dibuka.
  String? _lastPingError;
  DateTime? _lastPingErrorAt;

  @override
  void initState() {
    super.initState();
    GpsForegroundService.init();
    // Terima update "ping baru saja terkirim/gagal" dari isolate
    // background (GpsTrackingTaskHandler) supaya kartu tracking di
    // halaman ini bisa update jam "Titik terakhir dikirim pukul ..." (atau
    // pesan error) real-time selama app dibuka -- lihat
    // GpsTrackingTaskHandler._sendPing.
    FlutterForegroundTask.addTaskDataCallback(_onTrackingData);
    _loadPersistedPingError();
  }

  // Baca error ping terakhir yang tersimpan (kalau ada) -- penting karena
  // error paling sering terjadi selagi app diminimize/layar terkunci
  // (justru itu tujuan foreground service), jadi _onTrackingData (yang
  // cuma nangkap event SELAGI halaman ini terbuka) sendirian tidak cukup.
  Future<void> _loadPersistedPingError() async {
    final error =
        await FlutterForegroundTask.getData<String>(key: kGpsLastPingErrorKey);
    final errorAtMillis =
        await FlutterForegroundTask.getData<int>(key: kGpsLastPingErrorAtKey);
    if (!mounted || error == null) return;
    setState(() {
      _lastPingError = error;
      _lastPingErrorAt =
          errorAtMillis != null ? DateTime.fromMillisecondsSinceEpoch(errorAtMillis) : null;
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTrackingData);
    super.dispose();
  }

  void _onTrackingData(Object data) {
    if (!mounted) return;
    if (data is! Map) return;

    if (data['type'] == 'ping_sent') {
      final millis = data['timestampMillis'];
      if (millis is int) {
        setState(() {
          _lastPingAt = DateTime.fromMillisecondsSinceEpoch(millis);
          // Ping barusan berhasil -- bersihkan error lama kalau ada.
          _lastPingError = null;
          _lastPingErrorAt = null;
        });
      }
    } else if (data['type'] == 'ping_failed') {
      final millis = data['timestampMillis'];
      setState(() {
        _lastPingError = data['error']?.toString() ?? 'Tidak diketahui';
        _lastPingErrorAt =
            millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : DateTime.now();
      });
    }
  }

  // ============================================================
  // TRACKING
  // ============================================================

  void _resumeTrackingIfNeeded(ShipmentModel shipment, String employeeId) {
    if (_trackingActive) return;
    if (shipment.tripStartedAt == null) return;
    if (shipment.status == 'ARRIVED') return;

    _trackingActive = true; // set duluan, cegah _resumeTrackingIfNeeded
    // dipanggil berkali-kali sebelum GpsForegroundService.start selesai
    // (dipanggil dari dalam build() tiap kali data shipment berubah).
    GpsForegroundService.start(shipmentId: shipment.id, employeeId: employeeId);
  }

  Future<void> _stopTracking() async {
    _trackingActive = false;
    await GpsForegroundService.stop();
  }

  Future<void> _startTrip(ShipmentModel shipment, String employeeId) async {
    setState(() {
      _isStarting = true;
      _trackingError = null;
    });

    try {
      final position = await LocationHelper.getCurrentPosition(context);

      if (position == null) {
        setState(() {
          _isStarting = false;
          _trackingError =
              'Tidak bisa mengambil lokasi. Pastikan GPS aktif & coba lagi.';
        });
        return;
      }

      // Minta izin lokasi "selalu"/background + izin notifikasi &
      // pengecualian battery optimization -- semua ini perlu supaya
      // Foreground Service tracking bisa jalan mulus tanpa dibekukan
      // Android di tengah perjalanan. Kalau izin background ditolak,
      // tracking tetap dimulai (fallback: hanya jalan selagi app
      // dibuka) -- LocationHelper sudah kasih tahu risikonya ke driver.
      if (mounted) {
        await LocationHelper.requestBackgroundLocationPermission(context);
      }
      await GpsForegroundService.requestPermissions();

      await ShipmentService.startTrip(shipmentId: shipment.id);
      ref.invalidate(activeShipmentForDriverProvider(employeeId));

      _trackingActive = true;
      await GpsForegroundService.start(
        shipmentId: shipment.id,
        employeeId: employeeId,
      );
    } catch (e) {
      setState(() => _trackingError = 'Gagal memulai perjalanan: $e');
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  // ============================================================
  // KEMBALI KE KANTOR (mengakhiri perjalanan & tracking)
  // ============================================================

  Future<void> _confirmReturnToOffice(ShipmentModel shipment, String employeeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sudah Kembali ke Kantor?'),
        content: const Text(
          'Perjalanan akan ditandai selesai dan tracking lokasi akan dihentikan. '
          'Pastikan semua resi tujuan sudah diturunkan dan kendaraan benar-benar '
          'sudah sampai kembali di kantor pusat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, Sudah Sampai'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isReturning = true);

    try {
      await ShipmentService.returnToOffice(shipmentId: shipment.id);

      await _stopTracking();
      ref.invalidate(activeShipmentForDriverProvider(employeeId));
      ref.invalidate(preparedVehicleForDriverProvider(employeeId));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perjalanan selesai. Tracking lokasi dihentikan.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menandai kembali ke kantor: $e')),
      );
    } finally {
      if (mounted) setState(() => _isReturning = false);
    }
  }

  // ============================================================
  // EXPENSE
  // ============================================================

  Future<void> _openExpenseForm(ShipmentModel shipment, String employeeId) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExpenseFormSheet(
        shipmentId: shipment.id,
        employeeId: employeeId,
      ),
    );

    if (saved == true) {
      ref.invalidate(shipmentExpensesProvider(shipment.id));
    }
  }

  // ============================================================
  // SESSION / LOGOUT
  // ============================================================

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal logout: $e')),
      );
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

    if (result == true) await _logout();
  }

  /// Logout diblokir selama perjalanan (pergi & pulang) masih aktif --
  /// baru bisa logout setelah driver menekan "Sudah Kembali ke Kantor".
  Future<void> _showLogoutBlockedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tidak Bisa Logout'),
        content: const Text(
          'Anda sedang dalam perjalanan mengantar barang (pergi/pulang). '
          'Logout tidak diperbolehkan sampai perjalanan ditandai selesai lewat '
          'tombol "Sudah Kembali ke Kantor".',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: employeeAsync.when(
          data: (employee) {
            if (employee == null) {
              return const ErrorStateView(
                title: 'Data employee untuk akun ini tidak ditemukan.',
              );
            }

            return _buildBody(employee);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.blue),
          ),
          error: (error, _) => ErrorStateView(
            title: 'Data pengguna tidak dapat dimuat.',
            message: error.toString(),
            onRetry: () => ref.invalidate(currentEmployeeProvider),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(EmployeeModel employee) {
    final shipmentAsync = ref.watch(activeShipmentForDriverProvider(employee.id));

    final currentShipment = shipmentAsync.value;
    final tripActive = currentShipment != null &&
        currentShipment.tripStartedAt != null &&
        currentShipment.status != 'ARRIVED';

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: () async {
        ref.invalidate(activeShipmentForDriverProvider(employee.id));
        ref.invalidate(preparedVehicleForDriverProvider(employee.id));
        await ref.read(activeShipmentForDriverProvider(employee.id).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildHeader(employee, tripActive),
          const SizedBox(height: 18),
          shipmentAsync.when(
            data: (shipment) {
              if (shipment == null) {
                // Shipment sudah ARRIVED (hilang dari query aktif) atau
                // memang belum ada -- pastikan foreground service tracking
                // ikut berhenti, jangan sampai jalan terus tanpa shipment.
                if (_trackingActive) _stopTracking();

                return _buildNoShipmentState(employee);
              }

              _resumeTrackingIfNeeded(shipment, employee.id);

              return _buildShipmentSection(shipment, employee.id);
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: AppColors.blue)),
            ),
            error: (error, _) => ErrorStateView(
              title: 'Gagal memuat shipment.',
              message: error.toString(),
              onRetry: () => ref.invalidate(activeShipmentForDriverProvider(employee.id)),
            ),
          ),
        ],
      ),
    );
  }

  /// Belum ada shipment aktif. Kalau ternyata Admin sudah menyiapkan
  /// kendaraan tertentu untuk driver ini, tampilkan kartu "sudah
  /// disiapkan, tinggal tunggu Loading" -- supaya driver tahu statusnya,
  /// bukan cuma layar kosong tanpa keterangan.
  Widget _buildNoShipmentState(EmployeeModel employee) {
    final preparedVehicleAsync = ref.watch(preparedVehicleForDriverProvider(employee.id));

    return preparedVehicleAsync.when(
      data: (vehicle) {
        if (vehicle == null) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(Icons.local_shipping_outlined, size: 40, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text(
                  'Belum ada kendaraan yang disiapkan admin untuk Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.blue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.blue.withOpacity(0.20)),
          ),
          child: Column(
            children: [
              const Icon(Icons.local_shipping_rounded, size: 40, color: AppColors.blue),
              const SizedBox(height: 12),
              Text(
                'Kendaraan ${vehicle.plateNumber} sudah disiapkan untuk Anda',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tinggal menunggu bagian Loading mulai memuat barang. '
                'Manifest akan muncul di sini otomatis setelah muat dimulai.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          children: [
            Icon(Icons.local_shipping_outlined, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'Belum ada shipment yang ditugaskan ke Anda sebagai sopir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(EmployeeModel employee, bool tripActive) {
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.orange, AppColors.pink],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 29),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TRANS',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy),
                ),
                const SizedBox(height: 2),
                Text(
                  employee.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Sopir',
                    style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: tripActive ? _showLogoutBlockedDialog : _showLogoutConfirmation,
            icon: Icon(
              tripActive ? Icons.lock_outline_rounded : Icons.logout_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentSection(ShipmentModel shipment, String employeeId) {
    final vehicleAsync = ref.watch(vehicleByIdProvider(shipment.vehicleId));
    final tripActive = shipment.tripStartedAt != null && shipment.status != 'ARRIVED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        vehicleAsync.when(
          data: (vehicle) => _buildShipmentCard(shipment, vehicle),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Gagal memuat data kendaraan: $error'),
        ),
        const SizedBox(height: 16),
        _buildTrackingCard(shipment, employeeId),
        const SizedBox(height: 16),
        const Text(
          'Rute Tujuan',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary, fontSize: 15),
        ),
        const SizedBox(height: 8),
        _buildRouteMap(shipment),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final vehicle = vehicleAsync.value;
            if (vehicle == null) return;

            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ManifestPage(shipment: shipment, vehicle: vehicle),
              ),
            );
          },
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Lihat Manifest'),
        ),
        if (tripActive) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.green,
              side: const BorderSide(color: AppColors.green),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeliveryManifestPage(shipment: shipment),
                ),
              );
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Barang Sampai (Scan Turun)'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              onPressed: _isReturning ? null : () => _confirmReturnToOffice(shipment, employeeId),
              icon: _isReturning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.home_rounded),
              label: Text(_isReturning ? 'Menyimpan...' : 'Sudah Kembali ke Kantor'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildExpenseSection(shipment, employeeId),
      ],
    );
  }

  Widget _buildShipmentCard(ShipmentModel shipment, VehicleModel? vehicle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172B67), Color(0xFF2469D8)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.20),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shipment.shipmentNumber,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            vehicle != null
                ? '${vehicle.plateNumber}${vehicle.vehicleType != null ? ' • ${vehicle.vehicleType}' : ''}'
                : 'Memuat data kendaraan...',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              shipment.status,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  /// Format detik jadi label Indonesia yang gampang dibaca -- dipakai
  /// supaya kartu tracking tidak lagi hardcode "15 menit" (sekarang
  /// interval-nya bisa diatur admin lewat halaman "Profil Perusahaan",
  /// termasuk diisi angka detik kecil untuk uji coba).
  String _formatIntervalLabel(int seconds) {
    if (seconds < 60) return '$seconds detik';

    final minutes = seconds ~/ 60;
    final remainderSeconds = seconds % 60;

    if (remainderSeconds == 0) return '$minutes menit';

    return '$minutes menit $remainderSeconds detik';
  }

  Widget _buildTrackingCard(ShipmentModel shipment, String employeeId) {
    final isStarted = shipment.tripStartedAt != null;

    // Interval kirim lokasi sekarang dibaca dari company.
    // gps_ping_interval_seconds (bisa diatur admin), bukan angka tetap
    // "15 menit" lagi -- lihat GpsForegroundService & CompanyModel.
    final companyAsync = ref.watch(companyProvider);
    final intervalLabel =
        _formatIntervalLabel(companyAsync.value?.gpsPingIntervalSeconds ?? 900);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isStarted ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                color: isStarted ? AppColors.green : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isStarted
                      ? 'Tracking aktif -- lokasi terkirim tiap $intervalLabel, tetap jalan walau aplikasi diminimize/layar terkunci'
                      : 'Tracking belum dimulai',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (isStarted) ...[
            const SizedBox(height: 6),
            Text(
              _lastPingAt != null
                  ? 'Titik terakhir dikirim pukul ${_lastPingAt!.hour.toString().padLeft(2, '0')}:${_lastPingAt!.minute.toString().padLeft(2, '0')}'
                  : 'Menunggu titik pertama dikirim...',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          if (_trackingError != null) ...[
            const SizedBox(height: 8),
            Text(_trackingError!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
          // Error PENGIRIMAN PING (beda dari _trackingError di atas) --
          // ini yang muncul kalau tracking "aktif" tapi titik lokasi
          // gagal terus sampai ke server (izin lokasi dicabut Android,
          // RLS Supabase menolak, tidak ada internet, dll). Ditampilkan
          // MENCOLOK karena sebelumnya error jenis ini tidak pernah
          // kelihatan sama sekali (ditelan diam-diam).
          if (isStarted && _lastPingError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lastPingErrorAt != null
                              ? 'Pengiriman lokasi gagal (pukul ${_lastPingErrorAt!.hour.toString().padLeft(2, '0')}:${_lastPingErrorAt!.minute.toString().padLeft(2, '0')}):'
                              : 'Pengiriman lokasi gagal:',
                          style: const TextStyle(
                            color: AppColors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lastPingError!,
                          style: const TextStyle(color: AppColors.red, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isStarted) ...[
            const SizedBox(height: 14),
            PrimaryButton(
              label: 'Mulai Perjalanan',
              loadingLabel: 'Mengambil lokasi...',
              isLoading: _isStarting,
              icon: Icons.play_arrow_rounded,
              onPressed: () => _startTrip(shipment, employeeId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteMap(ShipmentModel shipment) {
    final pointsAsync = ref.watch(shipmentDestinationPointsProvider(shipment.id));

    return pointsAsync.when(
      data: (points) => RouteMapCard(points: points),
      loading: () => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
      error: (error, _) => Text('Gagal memuat rute: $error'),
    );
  }

  Widget _buildExpenseSection(ShipmentModel shipment, String employeeId) {
    final expensesAsync = ref.watch(shipmentExpensesProvider(shipment.id));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Laporan Pengeluaran',
                  style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openExpenseForm(shipment, employeeId),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah'),
              ),
            ],
          ),
          expensesAsync.when(
            data: (expenses) {
              if (expenses.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada laporan pengeluaran.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                );
              }

              return Column(
                children: expenses.map((expense) => _ExpenseTile(expense: expense)).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text('Gagal memuat pengeluaran: $error'),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final ShipmentExpenseModel expense;

  const _ExpenseTile({required this.expense});

  String _typeLabel(String code) {
    switch (code) {
      case 'BBM':
        return 'BBM';
      case 'PENGINAPAN':
        return 'Penginapan';
      case 'MAKAN':
        return 'Makan';
      default:
        return code;
    }
  }

  IconData _typeIcon(String code) {
    switch (code) {
      case 'BBM':
        return Icons.local_gas_station_rounded;
      case 'PENGINAPAN':
        return Icons.hotel_rounded;
      case 'MAKAN':
        return Icons.restaurant_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(expense.expenseType), size: 18, color: AppColors.blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel(expense.expenseType),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (expense.notes != null)
                  Text(
                    expense.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          Text(
            formatRupiah(expense.amount),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
