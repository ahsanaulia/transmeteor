import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../providers/dashboard_providers.dart';
import '../providers/driver_providers.dart';
import '../providers/loading_providers.dart';
import '../providers/master_data_providers.dart';
import '../providers/monitoring_providers.dart';
import '../providers/receiving_detail_providers.dart';
import '../providers/session_provider.dart';

/// Sinkronisasi REALTIME app-wide -- dengarkan perubahan (insert/update/
/// delete) di tabel-tabel Supabase lewat Postgres Changes, lalu otomatis
/// `ref.invalidate()` provider Riverpod yang datanya berasal dari tabel
/// itu.
///
/// KENAPA ARSITEKTURNYA BEGINI (dengar tabel mentah -> invalidate provider,
/// BUKAN ubah tiap provider jadi `.stream()` langsung ke Supabase):
/// Banyak provider di app ini (fleetPositionsProvider,
/// resiDeliveryMonitoringProvider, getShipmentPerformanceList, dst) hasil
/// dari QUERY GABUNGAN/AGREGASI lintas beberapa tabel (join manual di
/// Dart, bukan SQL view) -- Supabase `.stream()` HANYA bisa untuk 1 tabel
/// polos, tidak bisa dipakai langsung untuk query seperti itu. Solusi yang
/// aman & tidak perlu menulis ulang semua service query yang sudah teruji:
/// tetap pakai FutureProvider yang sudah ada apa adanya, tapi otomatis
/// panggil `ref.invalidate()` begitu ada perubahan di tabel manapun yang
/// jadi sumber datanya -- Riverpod otomatis fetch ulang & UI ikut ter-
/// update tanpa user perlu pull-to-refresh manual.
///
/// Berlaku di semua platform (Android & web) karena Supabase Realtime
/// jalan lewat WebSocket, bukan platform channel native.
class RealtimeSyncService {
  RealtimeSyncService(this._ref);

  final Ref _ref;
  final List<RealtimeChannel> _channels = [];
  final Map<String, Timer> _debounceTimers = {};

  static SupabaseClient get _client => SupabaseService.client;

