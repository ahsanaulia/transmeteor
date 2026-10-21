import '../core/services/supabase_service.dart';
import 'vehicle_service.dart';

/// Kumpulan query agregasi untuk halaman-halaman Monitoring admin/supervisor:
/// posisi armada, status pengiriman resi, dan kinerja perjalanan (durasi +
/// biaya). Semua hasil dibalikin sebagai Map mentah (bukan model) karena
/// datanya hasil gabungan beberapa tabel, mengikuti pola DashboardService.
class MonitoringService {
  static final _client = SupabaseService.client;

  // ============================================================
  // 1. MONITORING VEHICLES & DRIVER (posisi terakhir)
  // ============================================================

  /// Posisi terakhir SEMUA kendaraan aktif. Kendaraan yang lagi jalan
  /// (shipment DEPARTED & trip sudah di-Start) dapat titik dari ping
  /// lokasi terakhirnya. Kendaraan idle / belum pernah jalan tetap
  /// tampil di daftar tapi tanpa koordinat ('lokasi belum diketahui').
  static Future<List<Map<String, dynamic>>> getFleetPositions() async {
    final vehicleRows = await _client
        .from('vehicles')
        .select()
        .eq('is_active', true)
        .order('plate_number', ascending: true);

    final vehicles =
        (vehicleRows as List).map((d) => Map<String, dynamic>.from(d)).toList();

    final shipmentRows = await _client
        .from('shipments')
        .select('id, shipment_number, vehicle_id, driver_employee_id, status, trip_started_at')
        .inFilter('status', ['LOADING', 'DEPARTED']);

    final activeShipments =
        (shipmentRows as List).map((d) => Map<String, dynamic>.from(d)).toList();

    final shipmentByVehicle = <String, Map<String, dynamic>>{};
    for (final s in activeShipments) {
      shipmentByVehicle[s['vehicle_id'] as String] = s;
    }

    final trackedShipmentIds = activeShipments
        .where((s) => s['status'] == 'DEPARTED' && s['trip_started_at'] != null)
        .map((s) => s['id'] as String)
        .toList();

    final latestPingByShipment = <String, Map<String, dynamic>>{};
    if (trackedShipmentIds.isNotEmpty) {
      final pingRows = await _client
          .from('shipment_location_pings')
          .select('shipment_id, latitude, longitude, recorded_at')
          .inFilter('shipment_id', trackedShipmentIds)
          .order('recorded_at', ascending: false);

      for (final row in (pingRows as List)) {
        final map = Map<String, dynamic>.from(row);
        final sid = map['shipment_id'] as String;
        // Data sudah diurutkan terbaru dulu -- kemunculan pertama per
        // shipment_id otomatis jadi titik terakhirnya.
        latestPingByShipment.putIfAbsent(sid, () => map);
      }
    }

    final driverIds = <String>{
      for (final v in vehicles)
        if (v['driver_employee_id'] != null) v['driver_employee_id'] as String,
      for (final s in activeShipments)
        if (s['driver_employee_id'] != null) s['driver_employee_id'] as String,
    };

    final driverNameById = await _fetchEmployeeNames(driverIds);

    return vehicles.map((vehicle) {
      final vehicleId = vehicle['id'] as String;
      final shipment = shipmentByVehicle[vehicleId];
      final ping = shipment != null ? latestPingByShipment[shipment['id']] : null;

      final driverEmployeeId =
          (shipment?['driver_employee_id'] as String?) ?? vehicle['driver_employee_id'] as String?;

      return {
        'vehicleId': vehicleId,
        'plateNumber': vehicle['plate_number'],
        'vehicleType': vehicle['vehicle_type'],
        'driverName': driverEmployeeId != null
            ? (driverNameById[driverEmployeeId] ?? vehicle['driver_name'])
            : vehicle['driver_name'],
        'shipmentId': shipment?['id'],
        'shipmentNumber': shipment?['shipment_number'],
        'shipmentStatus': shipment?['status'],
        // Dipakai buat tahu apakah sopir sudah menekan "Mulai Perjalanan"
        // -- kalau shipment sudah DEPARTED tapi ini masih null, tracking
        // GPS belum pernah aktif sama sekali (lihat tombol "Mulai Paksa
        // Perjalanan" di FleetMonitoringPage).
        'tripStartedAt': shipment?['trip_started_at'] != null
            ? DateTime.parse(shipment!['trip_started_at'])
            : null,
        'latitude': ping?['latitude'],
        'longitude': ping?['longitude'],
        'lastPingAt': ping?['recorded_at'],
      };
    }).toList();
  }

  // ============================================================
  // 2. MONITORING RESI SAMPAI
  // ============================================================

