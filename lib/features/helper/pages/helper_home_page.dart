import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/driver_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/location_tracking_service.dart';
import '../../../services/shipment_service.dart';
import '../../auth/pages/login_page.dart';
import '../../driver/pages/delivery_manifest_page.dart';
import '../../loading/pages/manifest_page.dart';

class HelperHomePage extends ConsumerStatefulWidget {
  const HelperHomePage({super.key});

  @override
  ConsumerState<HelperHomePage> createState() => _HelperHomePageState();
}

class _HelperHomePageState extends ConsumerState<HelperHomePage> {
  Timer? _trackingTimer;
  DateTime? _lastPingAt;
  bool _isStarting = false;
  bool _isReturning = false;
  String? _trackingError;

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  void _resumeTrackingIfNeeded(ShipmentModel shipment, String employeeId) {
    if (_trackingTimer != null) return;
    if (shipment.tripStartedAt == null) return;
    if (shipment.status == 'ARRIVED') return;

    _startTrackingTimer(shipment.id, employeeId);
  }

  void _startTrackingTimer(String shipmentId, String employeeId) {
    _trackingTimer?.cancel();
    _sendPing(shipmentId, employeeId);

    _trackingTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _sendPing(shipmentId, employeeId);
    });
  }

  void _stopTrackingTimer() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  Future<void> _sendPing(String shipmentId, String employeeId) async {
    if (!mounted) return;

    final position = await LocationHelper.getCurrentPosition(context);
    if (position == null || !mounted) return;

    try {
      await LocationTrackingService.recordPing(
        shipmentId: shipmentId,
        employeeId: employeeId,
        roleAtPing: 'HELPER',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
      );

      if (mounted) setState(() => _lastPingAt = DateTime.now());
    } catch (_) {
      // Coba lagi di ping berikutnya.
    }
  }

  Future<void> _startTracking(ShipmentModel shipment, String employeeId) async {
    setState(() {
      _isStarting = true;
      _trackingError = null;
    });

    try {
      final position = await LocationHelper.getCurrentPosition(context);

      if (position == null) {
        setState(() => _isStarting = false);
        return;
      }

      _startTrackingTimer(shipment.id, employeeId);
    } catch (e) {
      setState(() => _trackingError = 'Gagal memulai tracking: $e');
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

      _stopTrackingTimer();
      ref.invalidate(activeShipmentForHelperProvider(employeeId));
      ref.invalidate(preparedVehicleForHelperProvider(employeeId));

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
  /// baru bisa logout setelah perjalanan ditandai selesai lewat "Sudah
  /// Kembali ke Kantor" (boleh driver atau helper yang menekannya).
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
    final shipmentAsync = ref.watch(activeShipmentForHelperProvider(employee.id));

    final currentShipment = shipmentAsync.value;
    final tripActive = currentShipment != null &&
        currentShipment.tripStartedAt != null &&
        currentShipment.status != 'ARRIVED';

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: () async {
        ref.invalidate(activeShipmentForHelperProvider(employee.id));
        ref.invalidate(preparedVehicleForHelperProvider(employee.id));
        await ref.read(activeShipmentForHelperProvider(employee.id).future);
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
                // Sama seperti DriverHomePage -- kalau shipment hilang dari
                // query aktif (mis. sudah ARRIVED), pastikan timer berhenti.
                _stopTrackingTimer();

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
              onRetry: () => ref.invalidate(activeShipmentForHelperProvider(employee.id)),
            ),
          ),
        ],
      ),
    );
  }

  /// Belum ada shipment aktif. Kalau ternyata Admin sudah menyiapkan
  /// kendaraan tertentu dengan employee ini sebagai helper, tampilkan
  /// kartu "sudah disiapkan, tinggal tunggu Loading" -- sama seperti
  /// DriverHomePage.
  Widget _buildNoShipmentState(EmployeeModel employee) {
    final preparedVehicleAsync = ref.watch(preparedVehicleForHelperProvider(employee.id));

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
                Icon(Icons.groups_outlined, size: 40, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text(
                  'Belum ada shipment yang mengikutsertakan Anda sebagai helper.',
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
            color: AppColors.green.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.green.withOpacity(0.20)),
          ),
          child: Column(
            children: [
              const Icon(Icons.local_shipping_rounded, size: 40, color: AppColors.green),
              const SizedBox(height: 12),
              Text(
                'Kendaraan ${vehicle.plateNumber} sudah disiapkan dengan Anda sebagai helper',
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
            Icon(Icons.groups_outlined, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'Belum ada shipment yang mengikutsertakan Anda sebagai helper.',
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
                colors: [AppColors.cyan, AppColors.green],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 29),
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
                    color: AppColors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Helper',
                    style: TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w800),
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
          colors: [Color(0xFF0F7B63), Color(0xFF13B9D6)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withOpacity(0.20),
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

  Widget _buildTrackingCard(ShipmentModel shipment, String employeeId) {
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
                _trackingTimer != null ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                color: _trackingTimer != null ? AppColors.green : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _trackingTimer != null
                      ? 'Tracking aktif -- lokasi terkirim tiap 15 menit sampai kembali ke kantor'
                      : 'Tracking belum dimulai di HP ini',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (_trackingTimer != null) ...[
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
          if (_trackingTimer == null) ...[
            const SizedBox(height: 14),
            PrimaryButton(
              label: 'Mulai Tracking',
              loadingLabel: 'Memulai...',
              isLoading: _isStarting,
              icon: Icons.play_arrow_rounded,
              backgroundColor: AppColors.green,
              onPressed: () => _startTracking(shipment, employeeId),
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
}