  void start() {
    // employees -- daftar pegawai, picker sopir/helper, siapa yang login.
    _listen('employees', [
      currentEmployeeProvider,
      allEmployeesProvider,
      driverEmployeesProvider,
      helperEmployeesProvider,
      fleetPositionsProvider,
      driverPerformanceSummaryProvider,
      vehiclePerformanceSummaryProvider,
    ]);

    // employee_roles -- jarang berubah, tapi tetap disinkronkan.
    _listen('employee_roles', [
      employeeRolesProvider,
      currentRoleProvider,
    ]);

    // company -- profil perusahaan, termasuk interval GPS.
    _listen('company', [companyProvider]);

    // vehicles -- daftar kendaraan, kendaraan siap pakai, posisi armada.
    _listen('vehicles', [
      vehiclesProvider,
      allVehiclesProvider,
      preparedVehicleForDriverProvider,
      preparedVehicleForHelperProvider,
      vehicleByIdProvider,
      activeShipmentForHelperProvider,
      fleetPositionsProvider,
      vehiclePerformanceSummaryProvider,
    ]);

    // shipments -- status LOADING/DEPARTED/ARRIVED, penugasan sopir, dsb.
    _listen('shipments', [
      shipmentsProvider,
      shipmentsLoadingProvider,
      activeShipmentForDriverProvider,
      activeShipmentForHelperProvider,
      activeShipmentForVehicleProvider,
      fleetPositionsProvider,
      resiDeliveryMonitoringProvider,
      shipmentPerformanceListProvider,
      driverPerformanceSummaryProvider,
      vehiclePerformanceSummaryProvider,
      dashboardSummaryProvider,
    ]);

    // shipment_scans -- tiap scan naik/turun barang (LOAD/DELIVER),
    // termasuk handoff "Selesaikan di Perwakilan" (representative_id
    // terisi, lihat RepresentativeHandoffPage) -- SAMA tabelnya, jadi
    // ikut provider manifest yang sama supaya progress "berapa barang
    // yang masih pending" langsung update di semua tab/HP begitu ada
    // scan/handoff baru.
    _listen('shipment_scans', [
      shipmentScansProvider,
      shipmentDeliverScansProvider,
      shipmentManifestByReceivingProvider,
      handoffCandidatesByReceivingProvider,
      shipmentManifestByDestinationProvider,
      shipmentDestinationPointsProvider,
      resiDeliveryMonitoringProvider,
      shipmentPerformanceListProvider,
      driverPerformanceSummaryProvider,
      vehiclePerformanceSummaryProvider,
      // receivingProgressSummaryProvider (status Penerimaan/Masih
      // Perjalanan/Selesai di Monitoring Resi) & unloadedZoneItemsProvider
      // (Monitoring Zona Storage) SAMA-SAMA dihitung dari baris scan LOAD/
      // DELIVER -- WAJIB ikut tersinkron di sini juga (SEBELUMNYA
      // receivingProgressSummaryProvider terlewat waktu fiturnya dibuat,
      // 9 Oktober 2026 -- ditambahkan sekaligus saat menambah
      // unloadedZoneItemsProvider).
      receivingProgressSummaryProvider,
      unloadedZoneItemsProvider,
    ]);

    // shipment_expenses -- laporan pengeluaran sopir (BBM, makan, dst).
    _listen('shipment_expenses', [
      shipmentExpensesProvider,
      shipmentPerformanceListProvider,
      driverPerformanceSummaryProvider,
      vehiclePerformanceSummaryProvider,
    ]);

    // shipment_location_pings -- titik GPS masuk tiap interval tracking.
    _listen('shipment_location_pings', [fleetPositionsProvider]);

    // receiving + receiving_details -- data resi & barang.
    _listen('receiving', [
      allReceivingsProvider,
      dashboardSummaryProvider,
      weeklyReceivingTrendProvider,
      resiDeliveryMonitoringProvider,
      // Nomor resi/nomor buku/tanggal terima/tujuan/alamat yang
      // ditampilkan di Monitoring Zona Storage berasal dari tabel ini
      // (join `receiving:receiving_id` di `getUnloadedZoneItems`).
      unloadedZoneItemsProvider,
    ]);
    _listen('receiving_details', [
      receivingDetailsProvider,
      receivingDetailByIdProvider,
      resiDeliveryMonitoringProvider,
      receivingProgressSummaryProvider,
      // storage_id barang (zona penyimpanan) & field barang lain yang
      // ditampilkan Monitoring Zona Storage ada di tabel ini.
      unloadedZoneItemsProvider,
    ]);

    // Data master (jarang berubah tapi tetap disinkronkan real-time
    // supaya halaman "Kelola ..." langsung update kalau diedit dari
    // device/tab lain, mis. admin buka Kelola Jenis Harga di 2 HP).
    _listen('item_types', [itemTypesProvider, allItemTypesProvider]);
    _listen('package_types', [packageTypesProvider]);
    _listen('pricing_types', [pricingTypesProvider, allPricingTypesProvider]);
    _listen('route_pricing', [routePricingsProvider]);
    // allSendersProvider ditambah 6 Oktober 2026 lanjutan -- halaman
    // admin baru "Daftar Pengirim Langganan" (SenderManagePage) ikut
    // realtime, SAMA seperti allDestinationsProvider untuk tujuan.
    _listen('senders', [sendersProvider, allSendersProvider]);

    // representatives -- tabel baru (6 Oktober 2026 lanjutan) untuk
    // fitur "Selesaikan di Perwakilan" di aplikasi sopir & halaman admin
    // "Daftar Perwakilan". Pencarian perwakilan sopir TIDAK lewat
    // provider (query langsung ke Supabase lewat SearchPickField, SAMA
    // seperti senders/destinations) -- yang perlu disinkronkan di sini
    // cuma allRepresentativesProvider (dipakai RepresentativeManagePage).
    _listen('representatives', [allRepresentativesProvider]);

    // storages -- tabel baru (8 Oktober 2026, "Zona Storage") dipakai
    // picker zona di form input detail barang (Receiving) & tampilan
    // info zona di checklist Loading, DAN halaman admin "Zona Storage".
    _listen('storages', [storagesProvider, allStoragesProvider]);
  }

  /// Buat 1 channel Realtime yang dengar SEMUA perubahan (insert/update/
  /// delete) di [table], lalu invalidate semua [providers] terkait --
  /// di-debounce 300ms per tabel supaya perubahan beruntun (mis. insert
  /// banyak baris sekaligus) tidak memicu fetch ulang berkali-kali dalam
  /// waktu singkat.
  void _listen(String table, List<ProviderOrFamily> providers) {
    final channel = _client.channel('realtime_sync_$table')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) => _scheduleInvalidate(table, providers),
      )
      ..subscribe();

    _channels.add(channel);
  }

  void _scheduleInvalidate(String table, List<ProviderOrFamily> providers) {
    _debounceTimers[table]?.cancel();
    _debounceTimers[table] = Timer(const Duration(milliseconds: 300), () {
      for (final provider in providers) {
        _ref.invalidate(provider);
      }
    });
  }

  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    for (final channel in _channels) {
      _client.removeChannel(channel);
    }
    _channels.clear();
  }
}
