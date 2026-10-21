import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';

import '../models/receiving_model.dart';
import '../models/receiving_detail_model.dart';

class ReceivingService {
  static final _client = SupabaseService.client;

  // Numpang bucket `expense-receipts` yang sudah PUBLIC & terbukti jalan
  // (dipakai company logo & bukti pengeluaran -- lihat
  // `CompanyService.uploadLogo`/`ExpenseService.uploadReceiptPhoto`) --
  // supaya tidak perlu bikin bucket baru lagi di Supabase Dashboard
  // (langkah manual yang pernah lupa dilakukan & menyebabkan upload logo
  // gagal diam-diam, lihat catatan di `CompanyService`).
  static const _photoBucket = 'expense-receipts';
  static const _photoFolder = 'item-photos';

  // FIX (5 Oktober 2026 -- permintaan user eksplisit: "jangan capture...
  // ambil dari data destinations", "itu standar aplikasi tabel relasi",
  // "ini berlaku untuk semua printout"): nomor HP tujuan TIDAK LAGI
  // dipercaya dari kolom snapshot `destination_phone` -- SEMUA query
  // `receiving` di bawah pakai select ini supaya hasilnya SELALU bawa
  // nomor HP LIVE dari tabel `destinations` (lewat relasi
  // `destination_id`), dibaca `ReceivingModel.fromMap` lewat key nested
  // `destinations.phone`. Berlaku untuk SEMUA cetakan yang pakai
  // `ReceivingModel.destinationPhone` (Resi/WA/Tanda Terima/dll) karena
  // semua baca dari field yang sama ini -- tidak perlu ubah tiap halaman
  // satu-satu, cukup di sumber datanya di sini.
  static const _receivingSelectWithLiveDestination =
      '*, destinations:destination_id(phone)';

  /// Upload foto barang (untuk item "Tanpa Label QR") ke Supabase
  /// Storage, balikin URL publiknya. Dipanggil dari
  /// `ReceivingDetailFormSheet` saat simpan, HANYA kalau staff memilih
  /// toggle "Tanpa Label QR" & mengambil foto baru.
  static Future<String> uploadItemPhoto({
    required String receivingId,
    required Uint8List bytes,
  }) async {
    final path =
        '$_photoFolder/$receivingId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage.from(_photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    return _client.storage.from(_photoBucket).getPublicUrl(path);
  }

  // ============================================================
  // RECEIVING
  // ============================================================

  /// Mengambil semua receiving.
  ///
  /// BUGFIX (16 Oktober 2026 -- laporan user: "Saat semua resi diload ...
  /// seharusnya kan kita tidak mengambil sekaligus?"): versi SEBELUMNYA
  /// di sini `.select()` TANPA `.range()`/paging sama sekali -- SAMA
  /// persis bug yang sudah pernah ditemukan & diperbaiki di
  /// `MonitoringService.getReceivingProgressSummary` (lihat doc comment
  /// di sana, 13 Oktober 2026). Supabase/PostgREST membatasi SETIAP
  /// request REST ke jumlah baris maksimum per bawaan project ("Max
  /// Rows", umumnya 1000) -- begitu total baris `receiving` melebihi
  /// itu, baris TERTUA otomatis KEPOTONG diam-diam dari hasil (karena
  /// `.order('created_at', ascending: false)` + limit implisit =
  /// SELALU buang yang paling lama lebih dulu), jadi Monitoring Resi
  /// (Admin maupun Supervisor) diam-diam kehilangan resi lama TANPA
  /// error apa pun yang kelihatan.
  ///
  /// Fix: paging `.range(from, to)` per 1000 baris, looping sampai
  /// halaman terakhir (baris yang didapat < ukuran halaman) -- SAMA
  /// pola dengan `getReceivingProgressSummary`, supaya SELALU dapat
  /// SEMUA baris berapa pun besar tabelnya, bukan sekadar menaikkan
  /// limit ke angka lain yang bisa kelebihan lagi di masa depan.
  ///
  /// CATATAN PERFORMA (belum dikerjakan, perlu keputusan terpisah):
  /// fix ini menjamin BENAR (tidak ada lagi resi yang hilang diam-diam),
  /// TAPI tetap mengambil & menyimpan SEMUA resi ke memori setiap kali
  /// Monitoring Resi dibuka -- di skala besar (user menyebut target
  /// ~100.000 resi) ini akan tetap terasa berat dibanding pagination
  /// sungguhan (infinite scroll/"muat lagi" dari server per halaman +
  /// pencarian/filter status dipindah ke query server). Itu perubahan
  /// arsitektur lebih besar (menyentuh Admin `ReceivingListPage` &
  /// Supervisor `SupervisorResiTab` sekaligus, plus logic pencarian &
  /// filter status yang sekarang jalan di Dart) -- SENGAJA belum
  /// dikerjakan di sini, perlu dikonfirmasi dulu ke user.
  static Future<List<ReceivingModel>> getReceivings() async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      // CATATAN: tiebreaker kedua `.order('id', ...)` SENGAJA
      // ditambahkan -- `.order('created_at', ...)` SAJA bukan urutan
      // yang unik (bisa ada >1 resi dengan `created_at` SAMA persis
      // kalau diinput beruntun cepat), jadi tanpa tiebreaker, baris
      // yang timestamp-nya "kebetulan pas di perbatasan 2 halaman" bisa
      // ke-skip ATAU kedobelan antar `.range()` -- `id` dijamin unik
      // jadi urutannya SELALU deterministik & konsisten antar halaman.
      final page = await _client
          .from('receiving')
          .select(_receivingSelectWithLiveDestination)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(from, from + pageSize - 1);