  /// Status pengiriman SEMUA resi yang sudah pernah dimuat ke kendaraan
  /// (lintas shipment), lengkap lokasi tiap barang saat discan turun --
  /// dibandingkan (secara visual di peta, tanpa logika jarak otomatis)
  /// dengan koordinat alamat resi yang terdaftar.
  ///
  /// SATU RESI BISA TERPECAH KE BEBERAPA KENDARAAN (mis. resi "15 kubik
  /// bata ringan" dimuat 2 truk, 7,5 kubik masing-masing) -- versi lama
  /// fungsi ini pakai `putIfAbsent` untuk field shipment/vehicle/driver,
  /// jadi kalau resi terpecah, cuma kendaraan yang PALING DULUAN ketemu
  /// di hasil query yang kesimpan, sisanya HILANG dari tampilan (admin
  /// bisa dikira seluruh resi ada di 1 truk, padahal tidak). Sekarang
  /// SEMUA kendaraan yang bawa bagian resi ini dikumpulkan di
  /// `shipments` (list, bukan field tunggal) -- widget monitoring WAJIB
  /// pakai field ini buat cek apakah resi terpecah
  /// (`isSplitAcrossShipments` / `shipments.length > 1`), jangan cuma
  /// baca `shipmentNumber`/`vehiclePlateNumber`/`driverName` tunggal
  /// (field-field itu tetap disediakan untuk kompatibilitas widget lama,
  /// diisi dari kendaraan yang bawa item PALING BANYAK -- TAPI bisa
  /// menyesatkan kalau resi ternyata terpecah, makanya UI baru harus cek
  /// `isSplitAcrossShipments` dulu).
  static Future<List<Map<String, dynamic>>> getResiDeliveryMonitoring() async {
    final loadRows = await _client
        .from('shipment_scans')
        .select('''
          shipment_id,
          receiving_detail_id,
          receiving_details (
            id,
            item_name,
            item_code,
            receiving_id,
            receiving:receiving_id (
              receipt_number,
              destination,
              destination_address,
              destination_latitude,
              destination_longitude
            )
          )
        ''')
        .eq('scan_type', 'LOAD');

    final deliverRows = await _client
        .from('shipment_scans')
        .select('receiving_detail_id, shipment_id, latitude, longitude, scanned_at')
        .eq('scan_type', 'DELIVER');

    final deliverByDetailId = <String, Map<String, dynamic>>{};
    for (final row in (deliverRows as List)) {
      final map = Map<String, dynamic>.from(row);
      final detailId = map['receiving_detail_id'] as String?;
      if (detailId != null) deliverByDetailId[detailId] = map;
    }

    final loads = (loadRows as List).map((d) => Map<String, dynamic>.from(d)).toList();

    final shipmentIds = loads.map((row) => row['shipment_id'] as String).toSet().toList();

    final shipmentInfoById = <String, Map<String, dynamic>>{};
    if (shipmentIds.isNotEmpty) {
      final shipmentRows = await _client
          .from('shipments')
          .select('id, shipment_number, status, driver_employee_id, vehicles(plate_number)')
          .inFilter('id', shipmentIds);

      for (final row in (shipmentRows as List)) {
        final map = Map<String, dynamic>.from(row);
        shipmentInfoById[map['id'] as String] = map;
      }
    }

    final driverIds = shipmentInfoById.values
        .map((s) => s['driver_employee_id'] as String?)
        .whereType<String>()
        .toSet();

    final driverNameById = await _fetchEmployeeNames(driverIds);

    final grouped = <String, Map<String, dynamic>>{};
    // Kendaraan/shipment per resi, di-key SHIPMENT ID (bukan putIfAbsent
    // per-resi) supaya SEMUA kendaraan yang bawa bagian resi ini kesimpan,
    // dengan itemCount masing-masing terakumulasi dengan benar.
    final shipmentsByReceiving = <String, Map<String, Map<String, dynamic>>>{};

    for (final row in loads) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      if (detail == null) continue;

      final receivingId = detail['receiving_id'] as String?;
      if (receivingId == null) continue;

      final receiving = detail['receiving'] as Map<String, dynamic>?;
      final detailId = detail['id'] as String?;
      final shipmentId = row['shipment_id'] as String?;
      final shipmentInfo = shipmentId != null ? shipmentInfoById[shipmentId] : null;
      final driverEmployeeId = shipmentInfo?['driver_employee_id'] as String?;
      final driverName = driverEmployeeId != null ? driverNameById[driverEmployeeId] : null;
      final vehiclePlateNumber = (shipmentInfo?['vehicles'] as Map?)?['plate_number'];

      grouped.putIfAbsent(
        receivingId,
        () => {
          'receivingId': receivingId,
          'receiptNumber': receiving?['receipt_number'],
          'destination': receiving?['destination'],
          'destinationAddress': receiving?['destination_address'],
          'destinationLatitude': receiving?['destination_latitude'],
          'destinationLongitude': receiving?['destination_longitude'],
          'totalItems': 0,
          'deliveredItems': 0,
          'deliveries': <Map<String, dynamic>>[],
        },
      );

      final group = grouped[receivingId]!;
      group['totalItems'] = (group['totalItems'] as int) + 1;

      if (shipmentId != null) {
        final shipmentsMap = shipmentsByReceiving.putIfAbsent(receivingId, () => {});
        final shipmentEntry = shipmentsMap.putIfAbsent(
          shipmentId,
          () => {
            'shipmentId': shipmentId,
            'shipmentNumber': shipmentInfo?['shipment_number'],
            'shipmentStatus': shipmentInfo?['status'],
            'vehiclePlateNumber': vehiclePlateNumber,
            'driverName': driverName,
            'itemCount': 0,
          },
        );
        shipmentEntry['itemCount'] = (shipmentEntry['itemCount'] as int) + 1;
      }

      if (detailId != null && deliverByDetailId.containsKey(detailId)) {
        final deliverRow = deliverByDetailId[detailId]!;
        group['deliveredItems'] = (group['deliveredItems'] as int) + 1;

        final deliverShipmentId = deliverRow['shipment_id'] as String?;
        final deliverShipmentInfo =
            deliverShipmentId != null ? shipmentInfoById[deliverShipmentId] : null;

        (group['deliveries'] as List<Map<String, dynamic>>).add({
          'itemName': detail['item_name'],
          'itemCode': detail['item_code'],
          'latitude': deliverRow['latitude'],
          'longitude': deliverRow['longitude'],
          'scannedAt': deliverRow['scanned_at'],
          // Kendaraan mana yang catat barang ini turun -- penting kalau
          // resi terpecah, supaya kelihatan barang ini turun dari truk
          // yang mana (bisa beda truk dengan yang tampil di kartu utama).
          'shipmentNumber': deliverShipmentInfo?['shipment_number'],
          'vehiclePlateNumber': (deliverShipmentInfo?['vehicles'] as Map?)?['plate_number'],
        });
      }
    }

