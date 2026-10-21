// FITUR (13 Oktober 2026 -- permintaan user "Tambahan Fitur" poin 2-4):
// status pembayaran resi. Default BAYAR_TUJUAN (dibayar di tempat tujuan
// saat barang diterima), atau BAYAR_DIKANTOR (dibayar di kantor/sebelum
// atau saat pengiriman). Diinput admin lewat fitur "Edit Resi".
/// FITUR (16 Oktober 2026 -- Monitoring Resi Supervisor, lazy-load +
/// pencarian server-side, lihat migrasi `add_receiving_computed_status.sql`):
/// status bisnis resi (BEDA dari `ReceivingModel.status` lama yang
/// isinya SELALU 'RECEIVED' -- lihat catatan di field itu). Dijaga
/// OTOMATIS oleh trigger database (`recalculate_receiving_status`),
/// SAMA formula dgn `_resiStatus()` yang dulu dihitung di Dart dari
/// `receivingProgressSummaryProvider`. Dibaca read-only dari kolom
/// `computed_status` -- aplikasi TIDAK PERNAH menulis kolom ini
/// langsung, supaya tidak ada 2 sumber kebenaran.
class ReceivingComputedStatus {
  static const penerimaan = 'PENERIMAAN';
  // FITUR (21 Oktober 2026, permintaan user eksplisit): status baru
  // "Sedang Dimuat" -- kendaraan sudah disiapkan Admin & barang sudah
  // tercatat loading, TAPI belum diberangkatkan (`vehicles.is_loading`
  // masih true). Konsisten dengan wording Monitoring Kendaraan & Sopir.
  // Lihat `migrasi_sedang_dimuat_dan_fix_selesai.sql`.
  static const sedangDimuat = 'SEDANG_DIMUAT';
  static const masihPerjalanan = 'MASIH_PERJALANAN';
  static const selesai = 'SELESAI';
}

class ReceivingPaymentStatus {
  static const bayarTujuan = 'BAYAR_TUJUAN';
  static const bayarDikantor = 'BAYAR_DIKANTOR';

  static String label(String value) {
    switch (value) {
      case bayarDikantor:
        return 'Bayar Dikantor';
      case bayarTujuan:
      default:
        return 'Bayar Tujuan';
    }
  }
}

