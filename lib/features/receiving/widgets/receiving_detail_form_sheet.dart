import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/item_type_model.dart';
import '../../../models/pricing_type_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/storage_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/receiving_service.dart';

/// Bottom sheet untuk tambah / ubah satu baris detail barang
/// (receiving_details) pada suatu resi.
///
/// Mode tambah: [existing] null, [itemCodeForNew] wajib diisi (kode item
/// sudah di-generate otomatis oleh pemanggil, lihat receiving_items_page).
/// Mode ubah: [existing] diisi -- item_code tidak berubah, field lain
/// di-prefill dari data yang sudah ada.
///
/// Widget ini melakukan sendiri panggilan ke ReceivingService (create/
/// update) -- pemanggil cukup `await showModalBottomSheet(...)` lalu
/// invalidate provider kalau hasilnya `true`.
///
/// [allowTotalOverride] (21 September 2026) -- khusus alur "Ubah Harga
/// (Admin)" dari `ReceivingItemDetailPage`: normalnya "Total Harga" cuma
/// teks read-only hasil `quantity * bundleQuantity * unitPrice` (tidak
/// bisa diubah manual). Kebutuhan pimpinan: total akhir kadang perlu
/// DIBULATKAN/DINAIKKAN dari kebijakan (mis. 3 barang @ Rp100.000 =
/// Rp300.000 otomatis, tapi pimpinan minta jadi Rp350.000) TANPA harus
/// mengarang-ngarang harga satuan supaya hasil kali-nya pas. Sengaja TIDAK
/// menambah kolom baru di Supabase -- kolom `receiving_details.total_price`
/// SUDAH ADA dan sudah nullable/independen dari `unit_price` (lihat
/// `ReceivingService`, tidak pernah dihitung ulang otomatis di database),
/// jadi cukup override NILAI yang dikirim ke `total_price` dari sisi
/// Flutter. `unit_price` yang tersimpan tetap apa adanya (harga satuan
/// asli) -- cuma totalnya yang boleh menyimpang dari qty × harga satuan,
/// dan itu memang legal secara data (bukan bug).
class ReceivingDetailFormSheet extends ConsumerStatefulWidget {
  final bool allowTotalOverride;
  final String receivingId;
  final String? itemCodeForNew;
  final ReceivingDetailModel? existing;
  // FITUR (8 Oktober 2026, lanjutan lagi -- "Editing di sisi Admin ...
  // tidak boleh ada loading ulang"): jumlah unit FISIK barang ini yang
  // SUDAH discan LOAD ke sebuah kendaraan (lihat
  // `ReceivingService.getLoadedUnitCount`, diisi pemanggil --
  // `ReceivingItemDetailPage` -- SEBELUM sheet ini dibuka). Default 0 =
  // belum ada yang dimuat / mode tambah baru, jadi behaviour LAMA (bebas
  // isi berapa saja) tetap sama persis untuk semua pemanggil lain
  // (`ReceivingItemsPage`, `AdminReceivingEntryPage`, dll) yang tidak
  // mengisi parameter ini. Kalau > 0, `_save()` menolak jumlah akhir di
  // bawah angka ini -- unit yang sudah fisik ada di kendaraan tidak boleh
  // "hilang" dari data tanpa discan ulang.
  final double minQuantity;

  const ReceivingDetailFormSheet({
    super.key,
    required this.receivingId,
    this.itemCodeForNew,
    this.existing,
    this.allowTotalOverride = false,
    this.minQuantity = 0,
  }) : assert(
          existing != null || itemCodeForNew != null,
          'itemCodeForNew wajib diisi kalau mode tambah baru',
        );

  @override
  ConsumerState<ReceivingDetailFormSheet> createState() =>
      _ReceivingDetailFormSheetState();
}