    final results = grouped.values.map((group) {
      final receivingId = group['receivingId'] as String;
      final shipments = (shipmentsByReceiving[receivingId]?.values.toList() ?? <Map<String, dynamic>>[])
        ..sort((a, b) => (b['itemCount'] as int).compareTo(a['itemCount'] as int));

      final primaryShipment = shipments.isNotEmpty ? shipments.first : null;

      return {
        ...group,
        'shipments': shipments,
        // Kompat lama, diisi dari kendaraan yang bawa item TERBANYAK --
        // widget baru sebaiknya pakai `shipments` + `isSplitAcrossShipments`.
        'shipmentId': primaryShipment?['shipmentId'],
        'shipmentNumber': primaryShipment?['shipmentNumber'],
        'shipmentStatus': primaryShipment?['shipmentStatus'],
        'vehiclePlateNumber': primaryShipment?['vehiclePlateNumber'],
        'driverName': primaryShipment?['driverName'],
        'isSplitAcrossShipments': shipments.length > 1,
      };
    }).toList();

    // Yang belum lengkap ditaruh duluan supaya lebih kelihatan perlu perhatian.
    results.sort((a, b) {
      final aComplete = (a['deliveredItems'] as int) >= (a['totalItems'] as int);
      final bComplete = (b['deliveredItems'] as int) >= (b['totalItems'] as int);
      if (aComplete == bComplete) return 0;
      return aComplete ? 1 : -1;
    });

