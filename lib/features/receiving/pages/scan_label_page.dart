import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scan_feedback.dart';
import '../../../models/daftar_label_barcode_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/receiving_model.dart';
import '../../../providers/session_provider.dart';
import '../../../services/label_barcode_service.dart';

/// Halaman "Scan Label" (Section A -- Fitur Label Barcode, 21 Oktober
/// 2026). Mengikat kode blanko Code128 (dari stok "Stok Label Barcode")
/// yang SUDAH ditempel fisik ke koli barang, ke 1 baris
/// `receiving_details` yang jenis labelnya BARCODE -- lihat
/// `ReceivingDetailModel.labelType`/[ReceivingDetailModel.isBarcode].
/// Target jumlah kode = [ReceivingDetailModel.totalPhysicalQuantity]
/// (sama seperti jumlah label QR yang biasanya dicetak untuk 1 baris
/// barang).
///
/// Dibuka dari `ReceivingItemsPage` (tap barang -> aksi "Scan Label",
/// hanya muncul kalau `item.isBarcode`).
class ScanLabelPage extends ConsumerStatefulWidget {
  final ReceivingModel receiving;
  final ReceivingDetailModel detail;

  const ScanLabelPage({
    super.key,
    required this.receiving,
    required this.detail,
  });

  @override
  ConsumerState<ScanLabelPage> createState() => _ScanLabelPageState();
}

class _ScanLabelPageState extends ConsumerState<ScanLabelPage> {
  final MobileScannerController _controller = MobileScannerController();

  bool _isProcessing = false;
  bool _isLoadingBound = true;
  List<DaftarLabelBarcodeModel> _bound = [];

  String? _lastFeedback;
  Color _lastFeedbackColor = AppColors.green;

  int get _target => widget.detail.totalPhysicalQuantity.round().clamp(1, 999999);

  @override
  void initState() {
    super.initState();
    _loadBound();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadBound() async {
    try {
      final bound = await LabelBarcodeService.getBoundToDetail(widget.detail.id);
      if (!mounted) return;
      setState(() {
        _bound = bound;
        _isLoadingBound = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingBound = false);
      _showFeedback('Gagal memuat daftar kode terikat: $e', AppColors.red);
    }
  }

  // ============================================================
  // SCAN -> BIND
  // ============================================================

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final rawValue =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    final code = rawValue.trim();

    setState(() => _isProcessing = true);

    try {
      if (_bound.any((b) => b.barcodeCode == code)) {
        _showFeedback('Kode ini sudah diikat ke barang ini.', AppColors.orange);
        return;
      }

      final employee = await ref.read(currentEmployeeProvider.future);

      await LabelBarcodeService.bindToReceivingDetail(
        barcodeCode: code,
        receivingDetailId: widget.detail.id,
        noResi: widget.receiving.receiptNumber,
        kodeBarang: widget.detail.itemCode,
        assignedBy: employee?.id,
      );

      await _loadBound();

      if (!mounted) return;
      _showFeedback(
        'Kode $code berhasil diikat (${_bound.length}/$_target).',
        AppColors.green,
        isSuccess: true,
      );
    } catch (e) {
      _showFeedback('Gagal mengikat kode: $e', AppColors.red);
    } finally {
      // Jeda anti-double-scan (sama seperti LoadingScanPage/DeliveryResiScanPage).
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) setState(() => _isProcessing = false);
    }
  }

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

  // ============================================================
  // UNBIND
  // ============================================================

  Future<void> _confirmUnbind(DaftarLabelBarcodeModel code) async {
    final alreadyScanned = await LabelBarcodeService.isCodeScanned(code.barcodeCode);

    if (!mounted) return;

    if (alreadyScanned) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tidak Bisa Dilepas'),
          content: Text(
            'Kode "${code.barcodeCode}" sudah pernah tercatat scan di '
            'Loading/Delivery -- tidak bisa dilepas lagi supaya riwayat '
            'scan tetap jelas asalnya.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Oke'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lepas Ikatan Kode?'),
        content: Text(
          'Kode "${code.barcodeCode}" akan dilepas dari barang ini & '
          'balik jadi stok belum dipakai. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lepas'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await LabelBarcodeService.unbind(code.barcodeCode);
      await _loadBound();
    } catch (e) {
      if (!mounted) return;
      _showFeedback('Gagal melepas kode: $e', AppColors.red);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Label',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              widget.detail.itemName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
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
            Expanded(flex: 4, child: _buildBoundList()),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final count = _bound.length;
    final isDone = count >= _target;

    return Container(
      width: double.infinity,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_target == 0) ? 0 : (count / _target).clamp(0, 1).toDouble(),
                minHeight: 10,
                backgroundColor: Colors.white24,
                color: isDone ? AppColors.green : AppColors.cyan,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _isLoadingBound ? '.../$_target' : '$count/$_target terikat',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildScanFrame() {
    return Center(
      child: Container(
        width: 260,
        height: 140,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 2),
          borderRadius: BorderRadius.circular(16),
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

  Widget _buildBoundList() {
    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Kode yang Sudah Terikat',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: _isLoadingBound
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
                : _bound.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada kode yang diikat -- arahkan kamera ke '
                          'barcode blanko yang sudah ditempel.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _bound.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final code = _bound[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.view_column_rounded,
                                  color: AppColors.cyan,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    code.barcodeCode,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _confirmUnbind(code),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: AppColors.red,
                                    size: 20,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
