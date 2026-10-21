import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/utils/scan_feedback.dart';
import '../../../core/utils/unit_code.dart';
import '../../../models/shipment_model.dart';
import '../../../providers/driver_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/label_barcode_service.dart';
import '../../../services/receiving_service.dart';
import '../../../services/shipment_service.dart';

/// Mode turun barang -- FIX (6 Oktober 2026 lanjutan, permintaan user
/// eksplisit, mirror perubahan di `LoadingScanPage`): "a. Label QR b.
/// Non Label QR" -- 2 pilihan setingkat, bukan lagi ikon kecil/banner
/// sekadar tambahan. [labelQr] = alur SUDAH ADA (scan kamera, tidak
/// diubah). [nonLabelQr] = checklist (centang banyak sekaligus) barang
/// resi ini yang turun dari kendaraan, submit sekali -- halaman ini
/// SUDAH per-resi (dipilih dari manifest di `DeliveryManifestPage`
/// sebelum masuk ke sini), jadi mode ini tidak perlu minta no resi lagi.
// FITUR (21 Oktober 2026 -- Section A, "Label Barcode"): [barcode]
// ditambahkan sebagai pilihan ke-3 setingkat (bukan sub-mode Label QR)
// -- jalur kamera juga, tapi membaca Code128 yang sudah diikat ke 1
// baris `receiving_details` lewat "Scan Label" (lihat
// `LabelBarcodeService`), BUKAN `item_code` langsung seperti [labelQr].
// Sama seperti [labelQr], WAJIB foto bukti dulu (lihat [_labelQrPhotoUrl]
// -- dipakai bersama oleh KEDUA mode kamera ini, karena keduanya
// jalur live-scan untuk resi yang sama; checklist [nonLabelQr] punya
// foto sendiri yang diambil saat submit).
enum _DeliveryMode { labelQr, nonLabelQr, barcode }

/// Scan barang turun, di-scope ke SATU resi. Kalau barang yang discan
/// ternyata milik resi lain, ditolak + warning merah -- supaya barang
/// antar-tujuan (dalam satu manifest yang punya banyak resi) tidak
/// tertukar saat diturunkan.
class DeliveryResiScanPage extends ConsumerStatefulWidget {
  final ShipmentModel shipment;
  final String receivingId;
  final String receiptNumber;
  final String destination;
  final String? destinationAddress;
  final int totalItems;

  const DeliveryResiScanPage({
    super.key,
    required this.shipment,
    required this.receivingId,
    required this.receiptNumber,
    required this.destination,
    this.destinationAddress,
    required this.totalItems,
  });

  @override
  ConsumerState<DeliveryResiScanPage> createState() => _DeliveryResiScanPageState();
}

class _DeliveryResiScanPageState extends ConsumerState<DeliveryResiScanPage> {
  final MobileScannerController _controller = MobileScannerController();

  bool _isProcessing = false;
  bool _isLocating = true;
  double? _latitude;
  double? _longitude;
  String? _lastFeedback;
  Color _lastFeedbackColor = AppColors.green;

  _DeliveryMode _mode = _DeliveryMode.labelQr;

  // FITUR (21 Oktober 2026 -- Section E, permintaan user eksplisit: "Semua
  // resi/barang harus difoto saat turun ... termasuk apakah barcode").
  // SEBELUMNYA tab "Label QR" (scan kamera) TIDAK PERNAH memfoto sama
  // sekali -- `url_foto_selesai` selalu null untuk jalur ini (keputusan 10
  // Oktober 2026, SEKARANG DIBALIK). Pendekatan yang DIKONFIRMASI user
  // (AskUserQuestion, "Opsi 1"): 1 foto diambil & diupload SEKALI di AWAL,
  // SEBELUM sopir mulai scan resi ini -- halaman ini SUDAH scoped ke 1
  // resi (dipilih dari manifest SEBELUM masuk ke sini), jadi "sampai
  // pindah resi lain" otomatis terpenuhi lewat lifecycle widget ini (buka
  // resi lain = instance State baru = `_labelQrPhotoUrl` balik null).
  // `_onDetect` MENOLAK scan sama sekali kalau foto ini belum ada (lihat
  // guard di awal method itu) -- bukan cuma disembunyikan di UI.
  String? _labelQrPhotoUrl;
  bool _isUploadingLabelQrPhoto = false;

