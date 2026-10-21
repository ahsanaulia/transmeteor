import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/destination_model.dart';
import '../../../models/package_type_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/receiving_model.dart';
import '../../../models/route_pricing_model.dart';
import '../../../models/sender_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/receiving_detail_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/destination_service.dart';
import '../../../services/receiving_service.dart';
import '../../../services/sender_service.dart';
import '../widgets/admin_receiving_detail_dialog.dart';
import '../../printing/pages/label_preview_page.dart';
import '../../printing/pages/receipt_preview_page.dart';

/// "Penerimaan Barang (Intervensi Admin)" (8 Oktober 2026, permintaan
/// user eksplisit) -- cara LAIN untuk mencatat resi + detail barangnya,
/// KHUSUS admin yang kerja dari komputer/Chrome, DI SAMPING alur mobile
/// yang sudah ada (`ReceivingCreatePage` -> `ReceivingItemsPage`, dipakai
/// staff Receiving di HP).
///
/// Perbedaan sengaja dari alur mobile (SEMUA alasan dari permintaan user):
/// 1. **Satu halaman, bentuk master-detail tabular** -- bukan 2 halaman
///    berpisah (buat resi dulu, baru pindah halaman detail barang). Header
///    resi (master) di atas, daftar barang (detail) di bawah sebagai
///    `DataTable` -- pola CRUD standar aplikasi desktop ("admin minta
///    dibuat tabular seperti CRUD umumnya master detail").
/// 2. **Foto tidak pernah wajib** -- dialog tambah/ubah barang
///    (`AdminReceivingDetailDialog`) punya field foto OPSIONAL (diubah 21
///    Oktober 2026, permintaan user eksplisit "Foto adalah opsional" --
///    SEBELUMNYA memang sengaja tidak ada field foto sama sekali di sini).
///    Pakai `ImageSource.gallery` (pilih file), bukan kamera -- admin
///    desktop tidak punya kamera fisik yang relevan.
/// 3. **Cuma 2 aksi cetak** -- "Cetak Label" & "Cetak Resi" saja (SAMA
///    PERSIS komponen yang sudah ada: `LabelPreviewPage`/
///    `ReceiptPreviewPage`, reuse langsung, TIDAK ada halaman cetak baru)
///    -- sesuai permintaan "Bisa cetak resi dan cetak label saja".
///
/// SENGAJA TIDAK menyertakan "Titik Lokasi Tujuan" (geocoding/pilih di
/// peta) yang ada di `ReceivingCreatePage` -- di luar scope permintaan ini
/// (resi + barang + cetak resi/label); kalau admin butuh titik lokasi,
/// tetap bisa diisi lewat alur mobile biasa untuk resi yang sama.
///
/// Backend 100% REUSE -- `ReceivingService.createReceiving`/
/// `createReceivingDetail`/`updateReceivingDetail`/`deleteReceivingDetail`
/// SAMA PERSIS dengan yang dipakai alur mobile. TIDAK ADA migrasi SQL baru
/// untuk fitur ini.
class AdminReceivingEntryPage extends ConsumerStatefulWidget {
  const AdminReceivingEntryPage({super.key});

  @override
  ConsumerState<AdminReceivingEntryPage> createState() =>
      _AdminReceivingEntryPageState();
}

