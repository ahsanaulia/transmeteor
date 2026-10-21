import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shipment_expense_model.dart';
import '../models/shipment_model.dart';
import '../models/vehicle_model.dart';
import '../services/expense_service.dart';
import '../services/shipment_service.dart';
import '../services/vehicle_service.dart';

/// Shipment aktif (LOADING/DEPARTED) untuk driver yang sedang login.
final activeShipmentForDriverProvider =
    FutureProvider.family<ShipmentModel?, String>((ref, employeeId) {
  return ShipmentService.getActiveShipmentForDriver(employeeId);
});

/// Shipment aktif untuk helper yang sedang login.
final activeShipmentForHelperProvider =
    FutureProvider.family<ShipmentModel?, String>((ref, employeeId) {
  return ShipmentService.getActiveShipmentForHelper(employeeId);
});

/// Kendaraan yang sudah disiapkan Admin untuk driver ini TAPI belum ada
/// shipment aktif -- dipakai DriverHomePage untuk kartu "Mobil sudah
/// disiapkan, tunggu Loading mulai muat" saat activeShipmentForDriver
/// masih null.
final preparedVehicleForDriverProvider =
    FutureProvider.family<VehicleModel?, String>((ref, employeeId) {
  return VehicleService.getPreparedVehicleForDriver(employeeId);
});

/// Sama seperti preparedVehicleForDriverProvider tapi untuk helper.
final preparedVehicleForHelperProvider =
    FutureProvider.family<VehicleModel?, String>((ref, employeeId) {
  return VehicleService.getPreparedVehicleForHelper(employeeId);
});

/// Detail kendaraan satu shipment -- dipakai buat nampilin plat nomor dkk
/// di DriverHomePage/HelperHomePage.
final vehicleByIdProvider =
    FutureProvider.family<VehicleModel?, String>((ref, vehicleId) {
  return VehicleService.getVehicleById(vehicleId);
});

/// Titik-titik tujuan manifest satu shipment -- buat peta rute.
final shipmentDestinationPointsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getShipmentDestinationPoints(shipmentId);
  },
);

/// Daftar pengeluaran satu shipment.
final shipmentExpensesProvider =
    FutureProvider.family<List<ShipmentExpenseModel>, String>(
  (ref, shipmentId) {
    return ExpenseService.getExpensesForShipment(shipmentId);
  },
);

/// Manifest shipment dikelompokkan per resi, lengkap progress barang
/// yang sudah turun -- dipakai di DeliveryManifestPage.
final shipmentManifestByReceivingProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getManifestGroupedByReceiving(shipmentId);
  },
);

/// Feed scan turun (DELIVER) satu shipment -- dipakai di
/// DeliveryResiScanPage (difilter per resi di widget-nya).
final shipmentDeliverScansProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getShipmentScanFeed(shipmentId, scanType: 'DELIVER');
  },
);

/// Barang yang sudah dimuat di shipment ini tapi belum turun, untuk SATU
/// resi -- dipakai checklist manual "Tanpa Label QR" di
/// DeliveryResiScanPage. Key-nya record (shipmentId, receivingId) karena
/// butuh 2 parameter.
///
/// **DIPERLUAS (10 Oktober 2026, permintaan user: "Penyelesaian barang
/// tanpa Label harus bisa menyelesaikan barang yang berlabel juga, ini
/// antisipasi jika camera sopir rusak atau label rusak")** -- SEBELUMNYA
/// hanya barang bertanda "Tanpa Label QR" (is_unlabeled) yang muncul di
/// sini. Sekarang SEMUA barang yang sudah LOAD tapi belum DELIVER muncul
/// (baik berlabel maupun tanpa label), lewat
/// `ShipmentService.getAvailableItemsForManualDeliver` -- nama provider
/// dipertahankan (tidak di-rename) supaya tidak perlu ubah semua
/// pemanggil lama, tapi perilakunya sudah berubah sesuai nama method
/// barunya.
final unlabeledItemsToDeliverProvider = FutureProvider.family<
    List<Map<String, dynamic>>, ({String shipmentId, String receivingId})>(
  (ref, params) {
    return ShipmentService.getAvailableItemsForManualDeliver(
      shipmentId: params.shipmentId,
      receivingId: params.receivingId,
    );
  },
);

/// Manifest shipment dikelompokkan per resi, progress dihitung per UNIT
/// FISIK (akurat sampai unit) -- dipakai KHUSUS mode "Per Resi" di
/// `RepresentativeHandoffPage` (fitur "Selesaikan di Perwakilan"). Lihat
/// doc comment panjang di
/// `ShipmentService.getHandoffCandidatesByReceiving` soal kenapa ini
/// method terpisah dari [shipmentManifestByReceivingProvider].
final handoffCandidatesByReceivingProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getHandoffCandidatesByReceiving(shipmentId);
  },
);
