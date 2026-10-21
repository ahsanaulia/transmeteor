import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../core/utils/unit_code.dart';
import '../models/receiving_detail_model.dart' show LabelType;
import '../models/receiving_model.dart';
import '../models/shipment_model.dart';
import '../models/shipment_scan_model.dart';
import 'label_barcode_service.dart';
import 'receiving_service.dart';
import 'vehicle_service.dart';

/// Dilempar saat unit_code yang sama sudah pernah discan dengan
/// scan_type yang sama -- ditangkap dari constraint
/// unique(unit_code, scan_type) di tabel shipment_scans.
class DuplicateScanException implements Exception {
  final String unitCode;

  DuplicateScanException(this.unitCode);

  @override
  String toString() =>
      'Barang dengan kode "$unitCode" sudah discan sebelumnya.';
}

/// Dilempar [ShipmentService.cancelManualLoad] -- FITUR "Pembatalan
/// Loading" (14 Oktober 2026, permintaan user eksplisit, lihat doc
/// comment [ShipmentService.getManualLoadCancelItems]). Loading barang
/// TIDAK BISA dibatalkan selama barang itu SUDAH ter-DELIVER (sudah
/// discan tiba) di shipment yang sama -- supaya tidak ada data yang
/// jadi aneh ("dianggap sudah tiba tapi tidak pernah tercatat naik").
class LoadAlreadyDeliveredException implements Exception {
  @override
  String toString() =>
      'Barang ini sudah tercatat tiba (DELIVER) di kendaraan ini -- '
      'loading tidak bisa dibatalkan.';
}

class ShipmentService {
  static final _client = SupabaseService.client;

  // ============================================================
  // SHIPMENTS
  // ============================================================