class _AdminReceivingEntryPageState
    extends ConsumerState<AdminReceivingEntryPage> {
  final _senderController = TextEditingController();
  final _destinationController = TextEditingController();
  final _nomorBukuController = TextEditingController();

  SenderModel? _selectedSender;
  DestinationModel? _selectedDestination;
  RoutePricingModel? _selectedRoute;
  PackageTypeModel? _selectedPackageType;

  // FITUR (14 Oktober 2026 -- permintaan user eksplisit): "Buat Resi
  // disisi Admin, tanggal jangan otomatis. Jamnya saja. 13:00:00. Jadi
  // tanggal resi bisa diedit. di Admin" -- SEBELUMNYA `received_at`
  // SELALU `DateTime.now()` (lihat default di
  // `ReceivingService.createReceiving`, parameter `receivedAt` TIDAK
  // dikirim dari sini sama sekali). SEKARANG admin bisa pilih TANGGAL-nya
  // sendiri (default hari ini, bisa diedit lewat `_pickDate`), tapi JAM-
  // nya TETAP tetap/fixed 13:00:00 (lihat `_saveHeader` -- BUKAN jam
  // saat tombol Simpan ditekan).
  DateTime _selectedDate = DateTime.now();

  bool _isSaving = false;
  String? _errorMessage;

  // Begitu header resi berhasil disimpan, halaman ini PINDAH ke mode
  // "detail" (tabel barang) -- TANPA pindah halaman (beda dari alur
  // mobile yang `Navigator.push` ke `ReceivingItemsPage` terpisah), sesuai
  // permintaan "satu halaman tabular master-detail".
  ReceivingModel? _receiving;

  @override
  void dispose() {
    _senderController.dispose();
    _destinationController.dispose();
    _nomorBukuController.dispose();
    super.dispose();
  }

  // ============================================================
  // RESET -- "Resi Baru" tanpa keluar dari halaman ini
  // ============================================================

  void _startNewReceiving() {
    setState(() {
      _receiving = null;
      _selectedSender = null;
      _selectedDestination = null;
      _selectedRoute = null;
      _selectedPackageType = null;
      _senderController.clear();
      _destinationController.clear();
      _nomorBukuController.clear();
      _selectedDate = DateTime.now();
      _errorMessage = null;
    });
  }

  // FITUR (14 Oktober 2026): pilih tanggal resi -- lihat doc comment
  // `_selectedDate`. `lastDate` SENGAJA dibolehkan sampai besok (bukan
  // hari ini saja) -- SAMA pola toleransi dengan `ReceivingReportPage.
  // _pickDate`, kalau admin input sedikit terlambat lewat tengah malam.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ============================================================
  // SELECT SENDER / DESTINATION (pola sama dengan ReceivingCreatePage)
  // ============================================================

  void _selectSender(SenderModel sender) {
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

  Future<void> _showCreateSenderDialog() async {
    final nameController =
        TextEditingController(text: _senderController.text.trim());
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<SenderModel>(
      context: context,
      builder: (dialogContext) {
        bool isCreating = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> createSender() async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Nama pengirim wajib diisi.')),
                );
                return;
              }

              setDialogState(() => isCreating = true);

              try {
                final sender = await SenderService.createSender(
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(sender);
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() => isCreating = false);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Gagal membuat pengirim: $e')),
                );
              }
            }

            return AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Pengirim Baru'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTextField(
                      controller: nameController,
                      label: 'Nama Pengirim',
                      icon: Icons.business_rounded,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: phoneController,
                      label: 'No. HP',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: addressController,
                      label: 'Alamat',
                      icon: Icons.location_on_outlined,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isCreating ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: isCreating ? null : createSender,
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();

    if (result != null && mounted) _selectSender(result);
  }

  void _selectDestination(DestinationModel destination) {
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

  Future<void> _showCreateDestinationDialog() async {
    final nameController =
        TextEditingController(text: _destinationController.text.trim());
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<DestinationModel>(
      context: context,
      builder: (dialogContext) {
        bool isCreating = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> createDestination() async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Nama tujuan wajib diisi.')),
                );
                return;
              }

              setDialogState(() => isCreating = true);

              try {
                final destination = await DestinationService.createDestination(
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(destination);
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() => isCreating = false);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Gagal membuat tujuan: $e')),
                );
              }
            }

            return AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Tujuan Baru'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTextField(
                      controller: nameController,
                      label: 'Nama Tujuan',
                      icon: Icons.place_rounded,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: phoneController,
                      label: 'No. HP',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: addressController,
                      label: 'Alamat',
                      icon: Icons.location_on_outlined,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isCreating ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: isCreating ? null : createDestination,
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();

    if (result != null && mounted) _selectDestination(result);
  }

  // ============================================================
  // SIMPAN HEADER (buat `receiving`) -- SAMA PERSIS panggilan service
  // dengan ReceivingCreatePage, cuma TANPA koordinat tujuan.
  // ============================================================

  Future<void> _saveHeader() async {
    if (_selectedSender == null) {
      setState(() => _errorMessage = 'Silakan pilih atau buat pengirim terlebih dahulu.');
      return;
    }

    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
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
      final employee = await ref.read(currentEmployeeProvider.future);
      if (employee == null) {
        throw Exception(
          'Data employee yang login tidak ditemukan. Silakan login ulang.',
        );
      }

      final selectedDestinationAddress = _selectedDestination?.address?.trim();
      final selectedDestinationPhone = _selectedDestination?.phone?.trim();

      // FITUR (14 Oktober 2026 -- lihat doc comment `_selectedDate`):
      // TANGGAL dari pilihan admin (`_selectedDate`, via `_pickDate`),
      // JAM SELALU fixed 13:00:00 -- BUKAN `DateTime.now()` (yang mana
      // jamnya berubah-ubah sesuai kapan tombol Simpan ditekan).
      final receivedAt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        13,
        0,
        0,
      );

      final receiving = await ReceivingService.createReceiving(
        senderId: _selectedSender!.id,
        receiverName: null,
        receiverPhone: null,
        packageTypeId: _selectedPackageType!.id,
        destination: destination,
        destinationAddress:
            (selectedDestinationAddress != null && selectedDestinationAddress.isNotEmpty)
                ? selectedDestinationAddress
                : null,
        destinationPhone:
            (selectedDestinationPhone != null && selectedDestinationPhone.isNotEmpty)
                ? selectedDestinationPhone
                : null,
        destinationId: _selectedDestination?.id,
        receivedAt: receivedAt,
        receivedBy: employee.id,
        route: _selectedRoute?.routeName,
        routePricingId: _selectedRoute?.id,
        nomorBuku: _nomorBukuController.text.trim().isEmpty
            ? null
            : _nomorBukuController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _receiving = receiving;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resi ${receiving.receiptNumber} dibuat. Lanjut tambah barang.')),
      );
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
  // DETAIL BARANG -- dialog tambah/ubah, konfirmasi hapus
  // ============================================================

  Future<void> _openAddDialog(List<ReceivingDetailModel> currentItems) async {
    final receiving = _receiving!;
    final sequence = currentItems.length + 1;
    final itemCode =
        '${receiving.receiptNumber}-${sequence.toString().padLeft(2, '0')}';

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AdminReceivingDetailDialog(
        receivingId: receiving.id,
        itemCodeForNew: itemCode,
      ),
    );

    if (saved == true) {
      ref.invalidate(receivingDetailsProvider(receiving.id));
    }
  }

  Future<void> _openEditDialog(ReceivingDetailModel detail) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AdminReceivingDetailDialog(
        receivingId: _receiving!.id,
        existing: detail,
      ),
    );

    if (saved == true) {
      ref.invalidate(receivingDetailsProvider(_receiving!.id));
    }
  }

  Future<void> _confirmDelete(ReceivingDetailModel detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Hapus Barang'),
          content: Text('Yakin mau hapus "${detail.itemName}" dari resi ini?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ReceivingService.deleteReceivingDetail(detail.id);
      ref.invalidate(receivingDetailsProvider(_receiving!.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menghapus barang: $e')));
    }
  }

  // ============================================================
  // CETAK -- cuma 2 aksi (Cetak Label, Cetak Resi), SAMA PERSIS halaman
  // preview yang sudah ada. Lihat doc comment kelas, poin 3.
  // ============================================================

  Future<void> _openLabelPreview(List<ReceivingDetailModel> items) async {
    final senders = await ref.read(sendersProvider.future);
    SenderModel? sender;
    for (final s in senders) {
      if (s.id == _receiving!.senderId) {
        sender = s;
        break;
      }
    }

    if (!mounted) return;

    final labelableItems = items.where((item) => !item.isUnlabeled).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LabelPreviewPage(
          receiving: _receiving!,
          items: labelableItems,
          sender: sender,
        ),
      ),
    );
  }

  Future<void> _openReceiptPreview(List<ReceivingDetailModel> items) async {
    final senders = await ref.read(sendersProvider.future);
    SenderModel? sender;
    for (final s in senders) {
      if (s.id == _receiving!.senderId) {
        sender = s;
        break;
      }
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptPreviewPage(
          receiving: _receiving!,
          sender: sender,
          items: items,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Penerimaan Barang (Admin)',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
        actions: [
          if (_receiving != null)
            TextButton.icon(
              onPressed: _startNewReceiving,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Resi Baru'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: _receiving == null ? _buildHeaderForm() : _buildDetailSection(),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER FORM (master) -- tampil sebelum resi dibuat
  // ============================================================

  Widget _buildHeaderForm() {
    final routePricingsAsync = ref.watch(routePricingsProvider);
    final packageTypesAsync = ref.watch(packageTypesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.navy, AppColors.blue, AppColors.cyan],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_document, color: Colors.white, size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Catat penerimaan barang langsung lewat komputer -- isi '
                    'header resi dulu, baru tambahkan barang di tabel.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: SearchPickField<SenderModel>(
              controller: _senderController,
              label: 'Cari Pengirim',
              hint: 'Ketik nama pengirim...',
              enabled: !_isSaving,
              onSearch: SenderService.searchSenders,
              itemLabel: (sender) => sender.name,
              itemSubtitle: (sender) => sender.phone,
              selected: _selectedSender,
              onSelected: _selectSender,
              onClear: _clearSender,
              addNewLabel: 'Tambah Pengirim Baru',
              onAddNew: _showCreateSenderDialog,
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                SearchPickField<DestinationModel>(
                  controller: _destinationController,
                  label: 'Penerima Tujuan',
                  hint: 'Cari tujuan yang sudah pernah dipakai...',
                  enabled: !_isSaving,
                  onSearch: DestinationService.searchDestinations,
                  itemLabel: (destination) => destination.name,
                  itemSubtitle: (destination) => destination.address,
                  selected: _selectedDestination,
                  onSelected: _selectDestination,
                  onClear: _clearDestination,
                  addNewLabel: 'Tambah Penerima Tujuan Baru',
                  onAddNew: _showCreateDestinationDialog,
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
                // FITUR (14 Oktober 2026 -- permintaan user eksplisit):
                // "tanggal jangan otomatis ... Jadi tanggal resi bisa
                // diedit di Admin" -- lihat doc comment `_selectedDate`/
                // `_pickDate`. Jam TETAP fixed 13:00:00 (lihat
                // `_saveHeader`), TIDAK ditampilkan/dipilih di sini --
                // cuma tanggalnya yang bisa diedit admin.
                InkWell(
                  onTap: _isSaving ? null : _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Tanggal Resi',
                      prefixIcon: const Icon(Icons.calendar_month_rounded),
                      filled: true,
                      fillColor: AppColors.fieldFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    child: Text(
                      formatDateId(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                PickerField<RoutePricingModel>(
                  label: 'Rute & Tarif',
                  hint: 'Pilih rute (opsional, kalau ada tarif khusus)',
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
                  onSelected: (route) => setState(() => _selectedRoute = route),
                  onClear: () => setState(() => _selectedRoute = null),
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
                  itemSubtitle: (packageType) =>
                      '${packageType.durationDays} hari · ${formatRupiah(packageType.price)}',
                  selectedText: (packageType) =>
                      '${packageType.name} · ${formatRupiah(packageType.price)}',
                  selected: _selectedPackageType,
                  onSelected: (packageType) =>
                      setState(() => _selectedPackageType = packageType),
                  onClear: () => setState(() => _selectedPackageType = null),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            InfoBanner(
              variant: InfoBannerVariant.error,
              message: _errorMessage!,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Simpan & Lanjut Tambah Barang',
            loadingLabel: 'Menyimpan...',
            isLoading: _isSaving,
            icon: Icons.check_circle_outline_rounded,
            onPressed: _saveHeader,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DETAIL SECTION (tabel barang) -- tampil setelah resi dibuat
  // ============================================================

  Widget _buildDetailSection() {
    final receiving = _receiving!;
    final detailsAsync = ref.watch(receivingDetailsProvider(receiving.id));
    final items = detailsAsync.value ?? [];
    final sendersAsync = ref.watch(sendersProvider);
    // Dipakai buat resolve `pricingTypeId`/`storageId` (cuma ID di model)
    // jadi nama yang ditampilkan di kolom "Jenis Tarif"/"Zona" tabel --
    // lihat `_buildItemsTable`.
    final pricingTypesAsync = ref.watch(pricingTypesProvider);
    final storagesAsync = ref.watch(storagesProvider);
    final pricingTypeNameById = <String, String>{
      for (final p in pricingTypesAsync.value ?? const []) p.id: p.name,
    };
    final storageNameById = <String, String>{
      for (final s in storagesAsync.value ?? const []) s.id: s.namaZona,
    };

    String senderName = 'Memuat...';
    if (sendersAsync.hasValue) {
      SenderModel? sender;
      for (final s in sendersAsync.value!) {
        if (s.id == receiving.senderId) {
          sender = s;
          break;
        }
      }
      senderName = sender?.name ?? '-';
    }

    final hasItems = items.isNotEmpty;
    final hasLabelableItems = items.any((item) => !item.isUnlabeled);

    final totalQuantity = items.fold<double>(0, (sum, item) => sum + item.quantity);
    final totalPrice =
        items.fold<double>(0, (sum, item) => sum + (item.totalPrice ?? 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _buildHeaderStat(
                  'No. Resi',
                  (receiving.nomorBuku != null && receiving.nomorBuku!.isNotEmpty)
                      ? '${receiving.receiptNumber} / ${receiving.nomorBuku}'
                      : receiving.receiptNumber,
                ),
                _buildHeaderStat('Pengirim', senderName),
                _buildHeaderStat('Tujuan', receiving.destination),
                _buildHeaderStat('Jenis Barang', '${items.length}'),
                _buildHeaderStat(
                  'Total Qty',
                  totalQuantity == totalQuantity.roundToDouble()
                      ? totalQuantity.toStringAsFixed(0)
                      : totalQuantity.toString(),
                ),
                _buildHeaderStat('Total Harga', formatRupiah(totalPrice)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Detail Barang',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openAddDialog(items),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah Barang'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: detailsAsync.when(
              data: (items) => _buildItemsTable(
                items,
                pricingTypeNameById: pricingTypeNameById,
                storageNameById: storageNameById,
              ),
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.blue)),
              error: (error, stackTrace) => ErrorStateView(
                title: 'Gagal memuat detail barang',
                message: error.toString(),
                onRetry: () => ref.invalidate(receivingDetailsProvider(receiving.id)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      hasLabelableItems ? () => _openLabelPreview(items) : null,
                  icon: const Icon(Icons.label_outline_rounded),
                  label: const Text('Cetak Label'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasItems ? () => _openReceiptPreview(items) : null,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Cetak Resi'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABEL BARANG -- `DataTable` (permintaan user: "dibuat tabular
  // seperti CRUD umumnya master detail"). Baris READ-ONLY + ikon
  // ubah/hapus per baris (bukan sel langsung bisa diedit) -- pola CRUD
  // tabel + dialog standar, konsisten dengan dialog tambah/ubah yang
  // sama dipakai lewat tombol "Tambah Barang".
  // ============================================================

  Widget _buildItemsTable(
    List<ReceivingDetailModel> items, {
    required Map<String, String> pricingTypeNameById,
    required Map<String, String> storageNameById,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.textSecondary.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum ada barang. Klik "Tambah Barang" untuk mulai.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text('Nama Barang')),
              DataColumn(label: Text('Jenis Tarif')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Zona')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Harga Satuan'), numeric: true),
              DataColumn(label: Text('Total'), numeric: true),
              DataColumn(label: Text('Aksi')),
            ],
            rows: [
              for (final item in items)
                DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          item.itemName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(pricingTypeNameById[item.pricingTypeId] ?? '-'),
                    ),
                    DataCell(Text(
                      '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toStringAsFixed(0) : item.quantity} '
                      '${item.quantityUnit}',
                    )),
                    DataCell(
                      Text(
                        item.storageId != null
                            ? (storageNameById[item.storageId] ?? '-')
                            : '-',
                      ),
                    ),
                    DataCell(
                      item.isUnlabeled
                          ? _buildStatusChip('Tanpa Label', AppColors.red)
                          : (item.isBundle
                              ? _buildStatusChip(
                                  'Bundle x${item.bundleQuantity}', AppColors.orange)
                              : const Text('-')),
                    ),
                    DataCell(Text(formatRupiah(item.unitPrice ?? 0))),
                    DataCell(Text(
                      formatRupiah(item.totalPrice ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Ubah',
                            onPressed: () => _openEditDialog(item),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Hapus',
                            onPressed: () => _confirmDelete(item),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
