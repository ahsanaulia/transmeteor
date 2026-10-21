import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/pdf_templates.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/company_model.dart';
import '../../../models/destination_model.dart';
import '../../../models/receiving_model.dart';
import '../../../services/company_service.dart';
import '../../../services/destination_service.dart';
import '../../../services/sender_service.dart';

/// Semua resi yang tujuannya sama dengan [destination] -- dipakai supaya
/// sopir tidak perlu bolak-balik ke tujuan yang sama beberapa kali kalau
/// ada beberapa pengirim berbeda kirim ke tujuan yang sama. Bisa dicetak
/// jadi satu PDF daftar resi per tujuan.
class ReceivingByDestinationPage extends StatefulWidget {
  final DestinationModel destination;

  const ReceivingByDestinationPage({
    super.key,
    required this.destination,
  });

  @override
  State<ReceivingByDestinationPage> createState() =>
      _ReceivingByDestinationPageState();
}

class _ReceivingByDestinationPageState
    extends State<ReceivingByDestinationPage> {
  List<ReceivingModel> _receivings = [];
  final Map<String, String> _senderNameById = {};
  CompanyModel? _company;

  bool _isLoading = true;
  bool _isPrinting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final receivings = await DestinationService.getReceivingsByDestination(
        widget.destination.id,
      );

      // Resolve nama pengirim buat tiap sender_id yang belum ada di cache
      // -- dilakukan sekali per sender unik, bukan per resi, supaya tidak
      // spam request kalau banyak resi punya pengirim yang sama.
      final uniqueSenderIds = receivings.map((r) => r.senderId).toSet();

      for (final senderId in uniqueSenderIds) {
        if (_senderNameById.containsKey(senderId)) continue;

        final sender = await SenderService.getSenderById(senderId);
        _senderNameById[senderId] = sender?.name ?? '-';
      }

      _company ??= await CompanyService.getCompany();

      if (!mounted) return;

      setState(() {
        _receivings = receivings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _printPdf() async {
    setState(() => _isPrinting = true);

    try {
      final doc = await PdfTemplates.buildReceivingsByDestinationDocument(
        destinationName: widget.destination.name,
        destinationAddress: widget.destination.address,
        destinationPhone: widget.destination.phone,
        receivings: _receivings,
        senderNameById: _senderNameById,
        company: _company,
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'resi-tujuan-${widget.destination.name}.pdf',
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.destination.name,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'Semua resi ke tujuan ini',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: (_isLoading || _isPrinting || _receivings.isEmpty)
                ? null
                : _printPdf,
            icon: _isPrinting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded, color: AppColors.navy),
            tooltip: 'Cetak Daftar Resi',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _receivings.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: PrimaryButton(
                  label: 'Cetak Daftar Resi (${_receivings.length})',
                  loadingLabel: 'Membuat PDF...',
                  isLoading: _isPrinting,
                  icon: Icons.print_rounded,
                  onPressed: _printPdf,
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    if (_errorMessage != null) {
      return ErrorStateView(
        title: 'Gagal memuat resi',
        message: _errorMessage,
        onRetry: _load,
      );
    }

    if (_receivings.isEmpty) {
      return const ErrorStateView(
        icon: Icons.inbox_outlined,
        title: 'Belum ada resi',
        message: 'Belum ada resi yang menuju tujuan ini.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: _receivings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final receiving = _receivings[index];

        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receiving.receiptNumber,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pengirim: ${_senderNameById[receiving.senderId] ?? '-'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima
                    // vs Tujuan): baris "Penerima" (dulu receiverName
                    // manual) dihapus -- SELURUH halaman ini sudah
                    // dikelompokkan untuk 1 tujuan yang sama
                    // (widget.destination, judul di AppBar), jadi
                    // menampilkannya lagi per baris cuma redundan.
                    // Diganti info jumlah barang & status yang lebih
                    // berguna per baris.
                    Text(
                      '${receiving.totalQuantity} barang • ${receiving.status}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatRupiah(receiving.totalPrice),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
