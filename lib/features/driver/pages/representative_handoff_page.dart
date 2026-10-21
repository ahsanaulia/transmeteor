import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/representative_model.dart';
import '../../../models/shipment_model.dart';
import '../../../providers/driver_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/representative_service.dart';
import '../../../services/shipment_service.dart';

/// Mode lingkup penyelesaian -- "pilihan setingkat" (SegmentedButton),
/// mengikuti pola yang sama dipakai Loading/Delivery (Label QR vs Tanpa
/// Label QR). Permintaan user eksplisit, 6 Oktober 2026 lanjutan: "ada
/// pilihan jika barang diselesaikan di perwakilan berdasarkan resi atau
/// daftar per tujuan".
enum _HandoffScopeMode { perResi, perTujuan }

/// Halaman "Selesaikan di Perwakilan" -- dipakai sopir kalau tujuan asli
/// TUTUP atau TIDAK BISA DIJANGKAU, sehingga barang (sisa yang belum
/// sempat discan turun) dititip dulu di perwakilan/agen, BUKAN langsung
/// diturunkan di tujuan. Permintaan user eksplisit:
///
/// "Ada kasus dimana barang tidak diselesaikan di tujuan. Karena tujuan
/// tutup atau tidak bisa dijangkau. Sehingga driver/sopir menurunkan
/// barang diperwakilan. pada aplikasi sopir ada pilihan jika barang
/// diselesaikan di perwakilan berdasarkan resi atau daftar per tujuan.
/// Sopir menulis nama perwakilan dan alamatnya dan mencari jika sudah
/// ada di aplikasi. Butuh tabel perwakilan. Dan secara otomatis HP
/// sopir mengirim informasi bahwa Resi dan barang sekian turun di
/// perwakilan yang dimaksud."
///
/// Alur 3 langkah:
/// 1. Pilih MODE (Per Resi -- satu resi saja, atau Per Tujuan -- semua
///    resi yang searah/satu tujuan sekaligus), lalu pilih target-nya.
/// 2. Cari perwakilan yang sudah pernah didaftarkan
///    (`SearchPickField<RepresentativeModel>`), atau tambah baru kalau
///    belum ada (nama + alamat, mengikuti pola PERSIS
///    `_showCreateSenderDialog` di `ReceivingCreatePage`).
/// 3. Konfirmasi -- catat SEMUA unit barang target terpilih yang masih
///    pending turun sebagai "diserahkan ke perwakilan" (lihat
///    `ShipmentService.recordRepresentativeHandoffForReceivings`), lalu
///    OTOMATIS buka WhatsApp ke nomor HP TUJUAN (live dari
///    `destinations`, SAMA seperti pola `ReceiptPreviewPage`) berisi
///    info resi/jumlah barang/nama & alamat perwakilan -- supaya
///    penerima tahu barangnya bisa diambil di perwakilan tersebut.
class RepresentativeHandoffPage extends ConsumerStatefulWidget {
  final ShipmentModel shipment;

  const RepresentativeHandoffPage({super.key, required this.shipment});

  @override
  ConsumerState<RepresentativeHandoffPage> createState() =>
      _RepresentativeHandoffPageState();
}

