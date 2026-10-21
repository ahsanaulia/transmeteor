import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/destination_model.dart';
import '../../../models/package_type_model.dart';
import '../../../models/receiving_model.dart';
import '../../../models/route_pricing_model.dart';
import '../../../models/sender_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/destination_service.dart';
import '../../../services/receiving_service.dart';
import '../../../services/sender_service.dart';

/// Bottom sheet "Edit Resi" (13 Oktober 2026 -- fitur baru, permintaan
/// user eksplisit: "Tambahan Fitur" poin 2-4, dikonfirmasi ulang:
/// "Yang menginput adalah admin ... Bukan dibagian edit. Tetapi di Resi.
/// Edit Resi").
///
/// Ini SATU-SATUNYA tempat di aplikasi admin menginput status pembayaran
/// (Bayar Tujuan/Bayar Dikantor) & DP (Down Payment) -- field ini TIDAK
/// ADA di layar "Terima Barang" (`ReceivingCreatePage`) sama sekali.
/// Selain itu, sheet ini juga membuka kesempatan memperbaiki header resi
/// lain (pengirim/tujuan/rute/nomor buku) kalau ada kesalahan input --
/// sebelumnya TIDAK ADA cara mengubah field-field ini sama sekali
/// setelah resi dibuat.
///
/// Diakses lewat tombol "Edit Resi" baru di AppBar
/// `ReceivingDetailPage` (Monitoring Resi -> pilih resi -> detail).
///
/// SENGAJA TIDAK menyediakan "Tambah Pengirim/Tujuan Baru" di sini
/// (beda dengan `ReceivingCreatePage`) -- sheet ini untuk MEMPERBAIKI
/// data resi yang sudah ada, bukan alur input resi baru. Kalau pengirim/
/// tujuan yang benar belum ada di master data, admin menambahkannya dulu
/// lewat menu masing-masing, baru kembali ke sini untuk memilihnya.
class ReceivingEditSheet extends ConsumerStatefulWidget {
  final ReceivingModel existing;

  const ReceivingEditSheet({super.key, required this.existing});

  @override
  ConsumerState<ReceivingEditSheet> createState() =>
      _ReceivingEditSheetState();
}

class _ReceivingEditSheetState extends ConsumerState<ReceivingEditSheet> {
  final _formKey = GlobalKey<FormState>();

  final _senderController = TextEditingController();
  final _destinationController = TextEditingController();
  late final TextEditingController _nomorBukuController;
  late final TextEditingController _dpAmountController;

  SenderModel? _selectedSender;
  DestinationModel? _selectedDestination;
  RoutePricingModel? _selectedRoute;
  PackageTypeModel? _selectedPackageType;

  late String _paymentStatus;

  bool _isLoadingInitial = true;
  String? _loadError;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _nomorBukuController =
        TextEditingController(text: existing.nomorBuku ?? '');
    _dpAmountController = TextEditingController(
      text: (existing.dpAmount != null && existing.dpAmount! > 0)
          ? _trimNumber(existing.dpAmount!)
          : '',
    );
    _paymentStatus = existing.paymentStatus;

