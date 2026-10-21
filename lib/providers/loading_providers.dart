import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shipment_model.dart';
import '../models/vehicle_model.dart';
import '../services/shipment_service.dart';
import '../services/vehicle_service.dart';

/// SEMUA kendaraan yang tidak dinonaktifkan (lihat doc comment
/// `VehicleService.getVehicles` -- **DIUBAH 10 Oktober 2026**, TIDAK
/// lagi digate oleh "sudah disiapkan admin"). Status "Dalam
/// Perjalanan"/"Siap Dimuat" dihitung live lewat
/// `activeShipmentForVehicleProvider`, bukan dari provider ini.
final vehiclesProvider = FutureProvider<List<VehicleModel>>((ref) {
  return VehicleService.getVehicles();
});

/// SEMUA kendaraan (termasuk yang dinonaktifkan) -- dipakai di halaman
/// "Siapkan Kendaraan"/"Pendataan Armada" dan ShipmentListPage.
final allVehiclesProvider = FutureProvider<List<VehicleModel>>((ref) {
  return VehicleService.getAllVehicles();
});

/// Shipment aktif (LOADING/DEPARTED) untuk satu kendaraan (kalau ada). Dipakai
/// di VehicleSelectPage untuk menampilkan badge "Lanjutkan Muat".
final activeShipmentForVehicleProvider =
    FutureProvider.family<ShipmentModel?, String>((ref, vehicleId) {
  return ShipmentService.getActiveShipmentForVehicle(vehicleId);
});

/// Feed scan (barang yang sudah naik) untuk satu shipment. Di-invalidate
/// tiap ada scan baru supaya tampilan di LoadingScanPage selalu live.
final shipmentScansProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getShipmentScanFeed(shipmentId);
  },
);

/// Semua shipment (riwayat loading), terbaru duluan -- dipakai di
/// ShipmentListPage supaya manifest bisa dibuka lagi kapan saja.
final shipmentsProvider = FutureProvider<List<ShipmentModel>>((ref) {
  return ShipmentService.getShipments();
});

/// Daftar SEMUA barang (berlabel QR maupun tidak) yang masih ada unit
/// fisik belum dimuat ke shipment manapun -- dipakai widget bersama
/// `ManualLoadChecklistView` (mode "Tanpa Label QR" di `LoadingScanPage`
/// DAN halaman admin "Loading Barang" `AdminManualLoadPage`).
///
/// SENGAJA plain `FutureProvider` (BUKAN family per shipmentId) -- daftar
/// ini GLOBAL, tidak di-scope ke shipment tertentu. Sempat
/// (6 Oktober 2026 pagi) jadi family yang di-scope per shipment, lalu
/// (7 Oktober 2026) terbukti scoping itu BUG (lihat doc comment panjang
/// `ShipmentService.getAvailableItemsForManualLoad`) dan dihapus total.
/// Diperluas lagi (7 Oktober 2026, permintaan user eksplisit) dari
/// sebelumnya cuma barang `is_unlabeled == true` jadi SEMUA barang --
/// scan QR saat loading tidak lagi wajib.
final availableManualLoadItemsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ShipmentService.getAvailableItemsForManualLoad();
});

/// Shipment yang masih berstatus LOADING (belum diberangkatkan) --
/// dipakai di halaman admin "Daftar Muatan" supaya Admin bisa lihat mobil
/// mana yang sedang dimuat dan memberangkatkannya.
final shipmentsLoadingProvider = FutureProvider<List<ShipmentModel>>((ref) async {
  final all = await ShipmentService.getShipments();
  return all.where((s) => s.status == 'LOADING').toList();
});

// ============================================================
// PEMBATALAN LOADING (ADMIN) -- 14 Oktober 2026
// ============================================================
//
// FITUR (permintaan user eksplisit): lihat doc comment panjang
// `ShipmentService.getManualLoadCancelItems` untuk detail penuh. Dipakai
// `ManualLoadCancelChecklistView` di tab "Batalkan Loading"
// `AdminManualLoadPage`.

/// Daftar resi yang SUDAH punya minimal 1 barang ter-LOAD ke 1 shipment
/// tertentu -- SENGAJA family per shipmentId (BEDA dari
/// [availableManualLoadItemsProvider] yang sengaja global), karena
/// pembatalan loading cuma relevan untuk resi yang memang sudah ada di
/// manifest shipment itu.
final receivingsLoadedOnShipmentProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, shipmentId) {
    return ShipmentService.getReceivingsLoadedOnShipment(shipmentId);
  },
);

/// Daftar SEMUA barang 1 resi, scoped ke 1 shipment -- dipakai langkah 2
/// `ManualLoadCancelChecklistView` setelah admin pilih resi dari
/// [receivingsLoadedOnShipmentProvider]. Key family: `(shipmentId,
/// receivingId)` digabung jadi 1 string (dipisah `::`) supaya tidak perlu
/// bikin class record/tuple baru cuma untuk key provider ini.
final manualLoadCancelItemsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, combinedKey) {
    final parts = combinedKey.split('::');
    return ShipmentService.getManualLoadCancelItems(
      shipmentId: parts[0],
      receivingId: parts[1],
    );
  },
);