class _ReceivingDetailFormSheetState
    extends ConsumerState<ReceivingDetailFormSheet> {
  late final TextEditingController _itemNameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _quantityUnitController;
  late final TextEditingController _weightController;
  late final TextEditingController _lengthController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _bundleQuantityController;
  late final TextEditingController _totalPriceOverrideController;
  // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang, "Pada
  // Monitoring Resi bagian Editing"). Lihat doc comment
  // [ReceivingDetailModel.discountPercent]/[discountAmount]. Dua
  // controller ini SELALU dibuat (bahkan kalau `allowTotalOverride`
  // false & field-nya tidak ditampilkan) supaya `_discountAmount`/
  // `_netPrice` aman dipanggil di mana pun -- defaultnya '0', jadi untuk
  // alur staff biasa (ReceivingItemsPage) yang tidak menampilkan field
  // ini, `_netPrice` selalu sama dengan `_totalPrice` (tidak ada efek
  // apa pun, perilaku lama tetap sama persis).
  late final TextEditingController _discountPercentController;
  late final TextEditingController _discountAmountController;

  ItemTypeModel? _selectedItemType;
  PricingTypeModel? _selectedPricingType;
  // FITUR (8 Oktober 2026 -- poin 3/6, Zona Storage): opsional, dipilih
  // staff saat input barang supaya nanti terlihat di checklist Loading
  // (poin 6) di mana lokasi fisik barang ini di gudang/perwakilan.
  StorageModel? _selectedStorage;

  // "Opsi Kiriman Tanpa Label QR" (23 September 2026) -- lihat doc
  // comment [ReceivingDetailModel.isUnlabeled]. _existingPhotoUrl dipakai
  // mode ubah (sudah ada foto tersimpan sebelumnya, ditampilkan sampai
  // staff ambil foto baru buat ganti). _newPhoto diisi kalau staff baru
  // saja ambil foto di sesi form ini -- belum ter-upload sampai _save().
  bool _isUnlabeled = false;
  XFile? _newPhoto;
  String? _existingPhotoUrl;

  bool _isSaving = false;
  String? _errorMessage;

  // Lihat doc comment [ReceivingDetailFormSheet.allowTotalOverride] di
  // atas. `_isSyncingTotalOverrideField` mencegah listener
  // `_onTotalOverrideFieldChanged` salah mengira update PROGRAMATIS (dari
  // `_syncTotalOverrideField`) sebagai ketikan manual admin.
  bool _totalManuallyOverridden = false;
  bool _isSyncingTotalOverrideField = false;

  // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang). Pola
  // IDENTIK `_totalManuallyOverridden`/`_isSyncingTotalOverrideField` di
  // atas, cuma untuk field "Diskon (Rp)": begitu admin isi % ATAU
  // quantity/harga satuan berubah, nilai Rp dihitung ulang otomatis
  // (dibulatkan ke kelipatan Rp1.000) KECUALI admin sudah pernah
  // mengetik manual di field Rp itu sendiri -- lihat
  // [_syncDiscountAmountField]/[_onDiscountAmountFieldChanged].
  bool _discountAmountManuallyOverridden = false;
  bool _isSyncingDiscountAmountField = false;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _itemNameController =
        TextEditingController(text: existing?.itemName ?? '');
    _quantityController = TextEditingController(
      text: existing != null ? _trimNumber(existing.quantity) : '1',
    );
    _quantityUnitController = TextEditingController(
      text: existing?.quantityUnit ?? 'UNIT',
    );
    _weightController = TextEditingController(
      text:
          existing?.weightKg != null ? _trimNumber(existing!.weightKg!) : '',
    );
    _lengthController = TextEditingController(
      text:
          existing?.lengthCm != null ? _trimNumber(existing!.lengthCm!) : '',
    );
    _widthController = TextEditingController(
      text: existing?.widthCm != null ? _trimNumber(existing!.widthCm!) : '',
    );
    _heightController = TextEditingController(
      text:
          existing?.heightCm != null ? _trimNumber(existing!.heightCm!) : '',
    );
    _unitPriceController = TextEditingController(
      text: existing?.unitPrice != null
          ? _trimNumber(existing!.unitPrice!)
          : '',
    );
    // Kosong = tidak bundle (1 satuan tercetak = 1 barang fisik).
    _bundleQuantityController = TextEditingController(
      text: (existing?.bundleQuantity != null && existing!.bundleQuantity! > 1)
          ? existing.bundleQuantity!.toString()
          : '',
    );

    _totalPriceOverrideController = TextEditingController(
      text: existing?.totalPrice != null
          ? _trimNumber(existing!.totalPrice!)
          : '',
    );

    // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang). Lihat
    // doc comment field [_discountPercentController]/[_discountAmountController]
    // di atas -- selalu '0' kalau belum pernah diisi (item baru ATAU
    // resi lama dari sebelum fitur ini ada).
    _discountPercentController = TextEditingController(
      text: _trimNumber(existing?.discountPercent ?? 0),
    );
    _discountAmountController = TextEditingController(
      text: _trimNumber(existing?.discountAmount ?? 0),
    );

    _isUnlabeled = existing?.isUnlabeled ?? false;
    _existingPhotoUrl = existing?.photoUrl;

    // Kalau resi ini SEBELUMNYA sudah pernah di-override manual (total
    // tersimpan tidak sama dengan qty × bundle × harga satuan - diskon
    // yang tersimpan), anggap sudah "manually overridden" dari awal
    // supaya saat form dibuka lagi TIDAK diam-diam ditimpa balik ke
    // hasil otomatis oleh listener kalkulator di bawah. Perbandingannya
    // SEKARANG pakai `computedNetFromExisting` (gross - diskon), BUKAN
    // gross polos lagi -- supaya item yang punya diskon tapi totalnya
    // TIDAK pernah di-override manual tidak salah terdeteksi sebagai
    // "override" cuma karena bedanya diskon.
    if (widget.allowTotalOverride && existing != null && existing.totalPrice != null) {
      final bundleMultiplier =
          (existing.bundleQuantity != null && existing.bundleQuantity! > 1)
              ? existing.bundleQuantity!
              : 1;
      final computedGrossFromExisting =
          existing.quantity * bundleMultiplier * (existing.unitPrice ?? 0);
      final computedNetFromExisting =
          computedGrossFromExisting - existing.discountAmount;

      if ((existing.totalPrice! - computedNetFromExisting).abs() > 0.5) {
        _totalManuallyOverridden = true;
      }

      // Pola yang sama untuk field Diskon (Rp): kalau nilai diskon
      // tersimpan beda dari hasil hitung otomatis (persen x gross,
      // dibulatkan ke kelipatan Rp1.000), anggap sudah "diedit manual"
      // dari awal -- supaya tidak diam-diam ditimpa balik begitu form
      // dibuka lagi.
      final computedDiscountFromExisting = _roundToThousand(
        computedGrossFromExisting * existing.discountPercent / 100,
      );
      if ((existing.discountAmount - computedDiscountFromExisting).abs() > 0.5) {
        _discountAmountManuallyOverridden = true;
      }
    }

    _quantityController.addListener(_onCalculatorFieldChanged);
    _unitPriceController.addListener(_onCalculatorFieldChanged);
    _bundleQuantityController.addListener(_onCalculatorFieldChanged);
    if (widget.allowTotalOverride) {
      _totalPriceOverrideController.addListener(_onTotalOverrideFieldChanged);
      _discountPercentController.addListener(_onDiscountPercentFieldChanged);
      _discountAmountController.addListener(_onDiscountAmountFieldChanged);
    }
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _quantityController.dispose();
    _quantityUnitController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _unitPriceController.dispose();
    _bundleQuantityController.dispose();
    _totalPriceOverrideController.dispose();
    _discountPercentController.dispose();
    _discountAmountController.dispose();

    super.dispose();
  }

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  void _onCalculatorFieldChanged() {
    setState(() {});

    // Gross (qty × bundle × harga satuan) berubah -- sinkronkan diskon
    // (Rp) DULU (kalau belum pernah diedit manual), baru field Total
    // Harga (yang sekarang = gross - diskon, lihat [_netPrice]), supaya
    // urutannya benar: total selalu baca diskon yang SUDAH ter-update.
    if (widget.allowTotalOverride && !_discountAmountManuallyOverridden) {
      _syncDiscountAmountField();
    }
    if (widget.allowTotalOverride && !_totalManuallyOverridden) {
      _syncTotalOverrideField();
    }
  }

  // Dipanggil dari listener [_totalPriceOverrideController] -- begitu
  // admin ketik apapun di field Total Harga (Admin), tandai sebagai
  // override manual (berhenti mengikuti hitungan otomatis) KECUALI
  // perubahan itu berasal dari [_syncTotalOverrideField] sendiri (dijaga
  // lewat [_isSyncingTotalOverrideField]).
  void _onTotalOverrideFieldChanged() {
    if (_isSyncingTotalOverrideField) return;
    if (!_totalManuallyOverridden) {
      setState(() => _totalManuallyOverridden = true);
    }
  }

  void _syncTotalOverrideField() {
    _isSyncingTotalOverrideField = true;
    _totalPriceOverrideController.text = _trimNumber(_netPrice);
    _isSyncingTotalOverrideField = false;
  }

  // Tombol "pakai hitungan otomatis lagi" -- admin berubah pikiran,
  // lepas override-nya, balik ikut qty × bundle × harga satuan - diskon.
  void _resetTotalOverride() {
    setState(() => _totalManuallyOverridden = false);
    _syncTotalOverrideField();
  }

  // ============================================================
  // DISKON PER BARANG (8 Oktober 2026, lanjutan lagi -- "Pada Monitoring
  // Resi bagian Editing ... Masukkan input diskon persen dan diskon
  // nilai"). Pola IDENTIK Total Harga Override di atas -- lihat doc
  // comment [_discountAmountManuallyOverridden] untuk alasan kenapa 2
  // mekanisme ini sengaja dibuat sama.
  // ============================================================

  // Dipanggil dari listener [_discountPercentController] -- begitu admin
  // ketik persen diskon, hitung ulang nilai Rp-nya (dibulatkan ke
  // kelipatan Rp1.000) KECUALI field Rp sudah pernah diedit manual.
  void _onDiscountPercentFieldChanged() {
    setState(() {});
    if (!_discountAmountManuallyOverridden) {
      _syncDiscountAmountField();
    }
    if (!_totalManuallyOverridden) {
      _syncTotalOverrideField();
    }
  }

  // Dipanggil dari listener [_discountAmountController] -- begitu admin
  // ketik LANGSUNG di field Rp (baik untuk koreksi hasil bulatan
  // otomatis, "jika hasil nilai diskon pecahan bisa diedit agar bulat",
  // maupun mengisi diskon flat tanpa lewat persen sama sekali), tandai
  // override manual (berhenti ikut dihitung ulang dari persen) KECUALI
  // perubahan itu berasal dari [_syncDiscountAmountField] sendiri.
  void _onDiscountAmountFieldChanged() {
    if (_isSyncingDiscountAmountField) return;
    if (!_discountAmountManuallyOverridden) {
      setState(() => _discountAmountManuallyOverridden = true);
    } else {
      setState(() {});
    }
    if (!_totalManuallyOverridden) {
      _syncTotalOverrideField();
    }
  }

  void _syncDiscountAmountField() {
    _isSyncingDiscountAmountField = true;
    _discountAmountController.text = _trimNumber(
      _roundToThousand(_totalPrice * _discountPercent / 100),
    );
    _isSyncingDiscountAmountField = false;
  }

  // Tombol "pakai hitungan otomatis lagi" untuk diskon -- sama seperti
  // [_resetTotalOverride], admin berubah pikiran & balik ikut hasil
  // bulatan otomatis dari persen.
  void _resetDiscountAmountOverride() {
    setState(() => _discountAmountManuallyOverridden = false);
    _syncDiscountAmountField();
    if (!_totalManuallyOverridden) {
      _syncTotalOverrideField();
    }
  }

  // Pembulatan ke kelipatan Rp1.000 terdekat (dikonfirmasi user) --
  // dipakai HANYA untuk hasil hitung otomatis persen->Rp, lihat doc
  // comment [ReceivingDetailModel.discountPercent].
  double _roundToThousand(double value) => (value / 1000).round() * 1000;

  double _parseNumber(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
  }

  double get _quantity => _parseNumber(_quantityController.text);
  double get _unitPrice => _parseNumber(_unitPriceController.text);
  double get _discountPercent => _parseNumber(_discountPercentController.text);
  double get _discountAmount => _parseNumber(_discountAmountController.text);

  // Isi per bundle (mis. "5" kalau 1 ikat isi 5 barang). null/kosong/<=1
  // berarti TIDAK bundle -- lihat catatan di ReceivingDetailModel.bundleQuantity.
  //
  // Item "Tanpa Label QR" SELALU null -- bundle itu konsep "kurangi
  // jumlah label yang dicetak", tidak relevan kalau memang tidak ada
  // label sama sekali.
  int? get _bundleQuantity {
    if (_isUnlabeled) return null;

    final raw = _bundleQuantityController.text.trim();
    if (raw.isEmpty) return null;

    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 1) return null;

    return parsed;
  }

  // ============================================================
  // FOTO BARANG (khusus item "Tanpa Label QR")
  // ============================================================

  Future<void> _pickPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (photo != null) {
      setState(() {
        _newPhoto = photo;
        // Foto baru menggantikan foto lama -- begitu staff simpan,
        // _existingPhotoUrl yang lama tidak dipakai lagi (diganti hasil
        // upload _newPhoto di _save()).
      });
    }
  }

  bool get _isBundle => _bundleQuantity != null;

  // Total GROSS (SEBELUM diskon) = jumlah satuan tercetak x isi per
  // bundle (1 kalau bukan bundle) x harga satuan. Contoh bundle: 4 ikat x
  // isi 5 x Rp30.000 = Rp600.000, tapi cuma 4 label yang dicetak (bukan
  // 20). TIDAK DIUBAH semantiknya (masih gross) walau fitur diskon
  // ditambahkan -- lihat [_netPrice] untuk hasil SETELAH diskon.
  double get _totalPrice => _quantity * (_bundleQuantity ?? 1) * _unitPrice;

  // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang): "Harga -
  // diskon adalah nilai total biaya barang" (permintaan user eksplisit).
  // Untuk alur yang TIDAK menampilkan field diskon (`allowTotalOverride`
  // false), `_discountAmount` selalu 0 (controller-nya tidak pernah
  // disentuh), jadi `_netPrice` selalu SAMA PERSIS `_totalPrice` --
  // perilaku lama tetap tidak berubah sama sekali untuk alur itu.
  double get _netPrice => _totalPrice - _discountAmount;

  // Nilai yang BENERAN dikirim ke `total_price` saat simpan & yang
  // ditampilkan di field admin -- pakai override manual kalau memang
  // sedang di-override, kalau tidak fallback ke hitungan otomatis
  // (sekarang net, bukan gross lagi -- lihat [_netPrice]).
  double get _effectiveTotalPrice {
    if (widget.allowTotalOverride && _totalManuallyOverridden) {
      return _parseNumber(_totalPriceOverrideController.text);
    }
    return _netPrice;
  }

  double? _optionalNumber(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }

  double? get _volumeM3 {
    final length = _optionalNumber(_lengthController.text);
    final width = _optionalNumber(_widthController.text);
    final height = _optionalNumber(_heightController.text);

    if (length == null || width == null || height == null) {
      return null;
    }

    return (length * width * height) / 1000000;
  }

  // ============================================================
  // PREFILL PILIHAN DARI DATA EXISTING (mode ubah)
  // ============================================================
  //
  // item_type_id/pricing_type_id existing cuma berupa ID (string), jadi
  // dicocokkan ke object model-nya begitu daftar item type / pricing type
  // selesai dimuat. Aman dipanggil di build() tanpa setState karena nilainya
  // dibaca lagi di build yang sama.

  // (8 Oktober 2026 -- ditambah [_hasPrefilled]): dulu dicek lewat
  // `_selectedItemType != null || _selectedPricingType != null` -- begitu
  // storage (yang boleh null walau sudah di-prefill) ikut jadi bagian
  // prefill, guard lama itu TIDAK CUKUP lagi (storage null tidak bisa
  // dibedakan dari "belum pernah di-prefill"). Flag eksplisit ini
  // menjamin prefill HANYA jalan SEKALI, persis perilaku lama -- supaya
  // kalau staff sengaja meng-clear salah satu pilihan (mis. Jenis Tarif),
  // build berikutnya TIDAK diam-diam mengisi ulang dari data existing.
  bool _hasPrefilled = false;

  void _prefillFromExisting(
    List<ItemTypeModel> itemTypes,
    List<PricingTypeModel> pricingTypes, [
    List<StorageModel> storages = const [],
  ]) {
    if (_hasPrefilled) return;

    final existing = widget.existing;
    if (existing == null) return;

    _hasPrefilled = true;

    for (final itemType in itemTypes) {
      if (itemType.id == existing.itemTypeId) {
        _selectedItemType = itemType;
        break;
      }
    }

    for (final pricingType in pricingTypes) {
      if (pricingType.id == existing.pricingTypeId) {
        _selectedPricingType = pricingType;
        break;
      }
    }

    // FITUR (8 Oktober 2026 -- poin 3): prefill zona storage dari
    // existing.storageId KALAU ada (resi lama bisa null, aman).
    if (existing.storageId != null) {
      for (final storage in storages) {
        if (storage.id == existing.storageId) {
          _selectedStorage = storage;
          break;
        }
      }
    }
  }

  void _selectPricingType(PricingTypeModel pricingType) {
    setState(() {
      _selectedPricingType = pricingType;
      _unitPriceController.text = _trimNumber(pricingType.price);
    });
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final itemName = _itemNameController.text.trim();
    final quantityUnit = _quantityUnitController.text.trim();

    if (itemName.isEmpty) {
      setState(() => _errorMessage = 'Nama barang wajib diisi.');
      return;
    }

    if (_selectedItemType == null) {
      setState(() => _errorMessage = 'Jenis barang wajib dipilih.');
      return;
    }

    if (_selectedPricingType == null) {
      setState(() => _errorMessage = 'Jenis tarif wajib dipilih.');
      return;
    }

    if (_quantity <= 0) {
      setState(() => _errorMessage = 'Jumlah barang harus lebih dari 0.');
      return;
    }

    // Lihat doc comment [ReceivingDetailFormSheet.minQuantity] -- jaring
    // pengaman utama "tidak boleh ada loading ulang" (permintaan user
    // eksplisit, 8 Oktober 2026). Dicek di sini (bukan cuma dibatasi di
    // UI) supaya tidak bisa dilewati lewat jalur mana pun.
    if (_quantity < widget.minQuantity) {
      setState(() => _errorMessage =
          'Jumlah tidak bisa dikurangi sampai di bawah '
          '${_trimNumber(widget.minQuantity)} -- sejumlah itu barang ini '
          'sudah dimuat ke kendaraan dan tidak boleh di-loading ulang.');
      return;
    }

    if (quantityUnit.isEmpty) {
      setState(() => _errorMessage = 'Satuan wajib diisi.');
      return;
    }

    // Item "Tanpa Label QR" wajib ada foto -- baik baru diambil sesi ini
    // (_newPhoto) maupun sudah ada dari sebelumnya (mode ubah,
    // _existingPhotoUrl). Tanpa foto, tidak ada bukti fisik barang ini
    // sama sekali (karena memang tidak ada label QR juga).
    if (_isUnlabeled && _newPhoto == null && _existingPhotoUrl == null) {
      setState(() => _errorMessage =
          'Barang Tanpa Label QR wajib difoto dulu sebagai bukti.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // Upload foto baru dulu kalau ada -- URL hasil upload inilah yang
      // dikirim sebagai photoUrl. Kalau tidak ada foto baru tapi mode
      // ubah & sebelumnya sudah ada foto, pertahankan URL lama. Kalau
      // togglenya OFF, foto tidak relevan lagi -- jangan dikirim.
      String? photoUrl;
      if (_isUnlabeled) {
        if (_newPhoto != null) {
          final bytes = await _newPhoto!.readAsBytes();
          photoUrl = await ReceivingService.uploadItemPhoto(
            receivingId: widget.receivingId,
            bytes: bytes,
          );
        } else {
          photoUrl = _existingPhotoUrl;
        }
      }

      if (_isEditMode) {
        await ReceivingService.updateReceivingDetail(
          detailId: widget.existing!.id,
          itemCode: widget.existing!.itemCode,
          itemTypeId: _selectedItemType!.id,
          pricingTypeId: _selectedPricingType!.id,
          itemName: itemName,
          quantity: _quantity,
          quantityUnit: quantityUnit,
          weightKg: _optionalNumber(_weightController.text),
          lengthCm: _optionalNumber(_lengthController.text),
          widthCm: _optionalNumber(_widthController.text),
          heightCm: _optionalNumber(_heightController.text),
          volumeM3: _volumeM3,
          unitPrice: _unitPrice,
          totalPrice: _effectiveTotalPrice,
          bundleQuantity: _bundleQuantity,
          isUnlabeled: _isUnlabeled,
          photoUrl: photoUrl,
          storageId: _selectedStorage?.id,
          discountPercent: _discountPercent,
          discountAmount: _discountAmount,
        );
      } else {
        await ReceivingService.createReceivingDetail(
          receivingId: widget.receivingId,
          itemCode: widget.itemCodeForNew!,
          itemTypeId: _selectedItemType!.id,
          pricingTypeId: _selectedPricingType!.id,
          itemName: itemName,
          quantity: _quantity,
          quantityUnit: quantityUnit,
          weightKg: _optionalNumber(_weightController.text),
          lengthCm: _optionalNumber(_lengthController.text),
          widthCm: _optionalNumber(_widthController.text),
          heightCm: _optionalNumber(_heightController.text),
          volumeM3: _volumeM3,
          unitPrice: _unitPrice,
          totalPrice: _effectiveTotalPrice,
          bundleQuantity: _bundleQuantity,
          isUnlabeled: _isUnlabeled,
          photoUrl: photoUrl,
          storageId: _selectedStorage?.id,
          discountPercent: _discountPercent,
          discountAmount: _discountAmount,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final itemTypesAsync = ref.watch(itemTypesProvider);
    final pricingTypesAsync = ref.watch(pricingTypesProvider);
    final storagesAsync = ref.watch(storagesProvider);

    if (itemTypesAsync.hasValue &&
        pricingTypesAsync.hasValue &&
        storagesAsync.hasValue) {
      _prefillFromExisting(
        itemTypesAsync.value!,
        pricingTypesAsync.value!,
        storagesAsync.value!,
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E4EC),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditMode ? 'Ubah Barang' : 'Tambah Barang',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppCard(
                        child: Column(
                          children: [
                            AppTextField(
                              controller: _itemNameController,
                              label: 'Nama Barang',
                              hint: 'Contoh: Kardus Elektronik',
                              icon: Icons.inventory_2_outlined,
                              enabled: !_isSaving,
                            ),
                            const SizedBox(height: 14),
                            PickerField<ItemTypeModel>(
                              label: 'Jenis Barang',
                              hint: 'Pilih jenis barang',
                              sheetTitle: 'Pilih Jenis Barang',
                              icon: Icons.category_outlined,
                              enabled: !_isSaving,
                              itemsAsync: itemTypesAsync,
                              itemsProvider: itemTypesProvider,
                              itemLabel: (type) => type.name,
                              itemSubtitle: (type) => type.handling,
                              selected: _selectedItemType,
                              onSelected: (type) {
                                setState(() => _selectedItemType = type);
                              },
                              onClear: () {
                                setState(() => _selectedItemType = null);
                              },
                            ),
                            const SizedBox(height: 14),
                            PickerField<PricingTypeModel>(
                              label: 'Jenis Tarif',
                              hint: 'Pilih jenis tarif',
                              sheetTitle: 'Pilih Jenis Tarif',
                              icon: Icons.sell_outlined,
                              enabled: !_isSaving,
                              itemsAsync: pricingTypesAsync,
                              itemsProvider: pricingTypesProvider,
                              itemLabel: (type) => type.name,
                              itemSubtitle: (type) => formatRupiah(type.price),
                              selectedText: (type) =>
                                  '${type.name} · ${formatRupiah(type.price)}',
                              selected: _selectedPricingType,
                              onSelected: _selectPricingType,
                              onClear: () {
                                setState(() => _selectedPricingType = null);
                              },
                            ),
                            const SizedBox(height: 14),
                            // FITUR (8 Oktober 2026 -- poin 3, Zona
                            // Storage): opsional -- dipilih staff kalau
                            // sudah tahu di zona mana barang ini akan
                            // diletakkan. Dipakai nanti di checklist
                            // Loading (poin 6) supaya petugas tahu di
                            // mana mencari barangnya.
                            PickerField<StorageModel>(
                              label: 'Zona Storage (Opsional)',
                              hint: 'Pilih zona penyimpanan, kalau ada',
                              sheetTitle: 'Pilih Zona Storage',
                              icon: Icons.warehouse_outlined,
                              enabled: !_isSaving,
                              itemsAsync: storagesAsync,
                              itemsProvider: storagesProvider,
                              itemLabel: (storage) => storage.namaZona,
                              itemSubtitle: (storage) => storage.deskripsi,
                              selected: _selectedStorage,
                              onSelected: (storage) {
                                setState(() => _selectedStorage = storage);
                              },
                              onClear: () {
                                setState(() => _selectedStorage = null);
                              },
                            ),
                            // Tombol refresh manual -- pelengkap fix realtime
                            // di picker_field.dart (lihat doc comment di
                            // sana). Realtime SEHARUSNYA sudah cukup, tapi
                            // ini jaring pengaman kalau koneksi WebSocket
                            // sempat putus/terlambat -- staff tidak perlu
                            // menutup & membuka ulang seluruh form cuma
                            // untuk memuat ulang daftar Jenis Tarif.
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: pricingTypesAsync.isLoading
                                    ? null
                                    : () {
                                        ref.invalidate(pricingTypesProvider);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            duration: Duration(seconds: 1),
                                            content:
                                                Text('Memuat ulang Jenis Tarif...'),
                                          ),
                                        );
                                      },
                                icon: pricingTypesAsync.isLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Ambil Tarif Baru'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.blue,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: AppTextField(
                                    controller: _quantityController,
                                    label: _isUnlabeled
                                        ? 'Jumlah'
                                        : 'Jumlah (yg dicetak label)',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    enabled: !_isSaving,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: AppTextField(
                                    controller: _quantityUnitController,
                                    label: 'Satuan',
                                    hint: 'pcs / ikat / dus / kubik',
                                    enabled: !_isSaving,
                                  ),
                                ),
                              ],
                            ),
                            // FITUR (8 Oktober 2026, lanjutan lagi --
                            // "tidak boleh ada loading ulang"): kasih
                            // tahu DULU sebelum admin coba kurangi &
                            // ditolak `_save()` -- lihat doc comment
                            // [ReceivingDetailFormSheet.minQuantity].
                            if (widget.minQuantity > 0) ...[
                              const SizedBox(height: 14),
                              InfoBanner(
                                variant: InfoBannerVariant.warning,
                                message:
                                    '${_trimNumber(widget.minQuantity)} dari barang ini sudah '
                                    'dimuat ke kendaraan. Jumlah tidak bisa dikurangi di '
                                    'bawah angka itu -- nama & harga tetap bebas diubah.',
                              ),
                            ],
                            // Bundle = kurangi JUMLAH LABEL yang dicetak --
                            // tidak relevan untuk item "Tanpa Label QR"
                            // (lihat toggle di kartu bawah), karena memang
                            // tidak ada label sama sekali yang dicetak.
                            if (!_isUnlabeled) ...[
                              const SizedBox(height: 14),
                              AppTextField(
                                controller: _bundleQuantityController,
                                label: 'Isi per Satuan (Bundle) -- opsional',
                                hint:
                                    'Kosongkan kalau lepasan. Isi mis. 5 kalau '
                                    '1 ${_quantityUnitController.text.trim().isEmpty ? 'ikat' : _quantityUnitController.text.trim()} '
                                    'berisi 5 barang',
                                icon: Icons.inventory_outlined,
                                keyboardType: TextInputType.number,
                                enabled: !_isSaving,
                              ),
                              // Penjelasan hidup: berapa label yang akan
                              // dicetak vs total barang fisik sebenarnya --
                              // supaya staff paham efek dari isi bundle
                              // SEBELUM simpan (mengurangi label dicetak
                              // adalah tujuan utama fitur ini).
                              if (_isBundle) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${_quantity == _quantity.roundToDouble() ? _quantity.toStringAsFixed(0) : _quantity} label '
                                  'dicetak, total barang fisik = ${_quantity.toStringAsFixed(0)} x '
                                  '${_bundleQuantity} = '
                                  '${(_quantity * _bundleQuantity!).toStringAsFixed(0)} '
                                  '${_quantityUnitController.text.trim().isEmpty ? '' : '(per ${_quantityUnitController.text.trim()})'}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildUnlabeledCard(),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DIMENSI & BERAT (opsional)',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: AppTextField(
                                    controller: _lengthController,
                                    label: 'Panjang (cm)',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    enabled: !_isSaving,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AppTextField(
                                    controller: _widthController,
                                    label: 'Lebar (cm)',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    enabled: !_isSaving,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AppTextField(
                                    controller: _heightController,
                                    label: 'Tinggi (cm)',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    enabled: !_isSaving,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AppTextField(
                              controller: _weightController,
                              label: 'Berat (kg)',
                              icon: Icons.scale_outlined,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              enabled: !_isSaving,
                            ),
                            if (_volumeM3 != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Volume: ${_volumeM3!.toStringAsFixed(4)} m³',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          children: [
                            AppTextField(
                              controller: _unitPriceController,
                              label: 'Harga Satuan',
                              hint: 'Terisi otomatis dari Jenis Tarif',
                              icon: Icons.attach_money_rounded,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              enabled: !_isSaving,
                            ),
                            const SizedBox(height: 14),
                            if (widget.allowTotalOverride) ...[
                              // FITUR (8 Oktober 2026, lanjutan lagi --
                              // "Pada Monitoring Resi bagian Editing.
                              // Masukkan input diskon persen dan diskon
                              // nilai ... per barang"). SATU diskon
                              // (dikonfirmasi user): isi % -> Rp
                              // otomatis terhitung & dibulatkan ke
                              // kelipatan Rp1.000 (lihat
                              // [_roundToThousand]), TAPI field Rp TETAP
                              // bisa diketik manual kalau hasil
                              // bulatannya masih perlu disesuaikan
                              // ("jika hasil nilai diskon pecahan bisa
                              // diedit agar bulat").
                              Text(
                                'Harga sebelum diskon: ${formatRupiah(_totalPrice)}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppTextField(
                                      controller: _discountPercentController,
                                      label: 'Diskon (%)',
                                      hint: '0',
                                      icon: Icons.percent_rounded,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      enabled: !_isSaving,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: AppTextField(
                                      controller: _discountAmountController,
                                      label: 'Diskon (Rp)',
                                      hint: 'Dibulatkan ke kelipatan Rp1.000',
                                      icon: Icons.money_off_rounded,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      enabled: !_isSaving,
                                      suffixIcon: _discountAmountManuallyOverridden
                                          ? IconButton(
                                              tooltip:
                                                  'Pakai hitungan otomatis lagi',
                                              onPressed: _isSaving
                                                  ? null
                                                  : _resetDiscountAmountOverride,
                                              icon: const Icon(
                                                Icons.restart_alt_rounded,
                                                size: 20,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              // Admin: total BISA diketik manual (lihat
                              // doc comment [allowTotalOverride] di atas)
                              // -- beda dari alur staff biasa yang totalnya
                              // murni read-only hasil kalkulator.
                              AppTextField(
                                controller: _totalPriceOverrideController,
                                label: 'Total Harga (Admin)',
                                hint: 'Ketik nilai lain untuk override kebijakan pimpinan',
                                icon: Icons.payments_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                enabled: !_isSaving,
                                suffixIcon: _totalManuallyOverridden
                                    ? IconButton(
                                        tooltip: 'Pakai hitungan otomatis lagi',
                                        onPressed:
                                            _isSaving ? null : _resetTotalOverride,
                                        icon: const Icon(
                                          Icons.restart_alt_rounded,
                                          size: 20,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _totalManuallyOverridden
                                    ? 'Di-override manual. Otomatis (harga - diskon): '
                                        '${formatRupiah(_netPrice)} (harga '
                                        '${formatRupiah(_totalPrice)} - diskon '
                                        '${formatRupiah(_discountAmount)}).'
                                    : 'Otomatis dari harga dikurangi diskon -- ketik nilai '
                                        'lain di atas untuk override.',
                                style: TextStyle(
                                  color: _totalManuallyOverridden
                                      ? AppColors.orange
                                      : AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else
                              Row(
                                children: [
                                  Text(
                                    _isBundle
                                        ? 'Total Harga (${_quantity.toStringAsFixed(0)} × ${_bundleQuantity} × harga)'
                                        : 'Total Harga',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    formatRupiah(_totalPrice),
                                    style: const TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        InfoBanner(
                          variant: InfoBannerVariant.error,
                          message: _errorMessage!,
                          onDismiss: () {
                            setState(() => _errorMessage = null);
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label:
                            _isEditMode ? 'Simpan Perubahan' : 'Tambah Barang',
                        loadingLabel: 'Menyimpan...',
                        isLoading: _isSaving,
                        icon: Icons.check_circle_outline_rounded,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // KARTU "TANPA LABEL QR"
  // ============================================================
  //
  // Permintaan eksplisit user (23 September 2026): opsi untuk barang
  // yang BENAR-BENAR tidak bisa dilabeli (mis. bata ringan curah 10
  // kubik) -- tidak ada label QR yang dicetak sama sekali, cukup 1 foto
  // sebagai bukti.
  Widget _buildUnlabeledCard() {
    final photoBytesFuture = _newPhoto?.readAsBytes();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tanpa Label QR',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Untuk barang yang benar-benar tidak bisa dilabeli '
                      '(mis. bata ringan curah, pasir) -- tidak dicetak '
                      'label QR, cukup 1 foto sebagai bukti.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _isUnlabeled,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _isUnlabeled = value),
                activeColor: AppColors.blue,
              ),
            ],
          ),
          if (_isUnlabeled) ...[
            const SizedBox(height: 10),
            if (_newPhoto != null && photoBytesFuture != null)
              FutureBuilder<Uint8List>(
                future: photoBytesFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      snapshot.data!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              )
            else if (_existingPhotoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _existingPhotoUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 160,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Gagal memuat foto.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            if (_newPhoto != null || _existingPhotoUrl != null)
              const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _pickPhoto,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(
                  _newPhoto != null || _existingPhotoUrl != null
                      ? 'Ambil Ulang Foto'
                      : 'Ambil Foto Barang',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  side: const BorderSide(color: AppColors.blue),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}