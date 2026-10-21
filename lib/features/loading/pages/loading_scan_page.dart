import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scan_feedback.dart';
import '../../../core/utils/unit_code.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/receiving_service.dart';
import '../../../services/shipment_service.dart';
import '../widgets/manual_load_checklist.dart';

/// Mode loading -- FIX (6 Oktober 2026 lanjutan, permintaan user
/// eksplisit): sebelumnya barang "Tanpa Label QR" cuma dilayani lewat
/// ikon kecil & bottom sheet "tandai satu-satu" di atas layar kamera.
/// User minta jadi 2 PILIHAN EKSPLISIT setingkat ("harus ada pilihan: a.
/// loading Label QR b. loading non Label QR") -- bukan lagi sekadar
/// fitur tambahan tersembunyi. [labelQr] = alur yang SUDAH ADA (scan
/// kamera, tidak diubah sama sekali). [nonLabelQr] = alur checklist
/// manual (TANPA scan kamera) -- staff masukkan/cari no resi dulu, baru
/// mencentang barang resi itu yang naik ke kendaraan ini, sekali submit.
///
/// DIPERLUAS (7 Oktober 2026, permintaan user eksplisit): dulu
/// [nonLabelQr] HANYA menampilkan barang `is_unlabeled == true`. Sekarang
/// menampilkan SEMUA barang (berlabel QR maupun tidak) yang masih ada
/// unit fisik belum dimuat ke shipment manapun -- scan QR saat loading
/// TIDAK WAJIB, staff bisa langsung centang manual kalau situasinya
/// darurat atau resi punya campuran barang berlabel & tanpa label. UI
/// checklist-nya sendiri DIPINDAH ke widget bersama
/// `ManualLoadChecklistView` (dipakai juga oleh halaman admin "Loading
/// Barang", lihat `AdminManualLoadPage`) supaya logic-nya tidak dobel.
enum _LoadingMode { labelQr, nonLabelQr }

/// Halaman scan barang naik ke kendaraan. Loading HANYA bertugas scan &
/// menyimpan -- TIDAK memberangkatkan kendaraan (itu wewenang Admin
/// lewat halaman "Daftar Muatan"). Setelah scan, staff cukup keluar dari
/// halaman ini (data otomatis tersimpan tiap scan); kendaraan tetap
/// muncul di "Pilih Kendaraan" untuk kemungkinan tambahan muatan sampai
/// benar-benar diberangkatkan Admin.
class LoadingScanPage extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final ShipmentModel shipment;

  const LoadingScanPage({
    super.key,
    required this.vehicle,
    required this.shipment,
  });

  @override
  ConsumerState<LoadingScanPage> createState() => _LoadingScanPageState();
}

class _LoadingScanPageState extends ConsumerState<LoadingScanPage> {
  final MobileScannerController _controller = MobileScannerController();

  bool _isProcessing = false;
  String? _lastFeedback;
  Color _lastFeedbackColor = AppColors.green;

  _LoadingMode _mode = _LoadingMode.labelQr;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // SCAN HANDLER (Label QR -- TIDAK DIUBAH)
  // ============================================================

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final rawValue =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;