class ReceivingModel {
  final String id;
  final String receiptNumber;
  final String senderId;
  // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs Tujuan):
  // field ini SENGAJA dibuat nullable & TIDAK LAGI diisi dari form
  // "Terima Barang" (field manual "Nama Penerima"/"No. HP" sudah
  // dihapus dari layar input, lihat receiving_create_page.dart).
  // Resi LAMA masih bisa punya nilainya (data historis, jangan dihapus/
  // dipakai lagi di laporan baru), resi BARU akan selalu null di sini.
  // Identitas "penerima" sekarang SEPENUHNYA diwakili oleh data Tujuan:
  // [destination] (nama) & [destinationPhone] (HP) di bawah -- SEMUA
  // tampilan/cetakan baru harus pakai dua field itu, BUKAN field ini.
  final String? receiverName;
  final String? receiverPhone;
  final String packageTypeId;
  final String destination;
  final String? destinationAddress;
  // FIX (5 Oktober 2026 -- permintaan user eksplisit: "jangan capture...
  // ambil dari data destinations", "itu standar aplikasi tabel relasi"):
  // SEBELUMNYA field ini snapshot (disalin sekali saat resi dibuat, lihat
  // migrasi `fix_penerima_tujuan_ambiguity.sql`) -- SEKARANG live-join
  // lewat `destination_id`, supaya begitu nomor HP diedit di tabel
  // `destinations`, SEMUA resi (lama & baru) otomatis ikut berubah di
  // semua cetakan, tanpa perlu SQL manual lagi. Diisi dari `fromMap` dari
  // relasi nested `destinations:destination_id(phone)` KALAU ada (query
  // sudah di-embed, lihat `ReceivingService`/`ShipmentService`), fallback
  // ke kolom lama `destination_phone` HANYA untuk resi yang `destinationId`
  // null (resi sangat lama sebelum ada field ini / tidak tertaut ke
  // master tujuan manapun). Kolom DB `destination_phone` & parameter
  // `destinationPhone` di create/update TETAP ada (dibiarkan terisi di DB
  // sebagai fallback historis itu), tapi TIDAK LAGI jadi sumber utama.
  final String? destinationPhone;
  final String? destinationId;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final DateTime receivedAt;
  final DateTime? expectedArrivalAt;
  final DateTime? arrivedAt;
  final int totalQuantity;
  final String receivedBy;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? route;
  final double totalPrice;
  final String? routePricingId;
  // FITUR (8 Oktober 2026 -- permintaan user poin 1-7, fitur Nomor Buku +
  // Zona Storage): nomor buku fisik (buku catatan manual perwakilan) yang
  // dicatat SAAT resi dibuat, opsional/boleh NULL. Dipakai untuk pencarian
  // di "Telusuri Kiriman" (poin 11) selain nomor resi, ditampilkan di
  // Daftar Resi (poin 4/5), dan dicetak di belakang nomor resi di semua
  // cetakan (poin 7) kalau terisi.
  final String? nomorBuku;
  // FITUR (13 Oktober 2026 -- permintaan user "Tambahan Fitur" poin 2-4):
  // status pembayaran resi (lihat ReceivingPaymentStatus) + nilai DP (Down
  // Payment, bayar sebagian di kantor). Default paymentStatus =
  // BAYAR_TUJUAN kalau DB belum mengisi (resi lama sebelum migrasi). DP
  // nullable/0 -- mayoritas resi tidak pakai DP sama sekali. Keduanya
  // HANYA diinput admin lewat fitur "Edit Resi" (bukan di layar input
  // "Terima Barang" / form tambah resi biasa).
  final String paymentStatus;
  final double? dpAmount;
  // FITUR (16 Oktober 2026 -- dibutuhkan Dashboard Supervisor, field
  // "Jika diedit kapan diperbarui datanya dan oleh siapa"): SEBELUMNYA
  // `updatedAt` sudah ada sejak awal, tapi TIDAK ADA cara tahu SIAPA
  // yang mengedit -- `updatedAt` ikut berubah bahkan untuk perubahan
  // otomatis sistem (trigger `trg_receiving_details_recalculate` saat
  // barang ditambah/diubah, bukan cuma "Edit Resi" admin). Kolom BARU
  // `updated_by` (nullable, employee id) HANYA diisi dari
  // `ReceivingService.updateReceiving` (satu-satunya tempat admin
  // mengedit header resi lewat "Edit Resi") -- resi yang BELUM PERNAH
  // di-"Edit Resi" (termasuk SEMUA resi lama sebelum migrasi kolom ini)
  // tetap null, UI menampilkan baris "Diperbarui" HANYA kalau nilai ini
  // terisi, BUKAN berdasar `updatedAt` semata (supaya tidak salah
  // menunjukkan "diedit" untuk resi yang updated_at-nya berubah murni
  // karena barang ditambah/dihitung ulang otomatis).
  final String? updatedBy;
  // FITUR (16 Oktober 2026 -- lihat doc comment `ReceivingComputedStatus`
  // di atas): status bisnis (Penerimaan/Masih Perjalanan/Selesai),
  // dihitung otomatis oleh database lewat kolom `computed_status` --
  // BEDA dari field `status` di atas (legacy, selalu 'RECEIVED').
  // Fallback ke PENERIMAAN kalau map belum punya kolom ini (migrasi
  // `add_receiving_computed_status.sql` belum dijalankan) supaya UI
  // tidak crash, bukan supaya dianggap benar -- lihat juga catatan di
  // `ReceivingService.getReceivingsPage`.
  final String computedStatus;

