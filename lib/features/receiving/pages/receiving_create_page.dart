import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/destination_model.dart';
import '../../../models/employee_model.dart';
import '../../../models/package_type_model.dart';
import '../../../models/route_pricing_model.dart';
import '../../../models/sender_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/destination_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/receiving_service.dart';
import '../../../services/sender_service.dart';

import 'destination_picker_map_page.dart';
import 'receiving_items_page.dart';

class ReceivingCreatePage extends ConsumerStatefulWidget {
  const ReceivingCreatePage({super.key});

  @override
  ConsumerState<ReceivingCreatePage> createState() =>
      _ReceivingCreatePageState();
}

class _ReceivingCreatePageState extends ConsumerState<ReceivingCreatePage> {
  // ============================================================
  // CONTROLLERS
  // ============================================================

  final _senderController = TextEditingController();
  final _destinationController = TextEditingController();
  // FITUR (8 Oktober 2026 -- poin 1-7, Nomor Buku): opsional, dicatat
  // SAAT resi dibuat kalau staff punya nomor buku fisiknya (buku catatan
  // manual perwakilan).
  final _nomorBukuController = TextEditingController();

  // ============================================================
  // STATE
  // ============================================================

  SenderModel? _selectedSender;
  DestinationModel? _selectedDestination;
  RoutePricingModel? _selectedRoute;
  PackageTypeModel? _selectedPackageType;

  double? _destinationLatitude;
  double? _destinationLongitude;
  bool _isGeocoding = false;

  bool _isSaving = false;

  String? _errorMessage;

  @override
  void dispose() {
    _senderController.dispose();
    _destinationController.dispose();
    _nomorBukuController.dispose();

    super.dispose();
  }

  // ============================================================
  // SELECT SENDER
  // ============================================================
  //
  // NOTE: pencarian & debounce sekarang ditangani oleh SearchPickField
  // (core/widgets/search_pick_field.dart) -- halaman ini cukup
  // menyediakan fungsi pencarian & callback pilih/hapus.

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

  // ============================================================
  // CREATE NEW SENDER
  // ============================================================