class _RepresentativeHandoffPageState
    extends ConsumerState<RepresentativeHandoffPage> {
  _HandoffScopeMode _scopeMode = _HandoffScopeMode.perResi;

  // Target terpilih (1 resi ATAU gabungan resi 1 tujuan) -- disatukan
  // jadi bentuk data yang sama supaya langkah 2 & 3 tidak perlu cabang
  // berbeda per mode.
  List<String>? _selectedReceivingIds;
  String? _selectedLabel; // No. resi (Per Resi) / nama tujuan (Per Tujuan)
  String? _selectedDestinationAddress;
  String? _selectedDestinationPhone;
  int? _selectedPendingCount;

  final _representativeSearchController = TextEditingController();
  RepresentativeModel? _selectedRepresentative;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _representativeSearchController.dispose();
    super.dispose();
  }

  void _resetSelection() {
    setState(() {
      _selectedReceivingIds = null;
      _selectedLabel = null;
      _selectedDestinationAddress = null;
      _selectedDestinationPhone = null;
      _selectedPendingCount = null;
      _selectedRepresentative = null;
      _representativeSearchController.clear();
    });
  }

  void _selectReceiving(Map<String, dynamic> group) {
    final totalItems = group['totalItems'] as int;
    final deliveredItems = group['deliveredItems'] as int;

    setState(() {
      _selectedReceivingIds = [group['receivingId'] as String];
      _selectedLabel = (group['receiptNumber'] ?? '-').toString();
      _selectedDestinationAddress = group['destinationAddress'] as String?;
      _selectedDestinationPhone = group['destinationPhone'] as String?;
      _selectedPendingCount = totalItems - deliveredItems;
      _selectedRepresentative = null;
      _representativeSearchController.clear();
    });
  }

  void _selectDestinationGroup(Map<String, dynamic> group) {
    final totalItems = group['totalItems'] as int;
    final deliveredItems = group['deliveredItems'] as int;

    setState(() {
      _selectedReceivingIds =
          List<String>.from(group['receivingIds'] as List);
      _selectedLabel = (group['destinationName'] ?? '-').toString();
      _selectedDestinationAddress = group['destinationAddress'] as String?;
      _selectedDestinationPhone = group['destinationPhone'] as String?;
      _selectedPendingCount = totalItems - deliveredItems;
      _selectedRepresentative = null;
      _representativeSearchController.clear();
    });
  }

  // ============================================================
  // CARI / TAMBAH PERWAKILAN
  // ============================================================

  void _selectRepresentative(RepresentativeModel representative) {
    setState(() {
      _selectedRepresentative = representative;
      _representativeSearchController.text = representative.name;
    });
  }

  void _clearRepresentative() {
    setState(() {
      _selectedRepresentative = null;
      _representativeSearchController.clear();
    });
  }

  /// Dialog ringkas "Perwakilan Baru" -- mengikuti pola PERSIS
  /// `_showCreateSenderDialog`/`_showCreateDestinationDialog` di
  /// `ReceivingCreatePage` (AlertDialog + StatefulBuilder, BUKAN bottom
  /// sheet -- sheet `RepresentativeFormSheet` dipakai KHUSUS admin).
  Future<void> _showCreateRepresentativeDialog() async {
    final nameController = TextEditingController(
      text: _representativeSearchController.text.trim(),
    );
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<RepresentativeModel>(
      context: context,
      builder: (dialogContext) {
        bool isCreating = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> createRepresentative() async {
              final name = nameController.text.trim();

              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Nama perwakilan wajib diisi.'),
                  ),
                );
                return;
              }

              setDialogState(() {
                isCreating = true;
              });

              try {
                final representative =
                    await RepresentativeService.createRepresentative(
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );

                if (!dialogContext.mounted) return;

                Navigator.of(dialogContext).pop(representative);
              } catch (e) {
                if (!dialogContext.mounted) return;

                setDialogState(() {
                  isCreating = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('Gagal membuat perwakilan: $e'),
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
                    Icons.storefront_rounded,
                    color: AppColors.orange,
                  ),
                  SizedBox(width: 10),
                  Text('Perwakilan Baru'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTextField(
                      controller: nameController,
                      label: 'Nama Perwakilan',
                      icon: Icons.storefront_outlined,
                      borderRadius: 14,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: phoneController,
                      label: 'No. HP (opsional)',
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
                  onPressed: isCreating ? null : createRepresentative,
                  icon: isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
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

    _selectRepresentative(result);
  }

  // ============================================================
  // SUBMIT
  // ============================================================

  Future<void> _submit() async {
    final receivingIds = _selectedReceivingIds;
    final representative = _selectedRepresentative;

    if (receivingIds == null || receivingIds.isEmpty || representative == null) {
      return;
    }

    setState(() => _isSubmitting = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final employee = await ref.read(currentEmployeeProvider.future);

      if (employee == null) {
        throw Exception('Data employee tidak ditemukan.');
      }

      // Lokasi OPSIONAL di sini -- beda dari DeliveryResiScanPage yang
      // menunggu lokasi dulu sebelum kamera aktif (scan kamera butuh
      // lokasi presisi tiap barang). Di sini sopir sudah pasti berhenti
      // di satu titik perwakilan untuk menitip SEKALIGUS -- gagal
      // ambil lokasi TIDAK membatalkan handoff, cukup dicatat null.
      final position = await LocationHelper.getCurrentPosition(context);

      final createdCount =
          await ShipmentService.recordRepresentativeHandoffForReceivings(
        shipmentId: widget.shipment.id,
        receivingIds: receivingIds,
        representativeId: representative.id,
        representativeName: representative.name,
        scannedBy: employee.id,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      ref.invalidate(shipmentManifestByReceivingProvider(widget.shipment.id));
      ref.invalidate(handoffCandidatesByReceivingProvider(widget.shipment.id));
      ref.invalidate(shipmentManifestByDestinationProvider(widget.shipment.id));
      ref.invalidate(shipmentDeliverScansProvider(widget.shipment.id));

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$createdCount barang dicatat turun di perwakilan '
            '${representative.name}.',
          ),
          backgroundColor: AppColors.green,
        ),
      );

      await _sendWhatsAppNotice(representative, createdCount);

      if (!mounted) return;
      _resetSelection();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mencatat handoff: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Otomatis buka WhatsApp ke nomor HP TUJUAN (BUKAN ke perwakilan) --
  /// permintaan user eksplisit: "secara otomatis HP sopir mengirim
  /// informasi bahwa Resi dan barang sekian turun di perwakilan yang
  /// dimaksud". Nomor Tujuan dipakai (live dari `destinations`,
  /// mengikuti pola PERSIS `ReceiptPreviewPage._sendWhatsAppToDestination`)
  /// supaya penerima tahu barangnya sekarang dititip di perwakilan &
  /// bisa diambil di sana.
  ///
  /// Kalau nomor Tujuan belum ada di data, WA TIDAK dikirim otomatis --
  /// cuma diberi tahu lewat SnackBar (SAMA PERSIS perilaku
  /// `ReceiptPreviewPage` kalau nomor kosong) -- handoff & pencatatan
  /// barangnya TETAP tersimpan, tidak dibatalkan.
  Future<void> _sendWhatsAppNotice(
    RepresentativeModel representative,
    int itemCount,
  ) async {
    final phone = _selectedDestinationPhone;

    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Catatan tersimpan, TAPI nomor HP Tujuan belum ada di data '
            'tujuan ini -- info perwakilan tidak bisa otomatis '
            'terkirim lewat WhatsApp.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }

    final normalized = _normalizePhoneForWa(phone);

    if (normalized == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nomor HP "$phone" tidak valid untuk WhatsApp.')),
      );
      return;
    }

    final text = _buildWhatsAppMessage(representative, itemCount);
    final uri = Uri.parse(
      'https://wa.me/$normalized?text=${Uri.encodeComponent(text)}',
    );

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('WhatsApp tidak bisa dibuka.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka WhatsApp: $e')),
      );
    }
  }

  String _buildWhatsAppMessage(
    RepresentativeModel representative,
    int itemCount,
  ) {
    final buffer = StringBuffer()
      ..writeln('*Info Barang Dititip di Perwakilan*')
      ..writeln('Resi     : ${_selectedLabel ?? '-'}')
      ..writeln('Jumlah   : $itemCount barang')
      ..writeln('Perwakilan : ${representative.name}');

    if (representative.address != null && representative.address!.isNotEmpty) {
      buffer.writeln('Alamat   : ${representative.address}');
    }
    if (representative.phone != null && representative.phone!.isNotEmpty) {
      buffer.writeln('No. HP   : ${representative.phone}');
    }

    buffer.writeln();
    buffer.writeln(
      'Tujuan pengiriman tidak dapat kami jangkau, sehingga barang '
      'dititipkan di perwakilan di atas. Silakan diambil di alamat '
      'tersebut. Terima kasih sudah menggunakan jasa kami.',
    );

    return buffer.toString();
  }

  /// Sama persis `ReceiptPreviewPage._normalizePhoneForWa`.
  String? _normalizePhoneForWa(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    }

    if (digits.length < 8) return null;

    return digits;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Selesaikan di Perwakilan'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const InfoBanner(
              variant: InfoBannerVariant.warning,
              message:
                  'Pakai halaman ini KHUSUS kalau tujuan asli tutup/tidak '
                  'bisa dijangkau, sehingga barang dititip dulu di '
                  'perwakilan/agen. Kalau tujuan masih bisa didatangi '
                  'normal, tetap turunkan barang lewat scan/checklist '
                  'biasa di manifest.',
            ),
            const SizedBox(height: 16),
            _buildScopeModeToggle(),
            const SizedBox(height: 12),
            _buildScopePicker(),
            if (_selectedReceivingIds != null) ...[
              const SizedBox(height: 20),
              _buildSelectedTargetCard(),
              const SizedBox(height: 20),
              _buildRepresentativePicker(),
            ],
            if (_selectedRepresentative != null) ...[
              const SizedBox(height: 24),
              _buildSubmitButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScopeModeToggle() {
    return SegmentedButton<_HandoffScopeMode>(
      segments: const [
        ButtonSegment(
          value: _HandoffScopeMode.perResi,
          label: Text('Per Resi'),
          icon: Icon(Icons.receipt_long_rounded),
        ),
        ButtonSegment(
          value: _HandoffScopeMode.perTujuan,
          label: Text('Per Tujuan'),
          icon: Icon(Icons.place_rounded),
        ),
      ],
      selected: {_scopeMode},
      onSelectionChanged: (selection) {
        setState(() {
          _scopeMode = selection.first;
          _resetSelection();
        });
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        selectedBackgroundColor: AppColors.orange,
        selectedForegroundColor: Colors.white,
      ),
    );
  }

  Widget _buildScopePicker() {
    return _scopeMode == _HandoffScopeMode.perResi
        ? _buildPerResiPicker()
        : _buildPerTujuanPicker();
  }

  Widget _buildPerResiPicker() {
    final manifestAsync =
        ref.watch(handoffCandidatesByReceivingProvider(widget.shipment.id));

    return manifestAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Belum ada resi di manifest shipment ini.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        return Column(
          children: groups.map((group) {
            final receivingId = group['receivingId'] as String;
            final totalItems = group['totalItems'] as int;
            final deliveredItems = group['deliveredItems'] as int;
            final pending = totalItems - deliveredItems;
            final isSelected = _selectedReceivingIds?.length == 1 &&
                _selectedReceivingIds!.first == receivingId;

            return _ScopeTile(
              title: (group['receiptNumber'] ?? '-').toString(),
              subtitle: (group['destination'] ?? '-').toString(),
              pendingCount: pending,
              isSelected: isSelected,
              onTap: pending <= 0 ? null : () => _selectReceiving(group),
            );
          }).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.blue)),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Gagal memuat manifest: $error',
          style: const TextStyle(color: AppColors.red),
        ),
      ),
    );
  }

  Widget _buildPerTujuanPicker() {
    final manifestAsync =
        ref.watch(shipmentManifestByDestinationProvider(widget.shipment.id));

    return manifestAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Belum ada tujuan di manifest shipment ini.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        return Column(
          children: groups.map((group) {
            final receivingIds =
                List<String>.from(group['receivingIds'] as List);
            final totalItems = group['totalItems'] as int;
            final deliveredItems = group['deliveredItems'] as int;
            final pending = totalItems - deliveredItems;
            final isSelected = _selectedReceivingIds != null &&
                _selectedReceivingIds!.length == receivingIds.length &&
                _selectedReceivingIds!.toSet().containsAll(receivingIds);

            return _ScopeTile(
              title: (group['destinationName'] ?? '-').toString(),
              subtitle: '${receivingIds.length} resi tergabung di tujuan ini',
              pendingCount: pending,
              isSelected: isSelected,
              onTap: pending <= 0 ? null : () => _selectDestinationGroup(group),
            );
          }).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.blue)),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Gagal memuat manifest: $error',
          style: const TextStyle(color: AppColors.red),
        ),
      ),
    );
  }

  Widget _buildSelectedTargetCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedLabel ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (_selectedDestinationAddress != null &&
                    _selectedDestinationAddress!.isNotEmpty)
                  Text(
                    _selectedDestinationAddress!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                Text(
                  '$_selectedPendingCount barang akan dititip di perwakilan',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _resetSelection,
            child: const Text('Ganti'),
          ),
        ],
      ),
    );
  }

  Widget _buildRepresentativePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Perwakilan',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SearchPickField<RepresentativeModel>(
          controller: _representativeSearchController,
          label: 'Cari Perwakilan',
          hint: 'Cari nama perwakilan yang sudah terdaftar...',
          onSearch: RepresentativeService.searchRepresentatives,
          itemLabel: (representative) => representative.name,
          itemSubtitle: (representative) => representative.address,
          selected: _selectedRepresentative,
          onSelected: _selectRepresentative,
          onClear: _clearRepresentative,
          addNewLabel: 'Tambah Perwakilan Baru',
          onAddNew: _showCreateRepresentativeDialog,
          notFoundMessage:
              'Perwakilan belum ditemukan. Pakai tombol di bawah untuk '
              'mendaftarkan yang baru.',
          selectedBuilder: (context, representative) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, color: AppColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        representative.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (representative.address != null &&
                          representative.address!.isNotEmpty)
                        Text(
                          representative.address!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: _isSubmitting ? null : _submit,
        style: FilledButton.styleFrom(backgroundColor: AppColors.green),
        icon: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_circle_rounded),
        label: Text(
          _isSubmitting
              ? 'Mencatat...'
              : 'Catat $_selectedPendingCount Barang Turun di Perwakilan',
        ),
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int pendingCount;
  final bool isSelected;
  final VoidCallback? onTap;

  const _ScopeTile({
    required this.title,
    required this.subtitle,
    required this.pendingCount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = pendingCount <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.orange : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (isDone ? AppColors.green : AppColors.orange).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isDone ? Icons.check_circle_rounded : Icons.inventory_2_outlined,
            color: isDone ? AppColors.green : AppColors.orange,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Text(
          isDone ? 'Selesai' : '$pendingCount tersisa',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDone ? AppColors.green : AppColors.orange,
          ),
        ),
      ),
    );
  }
}
