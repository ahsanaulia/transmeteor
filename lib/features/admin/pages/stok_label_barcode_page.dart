import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pdf_templates.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/daftar_label_barcode_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/label_barcode_service.dart';

/// Halaman "Stok Label Barcode" (Section A -- Fitur Label Barcode, 21
/// Oktober 2026). Mengelola STOK kode blanko Code128 yang akan dicetak
/// & ditempel fisik ke barang, lalu diikat ke 1 baris `receiving_details`
/// lewat menu "Scan Label" (halaman lain, belum dibuat) saat barang
/// datang. Halaman ini sendiri TIDAK mengikat kode ke barang apa pun --
/// cuma mengelola stoknya: (1) generate kode baru + cetak sebagai PDF,
/// (2) cetak ulang kode yang sudah pernah digenerate (berdasarkan
/// rentang nomor urut internal), (3) lihat ringkasan sudah
/// dipakai/belum. Lihat `LabelBarcodeService` & `migrasi_label_barcode.sql`
/// untuk arsitektur lengkap.
class StokLabelBarcodePage extends ConsumerStatefulWidget {
  const StokLabelBarcodePage({super.key});

  @override
  ConsumerState<StokLabelBarcodePage> createState() =>
      _StokLabelBarcodePageState();
}

/// FITUR (21 Oktober 2026, permintaan user eksplisit): 2 mode cetak untuk
/// kode blanko Label Barcode -- "Nanti admin yang tentukan jangan
/// otomatis", jadi SELALU ditanyakan lewat dialog
/// (`_StokLabelBarcodePageState._choosePrintMode`), TIDAK PERNAH dipilih
/// otomatis berdasarkan platform (web/Android/dll).
enum _PrintMode {
  /// Roll label thermal (150x50mm, 1 label/halaman PDF) -- dicetak lewat
  /// aplikasi printer thermal di HP/Android (`Printing.sharePdf`, admin
  /// pilih aplikasi tujuan dari share sheet).
  thermal,

  /// Kertas A4 biasa, grid 5x10 = 50 label/lembar -- dicetak lewat
  /// printer biasa, SENGAJA pakai `Printing.layoutPdf` (bukan sharePdf)
  /// supaya di web/Chrome langsung membuka dialog cetak native browser.
  a4,
}

class _StokLabelBarcodePageState extends ConsumerState<StokLabelBarcodePage> {
  bool _isBusy = false;
  String? _busyMessage;

