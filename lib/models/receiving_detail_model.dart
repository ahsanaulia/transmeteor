/// FITUR (21 Oktober 2026 -- Section A, "Label Barcode"). Pilihan
/// jenis label untuk 1 baris `receiving_details` -- SALING EKSKLUSIF,
/// menggantikan boolean [ReceivingDetailModel.isUnlabeled] sebagai
/// sumber kebenaran (lihat doc comment [ReceivingDetailModel.labelType]
/// & `migrasi_label_barcode.sql`).
class LabelType {
  static const qr = 'QR';
  static const tanpaLabel = 'TANPA_LABEL';
  static const barcode = 'BARCODE';
}

class ReceivingDetailModel {
  final String id;
  final String receivingId;
  final String itemCode;
  final String itemTypeId;
  final String pricingTypeId;
  final String itemName;
  final double quantity;
  final String quantityUnit;
  final double? weightKg;
  final double? lengthCm;
  final double? widthCm;
  final double? heightCm;
  final double? volumeM3;
  final double? unitPrice;
  final double? totalPrice;
  // Jumlah isi fisik per SATU satuan tercetak/tercatat (mis. quantity=4
  // "ikat", bundleQuantity=5 -> 4 label dicetak, tapi total barang fisik
  // = 4*5 = 20, dan total harga = 4*5*unitPrice). null atau 1 berarti
  // TIDAK bundle -- tiap satuan quantity = 1 barang fisik, seperti biasa.
  // Ditambahkan supaya staff bisa kelompokkan barang yang diikat/dus-kan
  // jadi 1 label per bundle (bukan 1 label per barang), karena stiker
  // label 50mm cepat habis kalau tiap barang fisik dapat label sendiri.
  final int? bundleQuantity;
  // "Opsi Kiriman Tanpa Label QR" (23 September 2026) -- untuk barang
  // yang BENAR-BENAR tidak bisa dilabeli (mis. bata ringan curah 10
  // kubik, pasir, barang curah lain tanpa permukaan untuk ditempel
  // stiker). Kalau true: TIDAK ada label QR yang digenerate/dicetak sama
  // sekali untuk baris ini (beda dari bundleQuantity, yang MENGURANGI
  // jumlah label tapi tetap generate label) -- cukup [photoUrl] sebagai
  // bukti. Loading/Delivery mengonfirmasi muat/turun lewat tombol manual
  // (bukan scan QR) yang tetap mencatat 1 baris `shipment_scans` sintetis
  // per tahap, supaya seluruh logic manifest/progress/PDF yang sudah ada
  // (berbasis hitung baris shipment_scans) tetap jalan tanpa perlu
  // kasus khusus di mana-mana -- lihat `ShipmentService.recordScan` &
  // pemanggilnya di LoadingScanPage/DeliveryResiScanPage.
  final bool isUnlabeled;
  // FITUR (21 Oktober 2026 -- Section A, "Label Barcode"): MENGGANTIKAN
  // [isUnlabeled] sebagai sumber kebenaran jenis label baris ini --
  // 'QR' (default, label QR biasa) / 'TANPA_LABEL' (dulu `isUnlabeled`
  // true) / 'BARCODE' (baru -- lihat `LabelBarcodeService`). Kolom DB
  // `is_unlabeled` SEKARANG generated column dari `label_type` (lihat
  // `migrasi_label_barcode.sql`) -- [isUnlabeled] di atas TETAP ADA &
  // TETAP terisi benar dari situ (jadi SELURUH kode lama yang baca
  // `isUnlabeled` tidak perlu diubah), tapi kode BARU yang perlu
  // membedakan BARCODE dari QR (keduanya `isUnlabeled == false`) harus
  // baca field ini, bukan [isUnlabeled].
  final String labelType;
  // Foto barang (wajib diisi kalau isUnlabeled true) -- URL publik hasil
  // upload ke Supabase Storage bucket `expense-receipts` folder
  // `item-photos/` (numpang bucket yang sudah terbukti public, pola sama
  // dengan `CompanyService.uploadLogo`/`ExpenseService.uploadReceiptPhoto`).
  final String? photoUrl;
  // FITUR (8 Oktober 2026 -- permintaan user poin 1-7, fitur Zona Storage):
  // menandai di zona/lokasi storage mana barang ini diletakkan (FK ke
  // `storages`), diisi SAAT pencatatan resi (poin 3), ditampilkan di
  // checklist centang barang Loading (poin 6) supaya petugas tahu di mana
  // mencari barangnya. Boleh NULL -- barang lama / belum sempat diisi
  // zonanya tetap valid, cukup tidak tampil info zona di checklist.
  final String? storageId;
  // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
  // "Masukkan input diskon persen dan diskon nilai ... per barang.
  // Diskon ini defaultnya 0. Harga - diskon adalah nilai total biaya
  // barang."). SATU diskon per barang (bukan 2 diskon yang dijumlah,
  // dikonfirmasi user) -- [discountPercent] HANYA dipakai untuk
  // MENGHITUNG [discountAmount] di `ReceivingDetailFormSheet` (dibulatkan
  // ke kelipatan Rp1.000), [discountAmount] adalah NILAI FINAL yang
  // benar-benar sudah dikurangkan dari (quantity x bundleQuantity x
  // unitPrice) untuk menghasilkan [totalPrice] yang tersimpan -- lihat
  // `ReceivingDetailFormSheet._netPrice`. Keduanya default 0 (tidak
  // nullable) -- resi lama otomatis aman, totalPrice-nya tidak berubah.
  final double discountPercent;
  final double discountAmount;
  // FITUR (17 Oktober 2026 -- redesain arsitektur permintaan user
  // eksplisit setelah kasus RESI000311: "Seharusnya ada kolom yang
  // menjadi penentu penyelesaian di receiving_details", nama kolom
  // didiktekan user sendiri: "namanya kolom flow_state dan
  // sisa_barang"). BERBEDA dari [ReceivingComputedStatus] (yang itu
  // level RESI, dijaga trigger live dari `shipment_scans`) -- kolom ini
  // level BARANG (1 baris `receiving_details`), SENGAJA ditulis
  // LANGSUNG oleh `ShipmentService` di titik aksi spesifik (loading,
  // shipment selesai jalan, intervensi admin), BUKAN dihitung ulang live
  // dari `shipment_scans` tiap kali dibaca -- lihat
  // `migrasi_flow_state_sisa_barang.sql` untuk aturan lengkapnya.
  // [flowState]: 'BELUM_DIMUAT' (default) / 'SUDAH_DIMUAT' / 'SELESAI'.
  // [sisaBarang]: jumlah unit fisik yang BELUM dimuat ke shipment
  // manapun (0 kalau sudah tuntas termuat).
  final String flowState;
  final int sisaBarang;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReceivingDetailModel({
    required this.id,
    required this.receivingId,
    required this.itemCode,
    required this.itemTypeId,
    required this.pricingTypeId,
    required this.itemName,
    required this.quantity,
    required this.quantityUnit,
    this.weightKg,
    this.lengthCm,
    this.widthCm,
    this.heightCm,
    this.volumeM3,
    this.unitPrice,
    this.totalPrice,
    this.bundleQuantity,
    this.isUnlabeled = false,
    this.labelType = LabelType.qr,
    this.photoUrl,
    this.storageId,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.flowState = 'BELUM_DIMUAT',
    this.sisaBarang = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// true kalau baris ini dicatat sebagai bundle (mis. "4 ikat isi 5"),
  /// bukan satuan barang lepasan biasa.
  bool get isBundle => bundleQuantity != null && bundleQuantity! > 1;

  /// FITUR (21 Oktober 2026 -- Section A): true kalau baris ini pakai
  /// Label Barcode (bukan QR maupun Tanpa Label) -- lihat doc comment
  /// [labelType].
  bool get isBarcode => labelType == LabelType.barcode;

  /// Total barang fisik sebenarnya -- untuk tampilan non-bundle sama
  /// dengan [quantity], untuk bundle dikali [bundleQuantity].
  double get totalPhysicalQuantity =>
      quantity * (isBundle ? bundleQuantity! : 1);

  factory ReceivingDetailModel.fromMap(
    Map<String, dynamic> map,
  ) {
    return ReceivingDetailModel(
      id: map['id'],
      receivingId: map['receiving_id'],
      itemCode: map['item_code'],
      itemTypeId: map['item_type_id'],
      pricingTypeId: map['pricing_type_id'],
      itemName: map['item_name'],
      quantity: (map['quantity'] as num).toDouble(),
      quantityUnit: map['quantity_unit'],
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      lengthCm: (map['length_cm'] as num?)?.toDouble(),
      widthCm: (map['width_cm'] as num?)?.toDouble(),
      heightCm: (map['height_cm'] as num?)?.toDouble(),
      volumeM3: (map['volume_m3'] as num?)?.toDouble(),
      unitPrice: (map['unit_price'] as num?)?.toDouble(),
      totalPrice: (map['total_price'] as num?)?.toDouble(),
      bundleQuantity: (map['bundle_quantity'] as num?)?.toInt(),
      isUnlabeled: map['is_unlabeled'] as bool? ?? false,
      labelType: map['label_type'] as String? ?? LabelType.qr,
      photoUrl: map['photo_url'] as String?,
      storageId: map['storage_id'] as String?,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      flowState: map['flow_state'] as String? ?? 'BELUM_DIMUAT',
      sisaBarang: (map['sisa_barang'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
      // DIUBAH (21 Oktober 2026 -- Section A): `is_unlabeled` SEKARANG
      // generated column di database (lihat `migrasi_label_barcode.sql`)
      // -- TIDAK BISA lagi ditulis langsung, `label_type` yang menjadi
      // sumber kebenaran yang dikirim.
      'label_type': labelType,
      'photo_url': photoUrl,
      'storage_id': storageId,
      'discount_percent': discountPercent,
      'discount_amount': discountAmount,
      'flow_state': flowState,
      'sisa_barang': sisaBarang,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}