    if (rawValue == null || rawValue.trim().isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final parsed = UnitCodeParser.parse(rawValue);

      final detail =
          await ReceivingService.getReceivingDetailByItemCode(parsed.itemCode);

      if (detail == null) {
        _showFeedback(
          'Kode "${parsed.itemCode}" tidak ditemukan di data penerimaan.',
          AppColors.red,
        );
        return;
      }

      final employee = await ref.read(currentEmployeeProvider.future);

      if (employee == null) {
        _showFeedback(
          'Data employee tidak ditemukan, tidak bisa mencatat scan.',
          AppColors.red,
        );
        return;
      }

      await ShipmentService.recordScan(
        shipmentId: widget.shipment.id,
        receivingDetailId: detail.id,
        unitCode: rawValue.trim(),
        unitIndex: parsed.unitIndex,
        scannedBy: employee.id,
      );

      ref.invalidate(shipmentScansProvider(widget.shipment.id));

      _showFeedback(
        '${detail.itemName} berhasil dicatat naik.',
        AppColors.green,
        isSuccess: true,
      );
    } on DuplicateScanException catch (e) {
      _showFeedback(e.toString(), AppColors.orange);
    } catch (e) {
      _showFeedback('Gagal mencatat scan: $e', AppColors.red);
    } finally {
      // Jeda anti-double-scan dipangkas dari 900ms -> 350ms (hasil uji
      // coba lapangan: 900ms kerasa lama & bikin staff mengira QR belum
      // kebaca, jadi mereka scan ulang berkali-kali). 350ms masih cukup
      // supaya kamera tidak langsung men-scan ulang kode yang sama
      // dalam sepersekian detik, tapi jauh lebih responsif. Duplikasi
      // scan tetap aman karena sudah ditolak server (DuplicateScanException).
      await Future.delayed(const Duration(milliseconds: 350));

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // [isSuccess] menentukan bunyi yang diputar -- ding (sukses) atau
  // buzz (gagal/ditolak). Dipanggil sebelum setState supaya bunyi
  // langsung kedengaran tanpa nunggu rebuild layar.
  void _showFeedback(String message, Color color, {bool isSuccess = false}) {
    if (isSuccess) {
      ScanFeedback.playSuccess();
    } else {
      ScanFeedback.playFailure();
    }

    if (!mounted) return;

    setState(() {
      _lastFeedback = message;
      _lastFeedbackColor = color;
    });
  }

  // Mode B ("Tanpa Label QR") sekarang sepenuhnya ditangani widget
  // bersama `ManualLoadChecklistView` (lihat import di atas) -- lihat doc
  // comment di widget itu & di `ShipmentService.getAvailableItemsForManualLoad`
  // untuk detail lengkap & riwayat perubahan 7 Oktober 2026.

  void _finishScanning() {
    // Loading cukup selesai scan & keluar -- data sudah tersimpan tiap
    // scan (recordScan langsung insert ke Supabase), tidak ada aksi
    // "berangkat" di sini. Kendaraan tetap LOADING & tetap muncul di
    // "Pilih Kendaraan" sampai Admin yang memberangkatkan.
    Navigator.of(context).pop();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final scansAsync = ref.watch(shipmentScansProvider(widget.shipment.id));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: Text(widget.shipment.shipmentNumber),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeToggle(),
          Expanded(
            child: _mode == _LoadingMode.labelQr
                ? _buildLabelQrBody(scansAsync)
                : _buildNonLabelBody(),
          ),
        ],
      ),
      // Tombol "Cetak Manifest" DIHAPUS dari halaman Loading (permintaan
      // user eksplisit, 7 Oktober 2026): manifest & tanda terima tujuan
      // TIDAK LAGI diproduksi/dicetak sebagai output Loading, melainkan
      // sepenuhnya jadi wewenang Admin (lihat `ShipmentDispatchPage` &
      // `ShipmentDepartedSearchPage` -- tombol "Manifest"/"Tanda Terima
      // Tujuan" di sana TIDAK diubah/dihapus, tetap satu-satunya jalan
      // mencetak dokumen itu).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: PrimaryButton(
            label: 'Selesai & Simpan',
            icon: Icons.check_circle_rounded,
            backgroundColor: AppColors.green,
            onPressed: _finishScanning,
          ),
        ),
      ),
    );
  }

  /// Pilihan eksplisit "a. Loading Label QR / b. Loading Non Label QR" --
  /// permintaan user, 6 Oktober 2026 lanjutan. Diletakkan paling atas
  /// badan halaman, SELALU terlihat, supaya staff sadar ada 2 jalur
  /// berbeda (bukan lagi ikon kecil yang mudah terlewat).
  Widget _buildModeToggle() {
    return Container(
      width: double.infinity,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SegmentedButton<_LoadingMode>(
        segments: const [
          ButtonSegment(
            value: _LoadingMode.labelQr,
            label: Text('Label QR'),
            icon: Icon(Icons.qr_code_scanner_rounded),
          ),
          ButtonSegment(
            value: _LoadingMode.nonLabelQr,
            label: Text('Tanpa Label QR'),
            icon: Icon(Icons.inventory_outlined),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() => _mode = selection.first);
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white,
          selectedBackgroundColor: AppColors.orange,
          selectedForegroundColor: Colors.white,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Mode A: Label QR (kamera -- SAMA PERSIS dengan sebelumnya)
  // ------------------------------------------------------------

  Widget _buildLabelQrBody(AsyncValue<List<Map<String, dynamic>>> scansAsync) {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _onDetect),
              _buildScanFrame(),
              if (_lastFeedback != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _buildFeedbackBanner(),
                ),
            ],
          ),
        ),
        Expanded(flex: 4, child: _buildScanFeed(scansAsync)),
      ],
    );
  }

  // ------------------------------------------------------------
  // Mode B: Tanpa Label QR (cari resi -> checklist -> submit) --
  // seluruh UI & logic-nya sudah dipindah ke widget bersama
  // `ManualLoadChecklistView` (lihat import di atas), supaya dipakai
  // juga oleh `AdminManualLoadPage` tanpa duplikasi.
  // ------------------------------------------------------------

  Widget _buildNonLabelBody() {
    return ManualLoadChecklistView(shipmentId: widget.shipment.id);
  }

  Widget _buildScanFrame() {
    return Center(
      child: Container(
        width: 230,
        height: 230,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 2),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  Widget _buildFeedbackBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _lastFeedbackColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Text(
        _lastFeedback ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildScanFeed(AsyncValue<List<Map<String, dynamic>>> scansAsync) {
    return Container(
      color: AppColors.background,
      child: scansAsync.when(
        data: (scans) {
          if (scans.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada barang yang discan.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded, size: 18, color: AppColors.blue),
                    const SizedBox(width: 8),
                    Text(
                      '${scans.length} barang sudah naik',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: scans.length,
                  itemBuilder: (context, index) {
                    final scan = scans[index];
                    final detail = scan['receiving_details'] as Map?;
                    final receiving = detail?['receiving'] as Map?;

                    final itemName = detail?['item_name'] ?? scan['unit_code'];
                    final itemCode = detail?['item_code'] ?? scan['unit_code'];
                    final receiptNumber = receiving?['receipt_number'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.blue.withOpacity(0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.check_rounded, color: AppColors.green, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemName.toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  [
                                    itemCode.toString(),
                                    if (receiptNumber != null) receiptNumber.toString(),
                                  ].join(' • '),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            'Gagal memuat daftar scan: $error',
            style: const TextStyle(color: AppColors.red),
          ),
        ),
      ),
    );
  }
}
