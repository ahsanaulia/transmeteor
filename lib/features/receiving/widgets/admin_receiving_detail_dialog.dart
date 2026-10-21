import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/item_type_model.dart';
import '../../../models/pricing_type_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/storage_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/receiving_service.dart';

/// Dialog tambah/ubah SATU baris `receiving_details`, versi DESKTOP untuk
/// "Penerimaan Barang (Intervensi Admin)" (8 Oktober 2026, permintaan user
/// eksplisit).
///
/// SENGAJA dibuat widget TERPISAH dari `ReceivingDetailFormSheet` (bottom
/// sheet mobile yang sudah ada), bukan dipakai ulang langsung -- alasannya:
/// 1. Bentuknya beda total (AlertDialog lebar-tetap untuk mouse/desktop vs
///    DraggableScrollableSheet penuh layar untuk jari/mobile).
/// 2. Yang paling penting: permintaan user EKSPLISIT "hilangkan keharusan
///    foto" untuk alur admin ini -- `ReceivingDetailFormSheet` MEWAJIBKAN
///    foto untuk barang "Tanpa Label QR"
///    (`_isUnlabeled && _newPhoto == null && _existingPhotoUrl == null`)
///    dan pakai `ImagePicker(source: ImageSource.camera)` yang juga tidak
///    relevan di Chrome desktop (admin tidak pegang kamera). Toggle "Tanpa
///    Label QR" TETAP ada di sini (field bisnis yang sah, menentukan ikut
///    tidaknya barang ini di "Cetak Label") -- cuma syarat fotonya yang
///    dihapus, `photoUrl` SELALU dikirim null dari jalur admin ini.
/// 3. Field "Total Harga (Admin)" override (`allowTotalOverride` di
///    `ReceivingDetailFormSheet`) SENGAJA TIDAK diikutkan di sini supaya
///    scope tetap fokus ke input cepat -- admin yang perlu override total
///    kebijakan pimpinan tetap pakai jalur yang SUDAH ADA (edit detail
///    lewat "Monitoring Resi" -> `ReceivingItemDetailPage`), BUKAN lewat
///    sini.
///
/// Backend-nya PERSIS SAMA (`ReceivingService.createReceivingDetail`/
/// `updateReceivingDetail`) -- tidak ada perubahan model/service/kolom
/// database sama sekali untuk fitur ini, murni UI alternatif untuk mengisi
/// data yang sama.
class AdminReceivingDetailDialog extends ConsumerStatefulWidget {
  final String receivingId;
  final String? itemCodeForNew;
  final ReceivingDetailModel? existing;

  const AdminReceivingDetailDialog({
    super.key,
    required this.receivingId,
    this.itemCodeForNew,
    this.existing,
  }) : assert(
          existing != null || itemCodeForNew != null,
          'itemCodeForNew wajib diisi kalau mode tambah baru',
        );

  @override
  ConsumerState<AdminReceivingDetailDialog> createState() =>
      _AdminReceivingDetailDialogState();
}