  Future<void> _showCreateSenderDialog() async {
    final nameController = TextEditingController(
      text: _senderController.text.trim(),
    );
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
                  const SnackBar(
                    content: Text(
                      'Nama pengirim wajib diisi.',
                    ),
                  ),
                );
                return;
              }

              setDialogState(() {
                isCreating = true;
              });

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

                setDialogState(() {
                  isCreating = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Gagal membuat pengirim: $e',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppColors.blue,
                  ),
                  SizedBox(width: 10),
                  Text('Pengirim Baru'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTextField(
                      controller: nameController,
                      label: 'Nama Pengirim',
                      icon: Icons.business_rounded,
                      borderRadius: 14,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: phoneController,
                      label: 'No. HP',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      borderRadius: 14,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: addressController,
                      label: 'Alamat',
                      icon: Icons.location_on_outlined,
                      maxLines: 3,
                      borderRadius: 14,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isCreating
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: isCreating ? null : createSender,
                  icon: isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                        ),
                  label: const Text('Simpan'),
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

    if (result == null || !mounted) return;

    _selectSender(result);
  }

  // ============================================================
  // SELECT DESTINATION
  // ============================================================
  //
  // NOTE: memilih tujuan dari daftar penerima yang sudah pernah dipakai
  // sebelumnya (tabel `destinations`), supaya tidak perlu ketik ulang
  // tujuan yang sama & memudahkan cetak daftar resi per tujuan nanti.
  // Field tujuan/alamat/koordinat TETAP bisa diedit manual setelah
  // dipilih -- staff yang memutuskan kalau memang ada perbedaan alamat
  // untuk penerima yang sama (tidak digabung otomatis).

  void _selectDestination(DestinationModel destination) {
    FocusScope.of(context).unfocus();

    setState(() {
      _selectedDestination = destination;
      _destinationController.text = destination.name;

      // Alamat & No. HP TIDAK lagi diketik manual (lihat perbaikan
      // ambiguitas Penerima vs Tujuan, 22 Sep 2026) -- keduanya diambil
      // LANGSUNG dari data tujuan yang dipilih (_selectedDestination),
      // ditampilkan read-only lewat _buildSelectedDestination().

      if (destination.latitude != null && destination.longitude != null) {
        _destinationLatitude = destination.latitude;
        _destinationLongitude = destination.longitude;
      }

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
  // CREATE NEW DESTINATION
  // ============================================================

  Future<void> _showCreateDestinationDialog() async {
    final nameController = TextEditingController(
      text: _destinationController.text.trim(),
    );
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
                  const SnackBar(
                    content: Text(
                      'Nama tujuan wajib diisi.',
                    ),
                  ),
                );
                return;
              }

              setDialogState(() {
                isCreating = true;
              });

              try {
                final destination = await DestinationService.createDestination(
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                  latitude: _destinationLatitude,
                  longitude: _destinationLongitude,
                );

                if (!dialogContext.mounted) return;

                Navigator.of(dialogContext).pop(destination);
              } catch (e) {
                if (!dialogContext.mounted) return;

                setDialogState(() {
                  isCreating = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Gagal membuat tujuan: $e',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.add_location_alt_rounded,
                    color: AppColors.blue,
                  ),
                  SizedBox(width: 10),
                  Text('Tujuan Baru'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTextField(
                      controller: nameController,
                      label: 'Nama Tujuan',
                      icon: Icons.place_rounded,
                      borderRadius: 14,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: phoneController,
                      label: 'No. HP',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      borderRadius: 14,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: addressController,
                      label: 'Alamat',
                      icon: Icons.location_on_outlined,
                      maxLines: 3,
                      borderRadius: 14,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isCreating
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: isCreating ? null : createDestination,
                  icon: isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                        ),
                  label: const Text('Simpan'),
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

    if (result == null || !mounted) return;

    _selectDestination(result);
  }

  // ============================================================
  // TITIK LOKASI TUJUAN
  // ============================================================

  Future<void> _geocodeAddress() async {
    final selectedAddress = _selectedDestination?.address?.trim();
    final address = (selectedAddress != null && selectedAddress.isNotEmpty)
        ? selectedAddress
        : _destinationController.text.trim();

    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi alamat atau tujuan dulu sebelum cari otomatis.'),
        ),
      );
      return;
    }

    setState(() {
      _isGeocoding = true;
    });

    final location = await GeocodingService.geocodeAddress(address);

    if (!mounted) return;

    setState(() {
      _isGeocoding = false;

      if (location != null) {
        _destinationLatitude = location.latitude;
        _destinationLongitude = location.longitude;
      }
    });

    if (location == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Titik tidak ditemukan dari alamat itu -- coba "Pilih di Peta" secara manual.',
          ),
        ),
      );
    }
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => DestinationPickerMapPage(
          initialLatitude: _destinationLatitude,
          initialLongitude: _destinationLongitude,
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _destinationLatitude = picked.latitude;
        _destinationLongitude = picked.longitude;
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _destinationLatitude = null;
      _destinationLongitude = null;
    });
  }

  // ============================================================
  // SAVE RECEIVING
  // ============================================================

  Future<void> _saveReceiving() async {
    FocusScope.of(context).unfocus();

    if (_selectedSender == null) {
      setState(() {
        _errorMessage =
            'Silakan pilih atau buat pengirim terlebih dahulu.';
      });
      return;
    }

    final destination =
        _destinationController.text.trim();

    if (destination.isEmpty) {
      setState(() {
        _errorMessage =
            'Tujuan pengiriman wajib diisi.';
      });
      return;
    }

    if (_selectedPackageType == null) {
      setState(() {
        _errorMessage =
            'Jenis pengiriman wajib dipilih.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // ============================================================
      // DITERIMA OLEH (employee yang sedang login)
      //
      // receivedBy = staff yang bertanggung jawab menerima barang ini
      // di kantor/counter -- diambil dari sesi login, bukan input manual.
      // ============================================================
      //
      // PENERIMA = DATA TUJUAN (22 Sep 2026, perbaikan ambiguitas)
      //
      // receiverName/receiverPhone SENGAJA dikirim null -- field manual
      // untuk itu sudah dihapus dari layar ini. Identitas "penerima"
      // sekarang sepenuhnya diwakili oleh data Tujuan yang dipilih staff
      // di atas (_selectedDestination): destinationAddress & destination
      // Phone diambil LANGSUNG dari situ (snapshot, sama seperti pola
      // destination/destinationAddress yang sudah ada sebelumnya) --
      // BUKAN diketik ulang manual.
      // ============================================================

      final employee = await ref.read(currentEmployeeProvider.future);

      if (employee == null) {
        throw Exception(
          'Data employee yang login tidak ditemukan. '
          'Silakan login ulang.',
        );
      }

      /*
       * NOTE soal harga:
       *
       * routePricingId & packageTypeId sekarang sudah tersambung ke
       * data master (route_pricing & package_types), tapi total_price
       * resi BELUM dihitung dari harga rute/jenis pengiriman di sini --
       * itu menyusul setelah halaman input detail barang per-item
       * (receiving_details) dibangun, karena total_price idealnya
       * dihitung sekali dari kombinasi rute + jenis pengiriman + semua
       * item, bukan dicicil dari beberapa tempat. Untuk sekarang
       * total_price tetap default 0 dari database.
       */

      final selectedDestinationAddress =
          _selectedDestination?.address?.trim();
      final selectedDestinationPhone =
          _selectedDestination?.phone?.trim();

      final receiving =
          await ReceivingService.createReceiving(
        senderId: _selectedSender!.id,
        receiverName: null,
        receiverPhone: null,
        packageTypeId: _selectedPackageType!.id,
        destination: destination,
        destinationAddress:
            (selectedDestinationAddress != null &&
                    selectedDestinationAddress.isNotEmpty)
                ? selectedDestinationAddress
                : null,
        destinationPhone:
            (selectedDestinationPhone != null &&
                    selectedDestinationPhone.isNotEmpty)
                ? selectedDestinationPhone
                : null,
        destinationId: _selectedDestination?.id,
        receivedBy: employee.id,
        route: _selectedRoute?.routeName,
        routePricingId: _selectedRoute?.id,
        nomorBuku: _nomorBukuController.text.trim().isEmpty
            ? null
            : _nomorBukuController.text.trim(),
      );

      // Titik lokasi tujuan (kalau ada) disimpan lewat request terpisah --
      // kalau ini gagal, jangan gagalkan seluruh proses simpan resi
      // (nomor resi sudah terlanjur jadi), staff masih bisa isi manual
      // lagi belakangan.
      if (_destinationLatitude != null && _destinationLongitude != null) {
        try {
          await ReceivingService.updateDestinationCoordinates(
            receivingId: receiving.id,
            latitude: _destinationLatitude!,
            longitude: _destinationLongitude!,
          );
        } catch (_) {
          // diabaikan dengan sengaja, lihat catatan di atas.
        }
      }

      if (!mounted) return;

      await SuccessResultDialog.show(
        context,
        title: 'Penerimaan Berhasil',
        message: 'Nomor resi berhasil dibuat oleh sistem.',
        valueLabel: 'NOMOR RESI',
        value: receiving.receiptNumber,
        buttonLabel: 'Tambah Barang',
        onDone: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ReceivingItemsPage(receiving: receiving),
            ),
          );
        },
        secondaryLabel: 'Nanti Saja',
        onSecondary: () {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            e.toString().replaceFirst(
                  'Exception: ',
                  '',
                );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);
    final routePricingsAsync = ref.watch(routePricingsProvider);
    final packageTypesAsync = ref.watch(packageTypesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: _isSaving
              ? null
              : () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.navy,
          ),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terima Barang',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Penerimaan barang baru',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  18,
                  8,
                  18,
                  30,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _buildIntroCard(),

                    const SizedBox(height: 16),

                    _buildReceivedByCard(employeeAsync),

                    const SizedBox(height: 20),

                    const SectionHeader(
                      icon: Icons.storefront_rounded,
                      title: 'Pengirim',
                      subtitle:
                          'Cari pengirim atau tambahkan baru',
                    ),

                    const SizedBox(height: 12),

                    _buildSenderSection(),

                    const SizedBox(height: 24),

                    const SectionHeader(
                      icon: Icons.local_shipping_rounded,
                      title: 'Pengiriman',
                      subtitle:
                          'Penerima tujuan dan informasi perjalanan',
                    ),

                    const SizedBox(height: 12),

                    _buildShippingSection(
                      routePricingsAsync,
                      packageTypesAsync,
                    ),

                    const SizedBox(height: 24),

                    const SectionHeader(
                      icon: Icons.pin_drop_rounded,
                      title: 'Titik Lokasi Tujuan',
                      subtitle:
                          'Opsional -- dipakai buat peta rute driver',
                    ),

                    const SizedBox(height: 12),

                    _buildLocationSection(),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 20),
                      InfoBanner(
                        variant: InfoBannerVariant.error,
                        message: _errorMessage!,
                        onDismiss: () {
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INTRO
  // ============================================================

  Widget _buildIntroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.navy,
            AppColors.blue,
            AppColors.cyan,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.20),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Penerimaan Baru',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Nomor resi akan dibuat otomatis oleh sistem.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DITERIMA OLEH
  // ============================================================

  Widget _buildReceivedByCard(
    AsyncValue<EmployeeModel?> employeeAsync,
  ) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.badge_rounded,
              color: AppColors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DITERIMA OLEH',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                employeeAsync.when(
                  data: (employee) => Text(
                    employee?.fullName ??
                        'Data employee tidak ditemukan',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  error: (error, stackTrace) => const Text(
                    'Gagal memuat data employee',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SENDER
  // ============================================================

  Widget _buildSenderSection() {
    return AppCard(
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
        selectedBuilder: (context, sender) =>
            _buildSelectedSender(sender),
        addNewLabel: 'Tambah Pengirim Baru',
        onAddNew: _showCreateSenderDialog,
      ),
    );
  }

  Widget _buildSelectedSender(SenderModel sender) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF2FF),
            Color(0xFFE8FBFF),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.blue.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.blue,
                  AppColors.cyan,
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.business_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  sender.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (sender.phone != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    sender.phone!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.green,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PENERIMA TUJUAN (kartu read-only setelah dipilih)
  // ============================================================
  //
  // Nama/HP/Alamat di sini murni DITAMPILKAN dari data tujuan yang
  // dipilih (DestinationModel) -- TIDAK BISA diketik ulang manual di
  // sini. Kalau datanya salah/kurang lengkap, perbaiki di master data
  // "Daftar Langganan Tujuan" (admin), bukan di form ini.

  Widget _buildSelectedDestination(DestinationModel destination) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF2FF),
            Color(0xFFE8FBFF),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.blue.withOpacity(0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.blue,
                  AppColors.cyan,
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.place_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (destination.phone != null &&
                    destination.phone!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    destination.phone!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (destination.address != null &&
                    destination.address!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    destination.address!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if ((destination.phone == null ||
                        destination.phone!.isEmpty) &&
                    (destination.address == null ||
                        destination.address!.isEmpty)) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Belum ada No. HP/alamat tersimpan untuk tujuan ini.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.green,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHIPPING
  // ============================================================

  Widget _buildShippingSection(
    AsyncValue<List<RoutePricingModel>> routePricingsAsync,
    AsyncValue<List<PackageTypeModel>> packageTypesAsync,
  ) {
    return AppCard(
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
            // Kartu read-only -- nama/HP/alamat penerima SEKARANG
            // sepenuhnya diambil dari data Tujuan yang dipilih di sini
            // (tidak ada lagi field manual terpisah, lihat perbaikan
            // ambiguitas Penerima vs Tujuan, 22 Sep 2026).
            selectedBuilder: (context, destination) =>
                _buildSelectedDestination(destination),
            addNewLabel: 'Tambah Penerima Tujuan Baru',
            onAddNew: _showCreateDestinationDialog,
            // Pencarian di sini sudah selalu query langsung ke server
            // (lihat doc comment SearchPickField.showRefreshButton) --
            // tombol ini jaring pengaman supaya staff yakin tujuan yang
            // baru saja didaftarkan admin lewat "Daftar Langganan
            // Tujuan" langsung ketemu tanpa perlu tutup-buka aplikasi.
            showRefreshButton: true,
            refreshLabel: 'Ambil Tujuan Baru',
          ),
          const SizedBox(height: 14),
          // FITUR (8 Oktober 2026 -- poin 3, Nomor Buku): opsional, dicatat
          // SAAT resi dibuat kalau staff punya nomor buku fisiknya.
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
            onSelected: (route) {
              setState(() {
                _selectedRoute = route;
              });
            },
            onClear: () {
              setState(() {
                _selectedRoute = null;
              });
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
            itemSubtitle: (packageType) => '${packageType.durationDays} '
                'hari · ${formatRupiah(packageType.price)}',
            selectedText: (packageType) =>
                '${packageType.name} · ${formatRupiah(packageType.price)}',
            selected: _selectedPackageType,
            onSelected: (packageType) {
              setState(() {
                _selectedPackageType = packageType;
              });
            },
            onClear: () {
              setState(() {
                _selectedPackageType = null;
              });
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TITIK LOKASI TUJUAN
  // ============================================================

  Widget _buildLocationSection() {
    final hasLocation = _destinationLatitude != null && _destinationLongitude != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLocation)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: AppColors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_destinationLatitude!.toStringAsFixed(6)}, '
                      '${_destinationLongitude!.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving ? null : _clearLocation,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            )
          else
            const Text(
              'Belum ada titik koordinat. Isi biar tujuan ini muncul di peta '
              'rute driver.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving || _isGeocoding ? null : _geocodeAddress,
                  icon: _isGeocoding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Cari Otomatis'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickOnMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Pilih di Peta'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SAVE BUTTON
  // ============================================================

  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        18,
        12,
        18,
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: PrimaryButton(
        label: 'Simpan Penerimaan',
        loadingLabel: 'Menyimpan...',
        isLoading: _isSaving,
        icon: Icons.check_circle_outline_rounded,
        onPressed: _saveReceiving,
      ),
    );
  }
}