  // State checklist tab "Tanpa Label QR".
  final Set<String> _checkedNonLabelItemIds = {};
  bool _isSubmittingNonLabel = false;

  // Foto bukti penyelesaian manual (WAJIB diambil sebelum submit checklist
  // -- permintaan user eksplisit 10 Oktober 2026: "Penyelesaian resi
  // barang tanpa label harus memfoto: dan mengirim fotonya ke supabase").
  // SATU foto per batch submit (bukan per barang) -- cukup sebagai bukti
  // kondisi fisik saat itu, lalu URL-nya dipakai sama untuk SEMUA baris
  // shipment_scans yang dibuat batch itu (lihat _submitCheckedNonLabelItems).
  XFile? _nonLabelPhoto;
  bool _isUploadingNonLabelPhoto = false;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Lokasi diambil sekali saat halaman dibuka -- karena tiap titik turun
  /// beda lokasi fisik (beda dari tracking 15-menitan perjalanan).
  Future<void> _captureLocation() async {
    final position = await LocationHelper.getCurrentPosition(context);

    if (!mounted) return;

    setState(() {
      _latitude = position?.latitude;
      _longitude = position?.longitude;
      _isLocating = false;
    });
  }

  // ============================================================
  // FOTO AWAL TAB "LABEL QR" (21 Oktober 2026 -- Section E, lihat doc
  // comment [_labelQrPhotoUrl])
  // ============================================================

  /// Ambil 1 foto & upload LANGSUNG ke Supabase (beda dari
  /// `_pickNonLabelPhoto` yang menunda upload sampai submit batch -- tab
  /// ini tidak punya langkah "submit", tiap deteksi kamera langsung
  /// tercatat, jadi URL foto harus SUDAH SIAP sebelum scan pertama boleh
  /// jalan). Kompresi sama seperti foto checklist manual (maxWidth/
  /// maxHeight 800px, kualitas 50%) -- lihat doc comment
  /// `_pickNonLabelPhoto` untuk alasannya.
  Future<void> _pickLabelQrPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (photo == null || !mounted) return;

    setState(() => _isUploadingLabelQrPhoto = true);