class _AdminReceivingDetailDialogState
    extends ConsumerState<AdminReceivingDetailDialog> {
  late final TextEditingController _itemNameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _quantityUnitController;
  late final TextEditingController _weightController;
  late final TextEditingController _lengthController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _bundleQuantityController;

  ItemTypeModel? _selectedItemType;
  PricingTypeModel? _selectedPricingType;
  StorageModel? _selectedStorage;

  // "Tanpa Label QR" TETAP ada (field bisnis sah), TANPA syarat foto --
  // lihat doc comment kelas di atas poin 2.
  bool _isUnlabeled = false;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditMode => widget.existing != null;

  // Sama persis pola `_hasPrefilled` di `receiving_detail_form_sheet.dart`
  // (8 Oktober 2026) -- guard eksplisit, BUKAN cek "salah satu field !=
  // null", supaya field yang boleh null (storage) tidak merusak logic
  // "sudah pernah di-prefill atau belum".
  bool _hasPrefilled = false;

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
    _bundleQuantityController = TextEditingController(
      text: (existing?.bundleQuantity != null && existing!.bundleQuantity! > 1)
          ? existing.bundleQuantity!.toString()
          : '',
    );

    _isUnlabeled = existing?.isUnlabeled ?? false;

    _quantityController.addListener(_refresh);
    _unitPriceController.addListener(_refresh);
    _bundleQuantityController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

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

    super.dispose();
  }

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  double _parseNumber(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
  }

  double? _optionalNumber(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }

  double get _quantity => _parseNumber(_quantityController.text);
  double get _unitPrice => _parseNumber(_unitPriceController.text);

  int? get _bundleQuantity {
    if (_isUnlabeled) return null;

    final raw = _bundleQuantityController.text.trim();
    if (raw.isEmpty) return null;

    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 1) return null;

    return parsed;
  }

  bool get _isBundle => _bundleQuantity != null;

  double get _totalPrice => _quantity * (_bundleQuantity ?? 1) * _unitPrice;

  double? get _volumeM3 {
    final length = _optionalNumber(_lengthController.text);
    final width = _optionalNumber(_widthController.text);
    final height = _optionalNumber(_heightController.text);

    if (length == null || width == null || height == null) {
      return null;
    }

    return (length * width * height) / 1000000;
  }

  void _prefillFromExisting(
    List<ItemTypeModel> itemTypes,
    List<PricingTypeModel> pricingTypes,
    List<StorageModel> storages,
  ) {
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

    if (quantityUnit.isEmpty) {
      setState(() => _errorMessage = 'Satuan wajib diisi.');
      return;
    }

    // SENGAJA TIDAK ADA validasi foto di sini -- lihat doc comment kelas
    // di atas (poin 2). `photoUrl` SELALU null dari jalur admin ini, foto
    // TIDAK wajib walau togglenya "Tanpa Label QR" dinyalakan.

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
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
          totalPrice: _totalPrice,
          bundleQuantity: _bundleQuantity,
          isUnlabeled: _isUnlabeled,
          photoUrl: null,
          storageId: _selectedStorage?.id,
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
          totalPrice: _totalPrice,
          bundleQuantity: _bundleQuantity,
          isUnlabeled: _isUnlabeled,
          photoUrl: null,
          storageId: _selectedStorage?.id,
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(_isEditMode ? 'Ubah Barang' : 'Tambah Barang'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppTextField(
                      controller: _quantityController,
                      label: _isUnlabeled ? 'Jumlah' : 'Jumlah (yg dicetak label)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
              if (!_isUnlabeled) ...[
                const SizedBox(height: 14),
                AppTextField(
                  controller: _bundleQuantityController,
                  label: 'Isi per Satuan (Bundle) -- opsional',
                  hint: 'Kosongkan kalau lepasan.',
                  icon: Icons.inventory_outlined,
                  keyboardType: TextInputType.number,
                  enabled: !_isSaving,
                ),
                if (_isBundle) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_quantity == _quantity.roundToDouble() ? _quantity.toStringAsFixed(0) : _quantity} label '
                    'dicetak, total barang fisik = ${_quantity.toStringAsFixed(0)} x '
                    '$_bundleQuantity = '
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
              const SizedBox(height: 14),
              // "Tanpa Label QR" TANPA syarat/UI foto -- lihat doc comment
              // kelas di atas poin 2 (permintaan user eksplisit, admin
              // desktop tidak pegang kamera).
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Tanpa Label QR',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Barang yang tidak dilabeli (mis. bata ringan '
                            'curah). Tidak perlu foto di jalur admin ini.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isUnlabeled,
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _isUnlabeled = value),
                      activeColor: AppColors.blue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _lengthController,
                      label: 'Panjang (cm)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_isSaving,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      controller: _widthController,
                      label: 'Lebar (cm)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_isSaving,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      controller: _heightController,
                      label: 'Tinggi (cm)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_isSaving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _weightController,
                label: 'Berat (kg) -- opsional',
                icon: Icons.scale_outlined,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                enabled: !_isSaving,
              ),
              if (_volumeM3 != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Volume: ${_volumeM3!.toStringAsFixed(4)} m³',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AppTextField(
                controller: _unitPriceController,
                label: 'Harga Satuan',
                hint: 'Terisi otomatis dari Jenis Tarif',
                icon: Icons.attach_money_rounded,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                enabled: !_isSaving,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    _isBundle
                        ? 'Total Harga (${_quantity.toStringAsFixed(0)} × $_bundleQuantity × harga)'
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_isEditMode ? 'Simpan Perubahan' : 'Tambah Barang'),
        ),
      ],
    );
  }
}