  ReceivingModel({
    required this.id,
    required this.receiptNumber,
    required this.senderId,
    this.receiverName,
    this.receiverPhone,
    required this.packageTypeId,
    required this.destination,
    this.destinationAddress,
    this.destinationPhone,
    this.destinationId,
    this.destinationLatitude,
    this.destinationLongitude,
    required this.receivedAt,
    this.expectedArrivalAt,
    this.arrivedAt,
    required this.totalQuantity,
    required this.receivedBy,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.route,
    required this.totalPrice,
    this.routePricingId,
    this.nomorBuku,
    this.paymentStatus = ReceivingPaymentStatus.bayarTujuan,
    this.dpAmount,
    this.updatedBy,
    this.computedStatus = ReceivingComputedStatus.penerimaan,
  });

  factory ReceivingModel.fromMap(Map<String, dynamic> map) {
    return ReceivingModel(
      id: map['id'],
      receiptNumber: map['receipt_number'],
      senderId: map['sender_id'],
      receiverName: map['receiver_name'],
      receiverPhone: map['receiver_phone'],
      packageTypeId: map['package_type_id'],
      destination: map['destination'],
      destinationAddress: map['destination_address'],
      // Live-join dulu (lihat catatan panjang di field `destinationPhone`
      // di atas) -- `map['destinations']` cuma ada kalau query pemanggil
      // sudah di-embed (`destinations:destination_id(phone)`). Kalau
      // tidak ada embed-nya (atau destination_id null / tujuan sudah
      // dihapus), fallback ke kolom snapshot lama supaya tidak tiba-tiba
      // kosong untuk pemanggil yang belum sempat diupdate query-nya.
      destinationPhone:
          (map['destinations'] as Map<String, dynamic>?)?['phone']
                  as String? ??
              map['destination_phone'] as String?,
      destinationId: map['destination_id'] as String?,
      destinationLatitude: (map['destination_latitude'] as num?)?.toDouble(),
      destinationLongitude: (map['destination_longitude'] as num?)?.toDouble(),
      receivedAt: DateTime.parse(map['received_at']),
      expectedArrivalAt: map['expected_arrival_at'] != null
          ? DateTime.parse(map['expected_arrival_at'])
          : null,
      arrivedAt: map['arrived_at'] != null
          ? DateTime.parse(map['arrived_at'])
          : null,
      totalQuantity: map['total_quantity'] ?? 0,
      receivedBy: map['received_by'],
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      route: map['route'],
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0,
      routePricingId: map['route_pricing_id'],
      nomorBuku: map['nomor_buku'] as String?,
      paymentStatus:
          map['payment_status'] as String? ??
              ReceivingPaymentStatus.bayarTujuan,
      dpAmount: (map['dp_amount'] as num?)?.toDouble(),
      updatedBy: map['updated_by'] as String?,
      computedStatus: map['computed_status'] as String? ??
          ReceivingComputedStatus.penerimaan,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_number': receiptNumber,
      'sender_id': senderId,
      'receiver_name': receiverName,
      'receiver_phone': receiverPhone,
      'package_type_id': packageTypeId,
      'destination': destination,
      'destination_address': destinationAddress,
      'destination_phone': destinationPhone,
      'destination_id': destinationId,
      'destination_latitude': destinationLatitude,
      'destination_longitude': destinationLongitude,
      'received_at': receivedAt.toIso8601String(),
      'expected_arrival_at': expectedArrivalAt?.toIso8601String(),
      'arrived_at': arrivedAt?.toIso8601String(),
      'total_quantity': totalQuantity,
      'received_by': receivedBy,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'route': route,
      'total_price': totalPrice,
      'route_pricing_id': routePricingId,
      'nomor_buku': nomorBuku,
      'payment_status': paymentStatus,
      'dp_amount': dpAmount,
      'updated_by': updatedBy,
    };
  }
}