    try {
      final bytes = await photo.readAsBytes();
      final url = await ShipmentService.uploadDeliveryCompletionPhoto(
        shipmentId: widget.shipment.id,
        bytes: bytes,
      );

      if (!mounted) return;
      setState(() {
        _labelQrPhotoUrl = url;
        _isUploadingLabelQrPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingLabelQrPhoto = false);
      ScanFeedback.playFailure();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengunggah foto: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  // ============================================================
  // SCAN HANDLER (Label QR)
  // ============================================================

  Future<void> _onDetect(BarcodeCapture capture) async {
    // FITUR (21 Oktober 2026 -- Section E): wajib ada foto bukti resi ini
    // dulu (lihat doc comment [_labelQrPhotoUrl]) sebelum scan APA PUN
    // dicatat -- bukan cuma UI yang disembunyikan, tapi benar-benar
    // ditolak di sini supaya tidak ada jalan pintas.
    if (_isProcessing || _isLocating || _labelQrPhotoUrl == null) return;

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

      if (detail.receivingId != widget.receivingId) {
        _showFeedback(
          'Barang ini BUKAN milik resi ${widget.receiptNumber} -- '
          'jangan diturunkan di sini! Cek resi yang benar supaya barang tidak tertukar.',
          AppColors.red,
        );
        return;
      }

      // Satu resi bisa dimuat terpecah ke beberapa kendaraan (mis. resi
      // 15 kubik bata ringan dimuat 2 truk 7,5 kubik masing-masing) --
      // jadi walau barang ini benar milik resi yang sama, belum tentu
      // fisiknya ada di KENDARAAN INI. Wajib dicek supaya tidak salah
      // catat "turun" di manifest truk yang sebenarnya tidak membawanya.
      final loadedHere = await ShipmentService.isUnitLoadedOnShipment(
        shipmentId: widget.shipment.id,
        unitCode: rawValue.trim(),
      );

      if (!loadedHere) {
        _showFeedback(
          'Barang ini TIDAK dimuat di kendaraan ${widget.shipment.shipmentNumber} -- '
          'resi ini kemungkinan terpecah ke kendaraan lain. Cari kendaraan yang '
          'benar-benar membawa barang ini sebelum dicatat turun.',
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
        scanType: 'DELIVER',
        latitude: _latitude,
        longitude: _longitude,
        // FITUR (21 Oktober 2026 -- Section E): foto awal resi ini (lihat
        // doc comment [_labelQrPhotoUrl]) dipakai sebagai bukti turun
        // untuk SETIAP unit yang discan di tab Label QR, SAMA seperti tab
        // checklist manual (`_deliverItem`) -- bedanya cuma momen
        // pengambilan fotonya (di awal, bukan di submit akhir).
        urlFotoSelesai: _labelQrPhotoUrl,
      );

      ref.invalidate(shipmentDeliverScansProvider(widget.shipment.id));

      _showFeedback(
        '${detail.itemName} berhasil dicatat turun.',
        AppColors.green,
        isSuccess: true,
      );
    } on DuplicateScanException catch (e) {
      _showFeedback(e.toString(), AppColors.orange);
    } catch (e) {
      _showFeedback('Gagal mencatat scan: $e', AppColors.red);
    } finally {
      // Sama seperti LoadingScanPage: jeda anti-double-scan dipangkas
      // dari 900ms -> 350ms supaya scan turun barang lebih responsif
      // (hasil uji coba lapangan).
      await Future.delayed(const Duration(milliseconds: 350));

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ============================================================
  // SCAN HANDLER (Scan Barcode -- Section A, 21 Oktober 2026)
  // ============================================================
  //
  // Mirip [_onDetect] (mode Label QR) tapi sumber kebenarannya BUKAN
  // `item_code` yang diparse langsung dari hasil scan -- kode Code128
  // di sini HARUS dicari dulu di `daftar_label_barcode` (lewat
  // [LabelBarcodeService.lookupByCode]) untuk tahu baris
  // `receiving_details` mana yang terikat ke kode itu (hasil ikatan
  // menu "Scan Label"). Guard resi/kendaraan SAMA PERSIS dengan
  // [_onDetect] supaya barang tidak tertukar antar resi/kendaraan.
  Future<void> _onDetectBarcode(BarcodeCapture capture) async {
    if (_isProcessing || _isLocating || _labelQrPhotoUrl == null) return;

    final rawValue =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    final code = rawValue.trim();

    setState(() {
      _isProcessing = true;
    });

    try {
      final stock = await LabelBarcodeService.lookupByCode(code);

      if (stock == null) {
        _showFeedback(
          'Kode "$code" tidak ditemukan di stok Label Barcode.',
          AppColors.red,
        );
        return;
      }

      if (!stock.isUsed || stock.receivingDetailId == null) {
        _showFeedback(
          'Kode "$code" belum diikat ke barang apa pun -- ikat dulu lewat '
          'menu "Scan Label" sebelum discan di sini.',
          AppColors.red,
        );
        return;
      }

      final detail =
          await ReceivingService.getReceivingDetailById(stock.receivingDetailId!);

      if (detail == null) {
        _showFeedback(
          'Barang untuk kode ini tidak ditemukan (mungkin sudah dihapus).',
          AppColors.red,
        );
        return;
      }

      if (detail.receivingId != widget.receivingId) {
        _showFeedback(
          'Barang ini BUKAN milik resi ${widget.receiptNumber} -- '
          'jangan diturunkan di sini! Cek resi yang benar supaya barang tidak tertukar.',
          AppColors.red,
        );
        return;
      }

      final loadedHere = await ShipmentService.isUnitLoadedOnShipment(
        shipmentId: widget.shipment.id,
        unitCode: code,
      );

      if (!loadedHere) {
        _showFeedback(
          'Barang ini TIDAK dimuat di kendaraan ${widget.shipment.shipmentNumber} -- '
          'resi ini kemungkinan terpecah ke kendaraan lain. Cari kendaraan yang '
          'benar-benar membawa barang ini sebelum dicatat turun.',
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
        unitCode: code,
        unitIndex: 1,
        scannedBy: employee.id,
        scanType: 'DELIVER',
        latitude: _latitude,
        longitude: _longitude,
        urlFotoSelesai: _labelQrPhotoUrl,
      );

      ref.invalidate(shipmentDeliverScansProvider(widget.shipment.id));

      _showFeedback(
        '${detail.itemName} berhasil dicatat turun.',
        AppColors.green,
        isSuccess: true,
      );
    } on DuplicateScanException catch (e) {
      _showFeedback(e.toString(), AppColors.orange);
    } catch (e) {
      _showFeedback('Gagal mencatat scan: $e', AppColors.red);
    } finally {
      await Future.delayed(const Duration(milliseconds: 350));

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // [isSuccess] menentukan bunyi yang diputar -- ding (sukses) atau
  // buzz (gagal/ditolak/salah resi).
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

  void _finishAndBack() {
    Navigator.of(context).pop();
  }

  // ============================================================
  // TAB "TANPA LABEL QR" -- checklist (6 Oktober 2026 lanjutan)
  // ============================================================
  //
  // **DIPERLUAS (10 Oktober 2026, permintaan user eksplisit)**:
  // SEBELUMNYA tab ini cuma menampilkan barang is_unlabeled (benar-benar
  // tidak punya QR). Sekarang menampilkan SEMUA barang resi ini yang
  // sudah dimuat di kendaraan ini & belum tercatat turun -- baik
  // berlabel QR maupun tidak (lihat
  // `ShipmentService.getAvailableItemsForManualDeliver`) -- supaya tab
  // ini juga bisa dipakai sebagai jalan keluar kalau kamera sopir
  // rusak atau label fisik rusak/tidak terbaca. Barang berlabel dengan
  // >1 unit dicatat per-unit lewat `item['remainingUnitCodes']`, SAMA
  // PERSIS pola `ManualLoadChecklistView._loadItem` di sisi Loading.
  //
  // **FOTO WAJIB (10 Oktober 2026, permintaan user eksplisit)**: "Dan
  // Penyelesaian resi barang tanpa label harus memfoto: dan mengirim
  // fotonya ke supabase. Jadi penyelesaian resi barang harus dilengkapi
  // url_foto_selesai." -- SATU foto per batch submit, diupload sekali ke
  // Supabase Storage lewat `ShipmentService.uploadDeliveryCompletionPhoto`,
  // lalu URL hasilnya ditulis ke KOLOM `url_foto_selesai` di SEMUA baris
  // shipment_scans yang dibuat batch itu. Kolom databasenya SENGAJA
  // dibuat boleh NULL (permintaan user: "tetapi boleh Null") -- scan lewat
  // kamera QR (`_onDetect` di atas) TIDAK PERNAH memfoto & TIDAK DIUBAH
  // sama sekali, jadi url_foto_selesai-nya selalu null untuk alur itu.

  /// Foto dikompres AGRESIF sebelum dikirim ke Supabase (permintaan user
  /// eksplisit, 10 Oktober 2026: "foto cukup pakai ukuran standar rendah
  /// saja. Yang penting terlihat jelas. Agar ukuran foto jpeg tidak
  /// sampai MB") -- dibatasi resolusinya (maxWidth/maxHeight 800px,
  /// mempertahankan rasio aslinya) DAN kualitas JPEG-nya diturunkan ke
  /// 50%. Kombinasi ini biasanya menghasilkan file jauh di bawah 1 MB
  /// (umumnya puluhan-ratusan KB) sambil tetap jelas terbaca sebagai
  /// bukti penyelesaian -- bukan foto produk detail yang butuh resolusi
  /// tinggi. Penting karena sopir sering kirim dari lokasi dengan sinyal
  /// seluler lemah.
  Future<void> _pickNonLabelPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (photo != null && mounted) {
      setState(() {
        _nonLabelPhoto = photo;
      });
    }
  }

  /// Catat 1 baris barang sebagai sudah turun -- memuat SEMUA unit fisik
  /// yang masih tersisa dari baris ini sekaligus (`item['remainingUnitCodes']`),
  /// mirror `ManualLoadChecklistView._loadItem` di sisi Loading. Barang
  /// tanpa label biasanya cuma 1 unit sintetis; barang berlabel dengan
  /// >1 box bisa beberapa unit_code sekaligus, masing-masing jadi baris
  /// shipment_scans DELIVER sendiri. [urlFotoSelesai] sama untuk semua
  /// unit baris ini (foto 1 batch). TIDAK menampilkan feedback UI
  /// sendiri -- pemanggil (submit checklist) yang mengelola ringkasan
  /// hasil & bunyi karena bisa dipanggil berkali-kali.
  Future<String?> _deliverItem(
    Map<String, dynamic> item,
    String urlFotoSelesai,
  ) async {
    final detailId = item['id'] as String;
    final remainingCodes =
        ((item['remainingUnitCodes'] as List?) ?? const []).cast<String>();

    if (remainingCodes.isEmpty) {
      return 'tidak ada unit tersisa untuk diturunkan (mungkin sudah tercatat semua)';
    }

    final employee = await ref.read(currentEmployeeProvider.future);
    if (employee == null) {
      return 'Data employee tidak ditemukan, tidak bisa mencatat.';
    }

    var successCount = 0;
    final errors = <String>[];

    for (final code in remainingCodes) {
      try {
        final parsed = UnitCodeParser.parse(code);

        await ShipmentService.recordScan(
          shipmentId: widget.shipment.id,
          receivingDetailId: detailId,
          unitCode: code,
          unitIndex: parsed.unitIndex,
          scannedBy: employee.id,
          scanType: 'DELIVER',
          notes: 'Manual: tanpa scan QR (checklist turun)',
          latitude: _latitude,
          longitude: _longitude,
          urlFotoSelesai: urlFotoSelesai,
        );

        successCount++;
      } on DuplicateScanException {
        errors.add('sudah tercatat turun (mungkin oleh staff lain)');
      } catch (e) {
        errors.add('gagal dicatat: $e');
      }
    }

    if (errors.isEmpty) return null;
    if (successCount == 0) return errors.first;
    return '$successCount unit berhasil, ${errors.length} unit gagal';
  }

  Future<void> _submitCheckedNonLabelItems(
    List<Map<String, dynamic>> allItems,
  ) async {
    final toSubmit = allItems
        .where((item) => _checkedNonLabelItemIds.contains(item['id']))
        .toList();

    if (toSubmit.isEmpty) return;

    final photo = _nonLabelPhoto;
    if (photo == null) {
      ScanFeedback.playFailure();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ambil foto bukti penyelesaian dulu sebelum submit.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmittingNonLabel = true;
      _isUploadingNonLabelPhoto = true;
    });

    String urlFotoSelesai;
    try {
      final bytes = await photo.readAsBytes();
      urlFotoSelesai = await ShipmentService.uploadDeliveryCompletionPhoto(
        shipmentId: widget.shipment.id,
        bytes: bytes,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmittingNonLabel = false;
          _isUploadingNonLabelPhoto = false;
        });
        ScanFeedback.playFailure();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengunggah foto: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isUploadingNonLabelPhoto = false);
    }

    var successCount = 0;
    final failures = <String>[];

    for (final item in toSubmit) {
      final itemName = item['item_name']?.toString() ?? 'Barang';
      final error = await _deliverItem(item, urlFotoSelesai);

      if (error == null) {
        successCount++;
      } else {
        failures.add('$itemName ($error)');
      }
    }

    ref.invalidate(shipmentDeliverScansProvider(widget.shipment.id));
    ref.invalidate(unlabeledItemsToDeliverProvider((
      shipmentId: widget.shipment.id,
      receivingId: widget.receivingId,
    )));

    if (successCount > 0) {
      ScanFeedback.playSuccess();
    } else {
      ScanFeedback.playFailure();
    }

    if (!mounted) return;

    setState(() {
      _isSubmittingNonLabel = false;
      _checkedNonLabelItemIds.clear();
      // Foto berlaku 1 batch saja -- batch berikutnya wajib foto baru.
      _nonLabelPhoto = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    if (failures.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$successCount barang berhasil dicatat turun.'),
          backgroundColor: AppColors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$successCount berhasil, ${failures.length} gagal: '
            '${failures.join(', ')}',
          ),
          backgroundColor: AppColors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final scansAsync = ref.watch(shipmentDeliverScansProvider(widget.shipment.id));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: Text(widget.receiptNumber),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildAddressBanner(),
          _buildModeToggle(),
          Expanded(
            child: switch (_mode) {
              _DeliveryMode.labelQr => _buildLabelQrBody(scansAsync),
              _DeliveryMode.barcode => _buildBarcodeBody(scansAsync),
              _DeliveryMode.nonLabelQr => _buildNonLabelBody(),
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _finishAndBack,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Selesai Resi Ini'),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.destination,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
          ),
          if (widget.destinationAddress != null && widget.destinationAddress!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.destinationAddress!,
                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  /// Pilihan eksplisit "a. Label QR / b. Non Label QR" (permintaan user,
  /// 6 Oktober 2026 lanjutan) -- resi sudah ditentukan dari manifest
  /// sebelum masuk ke halaman ini, jadi mode ini murni menentukan CARA
  /// penyelesaiannya (scan kamera vs centang manual).
  Widget _buildModeToggle() {
    return Container(
      width: double.infinity,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SegmentedButton<_DeliveryMode>(
        segments: const [
          ButtonSegment(
            value: _DeliveryMode.labelQr,
            label: Text('Label QR'),
            icon: Icon(Icons.qr_code_scanner_rounded),
          ),
          ButtonSegment(
            value: _DeliveryMode.barcode,
            label: Text('Scan Barcode'),
            icon: Icon(Icons.view_column_rounded),
          ),
          ButtonSegment(
            value: _DeliveryMode.nonLabelQr,
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
              if (_isLocating)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Mengambil lokasi titik turun...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_labelQrPhotoUrl == null)
                // FITUR (21 Oktober 2026 -- Section E): kamera DITUTUP
                // overlay ini sampai foto awal resi ini diambil -- lihat
                // doc comment [_labelQrPhotoUrl]/[_pickLabelQrPhoto].
                // `_onDetect` juga menolak scan sendiri (guard ganda),
                // overlay ini murni supaya sopir tidak bingung kenapa
                // kamera tidak merespons.
                Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Foto bukti resi ini wajib diambil dulu, '
                          'sebelum mulai scan barang.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isUploadingLabelQrPhoto ? null : _pickLabelQrPhoto,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                          icon: _isUploadingLabelQrPhoto
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            _isUploadingLabelQrPhoto
                                ? 'Mengunggah foto...'
                                : 'Ambil Foto Bukti',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
  // Mode C: Scan Barcode (Section A, 21 Oktober 2026) -- kamera juga,
  // tapi lewat [_onDetectBarcode]. Overlay foto wajib & scan feed SAMA
  // PERSIS dengan mode Label QR (lihat doc comment enum di atas) --
  // cuma bentuk kotak fokus kamera dibuat persegi panjang (bukan
  // persegi) supaya lebih pas untuk barcode linear Code128.
  // ------------------------------------------------------------

  Widget _buildBarcodeBody(AsyncValue<List<Map<String, dynamic>>> scansAsync) {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _onDetectBarcode),
              _buildBarcodeScanFrame(),
              if (_isLocating)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Mengambil lokasi titik turun...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_labelQrPhotoUrl == null)
                Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Foto bukti resi ini wajib diambil dulu, '
                          'sebelum mulai scan barang.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isUploadingLabelQrPhoto ? null : _pickLabelQrPhoto,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                          icon: _isUploadingLabelQrPhoto
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            _isUploadingLabelQrPhoto
                                ? 'Mengunggah foto...'
                                : 'Ambil Foto Bukti',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

  Widget _buildBarcodeScanFrame() {
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

  // ------------------------------------------------------------
  // Mode B: Tanpa Label QR (checklist -> submit)
  // ------------------------------------------------------------

  Widget _buildNonLabelBody() {
    final itemsAsync = ref.watch(
      unlabeledItemsToDeliverProvider((
        shipmentId: widget.shipment.id,
        receivingId: widget.receivingId,
      )),
    );

    return Container(
      color: AppColors.background,
      child: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tidak ada barang resi ini yang menunggu diturunkan '
                  'di kendaraan ini.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }

          final allChecked = items.every(
            (item) => _checkedNonLabelItemIds.contains(item['id']),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: CheckboxListTile(
                  value: allChecked,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _checkedNonLabelItemIds.addAll(
                          items.map((item) => item['id'] as String),
                        );
                      } else {
                        _checkedNonLabelItemIds.clear();
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text(
                    'Pilih Semua',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final id = item['id'] as String;
                    final itemName = item['item_name']?.toString() ?? '-';
                    final quantity = item['quantity'];
                    final quantityUnit = item['quantity_unit']?.toString() ?? '';
                    final isUnlabeled = item['is_unlabeled'] == true;
                    final remainingCount = item['remainingCount'] as int? ?? 1;
                    final totalUnitCount = item['totalUnitCount'] as int? ?? 1;
                    final checked = _checkedNonLabelItemIds.contains(id);

                    final subtitle = !isUnlabeled && remainingCount != totalUnitCount
                        ? 'Sisa $remainingCount dari $totalUnitCount unit • $quantity $quantityUnit'
                        : '$quantity $quantityUnit';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: checked
                              ? AppColors.green.withOpacity(0.5)
                              : AppColors.green.withOpacity(0.08),
                        ),
                      ),
                      child: CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _checkedNonLabelItemIds.add(id);
                            } else {
                              _checkedNonLabelItemIds.remove(id);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                itemName,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isUnlabeled ? AppColors.textSecondary : AppColors.blue)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isUnlabeled ? 'Tanpa Label' : 'Berlabel QR',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: isUnlabeled ? AppColors.textSecondary : AppColors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(subtitle),
                      ),
                    );
                  },
                ),
              ),
              _buildNonLabelPhotoCapture(),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _checkedNonLabelItemIds.isEmpty ||
                              _nonLabelPhoto == null ||
                              _isSubmittingNonLabel
                          ? null
                          : () => _submitCheckedNonLabelItems(items),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                      icon: _isSubmittingNonLabel
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
                        _isUploadingNonLabelPhoto
                            ? 'Mengunggah foto...'
                            : _checkedNonLabelItemIds.isEmpty
                                ? 'Pilih barang yang turun'
                                : _nonLabelPhoto == null
                                    ? 'Ambil foto bukti dulu'
                                    : 'Turunkan ${_checkedNonLabelItemIds.length} Barang Terpilih',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Gagal memuat daftar barang: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.red),
            ),
          ),
        ),
      ),
    );
  }

  /// Kartu foto bukti penyelesaian manual -- WAJIB diisi sebelum tombol
  /// submit checklist aktif (lihat validasi di `_submitCheckedNonLabelItems`
  /// & tombol disable di `_buildNonLabelBody`). Satu foto dipakai untuk
  /// SEMUA barang yang dicentang dalam 1 kali submit.
  Widget _buildNonLabelPhotoCapture() {
    final photo = _nonLabelPhoto;
    final photoBytesFuture = photo?.readAsBytes();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Foto Bukti Penyelesaian (wajib)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (photo != null && photoBytesFuture != null)
            FutureBuilder<Uint8List>(
              future: photoBytesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    snapshot.data!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          if (photo != null) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSubmittingNonLabel ? null : _pickNonLabelPhoto,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(photo != null ? 'Ambil Ulang Foto' : 'Ambil Foto Bukti'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orange,
                side: const BorderSide(color: AppColors.orange),
              ),
            ),
          ),
        ],
      ),
    );
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
        data: (allScans) {
          final scans = allScans.where((scan) {
            final detail = scan['receiving_details'] as Map?;
            return detail?['receiving_id'] == widget.receivingId;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded, size: 18, color: AppColors.green),
                    const SizedBox(width: 8),
                    Text(
                      '${scans.length}/${widget.totalItems} barang resi ini sudah turun',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: scans.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada barang resi ini yang discan turun.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: scans.length,
                        itemBuilder: (context, index) {
                          final scan = scans[index];
                          final detail = scan['receiving_details'] as Map?;

                          final itemName = detail?['item_name'] ?? scan['unit_code'];
                          final itemCode = detail?['item_code'] ?? scan['unit_code'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.green.withOpacity(0.08)),
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
                                        itemCode.toString(),
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
