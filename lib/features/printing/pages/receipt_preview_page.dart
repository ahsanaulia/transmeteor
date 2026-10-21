import 'dart:io';

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
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

/// Preview resi lengkap sebelum dicetak -- 2 aksi: cetak langsung ke
/// printer thermal, atau bagikan sebagai PDF (misal dikirim ke admin
/// back office untuk diprint pakai printer biasa).
class ReceiptPreviewPage extends ConsumerStatefulWidget {
  final ReceivingModel receiving;
  final SenderModel? sender;
  final List<ReceivingDetailModel> items;

  const ReceiptPreviewPage({
    super.key,
    required this.receiving,
    required this.sender,
    required this.items,
  });

  @override
  ConsumerState<ReceiptPreviewPage> createState() =>
      _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends ConsumerState<ReceiptPreviewPage> {
  bool _isBusy = false;

  Future<bool> _ensurePrinterReady() async {
    final alreadyConnected = await ref
        .read(printerConnectionProvider.notifier)
        .ensureStillConnected();

    if (alreadyConnected) return true;

    if (!mounted) return false;

    return PrinterConnectSheet.show(context);
  }

  Future<void> _printToThermal() async {
    final ready = await _ensurePrinterReady();
    if (!ready || !mounted) return;

    setState(() => _isBusy = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      // Ambil data perusahaan (nama/alamat/telp) dari cache provider supaya
      // kop resi thermal ikut nama perusahaan yang di-set admin di menu
      // "Profil Perusahaan", bukan hardcoded "TRANS".
      final company = await ref.read(companyProvider.future);

      // Nama tipe harga (mis. "Perdus", "Pcs") digabung ke nama barang
      // di kolom "Barang" -- tidak ada kolom terpisah untuk tipe harga.
      final pricingTypes = await ref.read(pricingTypesProvider.future);
      final pricingTypeNameById = PdfTemplates.pricingTypeNameMap(pricingTypes);

      final bytes = await PrintTemplates.buildReceiptBytes(
        receiving: widget.receiving,
        sender: widget.sender,
        items: widget.items,
        company: company,
        pricingTypeNameById: pricingTypeNameById,
      );

      final success = await PrinterService.printBytes(bytes);

      if (!success) {
        throw Exception('Printer tidak merespon.');
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Resi selesai dicetak.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mencetak resi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _sharePdf() async {
    setState(() => _isBusy = true);

    try {
      final company = await ref.read(companyProvider.future);

      final pricingTypes = await ref.read(pricingTypesProvider.future);
      final pricingTypeNameById = PdfTemplates.pricingTypeNameMap(pricingTypes);

      final doc = await PdfTemplates.buildReceiptDocument(
        receiving: widget.receiving,
        sender: widget.sender,
        items: widget.items,
        company: company,
        pricingTypeNameById: pricingTypeNameById,
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'resi-${widget.receiving.receiptNumber}.pdf',
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

  // ============================================================
  // KIRIM VIA WHATSAPP (23 September 2026, disederhanakan 5 Oktober 2026)
  // ============================================================
  //
  // FIX (5 Oktober 2026 -- permintaan user eksplisit): sebelumnya tombol
  // "Kirim via WhatsApp" buka bottom sheet yang MENANYAKAN dulu mau
  // kirim ke nomor siapa (Pengirim/Penerima), dan salah satu jalurnya
  // (`_shareViaWhatsApp`, share sheet native) bikin WhatsApp SENDIRI
  // balik nanya "mau kirim ke kontak mana" kalau nomornya belum
  // tersimpan -- user: "ditanyakan nomor WA yang mau dishare... saya mau
  // otomatis membuka aplikasi WA dan nomornya otomatis ambil dari
  // destinations". Sekarang disederhanakan jadi SATU jalur saja: tombol
  // langsung buka `wa.me/<nomor Tujuan>` (nomor Tujuan sekarang live dari
  // tabel `destinations`, lihat `ReceivingModel.destinationPhone`) TANPA
  // dialog pilihan apa pun -- staff tidak perlu memilih apa-apa lagi.
  //
  // `_openWhatsAppLink` (di bawah) TETAP dipakai sebagai mekanisme inti
  // (buka `wa.me` dengan teks resi sudah terisi) -- yang dihapus HANYA
  // bottom sheet pilihan & jalur share-sheet native (`_shareViaWhatsApp`,
  // yang butuh kontak sudah tersimpan & masih bisa nanya balik ke staff).
  // Kirim ke Pengirim TETAP bisa lewat tombol kecil terpisah
  // (`_sendWhatsAppToSender`, di action bar) -- sama-sama auto-buka,
  // tidak ada dialog, cuma dipisah tombolnya karena tujuannya beda orang.
  //
  // Keterbatasan `wa.me` TIDAK berubah (bukan sesuatu yang bisa diakali
  // dari sisi aplikasi): cuma bisa bawa teks, TIDAK bisa sekaligus attach
  // foto -- kalau resi ada foto barang tanpa label, staff tetap perlu
  // tombol terpisah "Lanjut Kirim Foto" (`_shareFotoSaja`) SETELAH teks
  // terkirim.

  /// Tombol utama "Kirim via WhatsApp" -- langsung buka WA ke nomor
  /// Tujuan (live dari `destinations`), TANPA bertanya apa pun ke staff.
  Future<void> _sendWhatsAppToDestination() async {
    final phone = widget.receiving.destinationPhone;

    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nomor HP Tujuan belum ada di data tujuan ini -- isi dulu di '
            'menu "Kelola Daftar Tujuan" supaya bisa kirim WA otomatis.',
          ),
        ),
      );
      return;
    }

    await _openWhatsAppLink(phone);
  }

  /// Tombol kecil terpisah "Kirim ke Pengirim" -- sama-sama auto-buka WA
  /// (tidak ada dialog), cuma targetnya nomor Pengirim, bukan Tujuan.
  Future<void> _sendWhatsAppToSender() async {
    final phone = widget.sender?.phone;

    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor HP Pengirim belum ada.')),
      );
      return;
    }

    await _openWhatsAppLink(phone);
  }

  /// Buka `wa.me/<nomor>` langsung ke chat nomor itu dengan teks resi
  /// sudah terisi di kotak ketik WhatsApp (staff masih harus tap Send
  /// sendiri, link `wa.me` tidak bisa auto-kirim -- keterbatasan WhatsApp
  /// sendiri). TIDAK bisa sekaligus bawa lampiran foto -- keterbatasan
  /// link `wa.me` itu sendiri, bukan bug. Kalau resi ini ada foto barang
  /// tanpa label, staff bisa lanjut pakai tombol "Lanjut Kirim Foto"
  /// (`_shareFotoSaja`) di action bar SETELAH yakin teks sudah terkirim.
  Future<void> _openWhatsAppLink(String phone) async {
    final normalized = _normalizePhoneForWa(phone);

    if (normalized == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nomor HP "$phone" tidak valid untuk WhatsApp.')),
      );
      return;
    }

    // Data perusahaan dibutuhkan buat footer teks WA (nama/alamat/HP
    // perusahaan, permintaan user 6 Oktober 2026) -- diambil di sini
    // (bukan di `_buildWhatsAppMessage` langsung) supaya method itu
    // tetap sinkron (tidak perlu `async`) dan dipanggil cuma sekali per
    // kirim. Gagal load TIDAK membatalkan kirim WA -- teks tetap
    // terkirim tanpa footer perusahaan kalau datanya kebetulan tidak
    // bisa diambil.
    CompanyModel? company;
    try {
      company = await ref.read(companyProvider.future);
    } catch (_) {
      company = null;
    }

    if (!mounted) return;

    final text = _buildWhatsAppMessage(company);
    final uri = Uri.parse('https://wa.me/$normalized?text=${Uri.encodeComponent(text)}');

    final messenger = ScaffoldMessenger.of(context);

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('WhatsApp tidak bisa dibuka.');

      if (!mounted) return;
      final hasPhoto = widget.items.any(
        (item) => item.photoUrl != null && item.photoUrl!.isNotEmpty,
      );
      if (hasPhoto) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Chat WA terbuka -- tap Send di WhatsApp untuk kirim '
              'teksnya. Resi ini ada foto barang; setelah teks terkirim, '
              'balik ke sini & pakai tombol "Lanjut Kirim Foto".',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal membuka WhatsApp: $e')),
      );
    }
  }

  /// Susulan dari `_openWhatsAppLink` -- share foto barang "Tanpa Label
  /// QR" resi ini SAJA (tanpa teks) lewat share sheet native. Staff
  /// pilih WhatsApp lalu pilih chat yang sama dengan yang baru dibuka
  /// lewat link (begitu sebuah chat pernah dikirimi pesan, WhatsApp
  /// biasanya memunculkannya di daftar "recent" share sheet -- jadi
  /// tidak perlu kontak itu tersimpan juga). SENGAJA tombol terpisah &
  /// manual (bukan otomatis dirantai setelah `_openWhatsAppLink`) supaya
  /// staff yang kontrol waktu -- perilaku "recent" WhatsApp tidak
  /// didokumentasikan resmi, jadi lebih aman staff pastikan dulu teksnya
  /// sudah benar-benar terkirim sebelum lanjut kirim foto.
  Future<void> _shareFotoSaja() async {
    setState(() => _isBusy = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final files = await _collectUnlabeledPhotoFiles();

      if (files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tidak ada foto barang tanpa label di resi ini.'),
          ),
        );
        return;
      }

      await SharePlus.instance.share(ShareParams(files: files));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal membuka share foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Kumpulkan + download semua foto barang "Tanpa Label QR" resi ini ke
  /// file temp lokal -- dipakai `_shareFotoSaja` (susulan setelah teks
  /// resi terkirim lewat `_openWhatsAppLink`, karena `wa.me` tidak bisa
  /// sekaligus bawa lampiran foto).
  Future<List<XFile>> _collectUnlabeledPhotoFiles() async {
    // toSet() dulu supaya kalau beberapa baris barang kebetulan share
    // foto yang sama persis tidak dikirim dobel.
    final photoUrls = widget.items
        .map((item) => item.photoUrl)
        .whereType<String>()
        .toSet()
        .toList();

    final files = <XFile>[];
    for (final url in photoUrls) {
      final file = await _downloadToTempFile(url);
      if (file != null) files.add(file);
    }
    return files;
  }

  /// Ubah nomor HP format lokal (mis. "08123456789", "0812-3456-789")
  /// jadi format internasional tanpa simbol yang dibutuhkan link wa.me
  /// (mis. "628123456789"). Return null kalau setelah dibersihkan nomor
  /// terlalu pendek untuk valid (kemungkinan data nomor memang rusak).
  String? _normalizePhoneForWa(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    } else if (!digits.startsWith('62')) {
      // Nomor tanpa awalan 0 atau 62 -- asumsikan sudah kode negara lain
      // yang memang ditulis manual, biarkan apa adanya.
    }

    if (digits.length < 8) return null;

    return digits;
  }

  // FIX (6 Oktober 2026 lanjutan, permintaan user):
  // 1. Baris "Tanggal" sekarang ikut menampilkan JAM terima barang
  //    (`formatTimeId`, lihat `core/utils/formatters.dart`) tepat
  //    setelah tanggalnya -- sebelumnya cuma tanggal tanpa jam.
  // 2. Ditambahkan footer identitas perusahaan pengirim jasa (nama,
  //    alamat, No. HP -- dari `CompanyModel`/menu "Profil Perusahaan")
  //    di BAGIAN BAWAH teks, setelah kalimat penutup. Baris yang
  //    datanya kosong/belum diisi admin otomatis dilewati (bukan
  //    ditampilkan sebagai "-").
  String _buildWhatsAppMessage(CompanyModel? company) {
    // FITUR (8 Oktober 2026 -- poin 7: "pada semua cetakan printout
    // dibelakang nomor resi tambahkan nomor buku jika ada") -- nomor buku
    // SENGAJA ditulis menyatu di baris "No. Resi" (bukan baris sendiri),
    // supaya konsisten dengan permintaan "di belakang nomor resi". Kosong
    // kalau `nomorBuku` null/kosong.
    final nomorBuku = widget.receiving.nomorBuku;
    final hasNomorBuku = nomorBuku != null && nomorBuku.isNotEmpty;
    final noResiLine = hasNomorBuku
        ? '${widget.receiving.receiptNumber} / $nomorBuku'
        : widget.receiving.receiptNumber;

    final buffer = StringBuffer()
      ..writeln('*Resi Penerimaan Barang*')
      ..writeln('No. Resi : $noResiLine')
      ..writeln(
        'Tanggal  : ${formatDateId(widget.receiving.receivedAt)}, '
        'pukul ${formatTimeId(widget.receiving.receivedAt)}',
      )
      ..writeln('Pengirim : ${widget.sender?.name ?? '-'}')
      ..writeln('Tujuan   : ${widget.receiving.destination}');

    if (widget.receiving.destinationAddress != null &&
        widget.receiving.destinationAddress!.isNotEmpty) {
      buffer.writeln('Alamat   : ${widget.receiving.destinationAddress}');
    }

    buffer.writeln();
    buffer.writeln('Daftar Barang:');

    for (final item in widget.items) {
      final qty = item.quantity == item.quantity.roundToDouble()
          ? item.quantity.toStringAsFixed(0)
          : item.quantity.toString();
      buffer.writeln('- ${item.itemName} ($qty ${item.quantityUnit})');
    }

    buffer.writeln();
    buffer.writeln('Terima kasih sudah menggunakan jasa kami.');

    final companyName = company?.name;
    final companyAddress = company?.address;
    final companyPhone = company?.phone;
    // FITUR (8 Oktober 2026 -- permintaan user eksplisit "Tambahkan link
    // tersebut di WA"): link publik website "Cek Resi" (`company_public_url`,
    // lihat `CompanyProfilePage`) disisipkan di footer WA supaya
    // customer bisa langsung klik untuk melacak kirimannya sendiri.
    // Disimpan sebagai kolom DB (bukan hardcode) supaya host bisa
    // berubah tanpa perlu build ulang app -- lihat catatan panjang di
    // `CompanyModel.companyPublicUrl`.
    //
    // **DIGANTI NAMA (13 Oktober 2026)** dari `company_track`/
    // `companyTrack` -- field & isinya SAMA (link publik cek resi),
    // cuma SEKARANG menunjuk ke WEBSITE TERPISAH (bukan halaman
    // embedded di app ini lagi) -- lihat doc comment
    // `CompanyModel.companyPublicUrl`.
    final companyPublicUrl = company?.companyPublicUrl;
    final hasCompanyPublicUrl =
        companyPublicUrl != null && companyPublicUrl.isNotEmpty;
    final hasCompanyInfo = (companyName != null && companyName.isNotEmpty) ||
        (companyAddress != null && companyAddress.isNotEmpty) ||
        (companyPhone != null && companyPhone.isNotEmpty) ||
        hasCompanyPublicUrl;

    if (hasCompanyInfo) {
      buffer.writeln();
      if (companyName != null && companyName.isNotEmpty) {
        buffer.writeln(companyName);
      }
      if (companyAddress != null && companyAddress.isNotEmpty) {
        buffer.writeln(companyAddress);
      }
      if (companyPhone != null && companyPhone.isNotEmpty) {
        buffer.writeln('Hp. $companyPhone');
      }
      if (hasCompanyPublicUrl) {
        buffer.writeln();
        buffer.writeln('Lacak kiriman Anda di:');
        // FITUR (21 Oktober 2026, permintaan user eksplisit: "{url}/{no
        // resi} dan browser membuka langsung tanpa memasukkan nomor
        // resinya") -- nomor resi disisipkan sebagai path di belakang
        // `company_public_url`, dibaca otomatis oleh website "Cek Resi"
        // (lihat `app.js::tryAutoSearchFromUrl` di cek-resi-web.zip --
        // WAJIB redeploy dengan file `_redirects` baru supaya path ini
        // tidak 404 di Netlify). Trailing slash di URL dibuang dulu
        // (kalau admin mengisinya dengan "/" di akhir) supaya tidak
        // jadi "//" dobel.
        final baseUrl = companyPublicUrl!.endsWith('/')
            ? companyPublicUrl.substring(0, companyPublicUrl.length - 1)
            : companyPublicUrl;
        buffer.writeln(
          '$baseUrl/${Uri.encodeComponent(widget.receiving.receiptNumber)}',
        );
      }
    }

    return buffer.toString();
  }

  /// Download foto barang dari Supabase Storage (public URL) ke file
  /// temp lokal -- `share_plus` butuh path file lokal (XFile), tidak
  /// bisa langsung kasih URL jaringan. Pakai `dart:io` HttpClient bawaan
  /// (bukan tambah dependency `http` baru) supaya minimal perubahan.
  Future<XFile?> _downloadToTempFile(String url) async {
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      httpClient.close();

      final tempDir = await Directory.systemTemp.createTemp('trans_wa_');
      final ext = url.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final file = File('${tempDir.path}/foto_barang_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes);

      return XFile(file.path);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // company di-watch (bukan read) supaya kartu preview otomatis ikut
    // update kalau admin baru saja mengubah Profil Perusahaan.
    final companyAsync = ref.watch(companyProvider);
    final company = companyAsync.value;

    // Map id tipe harga -> nama, dipakai buat gabungkan ke nama barang
    // di kolom "Barang" (lihat PdfTemplates.itemDisplayLabel).
    final pricingTypesAsync = ref.watch(pricingTypesProvider);
    final pricingTypeNameById = PdfTemplates.pricingTypeNameMap(
      pricingTypesAsync.value ?? const [],
    );

    final totalQuantity = widget.items.fold<double>(
      0,
      (sum, item) => sum + item.quantity,
    );

    // "Harga" & "Total" SENGAJA TIDAK ditampilkan di resi (permintaan
    // user, 3 Oktober 2026) -- resi penerimaan ini dilihat/dipegang
    // pihak luar (pengirim/tujuan), harga per barang & totalnya adalah
    // info internal yang tidak perlu mereka lihat. Berlaku SAMA di
    // preview ini, PDF (`PdfTemplates.buildReceiptDocument`), dan cetak
    // thermal (`PrintTemplates.buildReceiptBytes`) -- 3 tempat itu harus
    // selalu konsisten (apa yang di-preview = apa yang tercetak/
    // dibagikan). Harga TETAP tersimpan & bisa diedit seperti biasa di
    // halaman input barang (`ReceivingItemsPage`) -- cuma TIDAK
    // ditampilkan di dokumen resi ini.

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Preview Resi',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 140),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Header: nama perusahaan (fallback 'TRANS' kalau data
                  // company belum ke-load / belum diisi admin).
                  Text(
                    company?.name ?? 'TRANS',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  // Sub header 1: alamat perusahaan (tampil kalau diisi).
                  if (company?.address != null && company!.address!.isNotEmpty)
                    Text(
                      company.address!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  // Sub header 2: nomor telepon perusahaan (tampil kalau diisi).
                  if (company?.phone != null && company!.phone!.isNotEmpty)
                    Text(
                      'Hp. ${company.phone}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'RESI PENERIMAAN BARANG',
                    style: TextStyle(fontSize: 11, letterSpacing: 0.5),
                  ),
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // FITUR (8 Oktober 2026 -- poin 7): nomor buku
                          // disisipkan di belakang nomor resi kalau ada.
                          (widget.receiving.nomorBuku != null &&
                                  widget.receiving.nomorBuku!.isNotEmpty)
                              ? 'No. Resi : ${widget.receiving.receiptNumber} / ${widget.receiving.nomorBuku}'
                              : 'No. Resi : ${widget.receiving.receiptNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text('Tanggal  : ${formatDateId(widget.receiving.receivedAt)}'),
                        Text('Pengirim : ${widget.sender?.name ?? '-'}'),
                        // NOTE (22 Sep 2026 -- perbaikan ambiguitas
                        // Penerima vs Tujuan): baris "Penerima" terpisah
                        // (dulu receiverName manual) dihapus -- sudah
                        // diwakili "Tujuan" di bawah. "No. HP" sekarang
                        // dari destinationPhone (snapshot data Tujuan).
                        Text('Tujuan   : ${widget.receiving.destination}'),
                        if (widget.receiving.destinationAddress != null)
                          Text(
                            'Alamat   : ${widget.receiving.destinationAddress}',
                          ),
                        if (widget.receiving.destinationPhone != null &&
                            widget.receiving.destinationPhone!.isNotEmpty)
                          Text('No. HP   : ${widget.receiving.destinationPhone}'),
                        if (widget.receiving.route != null)
                          Text('Rute     : ${widget.receiving.route}'),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  for (final item in widget.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              PdfTemplates.itemDisplayLabel(
                                item.itemName,
                                item.pricingTypeId,
                                pricingTypeNameById,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item.quantity == item.quantity.roundToDouble()
                                  ? '${item.quantity.toStringAsFixed(0)} ${item.quantityUnit}'
                                  : '${item.quantity} ${item.quantityUnit}',
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total (${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity} pcs)',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  QrImageView(
                    data: widget.receiving.receiptNumber,
                    version: QrVersions.auto,
                    size: 140,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  Widget _buildActionBar() {
    // Tombol "Lanjut Kirim Foto" (fallback link wa.me, lanjutan 23
    // September 2026) HANYA relevan kalau resi ini memang ada foto
    // barang tanpa label -- kalau tidak ada foto sama sekali, tombol
    // "Kirim via WhatsApp" biasa sudah cukup (tidak perlu langkah
    // susulan apa pun), jadi tombol ini disembunyikan.
    final hasUnlabeledPhotos = widget.items.any(
      (item) => item.photoUrl != null && item.photoUrl!.isNotEmpty,
    );

    // Tombol kecil "Kirim ke Pengirim" (fix 5 Oktober 2026) HANYA
    // ditampilkan kalau nomor Pengirim memang ada -- kirim ke Tujuan
    // (tombol utama) sudah cukup untuk kasus sehari-hari.
    final hasSenderPhone =
        widget.sender?.phone != null && widget.sender!.phone!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _isBusy ? null : _sendWhatsAppToDestination,
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Kirim via WhatsApp'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.green,
                side: const BorderSide(color: AppColors.green),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
          if (hasSenderPhone) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: TextButton.icon(
                onPressed: _isBusy ? null : _sendWhatsAppToSender,
                icon: const Icon(Icons.call_made_rounded, size: 16),
                label: const Text(
                  'Kirim ke Pengirim juga',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
            ),
          ],
          if (hasUnlabeledPhotos) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: TextButton.icon(
                onPressed: _isBusy ? null : _shareFotoSaja,
                icon: const Icon(Icons.photo_outlined, size: 18),
                label: const Text(
                  'Lanjut Kirim Foto (setelah teks via link terkirim)',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
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
        ],
      ),
    );
  }
}