    return results;
  }

  /// Event "dimuat" (scan_type=LOAD) untuk SATU resi, dikelompokkan PER
  /// SHIPMENT/KENDARAAN -- dipakai `ReceivingDetailPage` (kotak biru
  /// detail resi, Monitoring Resi admin) untuk menambahkan "Kapan dimuat,
  /// di mobil mana (plat + sopir)" (13 Oktober 2026, permintaan user
  /// eksplisit).
  ///
  /// SATU RESI BISA TERPECAH KE 2-3 KENDARAAN (lihat doc comment
  /// `getResiDeliveryMonitoring` di atas) -- makanya hasilnya SELALU
  /// list (1 entri per shipment yang pernah memuat bagian resi ini),
  /// BUKAN field tunggal; pemanggil WAJIB tampilkan SEMUA entrinya, tidak
  /// cuma yang pertama.
  ///
  /// `loadedAt` diambil dari scan LOAD PALING AWAL milik shipment itu
  /// (kalau Loading balik lagi nambah muatan ke shipment yang sama,
  /// waktu "mulai dimuat" tetap yang pertama). `arrivedAt` HANYA diisi
  /// kalau status shipment itu sudah ARRIVED -- beda dengan RPC publik
  /// `track_shipment` (dipakai halaman tracking customer) yang SENGAJA
  /// cuma mengembalikan shipment LOADING/DEPARTED, fungsi ini
  /// mengembalikan SEMUA status termasuk ARRIVED supaya admin bisa lihat
  /// tanggal selesainya juga.
  static Future<List<Map<String, dynamic>>> getLoadingEventsForReceiving(
    String receivingId,
  ) async {
    final loadRows = await _client
        .from('shipment_scans')
        .select('shipment_id, scanned_at, receiving_details(receiving_id)')
        .eq('scan_type', 'LOAD');

    final relevant = (loadRows as List)
        .map((d) => Map<String, dynamic>.from(d))
        .where((row) {
      final detail = row['receiving_details'] as Map<String, dynamic>?;
      return detail?['receiving_id'] == receivingId;
    }).toList();

    if (relevant.isEmpty) return [];

    final byShipment = <String, List<Map<String, dynamic>>>{};
    for (final row in relevant) {
      final shipmentId = row['shipment_id'] as String?;
      if (shipmentId == null) continue;
      byShipment.putIfAbsent(shipmentId, () => []).add(row);
    }

    final shipmentIds = byShipment.keys.toList();

    final shipmentRows = await _client
        .from('shipments')
        .select(
          'id, shipment_number, status, driver_employee_id, arrived_at, vehicles(plate_number)',
        )
        .inFilter('id', shipmentIds);

    final shipmentInfoById = <String, Map<String, dynamic>>{};
    for (final row in (shipmentRows as List)) {
      final map = Map<String, dynamic>.from(row);
      shipmentInfoById[map['id'] as String] = map;
    }

    final driverIds = shipmentInfoById.values
        .map((s) => s['driver_employee_id'] as String?)
        .whereType<String>()
        .toSet();

    final driverNameById = await _fetchEmployeeNames(driverIds);

    final results = byShipment.entries.map((entry) {
      final shipmentId = entry.key;
      final scans = entry.value;
      final info = shipmentInfoById[shipmentId];

      DateTime? loadedAt;
      for (final scan in scans) {
        final scannedAtRaw = scan['scanned_at'] as String?;
        final scannedAt = scannedAtRaw != null ? DateTime.parse(scannedAtRaw) : null;
        if (scannedAt == null) continue;
        if (loadedAt == null || scannedAt.isBefore(loadedAt)) {
          loadedAt = scannedAt;
        }
      }

      final driverEmployeeId = info?['driver_employee_id'] as String?;
      final status = info?['status'] as String?;

      return {
        'shipmentId': shipmentId,
        'shipmentNumber': info?['shipment_number'],
        'shipmentStatus': status,
        'vehiclePlateNumber': (info?['vehicles'] as Map?)?['plate_number'],
        'driverName': driverEmployeeId != null ? driverNameById[driverEmployeeId] : null,
        'loadedAt': loadedAt,
        'itemCount': scans.length,
        'arrivedAt': status == 'ARRIVED' && info?['arrived_at'] != null
            ? DateTime.parse(info!['arrived_at'] as String)
            : null,
      };
    }).toList();

    // Urutkan dari yang pertama dimuat -- supaya kalau resi terpecah,
    // kendaraan "pertama jalan" tampil lebih dulu di kotak biru.
    results.sort((a, b) {
      final aAt = a['loadedAt'] as DateTime?;
      final bAt = b['loadedAt'] as DateTime?;
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return aAt.compareTo(bAt);
    });

    return results;
  }

  // FITUR (9 Oktober 2026 -- permintaan user eksplisit): "Pada saat
  // diklik Monitoring Resi: Terbuka Daftar Resi. Disini tambahkan
  // Informasi tentang Resi mana yang Selesai, Masih Perjalanan dan
  // Penerimaan. Sehingga halaman ini bisa jadi kontrol pimpinan resi
  // mana yang harus segera diberangkatkan."
  //
  // BEDA dengan `getResiDeliveryMonitoring()` di atas: fungsi itu CUMA
  // mengembalikan resi yang SUDAH PERNAH dimuat ke kendaraan (resi yang
  // belum sama sekali disentuh Loading tidak ikut ter-return sama
  // sekali -- lihat baris `.eq('scan_type', 'LOAD')` di awal fungsinya,
  // tanpa itu "Penerimaan" (belum dimuat) tidak akan pernah kelihatan).
  // Fungsi ini sebaliknya CUMA menghitung progress (jumlah baris LOAD &
  // DELIVER per resi) -- keputusan "resi ini sedang di tahap apa"
  // diserahkan ke pemanggil (`ReceivingListPage`) yang membandingkan
  // angka ini ke `ReceivingModel.totalQuantity` (SEMUA resi, termasuk
  // yang progress-nya kosong/belum tersentuh Loading sama sekali).
  //
  // Key hasil = receiving_id (resi). Value:
  //   'loaded'/'delivered' (int) = jumlah BARIS shipment_scans (1 baris =
  //       1 koli discan, SAMA granularitasnya dengan
  //       `receiving.total_quantity` yang dihitung trigger DB dari
  //       SUM(receiving_details.quantity) -- lihat
  //       receiving_totals_trigger.sql -- jadi aman dibandingkan langsung
  //       tanpa konversi apa pun).
  //
  // PERLUASAN (13 Oktober 2026 -- permintaan user "Penambahan informasi
  // pada MONITORING RESI": tampilkan plat kendaraan, nama sopir, tanggal
  // loading, & tanggal tiba di daftar resi) -- ditambahkan field baru,
  // DIAMBIL DARI QUERY YANG SAMA (tanpa query tambahan per resi, supaya
  // daftar resi yang panjang tetap cuma O(1) request, bukan N+1):
  //   'vehiclePlateNumber' (String?), 'driverName' (String?) -- dari
  //       shipment yang PERTAMA kali me-LOAD resi ini (earliest scan LOAD
  //       -- kalau resi terpecah ke beberapa kendaraan, yang ditampilkan
  //       SELALU kendaraan pertama, SAMA konvensi dengan
  //       `getLoadingEventsForReceiving` di atas). null kalau resi belum
  //       pernah di-LOAD sama sekali (status Penerimaan).
  //   'loadedAt' (DateTime?) -- waktu scan LOAD PERTAMA (bukan
  //       `shipments.loaded_at`).
  //   'deliveredAt' (DateTime?) -- waktu scan DELIVER TERAKHIR. SENGAJA
  //       BUKAN `shipments.arrived_at` ("truk balik kantor", konsep
  //       beda -- lihat section #22 dokumentasi arsitektur) -- supaya
  //       nilainya selalu konsisten dengan status "Selesai" yang dihitung
  //       dari delivered>=totalQuantity: begitu resi SELESAI, baris
  //       DELIVER terakhirnya PASTI ini.
  static Future<Map<String, Map<String, dynamic>>> getReceivingProgressSummary() async {
    // BUGFIX (13 Oktober 2026 -- RESI000793 sudah ada baris LOAD valid di
    // `shipment_scans` tapi badge Monitoring Resi masih nyangkut di
    // "Penerimaan"): versi SEBELUMNYA di sini `.select()` TANPA
    // `.range()`/pagination sama sekali. Supabase/PostgREST membatasi
    // SETIAP request REST ke jumlah baris maksimum per bawaan project
    // ("Max Rows", umumnya 1000) -- kalau total baris `shipment_scans`
    // (LOAD + DELIVER, 1 baris per koli fisik) sudah melebihi itu setelah
    // ~2 bulan berjalan, baris-baris TERBARU (termasuk LOAD scan hari ini)
    // ikut KEPOTONG diam-diam dari hasil, sehingga resi yang baru saja
    // dimuat tetap terhitung 'loaded': 0 di sini walau datanya sudah ada
    // di database.
    //
    // Fix: ambil SEMUA baris lewat paging `.range(from, to)` per 1000
    // baris, looping sampai halaman terakhir (baris yang didapat < ukuran
    // halaman) -- jadi aman berapa pun besar tabelnya nanti, tidak cuma
    // menaikkan limit ke angka lain yang bisa kelebihan lagi di masa
    // depan.
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final page = await _client
          .from('shipment_scans')
          .select(
            'scan_type, shipment_id, scanned_at, scanned_by, receiving_details(receiving_id)',
          )
          .inFilter('scan_type', ['LOAD', 'DELIVER'])
          .range(from, from + pageSize - 1);

      final pageRows =
          (page as List).map((d) => Map<String, dynamic>.from(d)).toList();
      rows.addAll(pageRows);

      if (pageRows.length < pageSize) break;
      from += pageSize;
    }

    final counts = <String, Map<String, int>>{};
    // Scan LOAD PERTAMA per resi -- {shipmentId, scannedAt}.
    final earliestLoad = <String, Map<String, dynamic>>{};
    // Scan DELIVER TERAKHIR per resi.
    final latestDeliverAt = <String, DateTime>{};

    for (final map in rows) {
      final detail = map['receiving_details'] as Map<String, dynamic>?;
      final receivingId = detail?['receiving_id'] as String?;
      if (receivingId == null) continue;

      final entry = counts.putIfAbsent(
        receivingId,
        () => {'loaded': 0, 'delivered': 0},
      );
      final scanType = map['scan_type'] as String?;
      final scannedAtRaw = map['scanned_at'] as String?;
      final scannedAt = scannedAtRaw != null ? DateTime.parse(scannedAtRaw) : null;

      if (scanType == 'LOAD') {
        entry['loaded'] = (entry['loaded'] ?? 0) + 1;
        if (scannedAt != null) {
          final currentAt = earliestLoad[receivingId]?['scannedAt'] as DateTime?;
          if (currentAt == null || scannedAt.isBefore(currentAt)) {
            earliestLoad[receivingId] = {
              'shipmentId': map['shipment_id'] as String?,
              'scannedAt': scannedAt,
              // FITUR (13 Oktober 2026 -- permintaan user: "Tambahkan
              // dibelakang tanggal Loading : nama Pegawai yang loading
              // dari tabel employee"): PEGAWAI yang MELAKUKAN SCAN LOAD
              // ini -- SENGAJA BEDA dari `driverName`/sopir resmi
              // shipment (bisa admin yang loading manual, lihat temuan
              // RESI000793/TASMAN sebelumnya di sesi ini).
              'scannedBy': map['scanned_by'] as String?,
            };
          }
        }
      } else if (scanType == 'DELIVER') {
        entry['delivered'] = (entry['delivered'] ?? 0) + 1;
        if (scannedAt != null) {
          final current = latestDeliverAt[receivingId];
          if (current == null || scannedAt.isAfter(current)) {
            latestDeliverAt[receivingId] = scannedAt;
          }
        }
      }
    }

    // 1x query tambahan (bukan per resi) buat ambil plat/sopir dari
    // shipment "pemuatan pertama" tiap resi yang sudah pernah di-LOAD.
    final shipmentIds = earliestLoad.values
        .map((v) => v['shipmentId'] as String?)
        .whereType<String>()
        .toSet();

    final shipmentInfoById = <String, Map<String, dynamic>>{};
    if (shipmentIds.isNotEmpty) {
      final shipmentRows = await _client
          .from('shipments')
          .select('id, driver_employee_id, completed_by_admin, vehicles(plate_number)')
          .inFilter('id', shipmentIds.toList());
      for (final row in (shipmentRows as List)) {
        final m = Map<String, dynamic>.from(row);
        shipmentInfoById[m['id'] as String] = m;
      }
    }

    final driverIds = shipmentInfoById.values
        .map((s) => s['driver_employee_id'] as String?)
        .whereType<String>()
        .toSet();
    // FITUR (13 Oktober 2026): gabung id sopir resmi DAN id pegawai yang
    // scan LOAD jadi 1x pemanggilan `_fetchEmployeeNames` saja (bukan 2x
    // query employees terpisah).
    final scannedByIds = earliestLoad.values
        .map((v) => v['scannedBy'] as String?)
        .whereType<String>()
        .toSet();
    final employeeNameById =
        await _fetchEmployeeNames({...driverIds, ...scannedByIds});

    final result = <String, Map<String, dynamic>>{};
    for (final entry in counts.entries) {
      final receivingId = entry.key;
      final load = earliestLoad[receivingId];
      final shipmentId = load?['shipmentId'] as String?;
      final info = shipmentId != null ? shipmentInfoById[shipmentId] : null;
      final driverId = info?['driver_employee_id'] as String?;
      final scannedById = load?['scannedBy'] as String?;

      result[receivingId] = {
        'loaded': entry.value['loaded'],
        'delivered': entry.value['delivered'],
        'vehiclePlateNumber': (info?['vehicles'] as Map?)?['plate_number'],
        'driverName': driverId != null ? employeeNameById[driverId] : null,
        'loadedAt': load?['scannedAt'] as DateTime?,
        'deliveredAt': latestDeliverAt[receivingId],
        // Nama pegawai yang MELAKUKAN scan LOAD (bisa beda dari
        // `driverName` -- lihat komentar di `earliestLoad` di atas).
        'loadedByName':
            scannedById != null ? employeeNameById[scannedById] : null,
        // BUGFIX TAMPILAN (14 Oktober 2026 -- laporan user: resi yang
        // diselesaikan lewat tombol "Selesaikan (Bypass)" tampil plat
        // placeholder (SEBELUMNYA "BYPASS-SIMULASI", SEKARANG
        // "DISELESAIKAN ADMIN" -- lihat `VehicleService.
        // getOrCreateBypassVehicle`) tanpa sopir, kelihatan seperti data
        // salah/error). UI (`ReceivingListPage`) pakai flag ini untuk
        // tampilkan label yang jujur ("Diselesaikan via Bypass Admin")
        // daripada plat palsu itu.
        //
        // BUGFIX LANJUTAN (16 Oktober 2026 -- user menegaskan ada 2 jenis
        // "diselesaikan paksa admin" yang BERBEDA, lihat project doc
        // Tambahan #48): SEBELUMNYA flag ini pakai `completed_by_admin`
        // -- TERNYATA SALAH, karena `ShipmentService.forceCompleteByAdmin`
        // ("Intervensi Admin" pada shipment yang BENAR-BENAR loading pakai
        // kendaraan & sopir asli) JUGA men-set `completed_by_admin = true`,
        // jadi resi yang dimuat ke kendaraan asli tapi shipment-nya
        // diselesaikan paksa admin ikut SALAH dilabeli "Bypass Admin" padahal
        // sopirnya nyata. Diganti jadi cek identitas KENDARAAN lewat
        // `VehicleService.isBypassPlaceholderPlate` -- satu-satunya
        // pembeda yang benar antara kedua jenis itu.
        'isBypassAdmin': VehicleService.isBypassPlaceholderPlate(
          (info?['vehicles'] as Map?)?['plate_number'] as String?,
        ),
      };
    }
    return result;
  }

  // FITUR (16 Oktober 2026 -- lanjutan lazy-load Monitoring Resi
  // Supervisor, permintaan user "jangan ambil sekaligus"): versi
  // SATU-RESI dari `getReceivingProgressSummary` di atas -- dipakai
  // `_ResiCard` (`supervisor_resi_tab.dart`) HANYA saat kartu resi
  // di-expand (pola SAMA dengan `receivingDetailsProvider`, lihat
  // BUGFIX PERFORMA 16 Oktober 2026 sebelumnya), BUKAN diambil untuk
  // SEMUA resi di layar sekaligus seperti `getReceivingProgressSummary`.
  //
  // SENGAJA TANPA paging `.range()` seperti versi "semua resi" di atas
  // -- query ini sudah di-scope ke 1 `receivingId` lewat
  // `receiving_details!inner(receiving_id)` + `.eq(...)`, jumlah baris
  // `shipment_scans` utk 1 resi secara alami kecil (sejumlah koli di
  // resi itu saja), jauh di bawah limit Max Rows berapa pun besar
  // tabelnya secara keseluruhan nanti.
  //
  // Return SAMA shape persis dengan 1 value `getReceivingProgressSummary`
  // (field 'loaded'/'delivered'/'vehiclePlateNumber'/'driverName'/
  // 'loadedAt'/'deliveredAt'/'loadedByName'/'isBypassAdmin'), null kalau
  // resi belum pernah tersentuh scan LOAD/DELIVER sama sekali.
  static Future<Map<String, dynamic>?> getReceivingProgress(
    String receivingId,
  ) async {
    final rows = await _client
        .from('shipment_scans')
        .select(
          'scan_type, shipment_id, scanned_at, scanned_by, '
          'receiving_details!inner(receiving_id)',
        )
        .eq('receiving_details.receiving_id', receivingId)
        .inFilter('scan_type', ['LOAD', 'DELIVER']);

    final scanRows =
        (rows as List).map((d) => Map<String, dynamic>.from(d)).toList();

    if (scanRows.isEmpty) return null;

    var loaded = 0;
    var delivered = 0;
    Map<String, dynamic>? earliestLoad; // {shipmentId, scannedAt, scannedBy}
    DateTime? latestDeliverAt;

    for (final map in scanRows) {
      final scanType = map['scan_type'] as String?;
      final scannedAtRaw = map['scanned_at'] as String?;
      final scannedAt =
          scannedAtRaw != null ? DateTime.parse(scannedAtRaw) : null;

      if (scanType == 'LOAD') {
        loaded++;
        if (scannedAt != null) {
          final currentAt = earliestLoad?['scannedAt'] as DateTime?;
          if (currentAt == null || scannedAt.isBefore(currentAt)) {
            earliestLoad = {
              'shipmentId': map['shipment_id'] as String?,
              'scannedAt': scannedAt,
              'scannedBy': map['scanned_by'] as String?,
            };
          }
        }
      } else if (scanType == 'DELIVER') {
        delivered++;
        if (scannedAt != null &&
            (latestDeliverAt == null || scannedAt.isAfter(latestDeliverAt))) {
          latestDeliverAt = scannedAt;
        }
      }
    }

    final shipmentId = earliestLoad?['shipmentId'] as String?;
    Map<String, dynamic>? shipmentInfo;
    if (shipmentId != null) {
      shipmentInfo = await _client
          .from('shipments')
          .select(
            'id, driver_employee_id, completed_by_admin, vehicles(plate_number)',
          )
          .eq('id', shipmentId)
          .maybeSingle();
    }

    final driverId = shipmentInfo?['driver_employee_id'] as String?;
    final scannedById = earliestLoad?['scannedBy'] as String?;
    final employeeNameById = await _fetchEmployeeNames({
      if (driverId != null) driverId,
      if (scannedById != null) scannedById,
    });

    return {
      'loaded': loaded,
      'delivered': delivered,
      'vehiclePlateNumber': (shipmentInfo?['vehicles'] as Map?)?['plate_number'],
      'driverName': driverId != null ? employeeNameById[driverId] : null,
      'loadedAt': earliestLoad?['scannedAt'] as DateTime?,
      'deliveredAt': latestDeliverAt,
      'loadedByName': scannedById != null ? employeeNameById[scannedById] : null,
      // Lihat bugfix lanjutan (16 Oktober 2026) di `getReceivingProgressSummary`
      // atas pembeda yang sama -- `completed_by_admin` SENDIRI tidak cukup,
      // dicek lewat plat kendaraannya.
      'isBypassAdmin': VehicleService.isBypassPlaceholderPlate(
        (shipmentInfo?['vehicles'] as Map?)?['plate_number'] as String?,
      ),
    };
  }

  // ============================================================
  // 3. MONITORING KINERJA PERJALANAN
  // ============================================================

  /// Kinerja per shipment: durasi (trip_started_at -> arrived_at, atau
  /// sampai sekarang kalau masih jalan), progress resi, dan rincian
  /// biaya (BBM/Penginapan/Makan). Filter opsional per kendaraan/sopir.
  static Future<List<Map<String, dynamic>>> getShipmentPerformanceList({
    String? vehicleId,
    String? driverEmployeeId,
  }) async {
    final builder = _client.from('shipments').select('''
          id,
          shipment_number,
          status,
          trip_started_at,
          arrived_at,
          created_at,
          vehicle_id,
          driver_employee_id,
          completed_by_admin,
          admin_completion_note,
          trip_started_by_admin,
          admin_start_trip_note,
          vehicles(plate_number)
        ''');

    final filtered = vehicleId != null
        ? builder.eq('vehicle_id', vehicleId)
        : (driverEmployeeId != null ? builder.eq('driver_employee_id', driverEmployeeId) : builder);

    final response = await filtered.order('created_at', ascending: false);

    final shipments = (response as List).map((d) => Map<String, dynamic>.from(d)).toList();

    if (shipments.isEmpty) return [];

    final shipmentIds = shipments.map((s) => s['id'] as String).toList();

    final expenseRows = await _client
        .from('shipment_expenses')
        .select('shipment_id, expense_type, amount')
        .inFilter('shipment_id', shipmentIds);

    final expensesByShipment = <String, Map<String, double>>{};
    for (final row in (expenseRows as List)) {
      final map = Map<String, dynamic>.from(row);
      final sid = map['shipment_id'] as String;
      final type = map['expense_type'] as String;
      final amount = (map['amount'] as num).toDouble();

      expensesByShipment.putIfAbsent(sid, () => {'BBM': 0.0, 'PENGINAPAN': 0.0, 'MAKAN': 0.0});
      expensesByShipment[sid]![type] = (expensesByShipment[sid]![type] ?? 0) + amount;
    }

    final loadRows = await _client
        .from('shipment_scans')
        .select('shipment_id, receiving_detail_id, receiving_details(receiving_id)')
        .inFilter('shipment_id', shipmentIds)
        .eq('scan_type', 'LOAD');

    final deliverRows = await _client
        .from('shipment_scans')
        .select('shipment_id, receiving_detail_id')
        .inFilter('shipment_id', shipmentIds)
        .eq('scan_type', 'DELIVER');

    final deliveredDetailIdsByShipment = <String, Set<String>>{};
    for (final row in (deliverRows as List)) {
      final map = Map<String, dynamic>.from(row);
      final sid = map['shipment_id'] as String;
      final detailId = map['receiving_detail_id'] as String?;
      if (detailId == null) continue;
      deliveredDetailIdsByShipment.putIfAbsent(sid, () => {}).add(detailId);
    }

    final resiSetByShipment = <String, Set<String>>{};
    final resiDeliveredByShipment = <String, Set<String>>{};

    for (final row in (loadRows as List)) {
      final map = Map<String, dynamic>.from(row);
      final sid = map['shipment_id'] as String;
      final detail = map['receiving_details'] as Map<String, dynamic>?;
      final receivingId = detail?['receiving_id'] as String?;
      final detailId = map['receiving_detail_id'] as String?;

      if (receivingId == null) continue;
      resiSetByShipment.putIfAbsent(sid, () => {}).add(receivingId);

      final delivered =
          detailId != null && (deliveredDetailIdsByShipment[sid]?.contains(detailId) ?? false);

      if (delivered) {
        resiDeliveredByShipment.putIfAbsent(sid, () => {}).add(receivingId);
      }
    }

    final driverIds = shipments
        .map((s) => s['driver_employee_id'] as String?)
        .whereType<String>()
        .toSet();

    final driverNameById = await _fetchEmployeeNames(driverIds);

    return shipments.map((s) {
      final id = s['id'] as String;
      final expenses = expensesByShipment[id] ?? {'BBM': 0.0, 'PENGINAPAN': 0.0, 'MAKAN': 0.0};
      final totalExpense = expenses.values.fold<double>(0, (sum, v) => sum + v);

      final tripStartedAt =
          s['trip_started_at'] != null ? DateTime.parse(s['trip_started_at']) : null;
      final arrivedAt = s['arrived_at'] != null ? DateTime.parse(s['arrived_at']) : null;

      int? durationMinutes;
      if (tripStartedAt != null) {
        durationMinutes = (arrivedAt ?? DateTime.now()).difference(tripStartedAt).inMinutes;
      }

      final driverId = s['driver_employee_id'] as String?;

      return {
        'shipmentId': id,
        'shipmentNumber': s['shipment_number'],
        'status': s['status'],
        'vehicleId': s['vehicle_id'],
        'vehiclePlateNumber': (s['vehicles'] as Map?)?['plate_number'],
        'driverEmployeeId': driverId,
        'driverName': driverId != null ? driverNameById[driverId] : null,
        'tripStartedAt': tripStartedAt,
        'arrivedAt': arrivedAt,
        'durationMinutes': durationMinutes,
        'totalResi': resiSetByShipment[id]?.length ?? 0,
        'deliveredResi': resiDeliveredByShipment[id]?.length ?? 0,
        // Jejak "Intervensi Admin" -- lihat ShipmentService.forceCompleteByAdmin
        // & ShipmentService.forceStartTripByAdmin (dua ujung berbeda:
        // akhir vs awal perjalanan).
        'completedByAdmin': (s['completed_by_admin'] as bool?) ?? false,
        'adminCompletionNote': s['admin_completion_note'],
        'tripStartedByAdmin': (s['trip_started_by_admin'] as bool?) ?? false,
        'adminStartTripNote': s['admin_start_trip_note'],
        'expenseBbm': expenses['BBM'] ?? 0.0,
        'expensePenginapan': expenses['PENGINAPAN'] ?? 0.0,
        'expenseMakan': expenses['MAKAN'] ?? 0.0,
        'totalExpense': totalExpense,
      };
    }).toList();
  }

  /// Rekap kinerja per sopir -- dihitung dari getShipmentPerformanceList
  /// (semua shipment), dikelompokkan per driver_employee_id.
  static Future<List<Map<String, dynamic>>> getDriverPerformanceSummary() async {
    final shipments = await getShipmentPerformanceList();
    return _summarizeBy(
      shipments,
      idKey: 'driverEmployeeId',
      labelKey: 'driverName',
      labelField: 'driverName',
      idField: 'driverEmployeeId',
    );
  }

  /// Rekap kinerja per kendaraan -- dikelompokkan per vehicle_id.
  static Future<List<Map<String, dynamic>>> getVehiclePerformanceSummary() async {
    final shipments = await getShipmentPerformanceList();
    return _summarizeBy(
      shipments,
      idKey: 'vehicleId',
      labelKey: 'vehiclePlateNumber',
      labelField: 'vehiclePlateNumber',
      idField: 'vehicleId',
    );
  }

  static List<Map<String, dynamic>> _summarizeBy(
    List<Map<String, dynamic>> shipments, {
    required String idKey,
    required String labelKey,
    required String labelField,
    required String idField,
  }) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final s in shipments) {
      final id = s[idKey] as String?;
      if (id == null) continue;

      grouped.putIfAbsent(
        id,
        () => {
          idField: id,
          labelField: s[labelKey] ?? '-',
          'totalTrips': 0,
          'completedTrips': 0,
          'totalExpense': 0.0,
          '_totalDurationMinutes': 0,
          '_durationSamples': 0,
        },
      );

      final group = grouped[id]!;
      group['totalTrips'] = (group['totalTrips'] as int) + 1;
      if (s['status'] == 'ARRIVED') group['completedTrips'] = (group['completedTrips'] as int) + 1;
      group['totalExpense'] = (group['totalExpense'] as double) + (s['totalExpense'] as double);

      final duration = s['durationMinutes'] as int?;
      if (duration != null) {
        group['_totalDurationMinutes'] = (group['_totalDurationMinutes'] as int) + duration;
        group['_durationSamples'] = (group['_durationSamples'] as int) + 1;
      }
    }

    return grouped.values.map((g) {
      final samples = g['_durationSamples'] as int;
      return {
        ...g,
        'avgDurationMinutes':
            samples > 0 ? (g['_totalDurationMinutes'] as int) / samples : null,
      };
    }).toList();
  }

  // ============================================================
  // 4. MONITORING ZONA STORAGE
  // ============================================================

  /// FITUR (9 Oktober 2026 -- permintaan user eksplisit): "Monitoring
  /// Zona Storage. Dipilih Zona maka akan muncul daftar barang yang ada
  /// dizona dilengkapi data Nomor Resi, nomor buku, tanggal terima, nama
  /// tujuan dan alamat tujuan. Ada Fungsi Cari search ... Hanya barang
  /// yang belum diloading dan dalam perjalanan."
  ///
  /// Mengembalikan SEMUA `receiving_details` yang (a) sudah ditandai
  /// zona storage-nya (`storage_id` TIDAK null) DAN (b) BELUM PERNAH
  /// disentuh scan LOAD sama sekali. Begitu 1 scan LOAD tercatat untuk 1
  /// baris (walaupun baru sebagian dari quantity-nya, mis. baru 2 dari 5
  /// koli), baris itu dianggap SUDAH MULAI keluar dari zona fisiknya --
  /// TIDAK ikut ditampilkan lagi di sini, sesuai permintaan user "Hanya
  /// barang yang belum diloading dan dalam perjalanan" (barang yang
  /// SUDAH dimuat ATAU SEDANG dalam perjalanan dikecualikan, karena
  /// secara fisik sudah tidak ada lagi di rak/zona gudangnya).
  ///
  /// SENGAJA tidak difilter per-zona atau kata kunci apa pun di sini --
  /// kedua filter itu (pilih zona / ketik kata kunci) dilakukan di Dart
  /// oleh `StorageZoneMonitoringPage` dari HASIL YANG SAMA, supaya ganti
  /// filter tidak perlu round-trip ke Supabase tiap kali (pola yang sama
  /// dipakai `getReceivingProgressSummary` di atas).
  static Future<List<Map<String, dynamic>>> getUnloadedZoneItems() async {
    final detailRows = await _client
        .from('receiving_details')
        .select('''
          id,
          receiving_id,
          item_name,
          item_code,
          quantity,
          quantity_unit,
          storage_id,
          receiving:receiving_id (
            receipt_number,
            nomor_buku,
            received_at,
            destination,
            destination_address,
            sender_id,
            received_by,
            updated_at,
            updated_by
          )
        ''')
        .not('storage_id', 'is', null);

    final loadRows = await _client
        .from('shipment_scans')
        .select('receiving_detail_id')
        .eq('scan_type', 'LOAD');

    final loadedDetailIds = (loadRows as List)
        .map((row) => row['receiving_detail_id'] as String?)
        .whereType<String>()
        .toSet();

    final results = <Map<String, dynamic>>[];
    for (final row in (detailRows as List)) {
      final map = Map<String, dynamic>.from(row);
      final detailId = map['id'] as String?;
      if (detailId == null || loadedDetailIds.contains(detailId)) continue;

      final receiving = map['receiving'] as Map<String, dynamic>?;
      results.add({
        'detailId': detailId,
        'receivingId': map['receiving_id'],
        'itemName': map['item_name'],
        'itemCode': map['item_code'],
        'quantity': (map['quantity'] as num?)?.toDouble() ?? 0,
        'quantityUnit': map['quantity_unit'],
        'storageId': map['storage_id'],
        'receiptNumber': receiving?['receipt_number'],
        'nomorBuku': receiving?['nomor_buku'],
        'receivedAt': receiving?['received_at'],
        'destination': receiving?['destination'],
        'destinationAddress': receiving?['destination_address'],
        // FITUR (16 Oktober 2026 -- Dashboard Supervisor, kelengkapan 12
        // field): sender/received_by/updated_at/updated_by resi pemilik
        // barang ini, supaya Tab "Monitoring Barang" bisa menampilkan
        // info lengkap tanpa query tambahan per baris.
        'senderId': receiving?['sender_id'],
        'receivedByEmployeeId': receiving?['received_by'],
        'updatedAt': receiving?['updated_at'],
        'updatedBy': receiving?['updated_by'],
      });
    }

    return results;
  }

  static Future<Map<String, dynamic>> _fetchEmployeeNames(Set<String> employeeIds) async {
    if (employeeIds.isEmpty) return {};

    final rows = await _client
        .from('employees')
        .select('id, full_name')
        .inFilter('id', employeeIds.toList());

    final result = <String, dynamic>{};
    for (final row in (rows as List)) {
      final map = Map<String, dynamic>.from(row);
      result[map['id'] as String] = map['full_name'];
    }
    return result;
  }
}