    _loadInitialSelections();
  }

  @override
  void dispose() {
    _senderController.dispose();
    _destinationController.dispose();
    _nomorBukuController.dispose();
    _dpAmountController.dispose();
    super.dispose();
  }

  // ============================================================
  // MUAT PILIHAN AWAL (dari ID yang sudah tersimpan di resi)
  // ============================================================
  //
  // SearchPickField/PickerField butuh OBJECT model (bukan cuma ID) untuk
  // ditampilkan sebagai "selected" -- jadi di sini resi existing (yang
  // cuma punya senderId/destinationId/routePricingId/packageTypeId)
  // dicocokkan dulu ke data master lengkapnya sebelum form ditampilkan.

  Future<void> _loadInitialSelections() async {
    try {
      final existing = widget.existing;

      final results = await Future.wait([
        SenderService.getSenderById(existing.senderId),
        existing.destinationId != null
            ? DestinationService.getDestinationById(existing.destinationId!)
            : Future.value(null),
        ref.read(routePricingsProvider.future),
        ref.read(packageTypesProvider.future),
      ]);

      if (!mounted) return;

      final sender = results[0] as SenderModel?;
      final destination = results[1] as DestinationModel?;
      final routes = results[2] as List<RoutePricingModel>;
      final packageTypes = results[3] as List<PackageTypeModel>;

      RoutePricingModel? route;
      for (final r in routes) {
        if (r.id == existing.routePricingId) {
          route = r;
          break;
        }
      }

      PackageTypeModel? packageType;
      for (final p in packageTypes) {
        if (p.id == existing.packageTypeId) {
          packageType = p;
          break;
        }
      }

      setState(() {
        _selectedSender = sender;
        if (sender != null) _senderController.text = sender.name;

        _selectedDestination = destination;
        _destinationController.text = destination?.name ?? existing.destination;

        _selectedRoute = route;
        _selectedPackageType = packageType;

        _isLoadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingInitial = false;
        _loadError = 'Gagal memuat data resi: $e';
      });
    }
  }

  // ============================================================
  // HELPER NOMOR
  // ============================================================

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  double? _parseDpAmount(String text) {
    final cleaned = text.trim().replaceAll('.', '').replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  // ============================================================
  // SENDER / DESTINATION (pilih dari master data existing)
  // ============================================================

  void _selectSender(SenderModel sender) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedSender = sender;
      _senderController.text = sender.name;
      _errorMessage = null;
    });
  }

  void _clearSender() {
    setState(() {
      _selectedSender = null;
      _senderController.clear();
    });
  }

  void _selectDestination(DestinationModel destination) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedDestination = destination;
      _destinationController.text = destination.name;
      _errorMessage = null;
    });
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationController.clear();
    });
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedSender == null) {
      setState(() => _errorMessage = 'Pengirim wajib dipilih.');
      return;
    }

    final destinationName = _destinationController.text.trim();
    if (destinationName.isEmpty) {
      setState(() => _errorMessage = 'Tujuan pengiriman wajib diisi.');
      return;
    }

    if (_selectedPackageType == null) {
      setState(() => _errorMessage = 'Jenis pengiriman wajib dipilih.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final dpAmount = _paymentStatus == ReceivingPaymentStatus.bayarDikantor
          ? _parseDpAmount(_dpAmountController.text)
          : null;

      final destinationAddress = _selectedDestination?.address?.trim();
      final destinationPhone = _selectedDestination?.phone?.trim();

      // FITUR (16 Oktober 2026 -- dibutuhkan Dashboard Supervisor):
      // catat SIAPA admin yang menyimpan perubahan ini, lihat doc
      // comment `ReceivingModel.updatedBy`.
      final employee = await ref.read(currentEmployeeProvider.future);
      if (employee == null) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Data employee admin tidak ditemukan.';
        });
        return;
      }

      await ReceivingService.updateReceiving(
        receivingId: widget.existing.id,
        senderId: _selectedSender!.id,
        packageTypeId: _selectedPackageType!.id,
        destination: destinationName,
        destinationAddress:
            (destinationAddress != null && destinationAddress.isNotEmpty)
                ? destinationAddress
                : widget.existing.destinationAddress,
        destinationPhone:
            (destinationPhone != null && destinationPhone.isNotEmpty)
                ? destinationPhone
                : widget.existing.destinationPhone,
        destinationId: _selectedDestination?.id ?? widget.existing.destinationId,
        route: _selectedRoute?.routeName,
        routePricingId: _selectedRoute?.id,
        nomorBuku: _nomorBukuController.text.trim().isEmpty
            ? null
            : _nomorBukuController.text.trim(),
        paymentStatus: _paymentStatus,
        dpAmount: dpAmount,
        updatedBy: employee.id,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Gagal menyimpan perubahan resi: $e');
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
    final routePricingsAsync = ref.watch(routePricingsProvider);
    final packageTypesAsync = ref.watch(packageTypesProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: _isLoadingInitial
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E4EC),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Edit Resi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No. Resi ${widget.existing.receiptNumber}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        if (_loadError != null) ...[
                          const SizedBox(height: 12),
                          InfoBanner(
                            variant: InfoBannerVariant.warning,
                            message: _loadError!,
                          ),
                        ],
                        const SizedBox(height: 16),
                        AppCard(
                          child: SearchPickField<SenderModel>(
                            controller: _senderController,
                            label: 'Pengirim',
                            hint: 'Ketik nama pengirim...',
                            enabled: !_isSaving,
                            onSearch: SenderService.searchSenders,
                            itemLabel: (sender) => sender.name,
                            itemSubtitle: (sender) => sender.phone,
                            selected: _selectedSender,
                            onSelected: _selectSender,
                            onClear: _clearSender,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppCard(
                          child: Column(
                            children: [
                              SearchPickField<DestinationModel>(
                                controller: _destinationController,
                                label: 'Tujuan',
                                hint: 'Cari tujuan yang sudah pernah dipakai...',
                                enabled: !_isSaving,
                                onSearch: DestinationService.searchDestinations,
                                itemLabel: (destination) => destination.name,
                                itemSubtitle: (destination) => destination.address,
                                selected: _selectedDestination,
                                onSelected: _selectDestination,
                                onClear: _clearDestination,
                              ),
                              const SizedBox(height: 14),
                              AppTextField(
                                controller: _nomorBukuController,
                                label: 'Nomor Buku (Opsional)',
                                hint: 'Nomor buku catatan manual, kalau ada',
                                icon: Icons.menu_book_rounded,
                                enabled: !_isSaving,
                              ),
                              const SizedBox(height: 14),
                              PickerField<RoutePricingModel>(
                                label: 'Rute & Tarif',
                                hint: 'Pilih rute (opsional)',
                                sheetTitle: 'Pilih Rute',
                                icon: Icons.alt_route_rounded,
                                enabled: !_isSaving,
                                itemsAsync: routePricingsAsync,
                                itemsProvider: routePricingsProvider,
                                itemLabel: (route) => route.routeName,
                                itemSubtitle: (route) =>
                                    '${route.routeCode} · ${formatRupiah(route.price)}',
                                selectedText: (route) =>
                                    '${route.routeName} · ${formatRupiah(route.price)}',
                                selected: _selectedRoute,
                                onSelected: (route) {
                                  setState(() => _selectedRoute = route);
                                },
                                onClear: () {
                                  setState(() => _selectedRoute = null);
                                },
                              ),
                              const SizedBox(height: 14),
                              PickerField<PackageTypeModel>(
                                label: 'Jenis Pengiriman',
                                hint: 'Pilih jenis pengiriman',
                                sheetTitle: 'Pilih Jenis Pengiriman',
                                icon: Icons.inventory_2_outlined,
                                enabled: !_isSaving,
                                itemsAsync: packageTypesAsync,
                                itemsProvider: packageTypesProvider,
                                itemLabel: (packageType) => packageType.name,
                                selectedText: (packageType) => packageType.name,
                                selected: _selectedPackageType,
                                onSelected: (packageType) {
                                  setState(() => _selectedPackageType = packageType);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // ============================================
                        // STATUS PEMBAYARAN + DP
                        // ============================================
                        //
                        // FITUR (13 Oktober 2026 -- permintaan user poin
                        // 2-4): SATU-SATUNYA tempat di aplikasi admin
                        // menginput ini.
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Status Pembayaran',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      selected: _paymentStatus ==
                                          ReceivingPaymentStatus.bayarTujuan,
                                      label: const Text('Bayar Tujuan'),
                                      labelStyle: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _paymentStatus ==
                                                ReceivingPaymentStatus.bayarTujuan
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                      ),
                                      selectedColor: AppColors.blue,
                                      onSelected: _isSaving
                                          ? null
                                          : (_) {
                                              setState(() {
                                                _paymentStatus =
                                                    ReceivingPaymentStatus
                                                        .bayarTujuan;
                                              });
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ChoiceChip(
                                      selected: _paymentStatus ==
                                          ReceivingPaymentStatus.bayarDikantor,
                                      label: const Text('Bayar Dikantor'),
                                      labelStyle: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _paymentStatus ==
                                                ReceivingPaymentStatus
                                                    .bayarDikantor
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                      ),
                                      selectedColor: AppColors.blue,
                                      onSelected: _isSaving
                                          ? null
                                          : (_) {
                                              setState(() {
                                                _paymentStatus =
                                                    ReceivingPaymentStatus
                                                        .bayarDikantor;
                                              });
                                            },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Default resi baru: Bayar Tujuan (dibayar '
                                'penerima di tempat tujuan). Bayar Dikantor '
                                '= sudah/akan dibayar di kantor -- boleh '
                                'sebagian (DP) di bawah ini.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),
                              AppTextField(
                                controller: _dpAmountController,
                                label: 'DP / Bayar Sebagian di Kantor (Rp)',
                                hint: 'Kosongkan kalau tidak ada DP',
                                icon: Icons.payments_outlined,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                enabled: !_isSaving &&
                                    _paymentStatus ==
                                        ReceivingPaymentStatus.bayarDikantor,
                              ),
                              if (_paymentStatus ==
                                  ReceivingPaymentStatus.bayarTujuan) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'DP hanya berlaku untuk status Bayar '
                                  'Dikantor.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          InfoBanner(
                            variant: InfoBannerVariant.error,
                            message: _errorMessage!,
                          ),
                        ],
                        const SizedBox(height: 20),
                        PrimaryButton(
                          label: 'Simpan Perubahan',
                          loadingLabel: 'Menyimpan...',
                          isLoading: _isSaving,
                          icon: Icons.check_circle_rounded,
                          backgroundColor: AppColors.green,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}