  int _belumDipakai = 0;
  int _terpakai = 0;
  int _maxSequenceNo = 0;
  bool _isLoadingSummary = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoadingSummary = true);

    try {
      final summary = await LabelBarcodeService.getStockSummary();
      if (!mounted) return;
      setState(() {
        _belumDipakai = summary.belumDipakai;
        _terpakai = summary.terpakai;
        _maxSequenceNo = summary.maxSequenceNo;
        _isLoadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingSummary = false);
      _showSnackBar('Gagal memuat ringkasan stok: $e', AppColors.red);
    }
  }

  // ============================================================
  // GENERATE KODE BARU
  // ============================================================

  Future<void> _generateNewCodes() async {
    final controller = TextEditingController(text: '100');

    final count = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Kode Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Berapa kode barcode baru yang ingin digenerate ke stok? '
              '(Maks. 5000 sekali generate.)',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Jumlah Kode',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.pop(context, parsed);
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (count == null || count <= 0) return;
    if (!mounted) return;

    // FITUR (21 Oktober 2026): mode cetak ditanyakan DULU (sebelum
    // generate) -- lihat doc comment `_PrintMode`.
    final mode = await _choosePrintMode();
    if (mode == null) return;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Generate $count kode baru...';
    });

    try {
      final employee = await ref.read(currentEmployeeProvider.future);

      final generated = await LabelBarcodeService.generateStock(
        count: count,
        createdBy: employee?.id,
      );

      if (!mounted) return;
      setState(() => _busyMessage = 'Menyiapkan PDF untuk dicetak...');

      await _printCodes(generated, mode);

      if (!mounted) return;
      _showSnackBar(
        '${generated.length} kode baru berhasil digenerate (nomor urut '
        '${generated.first.sequenceNo}-${generated.last.sequenceNo}).',
        AppColors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Gagal generate kode: $e', AppColors.red);
    } finally {
      if (mounted) setState(() => _isBusy = false);
      await _loadSummary();
    }
  }

  // ============================================================
  // CETAK ULANG (RENTANG NOMOR URUT)
  // ============================================================

  Future<void> _reprintRange() async {
    final fromController = TextEditingController();
    final toController = TextEditingController();

    final range = await showDialog<({int from, int to})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cetak Ulang dari Stok'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nomor urut internal tertinggi yang pernah digenerate saat '
              'ini: $_maxSequenceNo. Masukkan rentang nomor urut yang mau '
              'dicetak ulang.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: fromController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dari Nomor Urut',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: toController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sampai Nomor Urut',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final from = int.tryParse(fromController.text.trim());
              final to = int.tryParse(toController.text.trim());
              if (from == null || to == null || from > to) return;
              Navigator.pop(context, (from: from, to: to));
            },
            child: const Text('Cetak Ulang'),
          ),
        ],
      ),
    );

    if (range == null) return;
    if (!mounted) return;

    // FITUR (21 Oktober 2026): mode cetak ditanyakan DULU (sebelum
    // mengambil kode) -- lihat doc comment `_PrintMode`.
    final mode = await _choosePrintMode();
    if (mode == null) return;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Mengambil kode nomor urut ${range.from}-${range.to}...';
    });

    try {
      final codes = await LabelBarcodeService.getBySequenceRange(
        from: range.from,
        to: range.to,
      );

      if (codes.isEmpty) {
        if (!mounted) return;
        _showSnackBar(
          'Tidak ada kode di rentang nomor urut itu.',
          AppColors.orange,
        );
        return;
      }

      if (!mounted) return;
      setState(() => _busyMessage = 'Menyiapkan PDF untuk dicetak...');

      await _printCodes(codes, mode);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Gagal mengambil kode: $e', AppColors.red);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ============================================================
  // PILIH MODE CETAK (21 Oktober 2026, permintaan user eksplisit:
  // "Nanti admin yang tentukan jangan otomatis.") -- lihat doc comment
  // `_PrintMode`.
  // ============================================================

  Future<_PrintMode?> _choosePrintMode() {
    return showDialog<_PrintMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Mode Cetak'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PrintModeTile(
              icon: Icons.receipt_long_rounded,
              title: 'Cetak Thermal',
              subtitle: 'Roll label thermal (150 x 50mm per label) -- '
                  'dicetak lewat aplikasi printer thermal di HP/Android.',
              onTap: () => Navigator.pop(context, _PrintMode.thermal),
            ),
            const SizedBox(height: 10),
            _PrintModeTile(
              icon: Icons.print_rounded,
              title: 'Cetak Printer (A4)',
              subtitle: 'Kertas A4 biasa, 50 label/lembar (grid 5x10) -- '
                  'dicetak lewat printer biasa (mode web/Chrome).',
              onTap: () => Navigator.pop(context, _PrintMode.a4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PDF HELPER
  // ============================================================

  Future<void> _printCodes(
    List<DaftarLabelBarcodeModel> codes,
    _PrintMode mode,
  ) {
    return switch (mode) {
      _PrintMode.thermal => _printThermal(codes),
      _PrintMode.a4 => _printA4(codes),
    };
  }

  /// Mode "Cetak Thermal" -- SAMA PERSIS perilaku lama (sebelum ada
  /// pilihan mode): `Printing.sharePdf` membuka share sheet, admin pilih
  /// aplikasi printer thermal tujuan (biasanya aplikasi printer Android
  /// khusus). 1 halaman PDF = 1 label fisik (150x50mm) -- lihat doc
  /// comment `PdfTemplates.buildBarcodeStockSheet` soal kenapa ini sudah
  /// otomatis "pas" jumlahnya (tidak menggulung kosong) tanpa perlu
  /// pengaturan tambahan di sini.
  Future<void> _printThermal(List<DaftarLabelBarcodeModel> codes) async {
    final company = await ref.read(companyProvider.future);

    final doc = await PdfTemplates.buildBarcodeStockSheet(
      codes: codes,
      company: company,
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'label-barcode-thermal-${codes.first.sequenceNo}-${codes.last.sequenceNo}.pdf',
    );
  }

  /// Mode "Cetak Printer (A4)" -- SENGAJA pakai `Printing.layoutPdf`
  /// (BUKAN `sharePdf` seperti mode Thermal): di web/Chrome ini langsung
  /// membuka dialog cetak NATIVE browser (sesuai permintaan user: "Jika
  /// admin membukanya mode web chrome"), & di platform lain tetap jalan
  /// normal lewat preview cetak bawaan OS. Lihat
  /// `PdfTemplates.buildBarcodeStockSheetA4` untuk detail layout grid
  /// 5x10 & margin aman 10mm.
  Future<void> _printA4(List<DaftarLabelBarcodeModel> codes) async {
    final doc = await PdfTemplates.buildBarcodeStockSheetA4(codes: codes);
    final bytes = await doc.save();

    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name:
          'label-barcode-a4-${codes.first.sequenceNo}-${codes.last.sequenceNo}.pdf',
    );
  }

  void _showSnackBar(String message, Color color, {int durationSeconds = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: durationSeconds),
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
          'Stok Label Barcode',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const InfoBanner(
                  message:
                      'Kode di sini masih berupa BLANKO -- belum terikat ke '
                      'barang mana pun. Cetak, tempel fisik ke koli barang, '
                      'lalu ikat ke barangnya lewat menu "Scan Label" saat '
                      'barang datang.',
                ),
                const SizedBox(height: 16),
                _buildSummaryRow(),
                const SizedBox(height: 20),
                MenuActionCard(
                  icon: Icons.add_box_rounded,
                  title: 'Generate Kode Baru',
                  subtitle: 'Buat kode baru ke stok lalu cetak sebagai PDF',
                  accentColor: AppColors.violet,
                  dense: true,
                  onTap: _isBusy ? null : _generateNewCodes,
                ),
                const SizedBox(height: 10),
                MenuActionCard(
                  icon: Icons.print_rounded,
                  title: 'Cetak Ulang dari Stok',
                  subtitle:
                      'Cetak ulang kode yang sudah pernah digenerate '
                      '(berdasarkan rentang nomor urut)',
                  accentColor: AppColors.blue,
                  dense: true,
                  onTap: _isBusy ? null : _reprintRange,
                ),
              ],
            ),
            if (_isBusy)
              Container(
                color: Colors.black38,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.blue),
                        const SizedBox(height: 14),
                        Text(
                          _busyMessage ?? 'Memproses...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Belum Dipakai',
            value: _isLoadingSummary ? '...' : '$_belumDipakai',
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            label: 'Sudah Dipakai',
            value: _isLoadingSummary ? '...' : '$_terpakai',
            color: AppColors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            label: 'Nomor Urut\nTertinggi',
            value: _isLoadingSummary ? '...' : '$_maxSequenceNo',
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu baris pilihan di dialog "Pilih Mode Cetak" (lihat
/// `_StokLabelBarcodePageState._choosePrintMode`) -- widget kecil
/// terpisah murni supaya method dialog-nya tidak terlalu panjang.
class _PrintModeTile extends StatelessWidget {
  const _PrintModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fieldFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
    );
  }
}
