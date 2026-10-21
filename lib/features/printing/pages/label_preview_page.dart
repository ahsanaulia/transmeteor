import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pdf_templates.dart';
import '../../../core/utils/print_templates.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/company_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/receiving_model.dart';
import '../../../models/sender_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/printer_provider.dart';
import '../../../services/printer_service.dart';
import '../widgets/printer_connect_sheet.dart';

class _LabelUnit {
  final ReceivingDetailModel item;
  final int unitIndex;
  final int unitTotal;
  final String qrCode;

  const _LabelUnit({
    required this.item,
    required this.unitIndex,
    required this.unitTotal,
    required this.qrCode,
  });
}

/// Preview semua label box sebelum benar-benar dicetak -- supaya staff
/// nggak kaget ada barang ke-print sebelum sempat dicek datanya bener.
/// Ada 2 aksi: cetak langsung ke printer thermal, atau bagikan sebagai
/// PDF (misal dikirim ke admin back office biar diprint pakai printer
/// biasa saat antrian barang lagi banyak).
class LabelPreviewPage extends ConsumerStatefulWidget {
  final ReceivingModel receiving;
  final List<ReceivingDetailModel> items;
  final SenderModel? sender;

  const LabelPreviewPage({
    super.key,
    required this.receiving,
    required this.items,
    this.sender,
  });

  @override
  ConsumerState<LabelPreviewPage> createState() => _LabelPreviewPageState();
}

class _LabelPreviewPageState extends ConsumerState<LabelPreviewPage> {
  bool _isBusy = false;

  List<_LabelUnit> get _units {
    final units = <_LabelUnit>[];

    for (final item in widget.items) {
      final unitTotal = item.quantity.round().clamp(1, 999);

      for (var unitIndex = 1; unitIndex <= unitTotal; unitIndex++) {
        units.add(
          _LabelUnit(
            item: item,
            unitIndex: unitIndex,
            unitTotal: unitTotal,
            qrCode: unitTotal > 1
                ? '${item.itemCode}-U$unitIndex'
                : item.itemCode,
          ),
        );
      }
    }

    return units;
  }

  Future<bool> _ensurePrinterReady() async {
    final alreadyConnected = await ref
        .read(printerConnectionProvider.notifier)
        .ensureStillConnected();

    if (alreadyConnected) return true;

    if (!mounted) return false;

    return PrinterConnectSheet.show(context);
  }

  // "1 resi = 1 halaman cetak" (perubahan hasil uji coba lapangan: dulu
  // tiap label dianggap 1 halaman sendiri-sendiri -> tiap ganti label di
  // tengah resi yang sama, printer nyisain jeda/area kosong sebelum
  // label berikutnya). Sekarang SEMUA unit label dalam satu resi digabung
  // jadi SATU byte stream & dikirim SEKALI ke printer -- kertas cuma
  // benar-benar dipotong (cut) di paling akhir, lihat parameter
  // `cutAfter` di PrintTemplates.buildItemLabelBytes.
  Future<void> _printToThermal() async {
    final units = _units;
    if (units.isEmpty) return;

    final ready = await _ensurePrinterReady();
    if (!ready || !mounted) return;

    setState(() => _isBusy = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final company = await ref.read(companyProvider.future);

      final combined = <int>[];
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        final isLastUnit = i == units.length - 1;

        combined.addAll(
          await PrintTemplates.buildItemLabelBytes(
            receiving: widget.receiving,
            item: unit.item,
            unitIndex: unit.unitIndex,
            unitTotal: unit.unitTotal,
            sender: widget.sender,
            company: company,
            cutAfter: isLastUnit,
          ),
        );
      }

      final success = await PrinterService.printBytes(combined);

      if (!success) {
        throw Exception('Printer tidak merespon saat mencetak label.');
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Label selesai dicetak.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mencetak label: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _sharePdf() async {
    setState(() => _isBusy = true);

    try {
      final company = await ref.read(companyProvider.future);

      final doc = await PdfTemplates.buildLabelSheet(
        receiving: widget.receiving,
        items: widget.items,
        company: company,
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'label-${widget.receiving.receiptNumber}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = _units;
    final companyAsync = ref.watch(companyProvider);
    final company = companyAsync.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Preview Label',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 140),
          itemCount: units.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildLabelCard(units[index], company),
          ),
        ),
      ),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  // Desain label baru (minimalis, tinggi label dikurangi hingga 50%):
  // hanya 4 baris + QR -- TIDAK ada lagi info pengirim, no resi terpisah,
  // "Box X/Y", alamat perusahaan, atau rute. Harus persis sinkron dengan
  // PdfTemplates._buildLabelBox() dan PrintTemplates.buildItemLabelBytes().
  Widget _buildLabelCard(_LabelUnit unit, CompanyModel? company) {
    final companyLine = [
      company?.name ?? 'TRANS',
      if (company?.phone != null && company!.phone!.isNotEmpty)
        company.phone!,
    ].join(' ');

    final destinationLine = [
      widget.receiving.destination,
      if (widget.receiving.destinationAddress != null &&
          widget.receiving.destinationAddress!.isNotEmpty)
        widget.receiving.destinationAddress!,
    ].join(' - ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // (1) Nama perusahaan + no. telepon (alamat TIDAK ditampilkan).
          Text(
            companyLine,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 4),
          // (2) Nama tujuan + alamat tujuan.
          Text(
            destinationLine,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const Divider(height: 20),
          // (3) Nama barang + status satuan/bundle.
          Text(
            PdfTemplates.labelItemStatusLine(unit.item),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 14),
          // (4) QR + caption kode.
          QrImageView(data: unit.qrCode, version: QrVersions.auto, size: 120),
          const SizedBox(height: 8),
          Text(
            unit.qrCode,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
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
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : _sharePdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Bagikan PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: 'Cetak ke Printer',
                loadingLabel: 'Mencetak...',
                isLoading: _isBusy,
                icon: Icons.print_rounded,
                onPressed: _printToThermal,
              ),
            ),
          ],
        ),
      ),
    );
  }

}