  static Future<List<ShipmentModel>> getShipments() async {
    final response = await _client
        .from('shipments')
        .select()
        .order('created_at', ascending: false);

    return (response as List)
        .map((data) => ShipmentModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }

  /// Shipment aktif (LOADING/DEPARTED) untuk satu kendaraan (kalau ada).
  /// Harus cek kedua status ini -- kalau cuma LOADING, mobil yang sudah
  /// berangkat (DEPARTED) dianggap "bebas" dan bisa direbut jadi
  /// shipment baru. Samakan pola dengan getActiveShipmentForDriver.
  static Future<ShipmentModel?> getActiveShipmentForVehicle(
    String vehicleId,
  ) async {
    final response = await _client
        .from('shipments')
        .select()
        .eq('vehicle_id', vehicleId)
        .inFilter('status', ['LOADING', 'DEPARTED'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Shipment aktif (LOADING/DEPARTED) yang driver-nya adalah employee ini.
  /// Dipakai di DriverHomePage untuk nampilin manifest & tombol Start.
  static Future<ShipmentModel?> getActiveShipmentForDriver(
    String employeeId,
  ) async {
    final response = await _client
        .from('shipments')
        .select()
        .eq('driver_employee_id', employeeId)
        .inFilter('status', ['LOADING', 'DEPARTED'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Shipment aktif (LOADING/DEPARTED) di mana employee ini jadi salah
  /// satu helper KENDARAAN-nya (vehicles.helper1/2/3_employee_id).
  ///
  /// SENGAJA tidak ada tabel shipment_helpers terpisah -- helper sudah
  /// ditentukan sekali di level kendaraan saat Admin "Siapkan Kendaraan",
  /// jadi tidak perlu dicatat ulang per-shipment (DRY). Dipakai di
  /// HelperHomePage.
  static Future<ShipmentModel?> getActiveShipmentForHelper(
    String employeeId,
  ) async {
    final vehicleRows = await _client
        .from('vehicles')
        .select('id')
        .or(
          'helper1_employee_id.eq.$employeeId,'
          'helper2_employee_id.eq.$employeeId,'
          'helper3_employee_id.eq.$employeeId',
        );

    final vehicleIds =
        (vehicleRows as List).map((row) => row['id'] as String).toList();

    if (vehicleIds.isEmpty) return null;

    final response = await _client
        .from('shipments')
        .select()
        .inFilter('vehicle_id', vehicleIds)
        .inFilter('status', ['LOADING', 'DEPARTED'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Membuat shipment baru. shipment_number dibuat otomatis oleh trigger
  /// Postgres, Flutter tidak mengirimnya.
  ///
  /// [driverEmployeeId] diambil dari data kendaraan yang sudah disiapkan
  /// admin. Helper TIDAK dicatat di sini -- lihat catatan di
  /// getActiveShipmentForHelper soal kenapa tidak ada tabel terpisah.
  static Future<ShipmentModel> createShipment({
    required String vehicleId,
    required String loadedBy,
    String? destination,
    String? routePricingId,
    String? driverEmployeeId,
  }) async {
    final data = {
      'vehicle_id': vehicleId,
      'status': 'LOADING',
      'loaded_by': loadedBy,
      'loaded_at': DateTime.now().toIso8601String(),
      'destination': destination,
      'route_pricing_id': routePricingId,
      'driver_employee_id': driverEmployeeId,
    };

    final response =
        await _client.from('shipments').insert(data).select().single();

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Ambil shipment AKTIF (LOADING/DEPARTED) kendaraan ini kalau SUDAH ADA
  /// ("lanjutkan muat"), atau buat shipment LOADING baru kalau belum ada --
  /// dipakai BERSAMA oleh staff Loading (`VehicleSelectPage`) MAUPUN Admin
  /// (menu "Loading Barang" standalone di Dashboard, 7 Oktober 2026
  /// lanjutan -- sebelumnya intervensi admin cuma bisa lewat shipment yang
  /// SUDAH dibuat staff loading duluan di "Daftar Muatan"; sekarang admin
  /// bisa membuat/melanjutkan shipment sendiri, independen dari staff).
  /// SENGAJA 1 method -- supaya logic "lanjutkan vs buat baru" & pesan
  /// error "kendaraan belum disiapkan" TIDAK dobel-maintain di 2 tempat
  /// (lihat pola bug dobel-logic yang berulang di project ini, mis.
  /// `getAvailableUnlabeledItemsForShipment` vs mode Tanpa Label QR).
  static Future<ShipmentModel> resolveOrCreateShipmentForVehicle({
    required String vehicleId,
    required String? vehicleDriverEmployeeId,
    required String loadedBy,
  }) async {
    final existing = await getActiveShipmentForVehicle(vehicleId);
    if (existing != null) return existing;

    if (vehicleDriverEmployeeId == null) {
      throw Exception(
        'Kendaraan ini belum punya sopir. Tentukan sopirnya dulu lewat '
        'menu "Pendataan Armada".',
      );
    }

    return createShipment(
      vehicleId: vehicleId,
      loadedBy: loadedBy,
      driverEmployeeId: vehicleDriverEmployeeId,
    );
  }

  /// Menetapkan/mengganti driver shipment yang sudah ada.
  static Future<ShipmentModel> assignDriver({
    required String shipmentId,
    required String driverEmployeeId,
  }) async {
    final response = await _client
        .from('shipments')
        .update({
          'driver_employee_id': driverEmployeeId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', shipmentId)
        .select()
        .single();

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  static Future<ShipmentModel> updateShipmentStatus({
    required String shipmentId,
    required String status,
    DateTime? departedAt,
    DateTime? arrivedAt,
  }) async {
    final data = {
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
      if (departedAt != null) 'departed_at': departedAt.toIso8601String(),
      if (arrivedAt != null) 'arrived_at': arrivedAt.toIso8601String(),
    };

    final response = await _client
        .from('shipments')
        .update(data)
        .eq('id', shipmentId)
        .select()
        .single();

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Dipanggil saat driver pencet tombol Start di DriverHomePage --
  /// menandai waktu keberangkatan riil kendaraan (beda dari departed_at
  /// yang di-set staff Loading pas selesai scan muat).
  static Future<ShipmentModel> startTrip({
    required String shipmentId,
  }) async {
    final response = await _client
        .from('shipments')
        .update({
          'trip_started_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', shipmentId)
        .select()
        .single();

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Dipanggil saat driver/helper menekan "Sudah Kembali ke Kantor" --
  /// menandai SELURUH perjalanan benar-benar selesai (status ARRIVED).
  ///
  /// **DIKEMBALIKAN (13 Oktober 2026, permintaan user eksplisit:
  /// "Kembalikan perubahan, bahwa kendaraan harus disiapkan oleh admin
  /// baru muncul di loading")** -- fitur 10 Oktober 2026 yang menghapus
  /// baris ini DIBATALKAN. Begitu ARRIVED, kendaraan OTOMATIS
  /// dinonaktifkan lagi (`is_active=false`) dan hilang dari "Pilih
  /// Kendaraan" sampai Admin menyiapkannya ulang (pilih sopir lagi lewat
  /// "Siapkan Kendaraan").
  static Future<ShipmentModel> returnToOffice({
    required String shipmentId,
  }) async {
    // Dicek SEBELUM update -- jaga-jaga idempotent untuk
    // [_markLoadedItemsSelesaiForShipment] di bawah (lihat doc comment
    // method itu: menambah `selesai_barang`, BUKAN menimpa, jadi
    // dipanggil 2x untuk shipment yang SAMA akan menghitung ganda kalau
    // tidak dijaga di sini).
    final wasAlreadyArrived = await _isShipmentAlreadyArrived(shipmentId);

    final shipment = await updateShipmentStatus(
      shipmentId: shipmentId,
      status: 'ARRIVED',
      arrivedAt: DateTime.now(),
    );

    await VehicleService.setActive(shipment.vehicleId, false);

    // REDESAIN ARSITEKTUR (17 Oktober 2026, permintaan user eksplisit):
    // "Jika selesai jalan shipment ---- update kolom state". Lihat
    // [_markLoadedItemsSelesaiForShipment] untuk aturan lengkapnya.
    if (!wasAlreadyArrived) {
      await _markLoadedItemsSelesaiForShipment(shipmentId);
    }

    return shipment;
  }

  /// "Intervensi Admin" -- dipakai Admin (otoritas tertinggi) untuk
  /// MEMAKSA menyelesaikan shipment yang sedang LOADING/DEPARTED, TANPA
  /// perlu sopir menekan "Sudah Kembali ke Kantor" sendiri. Skenario:
  /// sopir mengalami kendala aplikasi di lapangan (HP rusak/hilang/
  /// baterai habis/tidak ada sinyal) sehingga tidak bisa menyelesaikan
  /// perjalanan lewat aplikasinya.
  ///
  /// Efeknya SAMA PERSIS dengan [returnToOffice] (status -> ARRIVED,
  /// arrived_at diisi) DITAMBAH jejak audit (`completed_by_admin = true`,
  /// `admin_completion_note` wajib diisi alasannya) supaya nanti kelihatan
  /// di Monitoring Kinerja Perjalanan mana yang diselesaikan normal oleh
  /// sopir vs. dipaksa admin. **DIKEMBALIKAN (13 Oktober 2026)**:
  /// panggilan `VehicleService.setActive(..., false)` SUDAH DITAMBAHKAN
  /// LAGI di sini, sama seperti [returnToOffice] -- lihat doc comment
  /// method itu.
  ///
  /// CATATAN: tracking GPS di HP sopir TIDAK dimatikan langsung dari sini
  /// (tidak ada cara kirim perintah ke HP sopir dari server) -- TAPI
  /// `DriverHomePage` sudah otomatis berhenti tracking sendiri begitu
  /// `activeShipmentForDriverProvider`-nya jadi null (shipment ini tidak
  /// lagi match filter status LOADING/DEPARTED), lewat realtime sync yang
  /// sudah ada -- asal HP sopir masih online. Kalau HP sopir benar-benar
  /// offline/mati, servicenya baru berhenti kalau/waktu HP itu nyala lagi
  /// dan datanya ke-refresh.
  static Future<ShipmentModel> forceCompleteByAdmin({
    required String shipmentId,
    required String note,
  }) async {
    // Lihat catatan idempotent di [returnToOffice] -- alasan SAMA.
    final wasAlreadyArrived = await _isShipmentAlreadyArrived(shipmentId);

    final response = await _client
        .from('shipments')
        .update({
          'status': 'ARRIVED',
          'arrived_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'completed_by_admin': true,
          'admin_completion_note': note,
        })
        .eq('id', shipmentId)
        .select()
        .single();

    final shipment = ShipmentModel.fromMap(Map<String, dynamic>.from(response));

    await VehicleService.setActive(shipment.vehicleId, false);

    // REDESAIN ARSITEKTUR (17 Oktober 2026, permintaan user eksplisit:
    // "jika intervensi di Sopir, selesaikan. Maka selain shipment harus
    // ada di dibarang selesai"). SEBELUMNYA method ini HANYA mengubah
    // status shipment -- barang (`receiving_details`) yang sudah
    // ter-LOAD ke shipment ini tidak pernah ikut ditandai selesai,
    // itulah akar masalah RESI000311 (barang yang memang belum sempat
    // di-LOAD tetap nyangkut, TAPI barang yang SUDAH ter-LOAD juga tidak
    // pernah "ditutup" statusnya). Sekarang SAMA PERSIS [returnToOffice]
    // -- lihat [_markLoadedItemsSelesaiForShipment].
    if (!wasAlreadyArrived) {
      await _markLoadedItemsSelesaiForShipment(shipmentId);
    }

    return shipment;
  }

  /// Dicek SEBELUM shipment diupdate ke ARRIVED -- lihat pakai di
  /// [returnToOffice]/[forceCompleteByAdmin].
  static Future<bool> _isShipmentAlreadyArrived(String shipmentId) async {
    final row = await _client
        .from('shipments')
        .select('status')
        .eq('id', shipmentId)
        .maybeSingle();
    return (row as Map?)?['status'] == 'ARRIVED';
  }

  /// Helper bersama [returnToOffice] & [forceCompleteByAdmin] -- dipanggil
  /// begitu 1 shipment "selesai jalan" (status -> ARRIVED, lewat sopir
  /// menekan tombol sendiri ATAUPUN dipaksa Admin), dan HANYA kalau
  /// shipment ini BELUM pernah ARRIVED sebelumnya (lihat
  /// [_isShipmentAlreadyArrived]). REDESAIN ARSITEKTUR (17 Oktober 2026,
  /// permintaan user eksplisit, lihat
  /// `migrasi_flow_state_sisa_barang.sql` poin 7): "Jika selesai jalan
  /// shipment ---- update kolom state".
  ///
  /// **PENAMBAHAN (permintaan user: "atau kita tambahkan state : 'loading
  /// sebagian' dan 'selesai sebagian'")**: menambah `selesai_barang`
  /// SEBANYAK unit fisik tiap baris yang memang ter-LOAD ke SHIPMENT INI
  /// SAJA (dihitung di RPC `mark_selesai_for_shipment`, BUKAN langsung
  /// menandai SELURUH baris `SELESAI`) -- supaya barang berlabel
  /// multi-unit yang fisiknya terpecah ke LEBIH DARI SATU shipment
  /// (sebagian unit sudah kembali, sebagian lagi masih di shipment lain
  /// yang belum kembali) berakhir di `SELESAI_SEBAGIAN`, BUKAN langsung
  /// `SELESAI` penuh secara prematur (ataupun tidak ditandai apa-apa).
  /// Barang yang HANYA ada di 1 shipment (kasus normal/paling umum) tetap
  /// otomatis jadi `SELESAI` begitu `selesai_barang` mencapai total unit
  /// fisiknya.
  ///
  /// Query & RPC di sini SENGAJA di-scope ke [shipmentId] saja -- 1
  /// shipment, BUKAN query global -- jadi aman dari kelas bug
  /// paginasi/skala yang pernah terjadi di
  /// [getAvailableItemsForManualLoad] (riwayat lengkap ada di doc comment
  /// method itu).
  static Future<void> _markLoadedItemsSelesaiForShipment(
    String shipmentId,
  ) async {
    await _client.rpc('mark_selesai_for_shipment', params: {
      'p_shipment_id': shipmentId,
    });
  }

  /// "Intervensi Admin: Mulai Paksa Perjalanan" -- permintaan eksplisit
  /// user (22 September 2026): sopir kadang lupa menekan "Mulai
  /// Perjalanan" di aplikasinya padahal kendaraan sudah fisik
  /// meninggalkan gudang -- akibatnya `trip_started_at` tetap null
  /// (tracking GPS tidak pernah aktif walau kendaraan sudah jalan).
  /// Admin (otoritas tertinggi) bisa lihat kondisi ini di Monitoring
  /// Kendaraan & Sopir (status "Berangkat" tapi belum ada titik lokasi
  /// sama sekali) dan berangkatkan paksa dari sini.
  ///
  /// Efeknya:
  /// - `trip_started_at` diisi sekarang (mirip persis sopir menekan
  ///   "Mulai Perjalanan" sendiri).
  /// - Kalau shipment ini masih berstatus LOADING (admin juga belum
  ///   sempat klik "Berangkatkan" di Daftar Muatan), status ikut
  ///   dinaikkan ke DEPARTED -- munculnya tombol ini artinya kendaraan
  ///   SUDAH fisik berangkat, jadi status harus mencerminkan itu.
  /// - `departed_at` diisi HANYA kalau belum ada nilainya sama sekali
  ///   (tidak menimpa waktu berangkat yang sudah benar dari alur normal).
  /// - Jejak audit `trip_started_by_admin = true` +
  ///   `admin_start_trip_note` (wajib diisi alasannya).
  ///
  /// CATATAN PENTING soal GPS tracking di HP sopir: kode ini CUMA
  /// mengubah data di Supabase -- tidak ada cara mengirim perintah
  /// langsung ke HP sopir dari server. TAPI `DriverHomePage` sudah
  /// otomatis RESUME tracking sendiri (`_resumeTrackingIfNeeded`) begitu
  /// `activeShipmentForDriverProvider`-nya melihat `tripStartedAt` terisi
  /// (lewat realtime sync yang sudah ada, tabel `shipments`) -- jadi
  /// begitu admin menekan tombol ini, tracking GPS otomatis AKTIF sendiri
  /// di HP sopir TANPA sopir perlu buka-tutup app atau tap apa pun, ASAL
  /// HP sopir masih online/terhubung internet. Kalau HP sopir offline,
  /// tracking baru mulai begitu HP itu online lagi dan datanya ke-refresh.
  static Future<ShipmentModel> forceStartTripByAdmin({
    required String shipmentId,
    required String note,
  }) async {
    final current = await _client
        .from('shipments')
        .select('status, departed_at, vehicle_id')
        .eq('id', shipmentId)
        .single();

    final data = <String, dynamic>{
      'trip_started_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'trip_started_by_admin': true,
      'admin_start_trip_note': note,
    };

    final wasLoading = current['status'] == 'LOADING';
    if (wasLoading) {
      data['status'] = 'DEPARTED';
    }
    if (current['departed_at'] == null) {
      data['departed_at'] = DateTime.now().toIso8601String();
    }

    final response = await _client
        .from('shipments')
        .update(data)
        .eq('id', shipmentId)
        .select()
        .single();

    // FITUR (21 Oktober 2026, permintaan user eksplisit, lihat doc
    // comment `VehicleService.setLoading`): tombol ini SECARA EFEKTIF
    // juga memberangkatkan kendaraan (status naik ke DEPARTED) kalau
    // sebelumnya masih LOADING -- `vehicles.is_loading` diturunkan juga
    // supaya Monitoring Resi konsisten (tidak nyangkut di "Sedang
    // Dimuat" walau shipment-nya sudah DEPARTED lewat jalur ini).
    if (wasLoading) {
      final vehicleId = current['vehicle_id'] as String?;
      if (vehicleId != null) {
        await VehicleService.setLoading(vehicleId, false);
      }
    }

    return ShipmentModel.fromMap(Map<String, dynamic>.from(response));
  }

  // ============================================================
  // SHIPMENT SCANS
  // ============================================================

  /// Query bersama: semua shipment_scans (LOAD) shipment ini, lengkap
  /// dengan data receiving_detail & receiving induknya (termasuk
  /// destination_id). Dipakai sebagai basis dua rekap cetak sekaligus --
  /// [getManifestPrintSummary] (per resi) dan
  /// [getManifestSummaryByDestination] (per tujuan, untuk Tanda Terima
  /// Tujuan) -- supaya query ke Supabase tidak dobel.
  ///
  /// `item_name`/`quantity_unit` ditambahkan (8 Oktober 2026, lanjutan
  /// lagi -- permintaan user eksplisit: "Daftar Muatan ... yang
  /// ditampilkan adalah Nama Barang dan jumlahnya. Bukan Jenis Tarif dan
  /// jumlahnya") supaya [getManifestSummaryByDestination] bisa
  /// mengelompokkan baris Tanda Terima Tujuan PER NAMA BARANG (bukan per
  /// jenis tarif seperti sebelumnya) -- lihat catatan di method itu.
  ///
  /// `discount_amount` ditambahkan (8 Oktober 2026, lanjutan lagi --
  /// permintaan user eksplisit: "Pada cetakan Tanda Terima Tujuan,
  /// Cantumkan harga diskon") supaya [getManifestSummaryByDestination]
  /// bisa menampilkan nilai diskon per baris, terpisah dari `total_price`
  /// (yang SUDAH net/setelah diskon) -- lihat catatan `totalDiscount` di
  /// method itu. [getManifestPrintSummary] (Manifest Muatan) TIDAK perlu
  /// field ini sama sekali -- cukup `total_price` apa adanya (sudah net),
  /// sesuai permintaan user "Di Manifest harga Adalah setelah diskon".
  static Future<List<Map<String, dynamic>>> _getLoadScansWithDetails(
    String shipmentId,
  ) async {
    final response = await _client
        .from('shipment_scans')
        .select('''
          id,
          unit_code,
          unit_index,
          receiving_detail_id,
          receiving_details (
            id,
            receiving_id,
            quantity,
            unit_price,
            bundle_quantity,
            total_price,
            pricing_type_id,
            item_name,
            quantity_unit,
            discount_amount,
            receiving:receiving_id (
              receipt_number,
              nomor_buku,
              destination,
              destination_id,
              destination_address,
              destination_phone,
              total_price,
              payment_status,
              dp_amount,
              destinations:destination_id (
                phone
              )
            )
          )
        ''')
        .eq('shipment_id', shipmentId)
        .eq('scan_type', 'LOAD');

    return (response as List)
        .map((data) => Map<String, dynamic>.from(data))
        .toList();
  }

  /// Nomor HP tujuan LIVE dari tabel `destinations` (fix 5 Oktober 2026 --
  /// permintaan user eksplisit: "jangan capture... ambil dari data
  /// destinations", "itu standar aplikasi tabel relasi", "ini berlaku
  /// untuk semua printout"). [receiving] adalah map nested hasil query
  /// `receiving:receiving_id(...)` yang SUDAH di-embed dengan
  /// `destinations:destination_id(phone)` (lihat
  /// `_getLoadScansWithDetails`). Fallback ke kolom snapshot lama
  /// `destination_phone` HANYA kalau `destination_id`-nya null (resi
  /// sangat lama yang tidak tertaut ke tujuan manapun) atau tujuannya
  /// sudah terhapus -- supaya tidak tiba-tiba kosong di kasus itu.
  static String? _liveDestinationPhone(Map<String, dynamic>? receiving) {
    final destinations = receiving?['destinations'] as Map<String, dynamic>?;
    final livePhone = destinations?['phone'] as String?;
    if (livePhone != null && livePhone.isNotEmpty) return livePhone;
    return receiving?['destination_phone'] as String?;
  }

  /// DIAGNOSTIK SEMENTARA (22 Sep 2026) -- investigasi bug "manifest
  /// kosong pas dibuat PDF, padahal daftar di layar (getShipmentScanFeed)
  /// ada isinya untuk shipment yang sama". Dipanggil dari
  /// `ManifestPage._sharePdf()` SEBELUM generate PDF sungguhan, supaya
  /// kelihatan PERSIS di langkah mana data hilang: (a) query mentah ke
  /// shipment_scans (rawRows) -- kalau ini 0 padahal layar ada isinya,
  /// berarti bukan soal query/RLS (query & role SAMA dengan
  /// getShipmentScanFeed), (b) embed receiving_details gagal ke-resolve
  /// (nullDetail) -- kalau ini > 0 dari rawRows, berarti murni soal embed
  /// PostgREST di `_getLoadScansWithDetails` (kolom yang diminta beda dari
  /// getShipmentScanFeed), atau (c) receiving_id/id kosong walau detail
  /// ada (nullReceivingIdOrDetailId).
  ///
  /// HAPUS method ini (dan pemanggilannya di ManifestPage) setelah bug ini
  /// selesai diperbaiki -- ini murni alat bantu debug, bukan fitur.
  static Future<Map<String, dynamic>> debugManifestDiagnostics(
    String shipmentId,
  ) async {
    final rows = await _getLoadScansWithDetails(shipmentId);

    int nullDetail = 0;
    int nullReceivingIdOrDetailId = 0;
    String? sampleDetailKeys;

    for (final row in rows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) {
        nullDetail++;
        continue;
      }
      sampleDetailKeys ??= detail.keys.join(', ');

      final receivingId = detail['receiving_id'] as String?;
      final detailId = detail['id'] as String?;
      if (receivingId == null || detailId == null) {
        nullReceivingIdOrDetailId++;
      }
    }

    // Panggil LANGSUNG getManifestPrintSummary (fungsi yang SAMA PERSIS
    // dipakai _sharePdf) di sini -- supaya kelihatan APAKAH fungsi
    // grouping-nya sendiri yang menghasilkan list kosong (walau rows di
    // atas sudah terbukti sehat), atau malah fungsi ini THROW/error
    // (yang mungkin selama ini ketangkep diam-diam di tempat lain).
    int? groupedCount;
    String? groupedFirstReceipt;
    String? groupedError;
    try {
      final grouped = await getManifestPrintSummary(shipmentId);
      groupedCount = grouped.length;
      if (grouped.isNotEmpty) {
        groupedFirstReceipt = grouped.first['receiptNumber']?.toString();
      }
    } catch (e) {
      groupedError = e.toString();
    }

    return {
      'rawRows': rows.length,
      'nullDetail': nullDetail,
      'nullReceivingIdOrDetailId': nullReceivingIdOrDetailId,
      'sampleDetailKeys': sampleDetailKeys,
      'groupedCount': groupedCount,
      'groupedFirstReceipt': groupedFirstReceipt,
      'groupedError': groupedError,
    };
  }

  /// Deteksi detail barang (`receiving_details`) yang LOAD scan-nya
  /// SUNGGUH tersebar di LEBIH DARI SATU shipment berbeda (kasus "resi
  /// dimuat 2+ truk sekaligus", contoh di komentar [recordScan]: "resi
  /// 15 kubik bata ringan dimuat 2 truk"). Dipakai [getManifestPrintSummary]
  /// & [getManifestSummaryByDestination] untuk memutuskan APAKAH baris
  /// itu perlu diprorata pakai jumlah scan fisik, atau cukup percaya
  /// langsung `quantity`/`total_price` SAAT INI (lihat catatan FIX
  /// panjang di [getManifestPrintSummary]).
  ///
  /// Query TANPA filter shipment_id (beda dari [_getLoadScansWithDetails])
  /// supaya kelihatan SEMUA shipment yang pernah memuat detail itu, lalu
  /// dikelompokkan di sisi Dart -- volume baris LOAD per detail biasanya
  /// kecil (quantity barang, bukan jutaan baris), jadi tidak perlu query
  /// SQL GROUP BY yang lebih rumit.
  static Future<Set<String>> _detailIdsSplitAcrossShipments(
    List<String> detailIds,
  ) async {
    if (detailIds.isEmpty) return {};

    final response = await _client
        .from('shipment_scans')
        .select('receiving_detail_id, shipment_id')
        .eq('scan_type', 'LOAD')
        .inFilter('receiving_detail_id', detailIds);

    final shipmentIdsByDetailId = <String, Set<String>>{};
    for (final data in (response as List)) {
      final row = Map<String, dynamic>.from(data);
      final detailId = row['receiving_detail_id'] as String?;
      final shipmentId = row['shipment_id'] as String?;
      if (detailId == null || shipmentId == null) continue;
      shipmentIdsByDetailId.putIfAbsent(detailId, () => <String>{}).add(shipmentId);
    }

    return shipmentIdsByDetailId.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();
  }

  /// FITUR (13 Oktober 2026 -- permintaan user "Tambahan Fitur" poin 7:
  /// "Jika 1 resi ternyata dimuat oleh beberapa kendaraan maka Pemuatan
  /// terakhir yang akan berisi berapa nilai tagihan Bayar Tujuan.").
  ///
  /// Dipakai [getManifestPrintSummary] & [getManifestSummaryByDestination]
  /// untuk memutuskan APAKAH [shipmentId] berhak menampilkan nilai
  /// tagihan Bayar Tujuan di kolom Keterangan untuk resi [receivingId] --
  /// supaya tagihan TIDAK dobel-tampil di setiap pemuatan parsial kalau
  /// resi ini terpecah ke beberapa kendaraan/shipment.
  ///
  /// "Terakhir" didefinisikan: SELURUH unit fisik resi ini (dihitung
  /// lewat [_physicalUnitCodes] -- SAMA PERSIS basis hitung
  /// "sudah dimuat semua" yang dipakai [getAvailableItemsForManualLoad])
  /// SUDAH ter-scan LOAD (lintas shipment apa pun, tidak cuma
  /// [shipmentId]), DAN [shipmentId] adalah shipment yang memegang scan
  /// LOAD dengan `scanned_at` PALING AKHIR di antara semua shipment yang
  /// memuat resi ini. Kalau resi masih termuat SEBAGIAN (belum ada
  /// shipment yang menggenapkan ke seluruh unit), TIDAK ADA shipment yang
  /// dianggap "terakhir" -- method ini kembalikan `false` untuk semua
  /// shipment, supaya tagihan belum ditampilkan di cetakan mana pun
  /// sampai benar-benar lunas termuat.
  ///
  /// Resi yang TIDAK PERNAH terpecah (semua unit dimuat ke 1 shipment
  /// saja, kasus mayoritas) otomatis dianggap "terakhir" juga lewat
  /// definisi yang sama ini (trivial -- shipment satu-satunya yang ada
  /// otomatis jadi "yang paling akhir").
  ///
  /// PERBAIKAN PERFORMA (14 Oktober 2026 -- laporan user: preview
  /// Tanda Terima Tujuan lama baru termuat di layar): method 1-resi ini
  /// SUDAH TIDAK DIPAKAI LAGI (dulu dipanggil sequential di dalam loop,
  /// 2 query PER RESI -- N+1). Logikanya sekarang dipindah ke
  /// [_isLastLoadingShipmentBatch] yang menghitung SEMUA resi sekaligus
  /// dengan cuma 2 query total. Dibiarkan di sini (tidak dihapus) hanya
  /// sebagai referensi dokumentasi definisi "terakhir" di atas.
  // ignore: unused_element
  static Future<bool> _isLastLoadingShipment({
    required String receivingId,
    required String shipmentId,
  }) async {
    final detailsResponse = await _client
        .from('receiving_details')
        .select('id, item_code, quantity, is_unlabeled')
        .eq('receiving_id', receivingId);

    final details = (detailsResponse as List)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();

    if (details.isEmpty) return false;

    final allCodes = details.expand(_physicalUnitCodes).toList();
    if (allCodes.isEmpty) return false;

    // Scoping ke [allCodes] 1 resi (BUKAN query global) -- aman dari
    // risiko URL kepanjangan, sama pola [getAvailableItemsForManualDeliver].
    final scansResponse = await _client
        .from('shipment_scans')
        .select('unit_code, shipment_id, scanned_at')
        .eq('scan_type', 'LOAD')
        .inFilter('unit_code', allCodes);

    final scans = (scansResponse as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    final loadedCodes = scans.map((s) => s['unit_code'] as String).toSet();
    final allLoaded = allCodes.every(loadedCodes.contains);
    if (!allLoaded) return false;

    scans.sort(
      (a, b) => (a['scanned_at'] as String).compareTo(b['scanned_at'] as String),
    );

    final lastShipmentId = scans.last['shipment_id'] as String?;
    return lastShipmentId == shipmentId;
  }

  /// Versi batch dari [_isLastLoadingShipment] -- PERBAIKAN PERFORMA
  /// (14 Oktober 2026, laporan user: preview Tanda Terima Tujuan lama
  /// baru termuat di layar). Logikanya PERSIS SAMA dengan versi
  /// sequential-nya (cek semua unit sudah LOAD + shipment dengan scan
  /// LOAD paling akhir yang dianggap "terakhir"), tapi dihitung untuk
  /// SEMUA [receivingIds] sekaligus dengan HANYA 2 query total (bukan
  /// 2 query PER RESI seperti sebelumnya) -- menghindari pola N+1 yang
  /// membuat preview lambat saat 1 shipment memuat banyak resi unik.
  static Future<Map<String, bool>> _isLastLoadingShipmentBatch({
    required Set<String> receivingIds,
    required String shipmentId,
  }) async {
    if (receivingIds.isEmpty) return {};

    final detailsResponse = await _client
        .from('receiving_details')
        .select('id, item_code, quantity, is_unlabeled, receiving_id')
        .inFilter('receiving_id', receivingIds.toList());

    final detailsByReceiving = <String, List<Map<String, dynamic>>>{};
    for (final d in (detailsResponse as List)) {
      final detail = Map<String, dynamic>.from(d);
      final receivingId = detail['receiving_id'] as String?;
      if (receivingId == null) continue;
      detailsByReceiving.putIfAbsent(receivingId, () => []).add(detail);
    }

    final codesByReceiving = <String, List<String>>{};
    final allCodes = <String>[];
    for (final entry in detailsByReceiving.entries) {
      final codes = entry.value.expand(_physicalUnitCodes).toList();
      codesByReceiving[entry.key] = codes;
      allCodes.addAll(codes);
    }

    final result = <String, bool>{};
    if (allCodes.isEmpty) {
      for (final id in receivingIds) {
        result[id] = false;
      }
      return result;
    }

    // Scoping ke [allCodes] resi-resi dalam [receivingIds] saja (BUKAN
    // query global) -- aman dari risiko URL kepanjangan, sama pola
    // [_isLastLoadingShipment] di atas.
    final scansResponse = await _client
        .from('shipment_scans')
        .select('unit_code, shipment_id, scanned_at')
        .eq('scan_type', 'LOAD')
        .inFilter('unit_code', allCodes);

    final scansByCode = <String, List<Map<String, dynamic>>>{};
    for (final r in (scansResponse as List)) {
      final scan = Map<String, dynamic>.from(r);
      final unitCode = scan['unit_code'] as String?;
      if (unitCode == null) continue;
      scansByCode.putIfAbsent(unitCode, () => []).add(scan);
    }
    final loadedCodes = scansByCode.keys.toSet();

    for (final receivingId in receivingIds) {
      final codes = codesByReceiving[receivingId] ?? [];
      if (codes.isEmpty) {
        result[receivingId] = false;
        continue;
      }

      final allLoaded = codes.every(loadedCodes.contains);
      if (!allLoaded) {
        result[receivingId] = false;
        continue;
      }

      final relevantScans = codes.expand((c) => scansByCode[c] ?? []).toList()
        ..sort(
          (a, b) => (a['scanned_at'] as String)
              .compareTo(b['scanned_at'] as String),
        );

      final lastShipmentId = relevantScans.last['shipment_id'] as String?;
      result[receivingId] = lastShipmentId == shipmentId;
    }

    return result;
  }

  /// Rekap cetak Manifest Muatan, DIGROUP PER RESI (bukan per barang) --
  /// perbaikan permintaan user (22 Sep 2026): cetakan sebelumnya
  /// menampilkan 1 baris per barang discan sehingga 1 resi bisa "dobel"
  /// muncul berkali-kali di manifest. Manifest adalah daftar MUATAN (1
  /// resi bisa saja terpecah ke beberapa shipment/manifest berbeda),
  /// karena itu nilai tarif yang ditampilkan DIPRORATA: kalau resi X isi
  /// 10 barang tapi yang dimuat ke shipment ini cuma 6, nilai tarif yang
  /// ditampilkan = 6/10 x total_price resi itu (bukan total_price penuh)
  /// -- supaya kalau resi yang sama juga muncul di manifest shipment
  /// lain, nilainya tidak dobel-hitung. Proration ini otomatis ikut
  /// menghormati fitur "Ubah Harga Admin" karena dihitung dari
  /// `total_price` (bukan dihitung ulang dari unit_price x quantity).
  ///
  /// Tiap baris hasil: receivingId, receiptNumber, destination,
  /// destinationAddress, itemCount (jumlah koli, lihat catatan FIX di
  /// bawah), jenisTarifCount (jumlah jenis_tarif berbeda dalam resi ini
  /// di shipment ini), totalValue (nilai tarif, lihat catatan FIX di
  /// bawah). Diurutkan per nomor resi.
  ///
  /// Baris `shipment_scans` yang linknya ke `receiving_details` tidak
  /// ketemu (data lama yang rusak/orphan) DI-SKIP dari rekap ini --
  /// SENGAJA, bukan bug. Kalau nanti ketemu kasus nyata, itu tanda ada
  /// masalah DATA (link putus), bukan sesuatu yang boleh "diakali" jadi
  /// baris PDF -- investigasi datanya langsung, jangan tambah logic
  /// pemulusan di sini tanpa user minta eksplisit.
  ///
  /// --- FIX penting (bug report 3 Oktober 2026) ---
  /// Proration SEBELUMNYA selalu dipakai untuk SEMUA detail, apa pun
  /// alasannya quantity != jumlah scan. Ini salah untuk kasus yang jauh
  /// lebih sering terjadi daripada "resi terpecah ke beberapa truk":
  /// ADMIN MENGEDIT quantity/total_price SETELAH barang itu sudah
  /// discan/dimuat (contoh nyata: receiving salah catat 1 koli padahal
  /// aslinya 2, admin koreksi quantity jadi 2 + total harga jadi
  /// Rp400.000 -- tapi karena cuma ada 1 baris scan LOAD yang sudah
  /// kejadian duluan, dulu proration menghitung seolah "cuma separuh
  /// barang yang dimuat", sehingga cetakan tidak pernah mencerminkan
  /// koreksi admin). Sekarang [_detailIdsSplitAcrossShipments] dipanggil
  /// dulu untuk membedakan 2 kasus:
  /// - Detail TIDAK pernah dipecah ke shipment lain (mayoritas kasus) --
  ///   percaya PENUH `quantity`/`total_price` SAAT INI dari
  ///   `receiving_details` (termasuk koreksi admin terbaru), proration
  ///   TIDAK dipakai sama sekali.
  /// - Detail SUNGGUH terpecah ke >1 shipment berbeda (kasus asli yang
  ///   dimaksud proration ini dulu dibuat) -- tetap prorata berdasar
  ///   jumlah scan fisik vs quantity, supaya tiap shipment cuma dapat
  ///   porsi yang benar-benar dimuat di situ (perilaku lama, TIDAK
  ///   berubah untuk kasus ini).
  static Future<List<Map<String, dynamic>>> getManifestPrintSummary(
    String shipmentId,
  ) async {
    final rows = await _getLoadScansWithDetails(shipmentId);

    final scannedCountByDetailId = <String, int>{};
    for (final row in rows) {
      final detailId = row['receiving_detail_id'] as String?;
      if (detailId == null) continue;
      scannedCountByDetailId[detailId] =
          (scannedCountByDetailId[detailId] ?? 0) + 1;
    }

    final splitDetailIds = await _detailIdsSplitAcrossShipments(
      scannedCountByDetailId.keys.toList(),
    );

    final grouped = <String, Map<String, dynamic>>{};
    final pricingTypeIdsByReceiving = <String, Set<String>>{};
    final countedDetailIds = <String>{};

    for (final row in rows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      final detailId = detail['id'] as String?;
      if (receivingId == null || detailId == null) continue;

      final receiving = detail['receiving'] as Map<String, dynamic>?;

      grouped.putIfAbsent(
        receivingId,
        () => {
          'receivingId': receivingId,
          'receiptNumber': receiving?['receipt_number'],
          // FITUR (8 Oktober 2026 -- poin 7): nomor buku, disisipkan di
          // belakang nomor resi di cetakan Manifest kalau ada.
          'nomorBuku': receiving?['nomor_buku'],
          'destination': receiving?['destination'],
          'destinationAddress': receiving?['destination_address'],
          'destinationPhone': _liveDestinationPhone(receiving),
          'itemCount': 0,
          // 'totalQuantity' (lanjutan fix 3 Oktober 2026): total koli
          // ASLI resi ini (field `quantity`), beda dari `itemCount`
          // KALAU resi ini genuinely terpecah ke beberapa kendaraan --
          // lihat catatan panjang di bawah.
          'totalQuantity': 0,
          'totalValue': 0.0,
          // FITUR (13 Oktober 2026 -- poin 2-7, status pembayaran & DP):
          // dipakai `PdfTemplates.buildManifestDocument` untuk mengisi
          // kolom Keterangan (lihat [_isLastLoadingShipment] untuk
          // 'receivingTotalPrice'/'isLastLoadingShipment' yang disisipkan
          // belakangan di bawah).
          'paymentStatus': receiving?['payment_status'] as String? ??
              ReceivingPaymentStatus.bayarTujuan,
          'dpAmount': (receiving?['dp_amount'] as num?)?.toDouble(),
          'receivingTotalPrice': (receiving?['total_price'] as num?)?.toDouble() ?? 0,
        },
      );
      pricingTypeIdsByReceiving.putIfAbsent(receivingId, () => <String>{});

      final pricingTypeId = detail['pricing_type_id'] as String?;
      if (pricingTypeId != null) {
        pricingTypeIdsByReceiving[receivingId]!.add(pricingTypeId);
      }

      // Jumlah koli & nilai tarif per receiving_detail HANYA dihitung
      // SEKALI (bukan diulang tiap baris scan unit) -- lihat catatan FIX
      // di doc comment method ini soal kapan diprorata vs kapan percaya
      // langsung quantity/total_price saat ini.
      if (!countedDetailIds.contains(detailId)) {
        countedDetailIds.add(detailId);

        final quantity = (detail['quantity'] as num?)?.toDouble() ?? 0;
        final totalPrice = (detail['total_price'] as num?)?.toDouble() ?? 0;
        final scannedCount = scannedCountByDetailId[detailId] ?? 0;
        final isSplit = splitDetailIds.contains(detailId);

        final int koliCount;
        final double value;
        if (isSplit) {
          // Lanjutan fix (3 Oktober 2026, permintaan user): untuk resi
          // yang SUNGGUH terpecah ke beberapa kendaraan (mis. 100 koli,
          // 40 di antaranya dimuat ke kendaraan ini), `itemCount` =
          // jumlah fisik di KENDARAAN INI SAJA (40), BUKAN total koli
          // resi (100) -- tapi nilai tarifnya tetap proporsional dari
          // `total_price` SAAT INI (lihat [_detailIdsSplitAcrossShipments]),
          // supaya kalau harga satuan resi itu diubah admin (mis. dari
          // Rp10.000 jadi Rp20.000/koli -- total_price resi otomatis ikut
          // naik dari Rp1.000.000 ke Rp2.000.000), bagian kendaraan ini
          // IKUT NAIK proporsional (40/100 x Rp2.000.000 = Rp800.000,
          // bukan tetap Rp400.000) -- PDF cetak tampilkan "40 dari 100
          // koli" (lihat `totalQuantity` di bawah & pdf_templates.dart)
          // supaya jelas ini cuma sebagian dari total resi.
          final proration =
              quantity > 0 ? (scannedCount / quantity).clamp(0, 1) : 1.0;
          koliCount = scannedCount;
          value = totalPrice * proration;
        } else {
          koliCount = quantity.round();
          value = totalPrice;
        }

        grouped[receivingId]!['itemCount'] =
            (grouped[receivingId]!['itemCount'] as int) + koliCount;
        grouped[receivingId]!['totalQuantity'] =
            (grouped[receivingId]!['totalQuantity'] as int) + quantity.round();
        grouped[receivingId]!['totalValue'] =
            (grouped[receivingId]!['totalValue'] as double) + value;
      }
    }

    // FITUR (13 Oktober 2026 -- poin 7): tentukan per resi apakah
    // [shipmentId] berhak menampilkan nilai tagihan Bayar Tujuan --
    // lihat doc comment [_isLastLoadingShipmentBatch].
    //
    // PERBAIKAN PERFORMA (14 Oktober 2026 -- laporan user: preview PDF
    // lama baru termuat di layar): SEBELUMNYA dipanggil [_isLastLoadingShipment]
    // 1x PER RESI UNIK di dalam loop ini (sequential, N+1 query -- 2
    // query PER RESI), SEKARANG 1x BATCH query untuk SEMUA resi
    // sekaligus SEBELUM loop mulai, lihat doc comment
    // [_isLastLoadingShipmentBatch].
    final isLastByReceiving = await _isLastLoadingShipmentBatch(
      receivingIds: grouped.keys.toSet(),
      shipmentId: shipmentId,
    );

    final result = <Map<String, dynamic>>[];
    for (final entry in grouped.values) {
      final receivingId = entry['receivingId'] as String;

      final isLast = isLastByReceiving[receivingId] ?? false;

      final paymentStatus = entry['paymentStatus'] as String;
      final dpAmount = entry['dpAmount'] as double?;
      final receivingTotalPrice = entry['receivingTotalPrice'] as double;

      // Nilai tagihan Bayar Tujuan HANYA disisipkan kalau: (a) status
      // pembayarannya memang Bayar Tujuan (Bayar Dikantor tidak punya
      // "tagihan" tersisa di tujuan -- sudah/akan lunas di kantor), DAN
      // (b) ini pemuatan TERAKHIR resi ini (supaya tidak dobel-tampil
      // kalau resi terpecah ke beberapa kendaraan, lihat poin 7).
      final billingAmount =
          (isLast && paymentStatus == ReceivingPaymentStatus.bayarTujuan)
              ? (receivingTotalPrice - (dpAmount ?? 0)).clamp(0, double.infinity)
              : null;

      result.add({
        ...entry,
        'jenisTarifCount': pricingTypeIdsByReceiving[receivingId]?.length ?? 0,
        'isLastLoadingShipment': isLast,
        'billingAmount': billingAmount,
      });
    }

    result.sort(
      (a, b) => (a['receiptNumber']?.toString() ?? '')
          .compareTo(b['receiptNumber']?.toString() ?? ''),
    );

    return result;
  }

  /// Rekap untuk cetak "Tanda Terima Tujuan" -- DIGROUP PER TUJUAN (bukan
  /// per resi), lalu di dalam tiap tujuan disiapkan per baris (nama
  /// barang x resi) supaya bisa ditampilkan digroup per NAMA BARANG,
  /// dengan nomor resi masing-masing tetap kelihatan (1 baris = 1 resi x
  /// 1 nama barang dalam tujuan itu).
  ///
  /// DIUBAH (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
  /// "Daftar Muatan ... yang ditampilkan adalah Nama Barang dan
  /// jumlahnya. Bukan Jenis Tarif dan jumlahnya. Semua cetakan output
  /// printout mengikuti pola tersebut."). SEBELUMNYA grouping-nya per
  /// JENIS TARIF (1 baris = 1 resi x 1 jenis tarif) -- efek sampingnya,
  /// kalau 1 resi punya 2 barang beda nama tapi sama jenis tarifnya,
  /// jumlahnya ke-gabung jadi 1 baris "Jenis Tarif" yang tidak
  /// menyebutkan nama barangnya sama sekali. Sekarang per NAMA BARANG,
  /// konsisten dengan pola yang sudah berlaku di Resi & Manifest (lihat
  /// `PdfTemplates.itemDisplayLabel`): yang tampil ke pihak luar/tujuan
  /// adalah Nama Barang, bukan jenis tarif internal perusahaan.
  ///
  /// Tujuan dikelompokkan pakai `destination_id` kalau resi itu punya
  /// (dibuat setelah fitur "Daftar Langganan Tujuan"), fallback ke nama
  /// tujuan teks (`destination`) untuk resi lama yang belum punya
  /// destination_id -- supaya resi lama & baru ke tujuan yang sama tetap
  /// tergabung dalam 1 halaman tanda terima.
  ///
  /// Nilai per baris diprorata sama seperti [getManifestPrintSummary]
  /// (lihat catatan FIX di sana -- SAMA PERSIS dipakai di sini lewat
  /// [_detailIdsSplitAcrossShipments]).
  ///
  /// Baris `shipment_scans` yang linknya ke `receiving_details` tidak
  /// ketemu DI-SKIP dari rekap ini -- lihat catatan sama di
  /// [getManifestPrintSummary] (SENGAJA, bukan diakali jadi baris PDF).
  ///
  /// --- FIX "Harga Satuan" (bug report 3 Oktober 2026, lanjutan) ---
  /// SEBELUMNYA "harga satuan" yang ditampilkan DIHITUNG BALIK lewat
  /// pembagian `totalValue / itemCount` -- niatnya supaya tetap "pas"
  /// kalau admin override total harga lewat `_totalPriceOverrideController`
  /// (lihat `receiving_detail_form_sheet.dart`), TAPI pembagian ini
  /// gampang menghasilkan angka ganjil/tidak bulat (mis. Rp400.000 / 3
  /// koli = Rp133.333) begitu `total_price` yang di-override TIDAK
  /// habis dibagi `itemCount` -- laporan user: "jangan pakai pembagian,
  /// kalau diedit di total harga, nolkan saja harga satuannya".
  ///
  /// Sekarang per receiving_detail dicek: apakah `total_price`-nya
  /// COCOK dengan `quantity x bundle_quantity x unit_price` (toleransi
  /// 0.5 rupiah, sama seperti pengecekan serupa di
  /// `receiving_detail_form_sheet.dart`)? Kalau TIDAK cocok (berarti
  /// admin override total secara manual), "harga satuan" detail itu =
  /// 0 (bukan hasil bagi apa pun). Kalau cocok (kasus normal, harga
  /// dihitung dari quantity x harga satuan seperti biasa), tampilkan
  /// `unit_price` MENTAH dari `receiving_details` apa adanya (tanpa
  /// pembagian sama sekali). Kalau 1 baris (rowKey) kebetulan gabungan
  /// dari >1 `receiving_detail` dengan harga satuan BEDA-BEDA, tidak ada
  /// satu angka yang bisa mewakili tanpa pembagian/rata-rata -- tampilkan
  /// 0 juga di kasus ini (lebih jujur daripada angka blended yang bisa
  /// menyesatkan).
  ///
  /// `totalDiscount` (per baris & per tujuan, 8 Oktober 2026, lanjutan
  /// lagi -- permintaan user eksplisit: "Pada cetakan Tanda Terima
  /// Tujuan, Cantumkan harga diskon") -- akumulasi `discount_amount`
  /// (lihat `ReceivingDetailModel.discountAmount`), diprorata SAMA
  /// PERSIS seperti `totalValue`/`itemCount` kalau detailnya genuinely
  /// terpecah ke beberapa shipment. MURNI untuk DITAMPILKAN sebagai
  /// informasi (baris "Diskon" di tabel) -- `totalValue` SENDIRI sudah
  /// net (dihitung dari `total_price` yang sudah dikurangi diskon),
  /// jadi `totalDiscount` TIDAK dikurangkan lagi dari `totalValue` di
  /// sini atau di `PdfTemplates`, cukup ditampilkan berdampingan.
  static Future<List<Map<String, dynamic>>> getManifestSummaryByDestination(
    String shipmentId,
  ) async {
    final rows = await _getLoadScansWithDetails(shipmentId);

    final scannedCountByDetailId = <String, int>{};
    for (final row in rows) {
      final detailId = row['receiving_detail_id'] as String?;
      if (detailId == null) continue;
      scannedCountByDetailId[detailId] =
          (scannedCountByDetailId[detailId] ?? 0) + 1;
    }

    final splitDetailIds = await _detailIdsSplitAcrossShipments(
      scannedCountByDetailId.keys.toList(),
    );

    // destinationKey -> info tujuan (nama, alamat, total)
    final destinations = <String, Map<String, dynamic>>{};
    // destinationKey -> rowKey ("itemName|receivingId") -> baris --
    // DIUBAH (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
    // "Daftar Muatan ... yang ditampilkan adalah Nama Barang dan
    // jumlahnya. Bukan Jenis Tarif dan jumlahnya. Semua cetakan output
    // printout mengikuti pola tersebut.") dari SEBELUMNYA
    // "pricingTypeId|receivingId" -- supaya 1 baris Tanda Terima Tujuan
    // = 1 NAMA BARANG dalam 1 resi (bukan 1 jenis tarif dalam 1 resi).
    // Efeknya: kalau 1 resi punya 2 barang BEDA NAMA tapi kebetulan sama
    // jenis tarifnya, SEKARANG tetap tampil 2 baris terpisah (dulu
    // ke-gabung jadi 1 baris "Jenis Tarif" yang menyembunyikan nama
    // barangnya) -- lebih jelas buat pihak tujuan yang terima barang.
    final rowsByDestination = <String, Map<String, Map<String, dynamic>>>{};
    final countedDetailIds = <String>{};

    for (final row in rows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final detailId = detail['id'] as String?;
      final receivingId = detail['receiving_id'] as String?;
      if (detailId == null || receivingId == null) continue;

      final receiving = detail['receiving'] as Map<String, dynamic>?;
      final destinationId = receiving?['destination_id'] as String?;
      final destinationName = receiving?['destination']?.toString() ?? '-';
      final destinationKey = destinationId ?? 'name:$destinationName';

      destinations.putIfAbsent(
        destinationKey,
        () => {
          'destinationName': destinationName,
          'destinationAddress': receiving?['destination_address'],
          'destinationPhone': _liveDestinationPhone(receiving),
          'totalValue': 0.0,
          'totalDiscount': 0.0,
        },
      );
      rowsByDestination.putIfAbsent(destinationKey, () => {});

      // DIUBAH (8 Oktober 2026, lanjutan lagi -- lihat catatan di
      // deklarasi `rowsByDestination` di atas): grouping key SEKARANG
      // nama barang, BUKAN jenis tarif lagi.
      final itemName = detail['item_name']?.toString() ?? '-';
      final quantityUnit = detail['quantity_unit']?.toString() ?? '';
      final rowKey = '$itemName|$receivingId';

      rowsByDestination[destinationKey]!.putIfAbsent(
        rowKey,
        () => {
          'itemName': itemName,
          'quantityUnit': quantityUnit,
          'receivingId': receivingId,
          'receiptNumber': receiving?['receipt_number'],
          // FITUR (8 Oktober 2026 -- poin 7): nomor buku, disisipkan di
          // belakang nomor resi di cetakan Tanda Terima Tujuan kalau ada.
          'nomorBuku': receiving?['nomor_buku'],
          // FITUR (13 Oktober 2026 -- poin 2-7, status pembayaran & DP):
          // dipakai `PdfTemplates._destinationReceiptRow` untuk mengisi
          // kolom Keterangan baru. 'isLastLoadingShipment'/'billingAmount'
          // disisipkan belakangan di bawah (lihat loop hasil akhir).
          'paymentStatus': receiving?['payment_status'] as String? ??
              ReceivingPaymentStatus.bayarTujuan,
          'dpAmount': (receiving?['dp_amount'] as num?)?.toDouble(),
          'receivingTotalPrice': (receiving?['total_price'] as num?)?.toDouble() ?? 0,
          'itemCount': 0,
          // 'totalQuantity' (lanjutan fix 3 Oktober 2026): total koli
          // ASLI resi ini, beda dari `itemCount` KALAU resi ini
          // genuinely terpecah ke beberapa kendaraan -- lihat catatan
          // panjang di [getManifestPrintSummary].
          'totalQuantity': 0,
          'totalValue': 0.0,
          // 'totalDiscount' (8 Oktober 2026, lanjutan lagi -- "Pada
          // cetakan Tanda Terima Tujuan, Cantumkan harga diskon"):
          // akumulasi `discount_amount` tiap receiving_detail yang
          // tergabung di baris ini, DIPRORATA sama seperti `totalValue`
          // kalau detailnya genuinely terpecah ke beberapa shipment --
          // lihat catatan proration di bawah. `totalValue` SENDIRI tetap
          // net (sudah dikurangi diskon, karena `total_price` tersimpan
          // sudah net) -- field ini MURNI untuk DITAMPILKAN sebagai
          // baris "Diskon" sendiri di cetakan, bukan dikurangkan lagi.
          'totalDiscount': 0.0,
          // '_unitPriceCandidate'/'_unitPriceMixed' (fix "Harga Satuan"
          // 3 Oktober 2026): dipakai sementara buat tentukan "harga
          // satuan" baris ini TANPA pembagian -- lihat catatan panjang
          // di doc comment method ini. Diubah jadi 'unitPrice' final di
          // langkah terakhir, 2 field ini TIDAK ikut ke hasil akhir.
          '_unitPriceCandidate': null,
          '_unitPriceMixed': false,
        },
      );

      // Jumlah koli & nilai tarif per receiving_detail HANYA dihitung
      // SEKALI (bukan diulang tiap baris scan unit) -- lihat catatan FIX
      // (bug report 3 Oktober 2026) di doc comment
      // [getManifestPrintSummary] soal kapan diprorata vs kapan percaya
      // langsung quantity/total_price saat ini, termasuk soal
      // `totalQuantity` untuk tampilan "40 dari 100 koli" di cetakan.
      if (!countedDetailIds.contains(detailId)) {
        countedDetailIds.add(detailId);

        final quantity = (detail['quantity'] as num?)?.toDouble() ?? 0;
        final totalPrice = (detail['total_price'] as num?)?.toDouble() ?? 0;
        final unitPriceRaw = (detail['unit_price'] as num?)?.toDouble() ?? 0;
        final bundleQuantity = (detail['bundle_quantity'] as num?)?.toInt() ?? 1;
        // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang).
        final discountAmount = (detail['discount_amount'] as num?)?.toDouble() ?? 0;
        final scannedCount = scannedCountByDetailId[detailId] ?? 0;
        final isSplit = splitDetailIds.contains(detailId);

        final int koliCount;
        final double value;
        final double discountValue;
        if (isSplit) {
          final proration =
              quantity > 0 ? (scannedCount / quantity).clamp(0, 1) : 1.0;
          koliCount = scannedCount;
          value = totalPrice * proration;
          discountValue = discountAmount * proration;
        } else {
          koliCount = quantity.round();
          value = totalPrice;
          discountValue = discountAmount;
        }

        // "Harga satuan" TANPA pembagian -- lihat catatan FIX di doc
        // comment method ini. `total_price` COCOK dengan quantity x
        // bundle x unit_price DIKURANGI diskon (toleransi 0.5 rupiah,
        // pola yang sama dipakai `receiving_detail_form_sheet.dart` buat
        // cek override -- `discountAmount` WAJIB ikut dikurangkan di
        // sini juga, 8 Oktober 2026 lanjutan lagi, supaya barang yang
        // cuma kena diskon TIDAK salah terdeteksi sebagai "di-override
        // admin") -> pakai unit_price mentah. TIDAK cocok (SUNGGUH
        // di-override admin) -> 0, bukan hasil bagi.
        final computedFromUnitPrice =
            quantity * bundleQuantity * unitPriceRaw - discountAmount;
        final isPriceOverridden = (totalPrice - computedFromUnitPrice).abs() > 0.5;
        final detailUnitPriceDisplay = isPriceOverridden ? 0.0 : unitPriceRaw;

        final line = rowsByDestination[destinationKey]![rowKey]!;
        line['itemCount'] = (line['itemCount'] as int) + koliCount;
        line['totalQuantity'] = (line['totalQuantity'] as int) + quantity.round();
        line['totalValue'] = (line['totalValue'] as double) + value;
        line['totalDiscount'] = (line['totalDiscount'] as double) + discountValue;

        final existingUnitPrice = line['_unitPriceCandidate'] as double?;
        if (existingUnitPrice == null) {
          line['_unitPriceCandidate'] = detailUnitPriceDisplay;
        } else if ((existingUnitPrice - detailUnitPriceDisplay).abs() > 0.5) {
          // >1 receiving_detail digabung di baris yang sama tapi harga
          // satuannya beda-beda -- tidak ada 1 angka yang jujur mewakili
          // tanpa pembagian/rata-rata, tandai "mixed" supaya ditampilkan
          // 0 (lihat langkah final di bawah).
          line['_unitPriceMixed'] = true;
        }

        destinations[destinationKey]!['totalValue'] =
            (destinations[destinationKey]!['totalValue'] as double) + value;
        destinations[destinationKey]!['totalDiscount'] =
            (destinations[destinationKey]!['totalDiscount'] as double) + discountValue;
      }
    }

    final result = <Map<String, dynamic>>[];

    // PERBAIKAN PERFORMA (14 Oktober 2026 -- laporan user: preview
    // Tanda Terima Tujuan lama baru termuat di layar): SEBELUMNYA
    // dipanggil [_isLastLoadingShipment] 1x PER RESI UNIK di dalam
    // loop di bawah (sequential, 2 query PER RESI), SEKARANG 1x BATCH
    // query untuk SEMUA resi sekaligus SEBELUM loop mulai, lihat doc
    // comment [_isLastLoadingShipmentBatch].
    final allReceivingIds = <String>{
      for (final lines in rowsByDestination.values)
        for (final line in lines.values) line['receivingId'] as String,
    };
    final isLastByReceiving = await _isLastLoadingShipmentBatch(
      receivingIds: allReceivingIds,
      shipmentId: shipmentId,
    );

    for (final entry in destinations.entries) {
      final destinationKey = entry.key;
      final destinationInfo = entry.value;

      final lineRows = <Map<String, dynamic>>[];
      for (final line in rowsByDestination[destinationKey]!.values) {
        final isMixed = line['_unitPriceMixed'] as bool;
        final candidate = line['_unitPriceCandidate'] as double?;
        // Tidak ada pembagian sama sekali di sini -- lihat catatan FIX
        // "Harga Satuan" di doc comment method ini.
        final unitPrice = isMixed ? 0.0 : (candidate ?? 0.0);

        final cleanedLine = Map<String, dynamic>.from(line)
          ..remove('_unitPriceCandidate')
          ..remove('_unitPriceMixed');

        final receivingId = line['receivingId'] as String;
        final isLast = isLastByReceiving[receivingId] ?? false;

        final paymentStatus = line['paymentStatus'] as String;
        final dpAmount = line['dpAmount'] as double?;
        final receivingTotalPrice = line['receivingTotalPrice'] as double;

        final billingAmount =
            (isLast && paymentStatus == ReceivingPaymentStatus.bayarTujuan)
                ? (receivingTotalPrice - (dpAmount ?? 0)).clamp(0, double.infinity)
                : null;

        lineRows.add({
          ...cleanedLine,
          'unitPrice': unitPrice,
          'isLastLoadingShipment': isLast,
          'billingAmount': billingAmount,
        });
      }

      result.add({
        'destinationKey': destinationKey,
        'destinationName': destinationInfo['destinationName'],
        'destinationAddress': destinationInfo['destinationAddress'],
        'destinationPhone': destinationInfo['destinationPhone'],
        'totalValue': destinationInfo['totalValue'],
        'totalDiscount': destinationInfo['totalDiscount'],
        'rows': lineRows,
      });
    }

    result.sort(
      (a, b) => (a['destinationName']?.toString() ?? '')
          .compareTo(b['destinationName']?.toString() ?? ''),
    );

    return result;
  }

  /// FITUR (16 Oktober 2026 -- Dashboard Supervisor, Tab "Monitoring
  /// Pemuatan & Penyelesaian"): select-nya DIPERLUAS (scanned_by di level
  /// scan; quantity/quantity_unit di receiving_details; nomor_buku/
  /// sender_id/received_at/updated_at/updated_by di receiving) supaya
  /// halaman detail barang read-only Supervisor bisa menampilkan 12 field
  /// kelengkapan informasi TANPA query tambahan per baris. Pemanggil lama
  /// (`ManifestPage`) tidak terpengaruh -- field yang sudah dipakainya
  /// tetap ada, field baru cuma ditambahkan di map hasil.
  static Future<List<Map<String, dynamic>>> getShipmentScanFeed(
    String shipmentId, {
    String scanType = 'LOAD',
  }) async {
    final response = await _client
        .from('shipment_scans')
        .select('''
          id,
          unit_code,
          unit_index,
          scan_type,
          scanned_at,
          scanned_by,
          latitude,
          longitude,
          receiving_details (
            id,
            item_code,
            item_name,
            quantity,
            quantity_unit,
            pricing_type_id,
            receiving_id,
            receiving:receiving_id (
              receipt_number,
              nomor_buku,
              destination,
              destination_address,
              sender_id,
              received_at,
              updated_at,
              updated_by
            )
          )
        ''')
        .eq('shipment_id', shipmentId)
        .eq('scan_type', scanType)
        .order('scanned_at', ascending: false);

    return (response as List)
        .map((data) => Map<String, dynamic>.from(data))
        .toList();
  }

  /// Manifest shipment ini dikelompokkan per resi (receiving), lengkap
  /// dengan progress berapa barang yang sudah diturunkan (DELIVER) dari
  /// total barang resi itu yang dimuat (LOAD). Dipakai di
  /// DeliveryManifestPage -- karena 1 manifest bisa berisi beberapa resi
  /// tujuan berbeda, driver/helper harus pilih 1 resi dulu sebelum scan
  /// turun, supaya barang antar-tujuan tidak tertukar.
  static Future<List<Map<String, dynamic>>> getManifestGroupedByReceiving(
    String shipmentId,
  ) async {
    final loadRows = await _client
        .from('shipment_scans')
        .select('''
          id,
          receiving_detail_id,
          receiving_details (
            id,
            receiving_id,
            receiving:receiving_id (
              receipt_number,
              destination,
              destination_address,
              destination_id,
              destination_phone,
              destinations:destination_id (
                phone
              )
            )
          )
        ''')
        .eq('shipment_id', shipmentId)
        .eq('scan_type', 'LOAD');

    final deliverRows = await _client
        .from('shipment_scans')
        .select('receiving_detail_id')
        .eq('shipment_id', shipmentId)
        .eq('scan_type', 'DELIVER');

    final deliveredDetailIds = (deliverRows as List)
        .map((row) => row['receiving_detail_id'] as String?)
        .whereType<String>()
        .toSet();

    final grouped = <String, Map<String, dynamic>>{};

    for (final row in (loadRows as List)) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      if (receivingId == null) continue;

      final receiving = detail['receiving'] as Map<String, dynamic>?;
      final detailId = detail['id'] as String?;

      grouped.putIfAbsent(
        receivingId,
        () => {
          'receivingId': receivingId,
          'receiptNumber': receiving?['receipt_number'],
          'destination': receiving?['destination'],
          'destinationAddress': receiving?['destination_address'],
          // Nomor HP tujuan LIVE dari tabel `destinations` (sama seperti
          // `_liveDestinationPhone` dipakai di tempat lain) -- ditambah
          // 6 Oktober 2026 lanjutan supaya `RepresentativeHandoffPage`
          // (mode "Per Resi") bisa langsung kirim WA otomatis ke tujuan
          // tanpa query terpisah.
          'destinationPhone': _liveDestinationPhone(receiving),
          'totalItems': 0,
          'deliveredItems': 0,
        },
      );

      grouped[receivingId]!['totalItems'] =
          (grouped[receivingId]!['totalItems'] as int) + 1;

      if (detailId != null && deliveredDetailIds.contains(detailId)) {
        grouped[receivingId]!['deliveredItems'] =
            (grouped[receivingId]!['deliveredItems'] as int) + 1;
      }
    }

    return grouped.values.toList();
  }

  /// Manifest shipment ini dikelompokkan PER TUJUAN (bukan per resi) --
  /// pengelompokan SAMA PERSIS dengan [getManifestSummaryByDestination]
  /// (dipakai PDF "Tanda Terima Tujuan": `destination_id` kalau resi punya,
  /// fallback nama tujuan teks untuk resi lama) -- supaya satu tujuan yang
  /// dikirim dari beberapa resi berbeda tetap tergabung jadi satu baris.
  /// Versi ini LEBIH RINGAN dari versi PDF (tidak menghitung nilai tarif),
  /// khusus dipakai "Intervensi Admin: Selesaikan Per Tujuan" (lihat
  /// [forceCompleteDestinationByAdmin]) supaya admin bisa lihat & pilih
  /// tujuan mana yang mau "disusulkan" status sudah-discan-turunnya.
  ///
  /// Beda dari `getManifestGroupedByReceiving` soal cara hitung
  /// `deliveredItems`: di sini dihitung per UNIT FISIK (`unit_code`,
  /// sesuai baris DELIVER yang benar-benar ada), BUKAN per
  /// `receiving_detail_id` (yang di versi lama bisa "kebawa lunas" kalau
  /// baru SEBAGIAN unit dalam 1 baris detail yang ke-scan) -- supaya
  /// progress yang ditampilkan ke admin akurat sampai ke unit.
  ///
  /// Tiap baris hasil: `destinationKey`, `destinationName`,
  /// `destinationAddress`, `destinationPhone`, `receivingIds` (List<String>,
  /// semua resi yang tergabung di tujuan ini -- dipakai langsung sebagai
  /// input `forceCompleteDestinationByAdmin`), `totalItems`,
  /// `deliveredItems`.
  static Future<List<Map<String, dynamic>>> getManifestGroupedByDestination(
    String shipmentId,
  ) async {
    final loadRows = await _getLoadScansWithDetails(shipmentId);
    final deliverRows =
        await getShipmentScanFeed(shipmentId, scanType: 'DELIVER');

    final deliveredUnitCodes = deliverRows
        .map((row) => row['unit_code']?.toString())
        .whereType<String>()
        .toSet();

    final destinations = <String, Map<String, dynamic>>{};

    for (final row in loadRows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      if (receivingId == null) continue;

      final receiving = detail['receiving'] as Map<String, dynamic>?;
      final destinationId = receiving?['destination_id'] as String?;
      final destinationName = receiving?['destination']?.toString() ?? '-';
      final destinationKey = destinationId ?? 'name:$destinationName';

      final entry = destinations.putIfAbsent(
        destinationKey,
        () => {
          'destinationKey': destinationKey,
          'destinationName': destinationName,
          'destinationAddress': receiving?['destination_address'],
          'destinationPhone': _liveDestinationPhone(receiving),
          'receivingIds': <String>{},
          'totalItems': 0,
          'deliveredItems': 0,
        },
      );

      (entry['receivingIds'] as Set<String>).add(receivingId);
      entry['totalItems'] = (entry['totalItems'] as int) + 1;

      final unitCode = row['unit_code']?.toString();
      if (unitCode != null && deliveredUnitCodes.contains(unitCode)) {
        entry['deliveredItems'] = (entry['deliveredItems'] as int) + 1;
      }
    }

    final result = destinations.values.map((entry) {
      return {
        ...entry,
        'receivingIds': (entry['receivingIds'] as Set<String>).toList(),
      };
    }).toList();

    result.sort(
      (a, b) => (a['destinationName']?.toString() ?? '')
          .compareTo(b['destinationName']?.toString() ?? ''),
    );

    return result;
  }

  /// "Intervensi Admin: Selesaikan Per Tujuan" -- permintaan eksplisit user
  /// (23 September 2026), BEDA dari [forceCompleteByAdmin] (yang memaksa
  /// SELURUH manifest/shipment selesai -- dipakai kalau sopir BENAR-BENAR
  /// tidak bisa pakai aplikasinya sama sekali, HP rusak/hilang/dsb).
  ///
  /// Skenario ini LEBIH SEMPIT: sopir sebenarnya masih bisa pakai aplikasi
  /// & sudah menurunkan barang secara fisik dengan benar, TAPI LUPA scan
  /// turun (DELIVER) untuk satu/beberapa TUJUAN tertentu saja. Admin bisa
  /// "menyusulkan" status sudah-discan HANYA untuk tujuan itu (dipilih dari
  /// [getManifestGroupedByDestination], bisa gabungan beberapa resi kalau
  /// tujuan itu dikirim dari beberapa resi berbeda -- SAMA PERSIS
  /// pengelompokan "Tanda Terima Tujuan"), TANPA memaksa seluruh
  /// perjalanan selesai (status shipment TIDAK diubah sama sekali di
  /// sini) -- kendaraan/shipment tetap jalan normal untuk tujuan-tujuan
  /// lain yang belum sampai.
  ///
  /// Efeknya: untuk setiap unit barang yang sudah tercatat LOAD ke
  /// [shipmentId] dan termasuk salah satu resi di [receivingIds], TAPI
  /// belum ada scan DELIVER-nya sama sekali, dibuatkan scan DELIVER baru
  /// lewat [recordScan] yang SAMA PERSIS dipakai scan manual sopir/helper
  /// (supaya format datanya identik, termasuk pemicu constraint unique
  /// yang sama) -- bedanya cuma kolom `notes` diisi "Intervensi Admin:
  /// <note>" sebagai jejak audit. SENGAJA pakai kolom `notes` yang memang
  /// sudah ada di `shipment_scans` (bukan bikin kolom baru seperti
  /// `completed_by_admin` di tabel `shipments`) supaya tidak perlu migrasi
  /// skema database.
  ///
  /// Unit yang SUDAH ada DELIVER-nya (unit_code sudah match, entah dari
  /// sopir asli atau pemanggilan sebelumnya) DILEWATI -- idempotent, aman
  /// dipanggil ulang. Mengembalikan jumlah unit yang berhasil ditambahkan.
  static Future<int> forceCompleteDestinationByAdmin({
    required String shipmentId,
    required List<String> receivingIds,
    required String scannedBy,
    required String note,
  }) async {
    if (receivingIds.isEmpty) return 0;

    final receivingIdSet = receivingIds.toSet();

    final loadRows = await _getLoadScansWithDetails(shipmentId);
    final deliverRows =
        await getShipmentScanFeed(shipmentId, scanType: 'DELIVER');

    final deliveredUnitCodes = deliverRows
        .map((row) => row['unit_code']?.toString())
        .whereType<String>()
        .toSet();

    var created = 0;

    for (final row in loadRows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      final detailId = detail['id'] as String?;
      if (receivingId == null || detailId == null) continue;
      if (!receivingIdSet.contains(receivingId)) continue;

      final unitCode = row['unit_code']?.toString();
      final unitIndex = row['unit_index'] as int?;
      if (unitCode == null || unitIndex == null) continue;
      if (deliveredUnitCodes.contains(unitCode)) continue;

      try {
        await recordScan(
          shipmentId: shipmentId,
          receivingDetailId: detailId,
          unitCode: unitCode,
          unitIndex: unitIndex,
          scannedBy: scannedBy,
          scanType: 'DELIVER',
          notes: 'Intervensi Admin: $note',
        );
        created++;
      } on DuplicateScanException {
        // Sudah keburu tercatat (race condition/scan lain barusan
        // masuk) -- bukan error, lewati saja.
        continue;
      }
    }

    return created;
  }

  // ============================================================
  // BYPASS ADMIN: SELESAIKAN RESI (TANPA LOADING) -- 10 Oktober 2026
  // ============================================================
  // Permintaan user eksplisit: "pada admin Monitoring Resi ... tambahkan
  // tombol disetiap resi: Selesaikan. Dan meskipun resi itu belum
  // diload. Bisa dipass agar selesai." -- dipakai admin untuk simulasi
  // awal: resi yang di dunia nyata TIDAK benar-benar dimuat & diantar,
  // tapi perlu ditandai "Selesai" di halaman Monitoring Resi
  // (`ReceivingListPage`) supaya tidak nyangkut selamanya di status
  // "Penerimaan"/"Masih Perjalanan".

  /// Memaksa SEMUA barang di resi [receivingId] tercatat SUDAH dimuat
  /// (LOAD) & SUDAH turun di tujuan (DELIVER) -- TANPA PEDULI apakah
  /// resi ini pernah tersentuh Loading sama sekali. BEDA dari
  /// [forceCompleteDestinationByAdmin] (yang itu mengasumsikan barang
  /// SUDAH ter-LOAD ke shipment tertentu, admin cuma menyusulkan
  /// DELIVER yang ketinggalan) -- method ini bisa dipanggil dari status
  /// APA PUN, termasuk resi yang badge-nya masih "Penerimaan" (belum
  /// ada LOAD sama sekali).
  ///
  /// Unit yang SUDAH punya scan LOAD/DELIVER (entah dari proses Loading
  /// asli, ATAUPUN dari pemanggilan sebelumnya) DILEWATI masing-masing
  /// secara independen -- idempotent & aman dipanggil berkali-kali,
  /// juga aman untuk resi yang SEBAGIAN sudah benar-benar dimuat (cuma
  /// sisanya yang di-bypass).
  ///
  /// Unit yang baru dibuat di sini ditautkan ke SATU shipment
  /// placeholder milik kendaraan "BYPASS-SIMULASI"
  /// (`VehicleService.getOrCreateBypassVehicle`), berstatus ARRIVED
  /// sejak awal (TIDAK pernah muncul sebagai "sedang dimuat" di mana
  /// pun) -- jejak audit `completed_by_admin = true` +
  /// `admin_completion_note` SAMA PERSIS pola [forceCompleteByAdmin].
  /// Shipment placeholder ini HANYA dibuat kalau memang ada unit yang
  /// perlu dibuat (resi yang sudah 100% lengkap tidak membuat shipment
  /// placeholder baru yang kosong).
  ///
  /// Mengembalikan jumlah baris `receiving_details` yang BARU ditandai
  /// selesai -- 0 artinya resi ini sudah lengkap sebelum tombol ditekan.
  ///
  /// **REDESAIN ARSITEKTUR TOTAL (17 Oktober 2026, permintaan user
  /// eksplisit setelah kasus RESI000311 & regresi paginasi)**: versi
  /// SEBELUMNYA method ini membuat baris `shipment_scans` LOAD+DELIVER
  /// SINTETIS untuk tiap unit fisik yang belum lengkap, ditautkan ke 1
  /// shipment placeholder bersama "DISELESAIKAN ADMIN" -- pendekatan itu
  /// yang (bersama proses Loading normal) membuat tabel `shipment_scans`
  /// membengkak sampai >1800 baris HANYA untuk shipment placeholder itu
  /// sendiri, salah satu pemicu bug skala/paginasi di
  /// [getAvailableItemsForManualLoad]. User menegaskan: "jadi jika
  /// diintervensi maka hanya mengupdate kolom tersebut" -- jadi SEKARANG
  /// method ini **TIDAK PERNAH LAGI** menulis apa pun ke
  /// `shipment_scans` -- cukup update `flow_state` & `sisa_barang`
  /// LANGSUNG di `receiving_details` ke status tuntas (`SELESAI`/`0`).
  ///
  /// Shipment placeholder "DISELESAIKAN ADMIN" & riwayat scan sintetis
  /// LAMA (sebelum migrasi ini) TETAP dibiarkan ada di database apa
  /// adanya (tidak dihapus) -- sudah diikutkan ke BACKFILL 1x di
  /// `migrasi_flow_state_sisa_barang.sql`, jadi tidak perlu lagi
  /// baris baru dibuat lewat jalur ini.
  static Future<int> forceCompleteReceivingByAdmin({
    required String receivingId,
    required String adminEmployeeId,
    required String note,
  }) async {
    final detailRows = await _client
        .from('receiving_details')
        .select('id, quantity, is_unlabeled, flow_state')
        .eq('receiving_id', receivingId);

    final details = (detailRows as List)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();

    if (details.isEmpty) return 0;

    final toFinish =
        details.where((d) => d['flow_state'] != 'SELESAI').toList();

    if (toFinish.isEmpty) return 0;

    // Loop per-baris (BUKAN 1 batch update) karena `selesai_barang` =
    // total unit fisik baris itu SENDIRI (beda-beda tiap baris, lihat
    // [_physicalUnitCodes]) -- wajar/cepat untuk jumlah barang 1 resi
    // (biasanya belasan baris, bukan ribuan).
    for (final detail in toFinish) {
      final total = _physicalUnitCodes(detail).length;
      await _client.from('receiving_details').update({
        'flow_state': 'SELESAI',
        'sisa_barang': 0,
        'selesai_barang': total,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', detail['id'] as String);
    }

    return toFinish.length;
  }

  /// BUGFIX (16 Oktober 2026 -- laporan user: "Setiap kali selesaikan resi
  /// diklik, ternyata menambah shipment baru?"): [forceCompleteReceivingByAdmin]
  /// SEBELUMNYA langsung `insert` baris baru ke tabel `shipments` SETIAP
  /// kali dipanggil -- padahal doc comment method itu SENDIRI sudah bilang
  /// "ditautkan ke SATU shipment placeholder" (tunggal). Akibatnya tiap
  /// resi BEDA yang di-"Selesaikan" (bypass) bikin baris shipment BARU
  /// terus-menerus (walau semuanya pakai kendaraan placeholder
  /// `BYPASS-SIMULASI` yang SAMA, lewat [VehicleService.
  /// getOrCreateBypassVehicle] yang MEMANG sudah benar reuse-nya) --
  /// mencemari daftar Shipment/Riwayat dengan banyak shipment "kosong"
  /// yang sebenarnya cuma penampung administratif.
  ///
  /// Diperbaiki pakai pola get-or-create YANG SAMA dengan
  /// [VehicleService.getOrCreateBypassVehicle] (dicari dulu lewat
  /// `vehicle_id` sebelum insert) -- kendaraan placeholder ini HANYA
  /// dipakai method ini, jadi AMAN mengasumsikan shipment PERTAMA yang
  /// ditemukan dengan `vehicle_id` itu adalah placeholder yang dimaksud.
  /// Sekarang SEMUA pemanggilan "Selesaikan Resi" (resi apa pun, kapan
  /// pun) menumpuk scan LOAD/DELIVER ke SATU shipment placeholder yang
  /// sama -- persis seperti niat awal di doc comment
  /// [forceCompleteReceivingByAdmin]. Catatan (`admin_completion_note`)
  /// shipment placeholder ini HANYA diisi SEKALI saat pertama kali dibuat
  /// (generik, bukan alasan 1 resi tertentu) -- alasan PER RESI tetap
  /// lengkap tercatat di `notes` tiap baris `shipment_scans`-nya masing-
  /// masing (lihat `recordScan` di bawah, parameter `notes`).
  static Future<String> _getOrCreateBypassShipment({
    required String bypassVehicleId,
    required String adminEmployeeId,
  }) async {
    final existing = await _client
        .from('shipments')
        .select('id')
        .eq('vehicle_id', bypassVehicleId)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    final response = await _client
        .from('shipments')
        .insert({
          'vehicle_id': bypassVehicleId,
          'status': 'ARRIVED',
          'loaded_by': adminEmployeeId,
          'loaded_at': DateTime.now().toIso8601String(),
          'arrived_at': DateTime.now().toIso8601String(),
          'completed_by_admin': true,
          'admin_completion_note':
              'Placeholder bypass admin (Monitoring Resi > Selesaikan) -- '
              'alasan tiap resi ada di catatan masing-masing scan, bukan di sini.',
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  /// Titik-titik tujuan (dari resi-resi yang ada di manifest shipment ini),
  /// dideduplikasi per resi -- dipakai buat gambar peta rute di DriverHomePage.
  static Future<List<Map<String, dynamic>>> getShipmentDestinationPoints(
    String shipmentId,
  ) async {
    final response = await _client
        .from('shipment_scans')
        .select('''
          receiving_details (
            receiving_id,
            receiving:receiving_id (
              destination,
              destination_address,
              destination_latitude,
              destination_longitude
            )
          )
        ''')
        .eq('shipment_id', shipmentId)
        .eq('scan_type', 'LOAD');

    final rows =
        (response as List).map((d) => Map<String, dynamic>.from(d)).toList();

    final seen = <String>{};
    final points = <Map<String, dynamic>>[];

    for (final row in rows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      if (receivingId == null || seen.contains(receivingId)) continue;
      seen.add(receivingId);

      final receiving = detail['receiving'] as Map<String, dynamic>?;
      if (receiving == null) continue;

      points.add({
        'receiving_id': receivingId,
        'destination': receiving['destination'],
        'destination_address': receiving['destination_address'],
        'latitude': receiving['destination_latitude'],
        'longitude': receiving['destination_longitude'],
      });
    }

    return points;
  }

  /// Cek apakah [unitCode] memang sudah tercatat NAIK (scan_type LOAD) di
  /// shipment [shipmentId] ini secara spesifik.
  ///
  /// KENAPA INI PERLU: satu resi bisa saja dimuat terpecah ke BEBERAPA
  /// kendaraan sekaligus (mis. resi "15 kubik bata ringan" dimuat 2 truk,
  /// masing-masing 7,5 kubik/7-8 label) -- itu SUDAH didukung otomatis
  /// dari sisi data (tiap label barang punya `unit_code` sendiri-sendiri,
  /// jadi bisa discan LOAD ke shipment manapun tanpa bentrok). TAPI di
  /// sisi TURUN barang, `DeliveryResiScanPage` sebelumnya cuma mengecek
  /// "barang ini milik resi yang benar?" -- TIDAK mengecek "barang ini
  /// memang dimuat di KENDARAAN INI?". Akibatnya driver/helper truk A
  /// bisa saja tanpa sengaja scan-turun label barang yang sebenarnya
  /// dimuat di truk B (resi sama, kendaraan beda) -- tercatat "turun" di
  /// shipment yang salah, membingungkan rekap manifest kedua truk.
  /// Dipanggil dari `DeliveryResiScanPage` sebelum menerima scan DELIVER.
  static Future<bool> isUnitLoadedOnShipment({
    required String shipmentId,
    required String unitCode,
  }) async {
    final response = await _client
        .from('shipment_scans')
        .select('id')
        .eq('shipment_id', shipmentId)
        .eq('unit_code', unitCode)
        .eq('scan_type', 'LOAD')
        .maybeSingle();

    return response != null;
  }

  /// Format unit_code SINTETIS untuk item "Tanpa Label QR" (permintaan
  /// eksplisit user, 23 September 2026 -- barang yang benar-benar tidak
  /// bisa dilabeli, mis. bata ringan curah 10 kubik). Dipakai
  /// `LoadingScanPage`/`DeliveryResiScanPage` saat staff menekan tombol
  /// manual "Tandai Sudah Dimuat/Diturunkan" (BUKAN hasil scan kamera)
  /// untuk `ReceivingDetailModel` yang `isUnlabeled == true`.
  ///
  /// Deterministik per [receivingDetailId] -- 1 item tanpa label = SELALU
  /// 1 unit sintetis, apa pun nilai `quantity`-nya (mis. "10" kubik),
  /// karena memang tidak ada cara menghitung/membedakan unit fisiknya
  /// tanpa label. KONSEKUENSI: beda dari barang berlabel yang bisa dimuat
  /// terpecah ke beberapa kendaraan sekaligus (tiap unit fisik punya
  /// unit_code sendiri), item tanpa label HANYA bisa dimuat ke SATU
  /// shipment -- percobaan "muat" kedua ke shipment lain akan ditolak
  /// `DuplicateScanException` (constraint unique(unit_code, scan_type) di
  /// `shipment_scans`, lihat `recordScan`), karena unit_code-nya sama
  /// persis. Ini WAJAR/disengaja, bukan bug -- barang curah tanpa label
  /// memang tidak punya cara dilacak per-pecahan seperti barang berlabel.
  ///
  /// SENGAJA tidak match pola suffix `-U{n}` yang dipakai
  /// `UnitCodeParser` (lihat `core/utils/unit_code.dart`) -- supaya tidak
  /// pernah bentrok/disalahartikan sebagai hasil scan kamera biasa.
  static String noLabelUnitCode(String receivingDetailId) =>
      'NOLABEL-$receivingDetailId';

  /// FITUR (21 Oktober 2026 -- Section A, "Label Barcode"). Isi
  /// `detail['_barcode_codes']` untuk tiap baris di [details] yang
  /// `label_type == BARCODE`, dengan daftar `barcode_code` yang SUDAH
  /// terikat ke baris itu (lewat menu "Scan Label", lihat
  /// `LabelBarcodeService.bindToReceivingDetail`). WAJIB dipanggil
  /// (di-await) SEBELUM [details] diproses lewat [_physicalUnitCodes] --
  /// kalau tidak, barang BARCODE akan selalu dianggap "0 unit fisik"
  /// (lihat fallback kosong di [_physicalUnitCodes]). SATU query batch
  /// (bukan N+1) lewat `LabelBarcodeService.getBoundCodesByDetailIds`.
  /// Baris yang bukan BARCODE tidak disentuh sama sekali.
  static Future<void> _attachBarcodeCodes(
    List<Map<String, dynamic>> details,
  ) async {
    final barcodeDetailIds = details
        .where((d) => d['label_type'] == LabelType.barcode)
        .map((d) => d['id'] as String)
        .toList();

    if (barcodeDetailIds.isEmpty) return;

    final codesByDetail =
        await LabelBarcodeService.getBoundCodesByDetailIds(barcodeDetailIds);

    for (final detail in details) {
      if (detail['label_type'] != LabelType.barcode) continue;
      detail['_barcode_codes'] = codesByDetail[detail['id']] ?? const <String>[];
    }
  }

  /// Hitung SEMUA unit_code fisik untuk 1 baris `receiving_details` --
  /// dipakai basis "sudah dimuat / belum" di
  /// [getAvailableItemsForManualLoad]. Untuk barang BARCODE (lihat
  /// [_attachBarcodeCodes], WAJIB dipanggil dulu), unit fisik = kode-kode
  /// yang sudah diikat lewat "Scan Label". Untuk barang tanpa label
  /// (`is_unlabeled == true`), cuma ada 1 unit sintetis ([noLabelUnitCode]).
  /// Untuk barang BERLABEL QR, jumlah unit fisik = `quantity` (dibulatkan,
  /// clamp 1..999) -- SENGAJA pola penomoran ini SAMA PERSIS dengan yang
  /// dipakai `PrintTemplates` saat generate label QR (`itemCode` polos
  /// kalau cuma 1 unit, atau `itemCode-U{n}` kalau lebih dari 1) supaya
  /// unit_code yang dicatat di sini SELALU cocok dengan unit_code yang
  /// akan ter-scan kalau barang itu nanti/sebelumnya di-scan QR manual
  /// lewat kamera -- tidak ada 2 skema penomoran berbeda untuk barang
  /// yang sama.
  static List<String> _physicalUnitCodes(Map<String, dynamic> detail) {
    if (detail['label_type'] == LabelType.barcode) {
      final codes = detail['_barcode_codes'] as List<String>?;
      return codes ?? const <String>[];
    }

    if (detail['is_unlabeled'] == true) {
      return [noLabelUnitCode(detail['id'] as String)];
    }

    final itemCode = detail['item_code'] as String;
    // `.clamp()` di `num` mengembalikan tipe statis `num` (bukan `int`)
    // walau dipanggil di atas hasil `.round()` -- `.toInt()` WAJIB di
    // sini supaya bisa dipakai sebagai argumen `List.generate` di bawah.
    final unitTotal = (detail['quantity'] as num).round().clamp(1, 999).toInt();

    if (unitTotal <= 1) return [itemCode];

    return List.generate(unitTotal, (i) => '$itemCode-U${i + 1}');
  }

  /// Daftar SEMUA barang (baik yang berlabel QR maupun Tanpa Label QR)
  /// yang MASIH ADA unit fisik belum dimuat ke shipment manapun --
  /// dipakai mode "Tanpa Label QR" (checklist manual) di `LoadingScanPage`
  /// DAN halaman admin "Loading Barang" (`AdminManualLoadPage`), lewat
  /// widget bersama `ManualLoadChecklistView`.
  ///
  /// **PERUBAHAN BESAR (7 Oktober 2026, permintaan user eksplisit,
  /// menggantikan versi lama)**: method ini dulu bernama
  /// `getAvailableUnlabeledItems`/`getAvailableUnlabeledItemsForShipment`
  /// dan HANYA menampilkan barang `is_unlabeled == true` (barang curah
  /// yang benar2 tidak bisa dilabeli). User minta filter-nya diperluas
  /// jadi CUMA "sudah dimuat atau belum" -- TIDAK peduli status label.
  /// Alasan user: 1 resi bisa punya campuran barang berlabel & tidak, dan
  /// scan QR saat loading TIDAK WAJIB -- staff/admin boleh langsung
  /// centang manual kalau situasinya darurat (atau sekadar lebih
  /// praktis), tanpa pernah menyalakan kamera.
  ///
  /// Untuk barang BERLABEL yang punya >1 unit fisik (lihat
  /// [_physicalUnitCodes]), baris ini dianggap "tersedia" selama MASIH
  /// ADA minimal 1 unit yang belum ter-LOAD ke shipment manapun -- hasil
  /// per baris menyertakan key `'remainingUnitCodes'` (unit_code yang
  /// belum termuat), `'remainingCount'`, & `'totalUnitCount'`, dipakai
  /// `ManualLoadChecklistView` untuk (a) menampilkan sisa unit & (b)
  /// memuat SEMUA unit yang tersisa sekaligus saat baris itu dicentang &
  /// disubmit -- 1 baris = 1 aksi "muat", konsisten dengan cara barang
  /// tanpa label sudah diperlakukan sejak awal (bukan checklist per-unit
  /// fisik, yang akan membuat UI pecah jadi sangat panjang untuk barang
  /// bundle/banyak box).
  ///
  /// SENGAJA global (TIDAK di-scope ke [shipmentId] tertentu, dan memang
  /// tidak menerima parameter itu sama sekali) -- lihat riwayat bug 7
  /// Oktober 2026 pagi: versi SEBELUMNYA (`getAvailableUnlabeledItemsForShipment`)
  /// sempat dibatasi ke resi/tujuan yang "relevan" dengan 1 shipment,
  /// tapi begitu shipment itu dapat 1 LOAD scan, filter itu langsung
  /// menyempit dan menyembunyikan resi SAH lainnya yang cuma belum
  /// kebagian giliran dimuat. Satu kendaraan WAJAR membawa banyak resi
  /// berbeda -- filter "relevan" semacam itu salah asumsi & melanggar
  /// aturan standing "jangan mencegat flow aplikasi". JANGAN tambahkan
  /// scoping serupa lagi di sini.
  ///
  /// CATATAN SKALA: query ini mengambil SEMUA `receiving_details` (tidak
  /// dibatasi tanggal/status) lalu membuang yang sudah fully-loaded di
  /// sisi aplikasi -- cukup untuk volume data saat ini (perusahaan
  /// logistik skala kecil-menengah). Kalau suatu saat jumlah
  /// `receiving_details` historis jadi sangat besar, pertimbangkan
  /// pindahkan filter "belum fully-loaded" ke SQL (function/view di
  /// Supabase) daripada nambah `.limit()` sembarangan di sini (`.limit()`
  /// berisiko menyembunyikan resi lama yang masih sah menunggu dimuat).
  ///
  /// **REDESAIN ARSITEKTUR TOTAL (17 Oktober 2026, permintaan user
  /// eksplisit setelah kasus RESI000311 & regresi paginasi 2 bug
  /// sebelumnya di method ini -- lihat riwayat panjangnya di git
  /// blame/versi lama kalau perlu)**: user menegaskan masalah sesungguhnya
  /// bukan soal paginasi ("JANGAN NGELES KE PAGINATION"), tapi arsitektur
  /// yang salah dari awal -- method ini dulu menentukan "sudah dimuat
  /// atau belum" dengan CROSS-REFERENCE LIVE ke SELURUH tabel
  /// `shipment_scans` (lintas SEMUA shipment, dari awal berdirinya
  /// perusahaan) setiap kali checklist dibuka. Sekarang method ini CUKUP
  /// membaca kolom `sisa_barang` (lihat `migrasi_flow_state_sisa_barang.sql`)
  /// yang DIJAGA LANGSUNG oleh aksi loading/pembatalan/intervensi admin
  /// (lihat [recordScan], [cancelManualLoad],
  /// [forceCompleteReceivingByAdmin]) -- TIDAK PERNAH LAGI meng-query
  /// SELURUH `shipment_scans` di sini.
  ///
  /// Query `shipment_scans` di bawah TETAP ada (dibutuhkan untuk tahu
  /// unit_code PERSIS mana saja yang tersisa pada barang berlabel
  /// multi-unit yang baru SEBAGIAN termuat -- `sisa_barang` cuma angka,
  /// bukan daftar kode) -- TAPI sekarang di-scope HANYA ke
  /// `receiving_detail_id` dari baris yang memang masih `sisa_barang > 0`
  /// (jumlahnya jauh lebih kecil dari seluruh riwayat perusahaan, dan
  /// dipecah per-batch supaya URL tidak kepanjangan) -- BUKAN lagi query
  /// tanpa filter ke SELURUH tabel seperti sebelumnya.
  static Future<List<Map<String, dynamic>>> getAvailableItemsForManualLoad() async {
    final rows = <Map<String, dynamic>>[];
    const detailsPageSize = 1000;
    var detailsFrom = 0;
    while (true) {
      final page = await _client
          .from('receiving_details')
          .select('''
          id,
          receiving_id,
          item_code,
          item_name,
          quantity,
          quantity_unit,
          photo_url,
          is_unlabeled,
          label_type,
          storage_id,
          sisa_barang,
          selesai_barang,
          flow_state,
          storages:storage_id (
            nama_zona
          ),
          receiving:receiving_id (
            receipt_number,
            nomor_buku,
            destination,
            destination_id,
            destination_address
          )
        ''')
          .gt('sisa_barang', 0)
          .order('id')
          .range(detailsFrom, detailsFrom + detailsPageSize - 1);

      final pageRows = (page as List)
          .map((data) => Map<String, dynamic>.from(data))
          .toList();
      rows.addAll(pageRows);

      if (pageRows.length < detailsPageSize) break;
      detailsFrom += detailsPageSize;
    }

    if (rows.isEmpty) return rows;

    await _attachBarcodeCodes(rows);
    final codesByRow = rows.map(_physicalUnitCodes).toList();
    final ids = rows.map((r) => r['id'] as String).toList();

    // Dipecah per-batch (BUKAN 1 query untuk SEMUA [ids] sekaligus) --
    // sama alasannya dengan bug URL-kepanjangan 7 Oktober 2026 yang
    // pernah terjadi di method ini (lihat riwayat lama): walau [ids]
    // sekarang sudah jauh lebih kecil (cuma barang yang `sisa_barang >
    // 0`, bukan seluruh `receiving_details` perusahaan), tetap dibatasi
    // per-batch sebagai jaring pengaman kalau suatu saat jumlahnya
    // membesar lagi.
    final loadedCodesByDetail = <String, Set<String>>{};
    const idChunkSize = 200;
    for (var i = 0; i < ids.length; i += idChunkSize) {
      final chunk = ids.sublist(i, (i + idChunkSize).clamp(0, ids.length));
      final scanRows = await _client
          .from('shipment_scans')
          .select('receiving_detail_id, unit_code')
          .eq('scan_type', 'LOAD')
          .inFilter('receiving_detail_id', chunk);

      for (final r in (scanRows as List)) {
        final map = Map<String, dynamic>.from(r);
        final detailId = map['receiving_detail_id'] as String?;
        final code = map['unit_code'] as String?;
        if (detailId == null || code == null) continue;
        (loadedCodesByDetail[detailId] ??= <String>{}).add(code);
      }
    }

    final available = <Map<String, dynamic>>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final codes = codesByRow[i];
      final loaded = loadedCodesByDetail[row['id']] ?? const <String>{};
      final remaining = codes.where((c) => !loaded.contains(c)).toList();

      // Jaring pengaman: kalau `sisa_barang` ternyata tidak sinkron
      // dengan `shipment_scans` (seharusnya tidak terjadi lagi dengan
      // desain baru ini, tapi jangan sampai baris "kosong" muncul di
      // checklist kalau memang terjadi kejanggalan data).
      if (remaining.isEmpty) continue;

      row['remainingUnitCodes'] = remaining;
      row['remainingCount'] = remaining.length;
      row['totalUnitCount'] = codes.length;
      available.add(row);
    }

    return available;
  }

  /// FITUR (17 Oktober 2026, permintaan user eksplisit: "Perbaiki bagian
  /// loading Tanpa Label agar ada isian jumlah barang. Bukan hanya
  /// centang... Jadi loading tanpa QR bisa split barang").
  ///
  /// Mencatat 1 baris checklist "Loading Tanpa QR" (lihat
  /// [getAvailableItemsForManualLoad] & `ManualLoadChecklistView`) naik
  /// ke [shipmentId] -- SEKARANG dengan dukungan jumlah SEBAGIAN, bukan
  /// cuma "semua unit tersisa atau tidak sama sekali" seperti sebelumnya.
  /// [item] adalah 1 baris persis seperti yang dikembalikan
  /// [getAvailableItemsForManualLoad] (harus masih punya
  /// `remainingUnitCodes`/`is_unlabeled`/`quantity`). [qty] arti dan
  /// efeknya BEDA tergantung jenis barangnya:
  ///
  ///  - **Berlabel QR** (`is_unlabeled == false`, unit fisik independen
  ///    satu sama lain -- lihat [_physicalUnitCodes]): [qty] = JUMLAH
  ///    UNIT (dibulatkan, 1..`remainingCount`) yang dimuat SEKARANG.
  ///    TIDAK perlu split apa pun -- tiap unit SUDAH punya `unit_code`
  ///    sendiri sejak barang dicatat, cukup pilih [qty] unit paling awal
  ///    dari `remainingUnitCodes` (urutan tetap, jadi aman dipanggil
  ///    berkali-kali kalau sisanya mau dimuat lain waktu).
  ///  - **Tanpa Label/curah** (`is_unlabeled == true`, 1 baris = 1 unit
  ///    sintetis APAPUN quantity-nya -- lihat [_physicalUnitCodes]):
  ///    kalau [qty] >= quantity baris ini, dianggap "muat semua", scan
  ///    langsung seperti biasa. Kalau [qty] LEBIH KECIL, baris ini
  ///    di-SPLIT dulu lewat
  ///    [ReceivingService.splitReceivingDetailForPartialLoad] (logika
  ///    SAMA PERSIS dengan skrip SQL manual yang sebelumnya dipakai admin
  ///    untuk kasus ini) -- porsi [qty] itu yang discan LOAD, sisanya
  ///    otomatis jadi baris baru yang masih menunggu (muncul lagi di
  ///    checklist ini).
  ///
  /// Mengembalikan `null` kalau semua berhasil, atau pesan error (dalam
  /// Bahasa Indonesia, siap ditampilkan ke user) kalau gagal/sebagian
  /// gagal -- pola SAMA dengan `ManualLoadChecklistView._loadItem` yang
  /// method ini gantikan.
  static Future<String?> recordManualLoad({
    required Map<String, dynamic> item,
    required num qty,
    required String shipmentId,
    required String scannedBy,
    required String notes,
  }) async {
    final detailId = item['id'] as String;
    final isUnlabeled = item['is_unlabeled'] == true;
    final remainingCodes =
        ((item['remainingUnitCodes'] as List?) ?? const []).cast<String>();

    if (remainingCodes.isEmpty) {
      return 'tidak ada unit tersisa untuk dimuat (mungkin sudah termuat semua)';
    }

    if (!isUnlabeled) {
      // Barang berlabel: [qty] = jumlah UNIT, ambil yang paling awal dari
      // remainingCodes supaya konsisten kalau dipanggil bertahap.
      final unitCount =
          qty.round().clamp(1, remainingCodes.length).toInt();
      final codesToLoad = remainingCodes.take(unitCount).toList();
      return _recordManualLoadScans(
        codes: codesToLoad,
        detailId: detailId,
        shipmentId: shipmentId,
        scannedBy: scannedBy,
        notes: notes,
      );
    }

    // Curah/tanpa label -- remainingCodes pasti cuma berisi 1 kode (1
    // baris = 1 unit sintetis, lihat [_physicalUnitCodes]).
    final rowQuantity = (item['quantity'] as num).toDouble();

    if (qty <= 0) {
      return 'jumlah yang dimuat harus lebih dari 0';
    }

    if (qty >= rowQuantity) {
      // Muat semuanya -- tidak perlu split sama sekali.
      return _recordManualLoadScans(
        codes: remainingCodes,
        detailId: detailId,
        shipmentId: shipmentId,
        scannedBy: scannedBy,
        notes: notes,
      );
    }

    // Split dulu -- baris LAMA (id TETAP SAMA, jadi `remainingCodes` di
    // atas -- `NOLABEL-<id>` -- masih valid tanpa perlu dihitung ulang)
    // diturunkan quantity-nya jadi porsi yang dimuat sekarang; sisanya
    // jadi baris baru yang belum ada scan sama sekali.
    try {
      await ReceivingService.splitReceivingDetailForPartialLoad(
        detailId: detailId,
        loadedQuantity: qty.toDouble(),
      );
    } catch (e) {
      return 'gagal membagi barang: $e';
    }

    return _recordManualLoadScans(
      codes: remainingCodes,
      detailId: detailId,
      shipmentId: shipmentId,
      scannedBy: scannedBy,
      notes: notes,
    );
  }

  /// Helper bersama [recordManualLoad] -- catat tiap [codes] sebagai 1
  /// baris `shipment_scans` LOAD lewat [recordScan] (unitIndex diambil
  /// dari suffix `-U{n}`/`NOLABEL-` via [UnitCodeParser], SAMA PERSIS
  /// seperti hasil scan kamera). Unit yang gagal (mis. race condition,
  /// staff lain barengan memuat unit yang sama) TIDAK membatalkan unit
  /// lain yang sudah berhasil.
  static Future<String?> _recordManualLoadScans({
    required List<String> codes,
    required String detailId,
    required String shipmentId,
    required String scannedBy,
    required String notes,
  }) async {
    var successCount = 0;
    final errors = <String>[];

    for (final code in codes) {
      try {
        final parsed = UnitCodeParser.parse(code);

        await recordScan(
          shipmentId: shipmentId,
          receivingDetailId: detailId,
          unitCode: code,
          unitIndex: parsed.unitIndex,
          scannedBy: scannedBy,
          notes: notes,
        );

        successCount++;
      } on DuplicateScanException {
        errors.add('sudah tercatat dimuat (mungkin oleh staff lain)');
      } catch (e) {
        errors.add('gagal dicatat: $e');
      }
    }

    if (errors.isEmpty) return null;
    if (successCount == 0) return errors.first;
    return '$successCount unit berhasil, ${errors.length} unit gagal';
  }

  /// Daftar barang milik satu resi ([receivingId]) yang fisiknya SUDAH
  /// dimuat ke [shipmentId] (sudah ada baris LOAD untuk shipment ini --
  /// resi bisa terpecah ke beberapa kendaraan, lihat
  /// [isUnitLoadedOnShipment]) tapi BELUM dicatat turun -- dipakai mode
  /// "Tanpa Label QR" di `DeliveryResiScanPage`.
  ///
  /// **PERUBAHAN BESAR (10 Oktober 2026, permintaan user eksplisit,
  /// menggantikan [getUnlabeledItemsToDeliver] lama)**: method ini dulu
  /// HANYA menampilkan barang `is_unlabeled == true`. User minta
  /// diperluas supaya BARANG BERLABEL QR JUGA bisa diselesaikan lewat
  /// checklist manual ini -- "Penyelesaian barang tanpa Label harus bisa
  /// menyelesaikan barang yang berlabel juga, ini antisipasi jika camera
  /// sopir rusak atau label rusak." Jadi filter-nya SEKARANG sama
  /// persis pola [getAvailableItemsForManualLoad] (sisi Loading, 7
  /// Oktober 2026): "sudah dimuat ke shipment ini tapi belum tercatat
  /// turun" -- TIDAK peduli status label.
  ///
  /// Untuk barang BERLABEL dengan >1 unit fisik (lihat
  /// [_physicalUnitCodes]), baris ini dianggap "tersedia" selama masih
  /// ada minimal 1 unit yang sudah LOAD di shipment ini tapi belum
  /// DELIVER -- hasil per baris menyertakan `'remainingUnitCodes'`,
  /// `'remainingCount'`, & `'totalUnitCount'`, SAMA PERSIS konvensi sisi
  /// Loading, dipakai UI checklist untuk menyelesaikan SEMUA unit yang
  /// tersisa sekaligus saat baris itu dicentang & disubmit.
  ///
  /// SENGAJA TETAP di-scope ke [shipmentId]+[receivingId] (BEDA dari
  /// [getAvailableItemsForManualLoad] yang sengaja global) -- karena
  /// konteksnya di sini sudah sempit sejak awal: halaman ini dibuka
  /// SETELAH staff pilih 1 resi spesifik dari manifest 1 shipment
  /// tertentu, jadi scoping di sini tidak punya risiko bug yang sama
  /// (lihat riwayat bug `getAvailableUnlabeledItemsForShipment` di doc
  /// comment [getAvailableItemsForManualLoad]).
  static Future<List<Map<String, dynamic>>> getAvailableItemsForManualDeliver({
    required String shipmentId,
    required String receivingId,
  }) async {
    final detailsResponse = await _client
        .from('receiving_details')
        .select('id, item_code, item_name, quantity, quantity_unit, is_unlabeled, label_type, photo_url')
        .eq('receiving_id', receivingId);

    final details = (detailsResponse as List)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();

    if (details.isEmpty) return details;

    await _attachBarcodeCodes(details);
    final codesByDetail = details.map(_physicalUnitCodes).toList();
    final allCandidateCodes = codesByDetail.expand((c) => c).toList();

    if (allCandidateCodes.isEmpty) return [];

    // Scoping ke [shipmentId] DI QUERY (beda dari pola global
    // getAvailableItemsForManualLoad) membuat `inFilter` di sini aman
    // dari risiko URL kepanjangan -- jumlah unit candidate dibatasi ke 1
    // resi saja, bukan seluruh riwayat `receiving_details`.
    final scansResponse = await _client
        .from('shipment_scans')
        .select('unit_code, scan_type')
        .eq('shipment_id', shipmentId)
        .inFilter('unit_code', allCandidateCodes);

    final scans = (scansResponse as List)
        .map((s) => Map<String, dynamic>.from(s))
        .toList();

    final loadedCodes = scans
        .where((s) => s['scan_type'] == 'LOAD')
        .map((s) => s['unit_code'] as String)
        .toSet();
    final deliveredCodes = scans
        .where((s) => s['scan_type'] == 'DELIVER')
        .map((s) => s['unit_code'] as String)
        .toSet();

    final available = <Map<String, dynamic>>[];

    for (var i = 0; i < details.length; i++) {
      final codes = codesByDetail[i];
      final remaining = codes
          .where((c) => loadedCodes.contains(c) && !deliveredCodes.contains(c))
          .toList();

      if (remaining.isEmpty) continue;

      final row = details[i];
      row['remainingUnitCodes'] = remaining;
      row['remainingCount'] = remaining.length;
      row['totalUnitCount'] = codes.length;
      available.add(row);
    }

    return available;
  }

  // ============================================================
  // PEMBATALAN LOADING (ADMIN) -- 14 Oktober 2026
  // ============================================================
  //
  // FITUR (permintaan user eksplisit): "Pembatalan Loading. Di admin
  // bisa dibatalkan loading. Dengan cara menghilangkan centangnya. Jadi
  // kalau diadmin barang yang diloading tidak hilang dari layar tetapi
  // patokannya centang. Beda dengan bagian loading. Barang sudah
  // diloading hilang dari layar."
  //
  // Scope DIKONFIRMASI user: per kendaraan/shipment, lewat alur "Loading
  // Barang" yang sudah ada (`AdminManualLoadPage`) -- admin pilih
  // kendaraan dulu (shipment-nya otomatis ada/dibuat lewat
  // `resolveOrCreateShipmentForVehicle`, SAMA PERSIS alur "Tambah" yang
  // sudah ada), lalu pilih 1 resi yang SUDAH ada muatannya di shipment
  // ini (lihat [getReceivingsLoadedOnShipment]), baru lihat SEMUA barang
  // resi itu dengan status "sudah dimuat ke kendaraan ini" per baris.

  /// Daftar resi yang SUDAH punya minimal 1 barang ter-LOAD ke
  /// [shipmentId] -- dipakai sebagai daftar pilihan "resi mana yang mau
  /// dibatalkan loading-nya" di halaman "Pembatalan Loading". SENGAJA
  /// di-scope ke [shipmentId] (BEDA dari daftar resi di
  /// [getAvailableItemsForManualLoad] yang sengaja global) -- karena
  /// pembatalan cuma relevan untuk resi yang memang SUDAH ada di manifest
  /// kendaraan ini.
  static Future<List<Map<String, dynamic>>> getReceivingsLoadedOnShipment(
    String shipmentId,
  ) async {
    // PAGINASI EKSPLISIT (17 Oktober 2026 -- lihat bug/fix panjang di doc
    // comment [getAvailableItemsForManualLoad], ditemukan dari laporan
    // user RESI000311 "nyangkut"): shipment PLACEHOLDER bypass admin
    // "DISELESAIKAN ADMIN" SENDIRIAN sudah >1800 baris `shipment_scans`
    // (dari penumpukan "Selesaikan Resi" bertahun-tahun) -- di ATAS batas
    // default 1000 baris per request PostgREST/Supabase kalau query
    // TIDAK diberi `.range()`. Tanpa paginasi, resi yang kebetulan
    // "kebuang" dari potongan 1000 baris pertama akan HILANG dari daftar
    // "Batalkan Loading" biar pun scan LOAD-nya betul-betul ada.
    final rows = <Map<String, dynamic>>[];
    const pageSize = 1000;
    var pageFrom = 0;
    while (true) {
      final page = await _client
          .from('shipment_scans')
          .select('''
          receiving_detail_id,
          receiving_details (
            receiving_id,
            receiving:receiving_id (
              receipt_number,
              nomor_buku,
              destination,
              destination_address
            )
          )
        ''')
          .eq('shipment_id', shipmentId)
          .eq('scan_type', 'LOAD')
          .range(pageFrom, pageFrom + pageSize - 1);

      final pageRows =
          (page as List).map((r) => Map<String, dynamic>.from(r)).toList();
      rows.addAll(pageRows);

      if (pageRows.length < pageSize) break;
      pageFrom += pageSize;
    }

    final seen = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final detail = row['receiving_details'] as Map?;
      final receivingId = detail?['receiving_id'] as String?;
      if (receivingId == null || seen.containsKey(receivingId)) continue;

      final receiving = detail?['receiving'] as Map?;
      seen[receivingId] = {
        'receivingId': receivingId,
        'receiptNumber': receiving?['receipt_number']?.toString() ?? '-',
        'nomorBuku': receiving?['nomor_buku']?.toString(),
        'destination': receiving?['destination']?.toString() ?? '-',
        'destinationAddress': receiving?['destination_address']?.toString(),
      };
    }

    final list = seen.values.toList();
    list.sort(
      (a, b) => (a['receiptNumber'] as String)
          .compareTo(b['receiptNumber'] as String),
    );
    return list;
  }

  /// Daftar SEMUA barang milik 1 resi ([receivingId]), SCOPED ke
  /// [shipmentId] -- dipakai halaman "Pembatalan Loading" SETELAH admin
  /// pilih resi dari [getReceivingsLoadedOnShipment].
  ///
  /// BEDA PALING PENTING dari [getAvailableItemsForManualLoad]: SEMUA
  /// baris barang resi ini TETAP tampil di sini terlepas statusnya
  /// (sudah dimuat ke [shipmentId] atau belum) -- TIDAK ada baris yang
  /// "menghilang" dari layar (beda dengan checklist "Loading Barang"
  /// biasa, di mana barang yang sudah dicatat naik langsung hilang dari
  /// daftar). Checkbox di UI merepresentasikan `isLoadedToThisShipment`
  /// (status riil di database), BUKAN sekadar "sudah dicentang user":
  /// - Mencentang baris yang BELUM termuat -> MEMUAT-nya (pakai
  ///   `remainingUnitCodes`, SAMA PERSIS [getAvailableItemsForManualLoad]).
  /// - Menghilangkan centang baris yang SUDAH termuat -> MEMBATALKAN
  ///   loading-nya (pakai `loadedToThisShipmentUnitCodes`, lihat
  ///   [cancelManualLoad]).
  ///
  /// `canCancel` SENGAJA dipisah dari `isLoadedToThisShipment` -- `false`
  /// kalau salah satu unit yang sudah dimuat ke shipment ini JUGA sudah
  /// ter-DELIVER (sudah discan tiba) -- UI harus menolak uncentang baris
  /// ini. [cancelManualLoad] menegakkan hal yang sama di sisi server
  /// sebagai jaring pengaman kalau ada yang lolos dari pengecekan UI.
  static Future<List<Map<String, dynamic>>> getManualLoadCancelItems({
    required String shipmentId,
    required String receivingId,
  }) async {
    final detailsResponse = await _client
        .from('receiving_details')
        .select('''
          id,
          item_code,
          item_name,
          quantity,
          quantity_unit,
          is_unlabeled,
          label_type,
          photo_url,
          storage_id,
          storages:storage_id (
            nama_zona
          )
        ''')
        .eq('receiving_id', receivingId);

    final details = (detailsResponse as List)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();

    if (details.isEmpty) return details;

    await _attachBarcodeCodes(details);
    final codesByDetail = details.map(_physicalUnitCodes).toList();
    final allCandidateCodes = codesByDetail.expand((c) => c).toList();

    if (allCandidateCodes.isEmpty) return [];

    // Scoping ke [allCandidateCodes] 1 resi saja (BUKAN query global) --
    // aman dari risiko URL kepanjangan, sama pola
    // [getAvailableItemsForManualDeliver]. TIDAK difilter `.eq('shipment_id', ...)`
    // di query ITU SENDIRI -- butuh tahu status "dimuat ke MANA PUN"
    // (buat `remainingUnitCodes`) SEKALIGUS status "dimuat ke
    // [shipmentId] ini secara spesifik" (buat `loadedToThisShipmentUnitCodes`),
    // jadi kedua perhitungan dipisah di sisi Dart dari 1 hasil query yang
    // sama.
    final scansResponse = await _client
        .from('shipment_scans')
        .select('unit_code, shipment_id, scan_type')
        .inFilter('unit_code', allCandidateCodes);

    final scans = (scansResponse as List)
        .map((s) => Map<String, dynamic>.from(s))
        .toList();

    final loadedAnywhereCodes = scans
        .where((s) => s['scan_type'] == 'LOAD')
        .map((s) => s['unit_code'] as String)
        .toSet();
    final loadedToThisShipmentCodes = scans
        .where((s) =>
            s['scan_type'] == 'LOAD' && s['shipment_id'] == shipmentId)
        .map((s) => s['unit_code'] as String)
        .toSet();
    final deliveredToThisShipmentCodes = scans
        .where((s) =>
            s['scan_type'] == 'DELIVER' && s['shipment_id'] == shipmentId)
        .map((s) => s['unit_code'] as String)
        .toSet();

    final result = <Map<String, dynamic>>[];

    for (var i = 0; i < details.length; i++) {
      final codes = codesByDetail[i];
      final row = details[i];

      final remainingUnitCodes =
          codes.where((c) => !loadedAnywhereCodes.contains(c)).toList();
      final loadedToThisShipmentUnitCodes =
          codes.where((c) => loadedToThisShipmentCodes.contains(c)).toList();
      final hasDeliveredToThisShipment = loadedToThisShipmentUnitCodes
          .any((c) => deliveredToThisShipmentCodes.contains(c));

      row['totalUnitCount'] = codes.length;
      row['remainingUnitCodes'] = remainingUnitCodes;
      row['remainingCount'] = remainingUnitCodes.length;
      row['loadedToThisShipmentUnitCodes'] = loadedToThisShipmentUnitCodes;
      row['loadedToThisShipmentCount'] = loadedToThisShipmentUnitCodes.length;
      row['isLoadedToThisShipment'] = loadedToThisShipmentUnitCodes.isNotEmpty;
      row['canCancel'] = !hasDeliveredToThisShipment;

      result.add(row);
    }

    return result;
  }

  /// Membatalkan loading 1 baris barang ([detailId]) dari [shipmentId] --
  /// FITUR "Pembatalan Loading" (lihat doc comment
  /// [getManualLoadCancelItems]). Menghapus SEMUA baris `shipment_scans`
  /// scan_type LOAD milik [detailId] yang tercatat di [shipmentId] --
  /// mengembalikan unit-unit itu ke status "belum dimuat" (otomatis
  /// muncul lagi di [getAvailableItemsForManualLoad] kalau [shipmentId]
  /// bukan satu-satunya yang pernah memuatnya; selalu begitu sih, karena
  /// kalau sudah dibatalkan dari sini ya artinya memang belum dimuat ke
  /// shipment lain manapun -- resi yang di-split ke 2+ kendaraan tetap
  /// aman karena query di sini SELALU di-scope `.eq('shipment_id', ...)`,
  /// tidak pernah menyentuh baris LOAD milik shipment lain).
  ///
  /// DITOLAK ([LoadAlreadyDeliveredException]) kalau salah satu unit itu
  /// SUDAH ter-DELIVER (sudah discan tiba) di [shipmentId] yang sama --
  /// jaring pengaman SERVER-SIDE, sama seperti `canCancel` yang dihitung
  /// [getManualLoadCancelItems] untuk UI, supaya tidak ada ketimpangan
  /// data "dianggap sudah tiba tapi tidak pernah tercatat naik" biar pun
  /// ada yang lolos dari pengecekan UI.
  static Future<void> cancelManualLoad({
    required String shipmentId,
    required String detailId,
  }) async {
    final scansResponse = await _client
        .from('shipment_scans')
        .select('id, unit_code, scan_type')
        .eq('shipment_id', shipmentId)
        .eq('receiving_detail_id', detailId);

    final scans = (scansResponse as List)
        .map((s) => Map<String, dynamic>.from(s))
        .toList();

    final loadScanIds = scans
        .where((s) => s['scan_type'] == 'LOAD')
        .map((s) => s['id'] as String)
        .toList();

    if (loadScanIds.isEmpty) return;

    final deliveredUnitCodes = scans
        .where((s) => s['scan_type'] == 'DELIVER')
        .map((s) => s['unit_code'] as String)
        .toSet();
    final loadedUnitCodes = scans
        .where((s) => s['scan_type'] == 'LOAD')
        .map((s) => s['unit_code'] as String)
        .toSet();

    if (loadedUnitCodes.any(deliveredUnitCodes.contains)) {
      throw LoadAlreadyDeliveredException();
    }

    await _client.from('shipment_scans').delete().inFilter('id', loadScanIds);

    // REDESAIN ARSITEKTUR (17 Oktober 2026, permintaan user eksplisit) --
    // kebalikan dari hook di [recordScan]: unit yang dibatalkan loadnya
    // kembali jadi "belum dimuat", jadi `sisa_barang` harus naik lagi
    // sebanyak unit yang dibatalkan & `flow_state` balik ke
    // `BELUM_DIMUAT` (tidak lagi tuntas) supaya baris ini otomatis
    // muncul lagi di [getAvailableItemsForManualLoad].
    await _client.rpc('inc_sisa_barang_on_cancel', params: {
      'p_detail_id': detailId,
      'p_count': loadScanIds.length,
    });
  }

  /// Mencatat satu scan barang (naik ke kendaraan / turun di tujuan,
  /// tergantung [scanType]). [latitude]/[longitude] diisi untuk scan_type
  /// DELIVER (lokasi driver/helper saat scan barang turun di titik itu).
  static Future<ShipmentScanModel> recordScan({
    required String shipmentId,
    required String receivingDetailId,
    required String unitCode,
    required int unitIndex,
    required String scannedBy,
    String scanType = 'LOAD',
    String? notes,
    double? latitude,
    double? longitude,
    // Diisi KHUSUS alur "Selesaikan di Perwakilan" (lihat
    // `recordRepresentativeHandoffForReceiving`) -- scan DELIVER biasa
    // langsung ke tujuan TETAP kirim null seperti sebelumnya.
    String? representativeId,
    // FITUR (10 Oktober 2026, permintaan user eksplisit: "Penyelesaian
    // resi barang tanpa label harus memfoto ... harus dilengkapi
    // url_foto_selesai"). Diisi HANYA oleh penyelesaian manual/tanpa-
    // kamera (checklist "Tanpa Label QR" di `DeliveryResiScanPage`,
    // lihat `getAvailableItemsForManualDeliver`) -- scan DELIVER hasil
    // kamera QR biasa TETAP kirim null (sudah terverifikasi lewat kode
    // QR-nya sendiri, tidak perlu foto tambahan). Kolom ini BOLEH null
    // di database (tidak semua baris scan punya foto penyelesaian) --
    // lihat migrasi `add_shipment_scans_url_foto_selesai.sql`.
    String? urlFotoSelesai,
  }) async {
    final data = {
      'shipment_id': shipmentId,
      'receiving_detail_id': receivingDetailId,
      'unit_code': unitCode,
      'unit_index': unitIndex,
      'scan_type': scanType,
      'scanned_by': scannedBy,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'representative_id': representativeId,
      'url_foto_selesai': urlFotoSelesai,
    };

    try {
      final response = await _client
          .from('shipment_scans')
          .insert(data)
          .select()
          .single();

      // REDESAIN ARSITEKTUR (17 Oktober 2026, permintaan user eksplisit):
      // "Jika seseorang loading atau dan selesai loading ----- update
      // kedua kolom itu" (`flow_state` & `sisa_barang` di
      // `receiving_details`, lihat `migrasi_flow_state_sisa_barang.sql`).
      // `recordScan` adalah SATU-SATUNYA titik penulisan baris LOAD/DELIVER
      // yang sesungguhnya (dipanggil langsung oleh scan kamera QR, DAN
      // oleh checklist manual lewat [_recordManualLoadScans]) -- jadi di
      // sinilah tempat paling tepat & terjamin selalu kena, 1 panggilan
      // RPC per unit fisik (SAMA granularitas dengan 1 baris
      // `shipment_scans` yang baru dibuat di atas). Sengaja HANYA untuk
      // `scanType == 'LOAD'` -- scan DELIVER per-unit TIDAK menyentuh
      // kolom ini (lihat [_markLoadedItemsSelesaiForShipment] untuk kapan
      // `flow_state` berpindah ke `SELESAI`).
      if (scanType == 'LOAD') {
        await _client.rpc('dec_sisa_barang_on_load', params: {
          'p_detail_id': receivingDetailId,
        });
      }

      return ShipmentScanModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw DuplicateScanException(unitCode);
      }
      rethrow;
    }
  }

  /// Upload foto bukti "Penyelesaian Resi Tanpa Label QR" ke Supabase
  /// Storage, balikin URL publiknya -- numpang bucket `expense-receipts`
  /// yang sudah terbukti public (pola SAMA PERSIS dengan
  /// `ReceivingService.uploadItemPhoto`, folder beda supaya tidak
  /// campur). Dipanggil SEKALI per submit checklist (1 foto berlaku
  /// untuk SEMUA barang yang dicentang dalam submit itu) -- lihat
  /// `DeliveryResiScanPage._submitCheckedNonLabelItems`.
  static Future<String> uploadDeliveryCompletionPhoto({
    required String shipmentId,
    required Uint8List bytes,
  }) async {
    const bucket = 'expense-receipts';
    final path =
        'delivery-completion-photos/$shipmentId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    return _client.storage.from(bucket).getPublicUrl(path);
  }

  // ============================================================
  // ADMINISTRASI -- ARSIP FOTO BARANG SAMPAI (10 Oktober 2026)
  // ============================================================
  //
  // Permintaan user eksplisit: "Unduh semua Foto Barang Sampai (jika
  // diklik akan mengunduh semua ke lokal dan menghapus di supabase)...
  // karena Supabase ini 500 MB saja" -- bucket Storage gratis Supabase
  // cuma 500 MB, jadi foto bukti penyelesaian (`url_foto_selesai`,
  // fitur #15 di atas) perlu diunduh admin ke HP-nya lalu dihapus dari
  // Supabase secara berkala supaya storage tidak penuh.

  static const _completionPhotoBucket = 'expense-receipts';

  /// Semua foto "Barang Sampai" (bukti penyelesaian manual tanpa kamera,
  /// kolom `url_foto_selesai`) yang MASIH tersimpan di Supabase Storage
  /// -- dipakai menu Administrasi "Unduh Semua Foto Barang Sampai".
  /// Dikelompokkan per URL (BUKAN per baris shipment_scans) karena 1
  /// foto berlaku untuk 1 batch submit checklist "Tanpa Label QR" --
  /// bisa jadi beberapa baris sekaligus menunjuk foto yang SAMA. Setiap
  /// batch SELALU berasal dari 1 resi yang sama (checklist di
  /// `DeliveryResiScanPage` sudah resi-scoped), jadi tiap foto bisa
  /// dinamai dari nomor resi itu.
  static Future<List<Map<String, dynamic>>> getCompletionPhotosToArchive() async {
    final response = await _client
        .from('shipment_scans')
        .select('''
          url_foto_selesai,
          scanned_at,
          receiving_details (
            receiving_id,
            receiving:receiving_id (
              receipt_number
            )
          )
        ''')
        .not('url_foto_selesai', 'is', null)
        .order('scanned_at', ascending: true);

    final rows = (response as List)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    final order = <String>[];
    final groups = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final url = row['url_foto_selesai'] as String?;
      if (url == null) continue;

      groups.putIfAbsent(url, () {
        order.add(url);
        final detail = row['receiving_details'] as Map?;
        final receiving = detail?['receiving'] as Map?;
        return {
          'url': url,
          'scannedAt': row['scanned_at'],
          'receiptNumber': receiving?['receipt_number'],
        };
      });
    }

    return order.map((url) => groups[url]!).toList();
  }

  /// Hapus 1 foto "Barang Sampai" dari Supabase Storage SETELAH berhasil
  /// diunduh ke lokal admin, DAN null-kan `url_foto_selesai` di SEMUA
  /// baris `shipment_scans` yang menunjuk foto ini -- supaya baris
  /// histori LOAD/DELIVER-nya (jam, lokasi, siapa yang scan) TETAP UTUH,
  /// yang dibersihkan cuma fotonya (itu yang bikin storage 500 MB
  /// penuh). Aman dipanggil berkali-kali -- kalau path-nya sudah tidak
  /// ada di Storage, `remove` tidak error, dan update kolom null tetap
  /// jalan.
  static Future<void> deleteCompletionPhoto(String url) async {
    final path = _storagePathFromPublicUrl(url, _completionPhotoBucket);

    if (path != null) {
      await _client.storage.from(_completionPhotoBucket).remove([path]);
    }

    await _client
        .from('shipment_scans')
        .update({'url_foto_selesai': null})
        .eq('url_foto_selesai', url);
  }

  /// Ambil path relatif DALAM bucket dari sebuah public URL Supabase
  /// Storage, misal
  /// ".../object/public/expense-receipts/delivery-completion-photos/x/123.jpg"
  /// -> "delivery-completion-photos/x/123.jpg". null kalau formatnya
  /// tidak dikenali -- jaga-jaga supaya tidak pernah salah hapus file
  /// lain di bucket yang sama.
  static String? _storagePathFromPublicUrl(String url, String bucket) {
    final marker = '/object/public/$bucket/';
    final index = url.indexOf(marker);
    if (index == -1) return null;
    return url.substring(index + marker.length);
  }

  // ============================================================
  // SELESAIKAN DI PERWAKILAN (6 Oktober 2026 lanjutan)
  // ============================================================
  //
  // Permintaan user eksplisit: "Ada kasus dimana barang tidak
  // diselesaikan di tujuan. Karena tujuan tutup atau tidak bisa
  // dijangkau. Sehingga driver/sopir menurunkan barang diperwakilan...
  // ada pilihan jika barang diselesaikan di perwakilan berdasarkan resi
  // atau daftar per tujuan... secara otomatis HP sopir mengirim
  // informasi bahwa Resi dan barang sekian turun di perwakilan yang
  // dimaksud."
  //
  // Dipakai `RepresentativeHandoffPage` -- BEDA dari
  // [forceCompleteDestinationByAdmin] (yang itu khusus ADMIN "menyusulkan"
  // scan yang KETINGGALAN tidak sengaja): ini dipakai SOPIR SENDIRI saat
  // memang SECARA FISIK barang diturunkan di perwakilan (bukan tujuan
  // asli), jadi representative_id diisi sebagai jejak lokasi fisik
  // barang sekarang.

  /// Manifest shipment ini dikelompokkan PER RESI, progress dihitung per
  /// UNIT FISIK -- SAMA PERSIS cara [getManifestGroupedByDestination]
  /// menghitung (unit_code yang benar-benar match baris DELIVER), BUKAN
  /// per `receiving_detail_id` seperti [getManifestGroupedByReceiving]
  /// (yang MEMANG bisa "kebawa lunas" kalau baru SEBAGIAN unit dalam 1
  /// baris detail yang ke-scan -- lihat doc comment panjang di
  /// [getManifestGroupedByDestination] soal ini).
  ///
  /// Dipakai KHUSUS mode "Per Resi" di `RepresentativeHandoffPage` --
  /// SENGAJA dibuat method terpisah (bukan numpang
  /// `getManifestGroupedByReceiving` yang sudah dipakai
  /// `DeliveryManifestPage`) karena akurasi "berapa barang resi ini yang
  /// masih pending turun" krusial di sini: salah hitung bisa membuat
  /// sopir mengira resi sudah selesai (padahal masih ada unit yang belum
  /// discan turun), sehingga unit itu tidak pernah dititip ke perwakilan
  /// ataupun dicatat turun normal -- tersangkut selamanya di manifest.
  static Future<List<Map<String, dynamic>>> getHandoffCandidatesByReceiving(
    String shipmentId,
  ) async {
    final loadRows = await _getLoadScansWithDetails(shipmentId);
    final deliverRows =
        await getShipmentScanFeed(shipmentId, scanType: 'DELIVER');

    final deliveredUnitCodes = deliverRows
        .map((row) => row['unit_code']?.toString())
        .whereType<String>()
        .toSet();

    final receivings = <String, Map<String, dynamic>>{};

    for (final row in loadRows) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      if (receivingId == null) continue;

      final receiving = detail['receiving'] as Map<String, dynamic>?;

      final entry = receivings.putIfAbsent(
        receivingId,
        () => {
          'receivingId': receivingId,
          'receiptNumber': receiving?['receipt_number'],
          'destination': receiving?['destination'],
          'destinationAddress': receiving?['destination_address'],
          'destinationPhone': _liveDestinationPhone(receiving),
          'totalItems': 0,
          'deliveredItems': 0,
        },
      );

      entry['totalItems'] = (entry['totalItems'] as int) + 1;

      final unitCode = row['unit_code']?.toString();
      if (unitCode != null && deliveredUnitCodes.contains(unitCode)) {
        entry['deliveredItems'] = (entry['deliveredItems'] as int) + 1;
      }
    }

    final result = receivings.values.toList();

    result.sort(
      (a, b) => (a['receiptNumber']?.toString() ?? '')
          .compareTo(b['receiptNumber']?.toString() ?? ''),
    );

    return result;
  }

  /// Semua unit barang (berlabel MAUPUN tanpa label) milik satu resi
  /// [receivingId] yang sudah dimuat di [shipmentId] tapi BELUM tercatat
  /// turun -- dasar perhitungan "sisa barang resi ini yang perlu
  /// dititip di perwakilan". BEDA dari [getUnlabeledItemsToDeliver] yang
  /// HANYA barang tanpa label -- titip-perwakilan berlaku untuk SISA
  /// barang resi itu apa pun status labelnya (sopir sudah sempat scan
  /// turun sebagian secara normal, sisanya baru dititip karena tujuan
  /// tutup, atau belum sempat scan sama sekali).
  static Future<List<Map<String, dynamic>>> getPendingDeliverUnitsByReceiving({
    required String shipmentId,
    required String receivingId,
  }) async {
    final loadResponse = await _client
        .from('shipment_scans')
        .select('''
          unit_code,
          unit_index,
          receiving_detail_id,
          receiving_details (
            id,
            receiving_id,
            item_name,
            quantity_unit,
            is_unlabeled
          )
        ''')
        .eq('shipment_id', shipmentId)
        .eq('scan_type', 'LOAD');

    final deliverRows =
        await getShipmentScanFeed(shipmentId, scanType: 'DELIVER');

    final deliveredUnitCodes = deliverRows
        .map((row) => row['unit_code']?.toString())
        .whereType<String>()
        .toSet();

    final result = <Map<String, dynamic>>[];

    for (final row in (loadResponse as List)) {
      final data = Map<String, dynamic>.from(row);
      final detail = data['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;
      if (detail['receiving_id'] != receivingId) continue;

      final unitCode = data['unit_code']?.toString();
      final unitIndex = data['unit_index'] as int?;
      final detailId = detail['id'] as String?;
      if (unitCode == null || unitIndex == null || detailId == null) continue;
      if (deliveredUnitCodes.contains(unitCode)) continue;

      result.add({
        'receivingDetailId': detailId,
        'unitCode': unitCode,
        'unitIndex': unitIndex,
        'itemName': detail['item_name'],
        'quantityUnit': detail['quantity_unit'],
        'isUnlabeled': detail['is_unlabeled'] ?? false,
      });
    }

    return result;
  }

  /// Catat SEMUA unit yang masih pending turun untuk SATU resi
  /// [receivingId] sebagai "diserahkan ke perwakilan" [representativeId]
  /// -- dipakai mode "Per Resi" di `RepresentativeHandoffPage`. Mencatat
  /// scan DELIVER SAMA PERSIS lewat [recordScan] (supaya seluruh logic
  /// manifest/progress yang sudah ada tetap jalan tanpa kasus khusus),
  /// bedanya `representative_id` diisi + `notes` berisi jejak nama
  /// perwakilan.
  ///
  /// Unit yang KEBURU tercatat turun (race condition/scan lain barusan
  /// masuk) dilewati -- idempotent, aman dipanggil ulang. Mengembalikan
  /// jumlah unit yang berhasil dicatat.
  static Future<int> recordRepresentativeHandoffForReceiving({
    required String shipmentId,
    required String receivingId,
    required String representativeId,
    required String representativeName,
    required String scannedBy,
    double? latitude,
    double? longitude,
  }) async {
    final pending = await getPendingDeliverUnitsByReceiving(
      shipmentId: shipmentId,
      receivingId: receivingId,
    );

    var created = 0;

    for (final unit in pending) {
      try {
        await recordScan(
          shipmentId: shipmentId,
          receivingDetailId: unit['receivingDetailId'] as String,
          unitCode: unit['unitCode'] as String,
          unitIndex: unit['unitIndex'] as int,
          scannedBy: scannedBy,
          scanType: 'DELIVER',
          notes: 'Diserahkan ke perwakilan: $representativeName',
          representativeId: representativeId,
          latitude: latitude,
          longitude: longitude,
        );
        created++;
      } on DuplicateScanException {
        continue;
      }
    }

    return created;
  }

  /// Sama seperti [recordRepresentativeHandoffForReceiving], TAPI untuk
  /// BEBERAPA resi sekaligus -- dipakai mode "Per Tujuan" di
  /// `RepresentativeHandoffPage` (satu tujuan bisa dikirim dari beberapa
  /// resi berbeda, lihat `getManifestGroupedByDestination.receivingIds`).
  /// Mode "Per Resi" tinggal panggil ini dengan list berisi SATU
  /// receivingId -- supaya kedua mode pakai jalur pencatatan yang sama
  /// persis (tidak ada logic bercabang/kasus khusus).
  static Future<int> recordRepresentativeHandoffForReceivings({
    required String shipmentId,
    required List<String> receivingIds,
    required String representativeId,
    required String representativeName,
    required String scannedBy,
    double? latitude,
    double? longitude,
  }) async {
    var total = 0;

    for (final receivingId in receivingIds) {
      total += await recordRepresentativeHandoffForReceiving(
        shipmentId: shipmentId,
        receivingId: receivingId,
        representativeId: representativeId,
        representativeName: representativeName,
        scannedBy: scannedBy,
        latitude: latitude,
        longitude: longitude,
      );
    }

    return total;
  }
}
