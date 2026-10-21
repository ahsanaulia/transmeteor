import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../providers/monitoring_providers.dart';

/// Monitoring Kinerja Perjalanan -- 3 tab: per shipment (detail), per
/// sopir (rekap), dan per kendaraan (rekap).
class TripPerformancePage extends StatelessWidget {
  const TripPerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Monitoring Kinerja Perjalanan'),
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          bottom: const TabBar(
            labelColor: AppColors.blue,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.blue,
            tabs: [
              Tab(text: 'Per Shipment'),
              Tab(text: 'Per Sopir'),
              Tab(text: 'Per Kendaraan'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ShipmentPerformanceTab(),
            _DriverPerformanceTab(),
            _VehiclePerformanceTab(),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(num? minutes) {
  if (minutes == null) return '-';
  final total = minutes.round();
  final hours = total ~/ 60;
  final mins = total % 60;
  if (hours <= 0) return '$mins menit';
  return '$hours jam $mins menit';
}

// ============================================================
// TAB 1: PER SHIPMENT
// ============================================================

class _ShipmentPerformanceTab extends ConsumerWidget {
  const _ShipmentPerformanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ShipmentPerformanceFilter.all;
    final shipmentsAsync = ref.watch(shipmentPerformanceListProvider(filter));

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: () async {
        ref.invalidate(shipmentPerformanceListProvider(filter));
        await ref.read(shipmentPerformanceListProvider(filter).future);
      },
      child: shipmentsAsync.when(
        data: (shipments) {
          if (shipments.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada perjalanan.', style: TextStyle(color: AppColors.textSecondary))),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: shipments.length,
            itemBuilder: (context, index) => _ShipmentPerformanceTile(data: shipments[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, _) => ErrorStateView(
          title: 'Gagal memuat kinerja perjalanan.',
          message: error.toString(),
          onRetry: () => ref.invalidate(shipmentPerformanceListProvider(filter)),
        ),
      ),
    );
  }
}

class _ShipmentPerformanceTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ShipmentPerformanceTile({required this.data});

  Color _statusColor(String? status) {
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

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String?;
    final color = _statusColor(status);
    final totalResi = data['totalResi'] as int;
    final deliveredResi = data['deliveredResi'] as int;
    final completedByAdmin = data['completedByAdmin'] as bool? ?? false;
    final tripStartedByAdmin = data['tripStartedByAdmin'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${data['shipmentNumber'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(status ?? '-', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${data['vehiclePlateNumber'] ?? '-'} • ${data['driverName'] ?? 'Belum ada sopir'}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          // Jejak audit: trip ini DIMULAI lewat "Intervensi Admin"
          // (ShipmentService.forceStartTripByAdmin), BUKAN sopir menekan
          // "Mulai Perjalanan" sendiri -- beda ujung dari completedByAdmin
          // di bawah (itu ujung akhir, ini ujung awal perjalanan).
          if (tripStartedByAdmin) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_rounded, size: 13, color: AppColors.blue),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    data['adminStartTripNote'] != null
                        ? 'Diberangkatkan Admin: ${data['adminStartTripNote']}'
                        : 'Diberangkatkan Admin',
                    style: const TextStyle(color: AppColors.blue, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
          // Jejak audit: shipment ini diselesaikan lewat "Intervensi Admin"
          // (ShipmentService.forceCompleteByAdmin), BUKAN sopir menekan
          // "Sudah Kembali ke Kantor" sendiri -- lihat catatannya juga
          // kalau admin sempat mengisi alasan.
          if (completedByAdmin) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_rounded, size: 13, color: AppColors.red),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    data['adminCompletionNote'] != null
                        ? 'Diselesaikan Admin: ${data['adminCompletionNote']}'
                        : 'Diselesaikan Admin',
                    style: const TextStyle(color: AppColors.red, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildStat('Durasi', _formatDuration(data['durationMinutes'] as int?), Icons.timer_outlined)),
              Expanded(child: _buildStat('Resi', '$deliveredResi/$totalResi', Icons.receipt_long_outlined)),
              Expanded(child: _buildStat('Biaya', formatRupiah(data['totalExpense'] as double), Icons.payments_outlined)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.navy)),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}

// ============================================================
// TAB 2: PER SOPIR
// ============================================================

class _DriverPerformanceTab extends ConsumerWidget {
  const _DriverPerformanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driversAsync = ref.watch(driverPerformanceSummaryProvider);

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: () async {
        ref.invalidate(driverPerformanceSummaryProvider);
        await ref.read(driverPerformanceSummaryProvider.future);
      },
      child: driversAsync.when(
        data: (drivers) {
          if (drivers.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada data sopir.', style: TextStyle(color: AppColors.textSecondary))),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: drivers.length,
            itemBuilder: (context, index) => _PerformanceSummaryTile(
              title: drivers[index]['driverName'] as String? ?? '-',
              icon: Icons.person_rounded,
              data: drivers[index],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, _) => ErrorStateView(
          title: 'Gagal memuat rekap sopir.',
          message: error.toString(),
          onRetry: () => ref.invalidate(driverPerformanceSummaryProvider),
        ),
      ),
    );
  }
}

// ============================================================
// TAB 3: PER KENDARAAN
// ============================================================

class _VehiclePerformanceTab extends ConsumerWidget {
  const _VehiclePerformanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(vehiclePerformanceSummaryProvider);

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: () async {
        ref.invalidate(vehiclePerformanceSummaryProvider);
        await ref.read(vehiclePerformanceSummaryProvider.future);
      },
      child: vehiclesAsync.when(
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada data kendaraan.', style: TextStyle(color: AppColors.textSecondary))),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: vehicles.length,
            itemBuilder: (context, index) => _PerformanceSummaryTile(
              title: vehicles[index]['vehiclePlateNumber'] as String? ?? '-',
              icon: Icons.local_shipping_rounded,
              data: vehicles[index],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, _) => ErrorStateView(
          title: 'Gagal memuat rekap kendaraan.',
          message: error.toString(),
          onRetry: () => ref.invalidate(vehiclePerformanceSummaryProvider),
        ),
      ),
    );
  }
}

class _PerformanceSummaryTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, dynamic> data;

  const _PerformanceSummaryTile({required this.title, required this.icon, required this.data});

  @override
  Widget build(BuildContext context) {
    final totalTrips = data['totalTrips'] as int;
    final completedTrips = data['completedTrips'] as int;
    final totalExpense = data['totalExpense'] as double;
    final avgDuration = data['avgDurationMinutes'] as double?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: AppColors.blue),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildStat('Perjalanan', '$completedTrips/$totalTrips selesai', Icons.local_shipping_outlined)),
              Expanded(child: _buildStat('Rata-rata Durasi', _formatDuration(avgDuration), Icons.timer_outlined)),
              Expanded(child: _buildStat('Total Biaya', formatRupiah(totalExpense), Icons.payments_outlined)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.navy)),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}