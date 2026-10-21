import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/monitoring_service.dart';
import '../services/shipment_service.dart';

/// Filter untuk shipmentPerformanceListProvider. Pakai
/// ShipmentPerformanceFilter.all untuk semua shipment tanpa filter.
class ShipmentPerformanceFilter {
  final String? vehicleId;
  final String? driverEmployeeId;

  const ShipmentPerformanceFilter({this.vehicleId, this.driverEmployeeId});

  static const ShipmentPerformanceFilter all = ShipmentPerformanceFilter();

  @override
  bool operator ==(Object other) {
    return other is ShipmentPerformanceFilter &&
        other.vehicleId == vehicleId &&
        other.driverEmployeeId == driverEmployeeId;
  }

  @override
  int get hashCode => Object.hash(vehicleId, driverEmployeeId);
}

/// Posisi lokasi terakhir semua kendaraan -- Monitoring Kendaraan & Sopir.
final fleetPositionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return MonitoringService.getFleetPositions();
});

/// Status pengiriman semua resi (lintas shipment) -- Monitoring Resi Sampai.
final resiDeliveryMonitoringProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return MonitoringService.getResiDeliveryMonitoring();
});

/// Event "dimuat" per shipment/kendaraan untuk SATU resi -- dipakai kotak
/// biru detail resi (`ReceivingDetailPage`, Monitoring Resi admin) untuk
/// menampilkan kapan dimuat, di kendaraan mana (bisa lebih dari satu
/// entri kalau resi terpecah ke beberapa kendaraan), dan kapan tiba kalau
/// shipment-nya sudah ARRIVED. Lihat doc comment
/// `MonitoringService.getLoadingEventsForReceiving`.
final resiLoadingEventsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, receivingId) {
  return MonitoringService.getLoadingEventsForReceiving(receivingId);
});

/// Progress loading/delivery (jumlah koli) PER RESI, TERMASUK resi yang
/// belum pernah disentuh Loading sama sekali -- dipakai badge status
/// "Penerimaan" / "Masih Perjalanan" / "Selesai" di `ReceivingListPage`
/// (Daftar Resi / Monitoring Resi), permintaan user (9 Oktober 2026).
/// Lihat doc comment `MonitoringService.getReceivingProgressSummary`.
final receivingProgressSummaryProvider =
    FutureProvider<Map<String, Map<String, dynamic>>>((ref) {
  return MonitoringService.getReceivingProgressSummary();
});

/// Versi SATU-RESI dari provider di atas (FITUR 16 Oktober 2026 --
/// lazy-load Monitoring Resi Supervisor, permintaan user "jangan ambil
/// sekaligus"): dipakai `_ResiCard` (`supervisor_resi_tab.dart`) HANYA
/// saat kartu resi di-expand -- field "Loading"/"Mobil & Sopir"/
/// "Tanggal Penyelesaian"/"Diselesaikan Paksa" baru di-fetch per-resi
/// saat itu, BUKAN diambil untuk semua resi yang tampil di layar
/// sekaligus seperti `receivingProgressSummaryProvider` di atas (yang
/// TETAP dipakai Admin `ReceivingListPage`, belum diubah). Lihat doc
/// comment `MonitoringService.getReceivingProgress`.
final receivingProgressProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, receivingId) {
  return MonitoringService.getReceivingProgress(receivingId);
});

/// Barang (receiving_details) yang sudah ditandai zona storage-nya TAPI
/// BELUM PERNAH dimuat/discan LOAD sama sekali -- dipakai
/// `StorageZoneMonitoringPage` (Monitoring Zona Storage, permintaan user
/// 9 Oktober 2026). Lihat doc comment
/// `MonitoringService.getUnloadedZoneItems` untuk detail filternya.
final unloadedZoneItemsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return MonitoringService.getUnloadedZoneItems();
});

/// Kinerja per shipment, dengan filter opsional per kendaraan/sopir.
final shipmentPerformanceListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, ShipmentPerformanceFilter>(
  (ref, filter) {
    return MonitoringService.getShipmentPerformanceList(
      vehicleId: filter.vehicleId,
      driverEmployeeId: filter.driverEmployeeId,
    );
  },
);

/// Rekap kinerja per sopir.
final driverPerformanceSummaryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return MonitoringService.getDriverPerformanceSummary();
});

/// Rekap kinerja per kendaraan.
final vehiclePerformanceSummaryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return MonitoringService.getVehiclePerformanceSummary();
});

/// Manifest shipment dikelompokkan PER TUJUAN (bukan per resi), lengkap
/// progress barang yang sudah turun -- dipakai FleetMonitoringPage untuk
/// dialog "Intervensi Admin: Selesaikan Per Tujuan" (lihat
/// `ShipmentService.getManifestGroupedByDestination` untuk detail
/// pengelompokannya, sama persis dengan PDF Tanda Terima Tujuan).
final shipmentManifestByDestinationProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getManifestGroupedByDestination(shipmentId);
  },
);