      final pageRows =
          (page as List).map((d) => Map<String, dynamic>.from(d)).toList();
      rows.addAll(pageRows);

      if (pageRows.length < pageSize) break;
      from += pageSize;
    }

    return rows.map((data) => ReceivingModel.fromMap(data)).toList();
  }

  // FITUR (16 Oktober 2026 -- lanjutan BUGFIX di atas, "true" lazy-
  // loading permintaan user): dipakai `SupervisorResiTab` (Monitoring
  // Resi Supervisor) sebagai pengganti `getReceivings()` di atas --
  // BUKAN ambil SEMUA resi lalu filter/cari di Dart, tapi 1 HALAMAN
  // kecil (`limit`) langsung dari Supabase, dengan kata kunci & filter
  // status DIKIRIM ke query (`.or`/`.eq`), bukan disaring belakangan di
  // memori. Status pakai kolom `computed_status` (lihat
  // `ReceivingComputedStatus` di `receiving_model.dart` & migrasi
  // `add_receiving_computed_status.sql`) -- dijaga otomatis oleh
  // trigger database, BUKAN dihitung lagi di sini.
  //
  // Scope SEKARANG baru Supervisor (`SupervisorResiTab`) -- Admin
  // `ReceivingListPage` BELUM dipindah ke method ini, masih pakai
  // `getReceivings()` lama (fetch semua), sesuai keputusan user supaya
  // perubahan scope-nya bertahap/lebih kecil risikonya.
  static Future<List<ReceivingModel>> getReceivingsPage({
    String keyword = '',
    String? status,
    bool sortOldestFirst = false,
    required int limit,
    required int offset,
  }) async {
    var query =
        _client.from('receiving').select(_receivingSelectWithLiveDestination);

    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isNotEmpty) {
      // Escape `%` (wildcard ILIKE) & `,` (pemisah antar kondisi di
      // `.or()`) di dalam kata kunci user supaya tidak merusak sintaks
      // filter PostgREST kalau kebetulan diketik user.
      final escaped =
          trimmedKeyword.replaceAll('%', r'\%').replaceAll(',', r'\,');
      query = query.or(
        'receipt_number.ilike.%$escaped%,'
        'nomor_buku.ilike.%$escaped%,'
        'destination.ilike.%$escaped%',
      );
    }

    if (status != null) {
      query = query.eq('computed_status', status);
    }

    // Tiebreaker `.order('id', ...)` -- alasan SAMA dengan
    // `getReceivings()` di atas (urutan deterministik antar halaman
    // walau ada `created_at` yang sama persis).
    final response = await query
        .order('created_at', ascending: sortOldestFirst)
        .order('id', ascending: sortOldestFirst)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((data) => ReceivingModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }

  /// Hitung jumlah resi per status (`computed_status`) -- dipakai badge
  /// angka di chip filter status Monitoring Resi Supervisor
  /// ("Penerimaan (12)", dst). SENGAJA hanya select kolom
  /// `computed_status` saja (BUKAN seluruh baris / tanpa join
  /// `destinations` seperti `getReceivings`/`getReceivingsPage`) supaya
  /// jauh lebih ringan, TAPI tetap paging `.range()` per 1000 baris
  /// (pola sama dengan method lain di atas) karena jumlah barisnya
  /// sendiri tetap bisa melebihi limit Max Rows di skala besar.
  ///
  /// Dipanggil SEKALI saat tab dibuka/di-refresh (BUKAN tiap kali user
  /// mengetik kata kunci) -- angkanya independen dari pencarian, sama
  /// perilaku dengan versi lama yang menghitung dari seluruh daftar
  /// resi (bukan dari hasil yang sudah tersaring kata kunci).
  static Future<Map<String, int>> getReceivingStatusCounts() async {
    const pageSize = 1000;
    final counts = <String, int>{
      'TOTAL': 0,
      ReceivingComputedStatus.penerimaan: 0,
      ReceivingComputedStatus.masihPerjalanan: 0,
      ReceivingComputedStatus.selesai: 0,
    };
    var from = 0;
    while (true) {
      final page = await _client
          .from('receiving')
          .select('computed_status')
          .range(from, from + pageSize - 1);

      final pageRows = (page as List);
      for (final row in pageRows) {
        final status = (Map<String, dynamic>.from(row))['computed_status']
                as String? ??
            ReceivingComputedStatus.penerimaan;
        counts['TOTAL'] = (counts['TOTAL'] ?? 0) + 1;
        counts[status] = (counts[status] ?? 0) + 1;
      }

      if (pageRows.length < pageSize) break;
      from += pageSize;
    }

    return counts;
  }

  /// Mengambil satu receiving berdasarkan ID.
  static Future<ReceivingModel?> getReceivingById(
    String id,
  ) async {
    final response = await _client
        .from('receiving')
        .select(_receivingSelectWithLiveDestination)
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ReceivingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Mengambil detail barang berdasarkan item_code. Dipakai saat scan
  /// loading -- QR yang dicetak berisi item_code, jadi hasil scan perlu
  /// di-resolve ke baris receiving_details ini.
  static Future<ReceivingDetailModel?> getReceivingDetailByItemCode(
    String itemCode,
  ) async {
    final response = await _client
        .from('receiving_details')
        .select()
        .eq('item_code', itemCode)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ReceivingDetailModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Mengambil receiving berdasarkan nomor resi.
  static Future<ReceivingModel?> getReceivingByReceiptNumber(
    String receiptNumber,
  ) async {
    final response = await _client
        .from('receiving')
        .select(_receivingSelectWithLiveDestination)
        .eq('receipt_number', receiptNumber)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ReceivingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Mengambil receiving berdasarkan nomor buku. Dipakai "Telusuri
  /// Kiriman" (poin 11) supaya customer bisa cari pakai nomor buku kalau
  /// mereka tidak punya/ingat nomor resinya.
  static Future<ReceivingModel?> getReceivingByNomorBuku(
    String nomorBuku,
  ) async {
    final response = await _client
        .from('receiving')
        .select(_receivingSelectWithLiveDestination)
        .eq('nomor_buku', nomorBuku)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ReceivingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Membuat receiving baru.
  ///
  /// Nomor resi dibuat otomatis oleh Supabase.
  /// Flutter tidak mengirim receipt_number.
  ///
  /// NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs Tujuan):
  /// [receiverName]/[receiverPhone] SENGAJA dibuat nullable & sudah
  /// TIDAK dikirim dari `ReceivingCreatePage` lagi (field manualnya
  /// sudah dihapus dari layar input) -- parameter ini dipertahankan
  /// cuma untuk kompatibilitas kalau ada pemanggil lain, defaultnya
  /// selalu null untuk resi baru. Identitas "penerima" sekarang
  /// sepenuhnya diwakili oleh [destination] (nama tujuan) & nomor HP
  /// tujuan.
  ///
  /// [destinationPhone] di sini TETAP dikirim & disimpan ke kolom
  /// `destination_phone` (fallback historis, lihat catatan di
  /// `ReceivingModel.destinationPhone`), TAPI SEJAK 5 Oktober 2026 ini
  /// BUKAN LAGI sumber utama yang ditampilkan/dicetak -- semua cetakan
  /// sekarang baca nomor HP LIVE dari tabel `destinations` lewat
  /// [destinationId] (lihat `_receivingSelectWithLiveDestination`).
  static Future<ReceivingModel> createReceiving({
    required String senderId,
    String? receiverName,
    String? receiverPhone,
    required String packageTypeId,
    required String destination,
    String? destinationAddress,
    String? destinationPhone,
    String? destinationId,
    DateTime? receivedAt,
    DateTime? expectedArrivalAt,
    required String receivedBy,
    String? route,
    String? routePricingId,
    // FITUR (8 Oktober 2026 -- poin 1-7, Nomor Buku): opsional, dicatat
    // saat resi dibuat kalau staff punya nomor buku fisiknya.
    String? nomorBuku,
  }) async {
    final data = {
      'sender_id': senderId,
      'receiver_name': receiverName,
      'receiver_phone': receiverPhone,
      'package_type_id': packageTypeId,
      'destination': destination,
      'destination_address': destinationAddress,
      'destination_phone': destinationPhone,
      'destination_id': destinationId,
      'received_at':
          (receivedAt ?? DateTime.now()).toIso8601String(),
      'expected_arrival_at':
          expectedArrivalAt?.toIso8601String(),
      'received_by': receivedBy,
      'status': 'RECEIVED',
      'route': route,
      'route_pricing_id': routePricingId,
      'nomor_buku': nomorBuku,
    };

    final response = await _client
        .from('receiving')
        .insert(data)
        .select(_receivingSelectWithLiveDestination)
        .single();

    return ReceivingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Mengubah status receiving.
  static Future<void> updateReceivingStatus({
    required String receivingId,
    required String status,
  }) async {
    await _client
        .from('receiving')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', receivingId);
  }

  /// FITUR (13 Oktober 2026 -- permintaan user "Tambahan Fitur", fitur
  /// baru "Edit Resi"): update header resi secara umum (BUKAN cuma status
  /// seperti [updateReceivingStatus] atau cuma koordinat seperti
  /// [updateDestinationCoordinates]). Dipanggil dari `ReceivingEditSheet`
  /// yang diakses lewat tombol "Edit Resi" di halaman Detail Monitoring
  /// Resi (bukan bagian "edit" lain yang sudah ada -- lihat catatan
  /// user: "Bukan dibagian edit. Tetapi di Resi. Edit Resi").
  ///
  /// Ini SATU-SATUNYA tempat admin menginput [paymentStatus] (status
  /// pembayaran: Bayar Tujuan/Bayar Dikantor) & [dpAmount] (DP, bayar
  /// sebagian di kantor) -- field ini TIDAK ADA di layar "Terima Barang"
  /// (`receiving_create_page.dart`) sama sekali.
  ///
  /// SENGAJA tidak menyentuh `destination_latitude`/`destination_longitude`
  /// (sudah ada method sendiri, [updateDestinationCoordinates]) ataupun
  /// `status`/`arrived_at` (field operasional, lihat
  /// [updateReceivingStatus]) -- supaya tidak ada 2 jalur berbeda yang
  /// bisa saling menimpa field yang sama.
  /// [updatedBy]: id employee admin yang menekan simpan di "Edit Resi"
  /// -- FITUR (16 Oktober 2026, dibutuhkan Dashboard Supervisor field
  /// "Jika diedit kapan diperbarui datanya dan oleh siapa"). Lihat doc
  /// comment `ReceivingModel.updatedBy` untuk detail kenapa field ini
  /// terpisah dari `updatedAt`.
  static Future<ReceivingModel> updateReceiving({
    required String receivingId,
    required String senderId,
    required String packageTypeId,
    required String destination,
    String? destinationAddress,
    String? destinationPhone,
    String? destinationId,
    String? route,
    String? routePricingId,
    String? nomorBuku,
    required String paymentStatus,
    double? dpAmount,
    required String updatedBy,
  }) async {
    final data = {
      'sender_id': senderId,
      'package_type_id': packageTypeId,
      'destination': destination,
      'destination_address': destinationAddress,
      'destination_phone': destinationPhone,
      'destination_id': destinationId,
      'route': route,
      'route_pricing_id': routePricingId,
      'nomor_buku': nomorBuku,
      'payment_status': paymentStatus,
      'dp_amount': dpAmount,
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await _client
        .from('receiving')
        .update(data)
        .eq('id', receivingId)
        .select(_receivingSelectWithLiveDestination)
        .single();

    return ReceivingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Menghapus receiving.
  ///
  /// Detail receiving akan ikut terhapus karena
  /// foreign key receiving_details menggunakan ON DELETE CASCADE.
  ///
  /// PERBAIKAN (14 Oktober 2026 -- permintaan user eksplisit: "Proses
  /// penghapusan resi di Admin. Harus menghapus data loading, jika
  /// sudah loading. Agar data tidak salah"). SEBELUMNYA, kalau resi ini
  /// sudah pernah discan LOAD/DELIVER ke sebuah shipment, Postgres
  /// MENOLAK hapusnya (FK violation `shipment_scans.receiving_detail_id`,
  /// `PostgrestException.code == '23503'`) -- penghapusan resi jadi
  /// tidak bisa jalan sama sekali selama masih ada riwayat loading.
  /// SEKARANG: SEMUA baris `shipment_scans` (LOAD maupun DELIVER) milik
  /// resi ini DIHAPUS DULU sebelum resi-nya sendiri dihapus, supaya
  /// penghapusan tetap BISA jalan tanpa menyisakan data loading yang
  /// salah/menggantung (mis. manifest/monitoring shipment yang masih
  /// "mengira" resi ini ada, padahal sudah terhapus admin).
  static Future<void> deleteReceiving(
    String receivingId,
  ) async {
    final detailsResponse = await _client
        .from('receiving_details')
        .select('id')
        .eq('receiving_id', receivingId);

    final detailIds = (detailsResponse as List)
        .map((d) => (d as Map)['id'] as String)
        .toList();

    if (detailIds.isNotEmpty) {
      await _client
          .from('shipment_scans')
          .delete()
          .inFilter('receiving_detail_id', detailIds);
    }

    await _client
        .from('receiving')
        .delete()
        .eq('id', receivingId);
  }

  // ============================================================
  // RECEIVING DETAILS
  // ============================================================
  //
  // NOTE: total_quantity & total_price pada tabel `receiving` dihitung
  // ulang otomatis oleh trigger Postgres `trg_receiving_details_recalculate`
  // (lihat supabase/receiving_totals_trigger.sql) setiap ada perubahan
  // di tabel ini. Service di sini tidak perlu (dan tidak boleh) menghitung
  // ulang total secara manual dari Flutter -- supaya totalnya tetap benar
  // walaupun datanya diubah dari luar aplikasi.

  /// Mengambil semua detail dari satu receiving.
  static Future<List<ReceivingDetailModel>>
      getReceivingDetails(
    String receivingId,
  ) async {
    final response = await _client
        .from('receiving_details')
        .select()
        .eq('receiving_id', receivingId)
        .order('created_at', ascending: true);

    return (response as List)
        .map(
          (data) => ReceivingDetailModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  /// Mengambil satu detail berdasarkan ID.
  static Future<ReceivingDetailModel?> getReceivingDetailById(
    String detailId,
  ) async {
    final response = await _client
        .from('receiving_details')
        .select()
        .eq('id', detailId)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ReceivingDetailModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Menambahkan detail barang ke receiving.
  static Future<ReceivingDetailModel> createReceivingDetail({
    required String receivingId,
    required String itemCode,
    required String itemTypeId,
    required String pricingTypeId,
    required String itemName,
    required double quantity,
    required String quantityUnit,
    double? weightKg,
    double? lengthCm,
    double? widthCm,
    double? heightCm,
    double? volumeM3,
    double? unitPrice,
    double? totalPrice,
    int? bundleQuantity,
    bool isUnlabeled = false,
    String? photoUrl,
    // FITUR (8 Oktober 2026 -- poin 3/6, Zona Storage): opsional, zona
    // tempat barang ini diletakkan di storage.
    String? storageId,
    // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang). Lihat
    // doc comment [ReceivingDetailModel.discountPercent]/[discountAmount]
    // -- default 0, jadi semua pemanggil lama (ReceivingItemsPage,
    // AdminReceivingDetailDialog) yang tidak mengisi parameter ini TIDAK
    // terpengaruh sama sekali.
    double discountPercent = 0,
    double discountAmount = 0,
  }) async {
    final data = {
      'receiving_id': receivingId,
      'item_code': itemCode,
      'item_type_id': itemTypeId,
      'pricing_type_id': pricingTypeId,
      'item_name': itemName,
      'quantity': quantity,
      'quantity_unit': quantityUnit,
      'weight_kg': weightKg,
      'length_cm': lengthCm,
      'width_cm': widthCm,
      'height_cm': heightCm,
      'volume_m3': volumeM3,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'bundle_quantity': bundleQuantity,
      'is_unlabeled': isUnlabeled,
      'photo_url': photoUrl,
      'storage_id': storageId,
      'discount_percent': discountPercent,
      'discount_amount': discountAmount,
    };

    final response = await _client
        .from('receiving_details')
        .insert(data)
        .select()
        .single();

    return ReceivingDetailModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Mengubah detail barang.
  static Future<ReceivingDetailModel>
      updateReceivingDetail({
    required String detailId,
    required String itemCode,
    required String itemTypeId,
    required String pricingTypeId,
    required String itemName,
    required double quantity,
    required String quantityUnit,
    double? weightKg,
    double? lengthCm,
    double? widthCm,
    double? heightCm,
    double? volumeM3,
    double? unitPrice,
    double? totalPrice,
    int? bundleQuantity,
    bool isUnlabeled = false,
    String? photoUrl,
    // FITUR (8 Oktober 2026 -- poin 3/6, Zona Storage): opsional, zona
    // tempat barang ini diletakkan di storage.
    String? storageId,
    // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang). Lihat
    // doc comment [ReceivingDetailModel.discountPercent]/[discountAmount]
    // -- default 0, jadi semua pemanggil lama (ReceivingItemsPage,
    // AdminReceivingDetailDialog) yang tidak mengisi parameter ini TIDAK
    // terpengaruh sama sekali.
    double discountPercent = 0,
    double discountAmount = 0,
  }) async {
    final data = {
      'item_code': itemCode,
      'item_type_id': itemTypeId,
      'pricing_type_id': pricingTypeId,
      'item_name': itemName,
      'quantity': quantity,
      'quantity_unit': quantityUnit,
      'weight_kg': weightKg,
      'length_cm': lengthCm,
      'width_cm': widthCm,
      'height_cm': heightCm,
      'volume_m3': volumeM3,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'bundle_quantity': bundleQuantity,
      'is_unlabeled': isUnlabeled,
      'photo_url': photoUrl,
      'storage_id': storageId,
      'discount_percent': discountPercent,
      'discount_amount': discountAmount,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await _client
        .from('receiving_details')
        .update(data)
        .eq('id', detailId)
        .select()
        .single();

    return ReceivingDetailModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  /// Menghapus detail barang.
  ///
  /// Kalau barang ini sudah pernah discan LOAD ke sebuah shipment,
  /// `shipment_scans.receiving_detail_id` menolak hapusnya (FK violation,
  /// `PostgrestException.code == '23503'`). Pemanggil (UI) yang menangkap
  /// error ini, BUKAN method ini, supaya pesannya bisa disesuaikan
  /// konteks.
  ///
  /// CATATAN (14 Oktober 2026): ini BEDA dengan `deleteReceiving` (hapus
  /// 1 resi PENUH) yang sekarang ikut menghapus data `shipment_scans`
  /// resi itu lebih dulu supaya resi yang sudah loading tetap bisa
  /// dihapus -- method INI (hapus 1 BARIS barang saja, bukan seluruh
  /// resi) TIDAK diubah, masih ditolak FK kalau barang itu sudah
  /// dimuat, supaya admin tidak diam-diam menghapus riwayat loading 1
  /// barang tanpa sadar sementara resi lainnya di baris lain masih utuh.
  static Future<void> deleteReceivingDetail(
    String detailId,
  ) async {
    await _client
        .from('receiving_details')
        .delete()
        .eq('id', detailId);
  }

  /// FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
  /// "Editing di sisi Admin ... Pertimbangan tambahan bahwa barang ini
  /// sudah dimuat diloading. Jadi tidak boleh ada loading ulang"). Dipakai
  /// `ReceivingItemDetailPage` SEBELUM admin boleh mengubah
  /// jumlah/menghapus barang -- kalau sebagian unit fisiknya SUDAH discan
  /// LOAD ke sebuah kendaraan, admin tidak boleh mengurangi jumlah sampai
  /// di bawah angka itu (unit yang sudah di kendaraan tidak boleh "hilang"
  /// dari data tanpa discan ulang) ataupun menghapus barisnya sama sekali
  /// (ditegakkan ganda lewat FK violation di atas sebagai jaring pengaman
  /// kalau ada yang lolos dari pengecekan di UI).
  ///
  /// Hitung berapa unit FISIK dari satu baris `receiving_details` yang
  /// sudah discan LOAD (ke shipment apa pun) -- SAMA PERSIS basis
  /// perhitungan "sudah dimuat" yang dipakai
  /// `ShipmentService.getAvailableItemsForManualLoad` (unit_code dari
  /// `shipment_scans` dengan `scan_type = 'LOAD'`), supaya tidak ada 2
  /// definisi "sudah dimuat" yang berbeda di aplikasi ini.
  static Future<int> getLoadedUnitCount(String detailId) async {
    final response = await _client
        .from('shipment_scans')
        .select('unit_code')
        .eq('receiving_detail_id', detailId)
        .eq('scan_type', 'LOAD');

    return (response as List).length;
  }

  /// FITUR (17 Oktober 2026, permintaan user eksplisit: "Perbaiki bagian
  /// loading Tanpa Label agar ada isian jumlah barang. Bukan hanya
  /// centang... Jadi loading tanpa QR bisa split barang").
  ///
  /// Membagi 1 baris barang CURAH/TANPA LABEL (`isUnlabeled == true`)
  /// jadi 2, supaya checklist "Loading Tanpa QR" (dipakai staff & admin
  /// lewat `ManualLoadChecklistView`) bisa memuat SEBAGIAN saja dari
  /// quantity-nya, bukan cuma "semua atau tidak sama sekali" seperti
  /// sebelumnya. Logikanya PERSIS SAMA dengan skrip SQL manual yang
  /// sebelumnya dipakai admin untuk kasus ini (`split_receiving_detail_
  /// partial_departed.sql`) -- dipindah ke sini supaya tidak perlu lagi
  /// buka Supabase SQL Editor tiap kali ada barang curah yang dimuat
  /// sebagian:
  ///   - Baris LAMA (id TETAP SAMA -- penting, supaya kalau baris ini
  ///     SUDAH pernah ada scan apa pun yang menunjuk id ini, scan itu
  ///     tetap valid): quantity diturunkan jadi [loadedQuantity] --
  ///     merepresentasikan porsi yang SEKARANG dimuat. Pemanggil
  ///     ([ShipmentService.recordManualLoad]) yang mencatat scan LOAD-nya
  ///     SETELAH split ini selesai, ke unit sintetis `NOLABEL-<id lama>`.
  ///   - Baris BARU: quantity = sisanya (quantity asli - [loadedQuantity]),
  ///     item_code baru (formula SAMA dengan `ReceivingItemsPage`:
  ///     `{nomor resi}-{urutan 2 digit}`), BELUM ada scan sama sekali --
  ///     otomatis tetap/kembali muncul di checklist Loading (sisa barang
  ///     yang masih menunggu, mis. karena truk hari itu sudah penuh).
  /// Harga (`total_price`) & diskon (`discount_amount`) dibagi
  /// proporsional sesuai porsi quantity, sama seperti skrip SQL-nya --
  /// `receiving.total_quantity`/`total_price` otomatis ikut benar lewat
  /// trigger `trg_receiving_details_recalculate` yang sudah ada di
  /// database, TIDAK perlu disentuh manual di sini.
  ///
  /// Mengembalikan id baris BARU (porsi sisa). Melempar [Exception] kalau
  /// [loadedQuantity] di luar rentang (0, quantity asli) -- pemanggil
  /// harus memastikan dulu [loadedQuantity] < quantity asli SEBELUM
  /// memanggil ini (kalau sama besar, tidak perlu split sama sekali --
  /// cukup scan langsung baris aslinya).
  static Future<String> splitReceivingDetailForPartialLoad({
    required String detailId,
    required double loadedQuantity,
  }) async {
    final original = await getReceivingDetailById(detailId);
    if (original == null) {
      throw Exception('receiving_details dengan id $detailId tidak ditemukan.');
    }

    if (loadedQuantity <= 0 || loadedQuantity >= original.quantity) {
      throw Exception(
        'loadedQuantity ($loadedQuantity) harus lebih dari 0 dan kurang '
        'dari quantity asli baris ini (${original.quantity}).',
      );
    }

    final remainingQuantity = original.quantity - loadedQuantity;

    final receiving = await getReceivingById(original.receivingId);
    if (receiving == null) {
      throw Exception('receiving dengan id ${original.receivingId} tidak ditemukan.');
    }

    final existingDetails = await getReceivingDetails(original.receivingId);
    final nextSeq = existingDetails.length + 1;
    final newItemCode =
        '${receiving.receiptNumber}-${nextSeq.toString().padLeft(2, '0')}';

    // Bagi harga & diskon proporsional sesuai porsi quantity -- SAMA
    // dengan rumus di `split_receiving_detail_partial_departed.sql`.
    final origDiscount = original.discountAmount;
    final origUnitPrice = original.unitPrice ?? 0.0;
    final oldDiscount =
        ((origDiscount * loadedQuantity) / original.quantity * 100).round() / 100;
    final newDiscount = origDiscount - oldDiscount;
    final oldTotal =
        ((origUnitPrice * loadedQuantity) * 100).round() / 100 - oldDiscount;
    final newTotal =
        ((origUnitPrice * remainingQuantity) * 100).round() / 100 - newDiscount;

    // Baris LAMA (id tetap sama) -- sekarang mewakili porsi yang sedang
    // dimuat.
    await updateReceivingDetail(
      detailId: original.id,
      itemCode: original.itemCode,
      itemTypeId: original.itemTypeId,
      pricingTypeId: original.pricingTypeId,
      itemName: original.itemName,
      quantity: loadedQuantity,
      quantityUnit: original.quantityUnit,
      weightKg: original.weightKg,
      lengthCm: original.lengthCm,
      widthCm: original.widthCm,
      heightCm: original.heightCm,
      volumeM3: original.volumeM3,
      unitPrice: original.unitPrice,
      totalPrice: oldTotal,
      bundleQuantity: original.bundleQuantity,
      isUnlabeled: original.isUnlabeled,
      photoUrl: original.photoUrl,
      storageId: original.storageId,
      discountPercent: original.discountPercent,
      discountAmount: oldDiscount,
    );

    // Baris BARU -- porsi yang masih tinggal, belum ada scan sama sekali.
    final newDetail = await createReceivingDetail(
      receivingId: original.receivingId,
      itemCode: newItemCode,
      itemTypeId: original.itemTypeId,
      pricingTypeId: original.pricingTypeId,
      itemName: original.itemName,
      quantity: remainingQuantity,
      quantityUnit: original.quantityUnit,
      weightKg: original.weightKg,
      lengthCm: original.lengthCm,
      widthCm: original.widthCm,
      heightCm: original.heightCm,
      volumeM3: original.volumeM3,
      unitPrice: original.unitPrice,
      totalPrice: newTotal,
      bundleQuantity: original.bundleQuantity,
      isUnlabeled: original.isUnlabeled,
      photoUrl: original.photoUrl,
      storageId: original.storageId,
      discountPercent: original.discountPercent,
      discountAmount: newDiscount,
    );

    return newDetail.id;
  }

  // ============================================================
  // KOORDINAT TUJUAN (geocoding / pilihan manual di peta)
  // ============================================================

  /// Menyimpan koordinat tujuan hasil geocoding otomatis ATAU hasil staff
  /// pilih manual titik di peta.
  static Future<ReceivingModel> updateDestinationCoordinates({
    required String receivingId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client
        .from('receiving')
        .update({
          'destination_latitude': latitude,
          'destination_longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', receivingId)
        .select(_receivingSelectWithLiveDestination)
        .single();

    return ReceivingModel.fromMap(Map<String, dynamic>.from(response));
  }
}
