import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/company_model.dart';
import '../../models/pricing_type_model.dart';
import '../../models/receiving_detail_model.dart';
import '../../models/receiving_model.dart';
import '../../models/sender_model.dart';
import '../../models/shipment_model.dart';
import '../../models/vehicle_model.dart';
import 'formatters.dart';

/// Kumpulan fungsi yang menyusun dokumen PDF (buat "Bagikan PDF") --
/// isinya semirip mungkin sama yang dicetak ke printer thermal, cuma
/// dalam bentuk PDF A4/A5 biasa supaya bisa diprint pakai printer kantor
/// biasa di back office.
///
/// Layout resi & manifest mengikuti contoh formulir cetak fisik yang
/// dipakai perusahaan (kop nama+alamat perusahaan di kiri, judul dokumen
/// di kanan, field info pengiriman, tabel barang bergaris/berborder,
/// baris "Keterangan" + "Total" di bagian bawah).
class PdfTemplates {
  // ============================================================
  // KOP PERUSAHAAN
  // ============================================================
  //
  // NOTE: logo diambil dari URL publik (Supabase Storage).
  //
  // BUGFIX (16 Oktober 2026 -- laporan user: "logo tidak muncul di SEMUA
  // cetakan PDF", padahal logo yang SAMA tampil normal di halaman Profil
  // Perusahaan & Dashboard Supervisor (keduanya pakai `Image.network`)):
  // SEBELUMNYA fetch logo di sini pakai `HttpClient` dari `dart:io` --
  // package ini TIDAK ADA/TIDAK didukung di Flutter WEB (`dart:io` cuma
  // berisi stub kosong di web, `HttpClient()` melempar `UnsupportedError`
  // begitu dipanggil). Aplikasi ini di-deploy ke web (Netlify, lihat
  // Tambahan #40) -- jadi tiap kali generate PDF di build web,
  // `_fetchLogoBytes` SELALU gagal kena `UnsupportedError`, DITANGKAP
  // DIAM-DIAM oleh `catch (_) { return null; }` di bawah (supaya
  // kegagalan ambil logo tidak menggagalkan seluruh cetakan, lihat NOTE
  // di atas) -- efeknya logo SELALU kosong di semua dokumen PDF, TANPA
  // error apa pun yang kelihatan. `Image.network` (dipakai halaman lain)
  // TIDAK kena masalah ini karena Flutter Web mengimplementasikannya
  // lewat `fetch`/XHR browser, bukan `dart:io`.
  //
  // Diganti pakai `package:http` (`http.get`, sudah jadi dependency
  // proyek ini) -- package ini punya implementasi yang benar-benar
  // berjalan di SEMUA platform (web lewat `BrowserClient`/`fetch`, Android/
  // iOS/Desktop lewat `IOClient`/`dart:io` di baliknya), jadi fetch logo
  // untuk PDF sekarang konsisten dengan `Image.network` di tempat lain.
  static Future<Uint8List?> _fetchLogoBytes(String? logoUrl) async {
    if (logoUrl == null || logoUrl.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(logoUrl));

      if (response.statusCode != 200) return null;

      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // NAMA BARANG + TIPE HARGA
  // ============================================================
  //
  // Aturan tampilan (berlaku di SEMUA dokumen -- Resi PDF, Resi thermal,
  // Manifest): nama barang digabung langsung dengan nama tipe harganya
  // jadi SATU teks, mis. item "Air Mineral" dengan tipe harga "Perdus"
  // tampil sebagai "Air Mineral Perdus" di kolom "Nama Barang". Tipe
  // harga TIDAK PERNAH punya kolom sendiri di tabel manapun.
  //
  // Kalau nanti mau ubah urutannya (mis. tipe harga duluan baru nama),
  // atau mau kasih pemisah (mis. "Air Mineral - Perdus"), cukup ubah
  // fungsi `itemDisplayLabel` ini -- dipakai bersama oleh semua dokumen
  // PDF dan juga versi thermal (dipanggil dari `print_templates.dart`).

  /// Bikin lookup cepat id tipe harga -> nama, dari daftar
  /// `pricingTypesProvider`. Dipanggil sekali di pemanggil (halaman
  /// preview), hasilnya dioper ke fungsi build dokumen di bawah supaya
  /// tidak perlu query berulang per baris.
  static Map<String, String> pricingTypeNameMap(
    List<PricingTypeModel> pricingTypes,
  ) {
    return {for (final p in pricingTypes) p.id: p.name};
  }

  /// Gabungkan nama barang + nama tipe harga jadi satu label tampilan.
  /// Kalau tipe harganya tidak ketemu di map (mis. belum sempat ke-load),
  /// tetap fallback ke nama barang saja supaya tidak pernah kosong.
  static String itemDisplayLabel(
    String itemName,
    String? pricingTypeId,
    Map<String, String> pricingTypeNameById,
  ) {
    final pricingTypeName =
        pricingTypeId != null ? pricingTypeNameById[pricingTypeId] : null;

    if (pricingTypeName == null || pricingTypeName.isEmpty) return itemName;

    return '$itemName $pricingTypeName';
  }

  // ============================================================
  // STATUS SATUAN / BUNDLE DI LABEL
  // ============================================================
  //
  // Dipakai KHUSUS di Label (bukan Resi/Manifest) untuk baris "nama
  // barang + status" -- lihat ReceivingDetailModel.bundleQuantity untuk
  // definisi bundle. Dipakai bersama oleh label thermal
  // (print_templates.dart) dan label PDF (di bawah).

  /// Contoh hasil: "Ban Motor Batlax 1 ikat (isi 5)" (bundle) atau
  /// "Kardus Elektronik 1 pcs" (bukan bundle, satuan lepasan biasa).
  static String labelItemStatusLine(ReceivingDetailModel item) {
    final unit = item.quantityUnit.trim().isEmpty
        ? 'pcs'
        : item.quantityUnit.trim();
    final base = '${item.itemName} 1 $unit';

    if (item.isBundle) {
      return '$base (isi ${item.bundleQuantity})';
    }

    return base;
  }

  /// Baris kop: logo + nama/alamat/telepon perusahaan di kiri, judul
  /// dokumen (mis. "Manifes Barang") + nomor & tanggal di kanan --
  /// mengikuti contoh formulir cetak fisik.
  /// `scale` (DITAMBAHKAN 8 Oktober 2026, lanjutan lagi -- permintaan
  /// user eksplisit: "perkecil jarak antar baris dan kurangi besar huruf
  /// 20% pada cetakan output Tanda Terima Tujuan. Agar menghemat
  /// Kertas"): default 1.0 -- SEMUA dokumen lain yang pakai kop ini
  /// (Resi, Label, Manifest) TIDAK TERPENGARUH sama sekali. HANYA
  /// `buildDestinationReceiptDocument` yang memanggil dengan `scale: 0.8`
  /// lewat `_buildDestinationReceiptFullHeader` -- lihat catatan di sana.
  ///
  /// RIWAYAT `logoAboveName` (SEMPAT ditambahkan 16 Oktober 2026 siang --
  /// permintaan user "Pada Tanda terima tujuan. Tambahkan logo diatas
  /// nama perusahaan.", lalu DIBATALKAN LAGI 16 Oktober 2026 sore --
  /// permintaan user eksplisit: "Logo di Tanda Terima Tujuan jangan
  /// mengambil baris sendiri. Tetapi: Logo kiri dan kanannya Nama
  /// perusahaan/alamat/telepon"): parameter ini SUDAH DIHAPUS lagi --
  /// logo SEMUA dokumen (termasuk Tanda Terima Tujuan) SEKARANG SELALU
  /// di SAMPING (kiri) nama/alamat/telepon perusahaan, TIDAK PERNAH di
  /// ATAS/baris sendiri lagi.
  static pw.Widget _buildCompanyHeader({
    required CompanyModel? company,
    required Uint8List? logoBytes,
    required String documentTitle,
    required String documentNumber,
    required DateTime documentDate,
    double scale = 1.0,
  }) {
    final companyName = company?.name ?? 'TRANS';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null) ...[
          pw.Container(
            width: 46 * scale,
            height: 46 * scale,
            alignment: pw.Alignment.center,
            child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 10 * scale),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18 * scale),
              ),
              if (company?.address != null && company!.address!.isNotEmpty)
                pw.Text(company.address!, style: pw.TextStyle(fontSize: 9 * scale)),
              if (company?.phone != null && company!.phone!.isNotEmpty)
                pw.Text('Hp. ${company.phone}', style: pw.TextStyle(fontSize: 9 * scale)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              documentTitle,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14 * scale),
            ),
            pw.SizedBox(height: 3 * scale),
            pw.Text(documentNumber, style: pw.TextStyle(fontSize: 9 * scale)),
            pw.Text(formatDateId(documentDate), style: pw.TextStyle(fontSize: 9 * scale)),
          ],
        ),
      ],
    );
  }

  /// Baris info berlabel (mis. "Sopir", "Kepada", "Alamat") dengan titik
  /// dua sejajar -- mengikuti contoh formulir cetak fisik.
  ///
  /// `scale` (DITAMBAHKAN 8 Oktober 2026, lanjutan lagi -- lihat catatan
  /// `scale` di `_buildCompanyHeader`): default 1.0, dokumen lain tidak
  /// terpengaruh. Ikut mengecilkan jarak antar baris (`padding bottom`)
  /// & lebar kolom label, sebanding dengan pengecilan fontnya.
  static pw.Widget _buildInfoRow(String label, String value, {double scale = 1.0}) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 2 * scale),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 70 * scale,
            child: pw.Text(label, style: pw.TextStyle(fontSize: 10 * scale)),
          ),
          pw.Text(':  ', style: pw.TextStyle(fontSize: 10 * scale)),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '-' : value,
              style: pw.TextStyle(fontSize: 10 * scale),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LABEL BOX (STIKER THERMAL LANDSCAPE)
  // ============================================================
  //
  // NOTE: satu box/unit (atau satu BUNDLE, lihat catatan di
  // print_templates.dart::buildItemLabelBytes) = satu halaman/lembar
  // stiker, orientasi landscape (lebar > tinggi). Ukuran defaultnya
  // 150 x 50mm (P x T) -- tingginya SUDAH dipangkas ~50% dari versi
  // sebelumnya (dulu 100mm) mengikuti keputusan setelah uji coba
  // lapangan, karena isi label sekarang jauh lebih ringkas (lihat isi
  // di bawah). Semua ukuran font/spacing di sini proporsional (bukan
  // fixed px besar), supaya kalau dicetak di stiker beda ukuran isinya
  // masih pas & terbaca -- tinggal ganti [labelWidthMm]/[labelHeightMm].

  /// Lembar label PDF, 1 halaman per box/bundle. Isinya PERSIS sama
  /// dengan versi thermal (`PrintTemplates.buildItemLabelBytes`) --
  /// cuma 4 info + QR:
  ///   1) Nama perusahaan + No. WA (TANPA alamat)
  ///   2) Nama tujuan + alamat tujuan
  ///   3) Nama barang + status satuan/bundle
  ///   4) QR + kode di bawahnya
  /// Data pengirim, nomor resi terpisah, "Box X/Y", HP penerima, dan
  /// rute SENGAJA tidak dicetak lagi di label (masih lengkap di Resi).
  static Future<pw.Document> buildLabelSheet({
    required ReceivingModel receiving,
    required List<ReceivingDetailModel> items,
    CompanyModel? company,
    double labelWidthMm = 150,
    double labelHeightMm = 50,
  }) async {
    final doc = pw.Document();

    final pageFormat = PdfPageFormat(
      labelWidthMm * PdfPageFormat.mm,
      labelHeightMm * PdfPageFormat.mm,
      marginAll: 6 * PdfPageFormat.mm,
    );

    for (final item in items) {
      final unitTotal = item.quantity.round().clamp(1, 999);

      for (var unitIndex = 1; unitIndex <= unitTotal; unitIndex++) {
        final qrCode =
            unitTotal > 1 ? '${item.itemCode}-U$unitIndex' : item.itemCode;

        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (context) => _buildLabelBox(
              receiving: receiving,
              item: item,
              qrCode: qrCode,
              company: company,
            ),
          ),
        );
      }
    }

    return doc;
  }

  static pw.Widget _buildLabelBox({
    required ReceivingModel receiving,
    required ReceivingDetailModel item,
    required String qrCode,
    CompanyModel? company,
  }) {
    // 1) Nama perusahaan + No. WA -- satu baris, TANPA alamat.
    final companyLine = [
      company?.name ?? 'TRANS',
      if (company?.phone != null && company!.phone!.isNotEmpty)
        company.phone!,
    ].join(' ');

    // 2) Nama tujuan + alamat tujuan -- satu baris.
    final destinationLine = [
      receiving.destination,
      if (receiving.destinationAddress != null &&
          receiving.destinationAddress!.isNotEmpty)
        receiving.destinationAddress!,
    ].join(' - ');

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // --------------------------------------------------------
        // KIRI: kop ringkas + tujuan + nama barang/status
        // --------------------------------------------------------
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                companyLine,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                destinationLine,
                style: const pw.TextStyle(fontSize: 9),
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
              ),
              pw.Divider(height: 10, thickness: 0.7),
              // 3) Nama barang + status satuan/bundle, mis. "Ban Motor
              // Batlax 1 ikat (isi 5)".
              pw.Text(
                labelItemStatusLine(item),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        // --------------------------------------------------------
        // KANAN: 4) QR code + kode di bawahnya
        // --------------------------------------------------------
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrCode,
                width: 60,
                height: 60,
                drawText: false,
              ),
              pw.SizedBox(height: 3),
              pw.Text(qrCode, style: const pw.TextStyle(fontSize: 6.5), textAlign: pw.TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RESI PENERIMAAN
  // ============================================================

  /// Dokumen resi lengkap: kop perusahaan + info pengirim/penerima/tujuan
  /// + tabel barang bergaris (Nama Barang/Banyaknya) + Keterangan &
  /// Total, lalu QR code di bagian paling bawah buat discan.
  ///
  /// TIDAK ADA kolom/info harga sama sekali (permintaan user, 3 Oktober
  /// 2026) -- resi ini dipegang/dilihat pihak luar (pengirim/tujuan),
  /// harga per barang & totalnya adalah info internal yang tidak perlu
  /// mereka lihat. Harga TETAP tersimpan & bisa diedit seperti biasa di
  /// `ReceivingItemsPage`, cuma tidak ikut tercetak di sini. Berlaku
  /// SAMA di preview on-screen (`ReceiptPreviewPage`) & cetak thermal
  /// (`PrintTemplates.buildReceiptBytes`) -- 3 tempat itu harus selalu
  /// konsisten (apa yang di-preview = apa yang tercetak/dibagikan).
  static Future<pw.Document> buildReceiptDocument({
    required ReceivingModel receiving,
    required SenderModel? sender,
    required List<ReceivingDetailModel> items,
    CompanyModel? company,
    Map<String, String> pricingTypeNameById = const {},
  }) async {
    final doc = pw.Document();

    final logoBytes = await _fetchLogoBytes(company?.logoUrl);

    final totalQuantity = items.fold<double>(0, (sum, i) => sum + i.quantity);

    // NOTE (22 Sep 2026 -- fix "PDF kosong/terpotong" root-cause class):
    // `pw.Page` adalah widget SATU HALAMAN UKURAN TETAP (A4) -- kalau isi
    // childnya (di sini: tabel barang, bisa panjang kalau item banyak)
    // tidak muat di satu halaman, package `pdf` DIAM-DIAM memotong
    // sisanya tanpa error apapun (doc.save() tetap sukses, hasilnya PDF
    // valid tapi TIDAK LENGKAP). Ini persis root cause yang sama dengan
    // bug "Manifest kosong setelah shipment berangkat" yang sudah
    // diperbaiki sebelumnya di `buildManifestDocument` &
    // `buildDestinationReceiptDocument` -- lihat catatan detail di
    // project doc arsitektur-flutter.md. Sesuai standing rule di doc itu
    // ("semua dokumen PDF yang isinya bisa panjang/variabel WAJIB pakai
    // pw.MultiPage, JANGAN pw.Page"), fungsi ini (resi bisa punya banyak
    // baris barang) diubah dari `pw.Page` -> `pw.MultiPage`: kop
    // perusahaan + info pengirim/tujuan jadi `header:` (otomatis
    // berulang di tiap halaman kalau tabel meluber lebih dari 1
    // halaman), tabel + total + QR jadi `build:` (list widget, otomatis
    // dipaginasi oleh package -- TIDAK ADA logika data yang berubah,
    // cuma restrukturisasi supaya konten bisa lanjut ke halaman
    // berikutnya alih-alih terpotong diam-diam).
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildCompanyHeader(
              company: company,
              logoBytes: logoBytes,
              documentTitle: 'Resi Penerimaan',
              // FITUR (8 Oktober 2026 -- poin 7): nomor buku disisipkan
              // di belakang nomor resi kalau ada.
              documentNumber: (receiving.nomorBuku != null &&
                      receiving.nomorBuku!.isNotEmpty)
                  ? '${receiving.receiptNumber} / ${receiving.nomorBuku}'
                  : receiving.receiptNumber,
              documentDate: receiving.receivedAt,
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs
            // Tujuan): "Kepada"/"Hp" di sini SEKARANG bersumber dari
            // data Tujuan (receiving.destination/destinationPhone),
            // BUKAN lagi dari receiverName/receiverPhone manual (field
            // itu sudah dihapus dari form input & selalu null untuk
            // resi baru) -- berlaku juga untuk resi lama supaya
            // tampilannya konsisten satu sumber data.
            _buildInfoRow('Pengirim', sender?.name ?? '-'),
            _buildInfoRow('Kepada', receiving.destination),
            _buildInfoRow('Alamat', receiving.destinationAddress ?? receiving.destination),
            if (receiving.destinationPhone != null &&
                receiving.destinationPhone!.isNotEmpty)
              _buildInfoRow('Hp', receiving.destinationPhone!),
            if (receiving.route != null) _buildInfoRow('Rute', receiving.route!),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          pw.Table(
                border: pw.TableBorder.all(width: 0.6),
                columnWidths: const {
                  0: pw.FlexColumnWidth(4.4),
                  1: pw.FlexColumnWidth(2.2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8ECF5)),
                    children: [
                      _headerCell('Nama Barang'),
                      _headerCell('Banyaknya', align: pw.Alignment.center),
                    ],
                  ),
                  for (final item in items)
                    pw.TableRow(
                      children: [
                        _bodyCell(
                          itemDisplayLabel(
                            item.itemName,
                            item.pricingTypeId,
                            pricingTypeNameById,
                          ),
                        ),
                        _bodyCell(
                          item.quantity == item.quantity.roundToDouble()
                              ? '${item.quantity.toStringAsFixed(0)} ${item.quantityUnit}'
                              : '${item.quantity} ${item.quantityUnit}',
                          align: pw.Alignment.center,
                        ),
                      ],
                    ),
                  // Baris kosong pengisi, mengikuti contoh formulir fisik
                  // supaya tabel tetap terlihat rapi walau item sedikit.
                  for (var i = items.length; i < 6; i++)
                    pw.TableRow(
                      children: [
                        _bodyCell(''),
                        _bodyCell(''),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Keterangan:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                        ),
                        pw.Text(
                          'Barang rusak/kurang di luar tanggung jawab perusahaan.',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                        pw.Text(
                          'Komplain maksimal 10 hari, lebih dari itu tidak dilayani.',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Text(
                    'Total (${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity} pcs)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: receiving.receiptNumber,
                      width: 90,
                      height: 90,
                      drawText: false,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      (receiving.nomorBuku != null &&
                              receiving.nomorBuku!.isNotEmpty)
                          ? '${receiving.receiptNumber} / ${receiving.nomorBuku}'
                          : receiving.receiptNumber,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );

    return doc;
  }

  /// `fontSize`/`verticalPadding` (DITAMBAHKAN 8 Oktober 2026, lanjutan
  /// lagi -- lihat catatan `scale` di `_buildCompanyHeader`): default
  /// SAMA PERSIS nilai lama (9.5 / 5) supaya Manifest & dokumen lain yang
  /// pakai sel ini TIDAK TERPENGARUH. HANYA dipanggil dengan nilai lebih
  /// kecil dari `buildDestinationReceiptDocument`/`_destinationReceiptRow`.
  static pw.Widget _headerCell(
    String text, {
    pw.Alignment align = pw.Alignment.centerLeft,
    double fontSize = 9.5,
    double verticalPadding = 5,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: verticalPadding),
      alignment: align,
      child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)),
    );
  }

  static pw.Widget _bodyCell(
    String text, {
    pw.Alignment align = pw.Alignment.centerLeft,
    double fontSize = 9.5,
    double verticalPadding = 5,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: verticalPadding),
      alignment: align,
      child: pw.Text(text, style: pw.TextStyle(fontSize: fontSize)),
    );
  }

  // ============================================================
  // LAPORAN HARIAN
  // ============================================================

  /// Laporan rekap resi untuk satu tanggal, milik satu petugas penerima
  /// (received_by) -- dicetak petugas Receiving tiap sore (atau tanggal
  /// lain kalau perlu cetak ulang). Dibagikan sebagai PDF saja, tidak
  /// ada versi cetak thermal (tabelnya kelebaran buat kertas struk 80mm).
  static Future<pw.Document> buildDailyReceivingReportDocument({
    required DateTime date,
    required String staffName,
    required List<ReceivingModel> receivings,
    CompanyModel? company,
  }) async {
    final doc = pw.Document();

    final logoBytes = await _fetchLogoBytes(company?.logoUrl);

    final totalQuantity =
        receivings.fold<double>(0, (sum, r) => sum + r.totalQuantity);
    final totalValue = receivings.fold<double>(0, (sum, r) => sum + r.totalPrice);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildCompanyHeader(
              company: company,
              logoBytes: logoBytes,
              documentTitle: 'Laporan Resi Harian',
              documentNumber: 'Petugas: $staffName',
              documentDate: date,
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs
          // Tujuan): kolom "Penerima" (dulu dari receiverName manual)
          // diganti "HP Tujuan" (destinationPhone, snapshot dari data
          // Tujuan) -- kolom "Tujuan" (nama) sudah ada sendiri di
          // sebelahnya, jadi tidak perlu diulang.
          pw.Table.fromTextArray(
            headers: ['No', 'No. Resi', 'Tujuan', 'HP Tujuan', 'Qty', 'Nilai'],
            data: [
              for (var i = 0; i < receivings.length; i++)
                [
                  '${i + 1}',
                  // FITUR (8 Oktober 2026 -- poin 7): nomor buku di
                  // belakang nomor resi kalau ada.
                  (receivings[i].nomorBuku != null &&
                          receivings[i].nomorBuku!.isNotEmpty)
                      ? '${receivings[i].receiptNumber} / ${receivings[i].nomorBuku}'
                      : receivings[i].receiptNumber,
                  receivings[i].destination,
                  receivings[i].destinationPhone ?? '-',
                  receivings[i].totalQuantity ==
                          receivings[i].totalQuantity.roundToDouble()
                      ? receivings[i].totalQuantity.toStringAsFixed(0)
                      : receivings[i].totalQuantity.toString(),
                  formatRupiah(receivings[i].totalPrice),
                ],
            ],
            cellAlignments: {
              0: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.6),
              1: const pw.FlexColumnWidth(1.6),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(1.6),
              4: const pw.FlexColumnWidth(0.8),
              5: const pw.FlexColumnWidth(1.4),
            },
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total ${receivings.length} resi (${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity} pcs)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatRupiah(totalValue),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  // ============================================================
  // MANIFEST KENDARAAN
  // ============================================================

  /// Manifest muatan shipment: kop perusahaan + info sopir/kendaraan +
  /// tabel muatan DIGROUP PER RESI (bukan per barang) -- perbaikan
  /// permintaan user (22 Sep 2026): manifest adalah daftar MUATAN, bukan
  /// daftar barang satuan, jadi 1 resi hanya boleh muncul SATU KALI di
  /// tabel walau resi itu berisi banyak barang. [resiSummaries] adalah
  /// hasil `ShipmentService.getManifestPrintSummary` (sudah dikelompokkan
  /// & nilainya diprorata di sana, lihat catatan di method itu). Kolom:
  /// No | No. Resi & Tujuan | Alamat Tujuan | Jumlah Barang (+jenis tarif)
  /// | Nilai Tarif. Dibagikan sebagai PDF dari ManifestPage.
  static Future<pw.Document> buildManifestDocument({
    required ShipmentModel shipment,
    required VehicleModel vehicle,
    required List<Map<String, dynamic>> resiSummaries,
    CompanyModel? company,
  }) async {
    final doc = pw.Document();

    final logoBytes = await _fetchLogoBytes(company?.logoUrl);

    final totalItems = resiSummaries.fold<int>(
      0,
      (sum, e) => sum + (e['itemCount'] as int? ?? 0),
    );
    final totalValue = resiSummaries.fold<double>(
      0,
      (sum, e) => sum + ((e['totalValue'] as num?)?.toDouble() ?? 0),
    );

    // PERBAIKAN BUG (22 Sep 2026): sebelumnya pakai `pw.Page` (1 halaman
    // TETAP, tidak bisa nambah halaman) -- begitu manifest digroup PER
    // RESI (bukan per barang) dan jumlah resi cukup banyak (mis. 22 resi
    // dari 29 barang discan), total tinggi konten (kop + tabel + total +
    // QR) jadi TIDAK MUAT di 1 halaman A4. `pw.Page` TIDAK memotong ke
    // halaman baru kalau kelebihan -- dia diam-diam GAGAL menggambar
    // bagian yang tidak muat (termasuk seluruh tabelnya), padahal
    // `resiSummaries` datanya sendiri TERBUKTI ada (lihat
    // `ShipmentService.debugManifestDiagnostics`). Efeknya: kop &
    // info sopir/kendaraan tetap tercetak (muat), tapi tabel muatan +
    // total + QR hilang total tanpa error apa pun -- persis laporan user
    // "manifest kosong pas dibuat PDF, padahal data di layar ada".
    //
    // Diganti ke `pw.MultiPage` (dipakai juga di
    // `buildDailyReceivingReportDocument`/`buildManifestSummaryByDestination
    // Document` di file ini) -- otomatis lanjut ke halaman berikutnya
    // kalau kontennya tidak muat, jadi TIDAK ADA LAGI konten yang hilang
    // diam-diam, berapa pun banyaknya resi.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildCompanyHeader(
              company: company,
              logoBytes: logoBytes,
              documentTitle: 'Manifes Barang',
              documentNumber: shipment.shipmentNumber,
              documentDate: shipment.loadedAt ?? shipment.createdAt,
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            _buildInfoRow('Sopir', vehicle.driverName ?? '-'),
            _buildInfoRow('Hp', vehicle.driverPhone ?? '-'),
            _buildInfoRow('Kendaraan', vehicle.plateNumber),
            if (vehicle.vehicleType != null) _buildInfoRow('Jenis', vehicle.vehicleType!),
            _buildInfoRow('Status', _manifestStatusLabel(shipment.status)),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          if (resiSummaries.isEmpty)
            pw.Text(
              'Belum ada barang yang discan untuk shipment ini.',
              style: const pw.TextStyle(fontSize: 10),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.4),
                1: pw.FlexColumnWidth(2.1),
                2: pw.FlexColumnWidth(2.3),
                3: pw.FlexColumnWidth(1.7),
                4: pw.FlexColumnWidth(1.6),
                5: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8ECF5)),
                  children: [
                    _headerCell('No', align: pw.Alignment.center),
                    _headerCell('No. Resi / Tujuan'),
                    _headerCell('Alamat Tujuan'),
                    _headerCell('Jumlah Barang'),
                    _headerCell('Nilai Tarif', align: pw.Alignment.centerRight),
                    _headerCell('Keterangan'),
                  ],
                ),
                for (var i = 0; i < resiSummaries.length; i++)
                  _manifestSummaryRow(i, resiSummaries[i]),
              ],
            ),
          _buildKantorDpRecap(resiSummaries),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Keterangan:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                    ),
                    pw.Text(
                      'Barang rusak/kurang di luar tanggung jawab perusahaan.',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Total Barang: $totalItems koli (${resiSummaries.length} resi)',
                    style: const pw.TextStyle(fontSize: 9.5),
                  ),
                  pw.Text(
                    formatRupiah(totalValue),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: shipment.shipmentNumber,
              width: 90,
              height: 90,
              drawText: false,
            ),
          ),
        ],
      ),
    );

    return doc;
  }

  /// FITUR (16 Oktober 2026 -- permintaan user eksplisit): "Tambahkan
  /// pada bagian bawah tabel Pembayaran di Kantor dan DP. Isinya: Nomor
  /// Resi, Nama Tujuan, dan DP Bayar Kantor. Dan Totalnya paling
  /// bawah." Rekap tabel KEDUA, ditaruh LANGSUNG di bawah tabel muatan
  /// utama (sebelum baris "Keterangan:"/"Total Barang") -- HANYA berisi
  /// resi yang MEMANG ada pembayaran di kantor (DP apa pun, atau status
  /// Bayar Dikantor lunas penuh), dari resi yang MURNI Bayar Tujuan
  /// (tanpa DP) TIDAK ikut masuk. Nilainya SAMA PERSIS dengan baris
  /// "Bayar Kantor : ..." di kolom Keterangan tabel utama (SATU SUMBER
  /// KEBENARAN lewat `_bayarKantorAmount`, lihat doc comment di sana) --
  /// rekap ini murni supaya admin/kasir tidak perlu scroll cari satu-satu
  /// baris "Bayar Kantor" di kolom Keterangan, semuanya sudah terkumpul
  /// di 1 tabel + total di baris paling bawah.
  ///
  /// Kalau TIDAK ADA resi yang punya pembayaran kantor sama sekali di
  /// shipment ini, SENGAJA tidak menampilkan apa pun (`pw.SizedBox()`
  /// kosong) -- tidak ada gunanya mencetak tabel rekap kosong.
  static pw.Widget _buildKantorDpRecap(List<Map<String, dynamic>> resiSummaries) {
    final rows = <Map<String, dynamic>>[];

    for (final entry in resiSummaries) {
      final amount = _bayarKantorAmount(entry);
      if (amount == null) continue;

      final receiptNumber = entry['receiptNumber']?.toString() ?? '-';
      final nomorBuku = entry['nomorBuku']?.toString();

      rows.add({
        'receiptLabel': (nomorBuku != null && nomorBuku.isNotEmpty)
            ? '$receiptNumber / $nomorBuku'
            : receiptNumber,
        'destination': entry['destination']?.toString() ?? '-',
        'amount': amount,
      });
    }

    if (rows.isEmpty) return pw.SizedBox();

    final total = rows.fold<double>(0, (s, r) => s + (r['amount'] as double));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Text(
          'Pembayaran di Kantor dan DP',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.4),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(2.8),
            3: pw.FlexColumnWidth(1.8),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8ECF5)),
              children: [
                _headerCell('No', align: pw.Alignment.center),
                _headerCell('Nomor Resi'),
                _headerCell('Nama Tujuan'),
                _headerCell('DP / Bayar Kantor', align: pw.Alignment.centerRight),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              pw.TableRow(
                children: [
                  _bodyCell('${i + 1}', align: pw.Alignment.center),
                  _bodyCell(rows[i]['receiptLabel'] as String),
                  _bodyCell(rows[i]['destination'] as String),
                  _bodyCell(
                    formatRupiah(rows[i]['amount'] as double),
                    align: pw.Alignment.centerRight,
                  ),
                ],
              ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F6FF)),
              children: [
                pw.SizedBox(),
                pw.SizedBox(),
                _headerCell('Total', align: pw.Alignment.centerRight),
                _headerCell(formatRupiah(total), align: pw.Alignment.centerRight),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _manifestSummaryRow(int index, Map<String, dynamic> entry) {
    final receiptNumber = entry['receiptNumber']?.toString() ?? '-';
    // FITUR (8 Oktober 2026 -- poin 7): nomor buku di belakang nomor resi
    // kalau ada.
    final nomorBuku = entry['nomorBuku']?.toString();
    final destination = entry['destination']?.toString() ?? '-';
    final destinationPhone = entry['destinationPhone']?.toString();
    final destinationAddress = entry['destinationAddress']?.toString() ?? '-';
    final totalValue = (entry['totalValue'] as num?)?.toDouble() ?? 0;
    final koliLabel = _koliLabel(entry);

    return pw.TableRow(
      children: [
        _bodyCell('${index + 1}', align: pw.Alignment.center),
        _manifestDestinationCell(
          (nomorBuku != null && nomorBuku.isNotEmpty)
              ? '$receiptNumber / $nomorBuku'
              : receiptNumber,
          destination,
          destinationPhone,
        ),
        _bodyCell(destinationAddress),
        // DIUBAH (16 Oktober 2026 -- permintaan user eksplisit): akhiran
        // "(N jenis)" dihapus -- cukup "{jumlah} koli" (lihat doc
        // comment `_koliLabel` untuk perubahan "koli/paket" -> "koli").
        _bodyCell(koliLabel),
        _bodyCell(formatRupiah(totalValue), align: pw.Alignment.centerRight),
        _manifestKeteranganCell(entry),
      ],
    );
  }

  /// Label jumlah koli untuk 1 baris Manifest Muatan / Tanda Terima
  /// Tujuan (lanjutan fix 3 Oktober 2026, permintaan user): kalau resi
  /// ini genuinely terpecah ke beberapa kendaraan (`totalQuantity` dari
  /// [ShipmentService] lebih besar dari `itemCount` fisik di kendaraan
  /// ini), tampilkan "40 dari 100 koli" supaya jelas ini cuma SEBAGIAN
  /// dari total resi -- bukan koli yang "hilang"/salah hitung. Kasus
  /// normal (tidak terpecah, mayoritas kasus) tetap tampil polos "100
  /// koli" seperti sebelumnya (totalQuantity == itemCount).
  ///
  /// DIUBAH (16 Oktober 2026 -- permintaan user eksplisit, "Pada Manifest
  /// ... Pada kolom jumlah barang, hilangkan '(paket {jumlah} jenis)' jadi
  /// cukup tertulis '{jumlah} koli'"): label SEBELUMNYA "X koli/paket" ->
  /// SEKARANG cuma "X koli" (akhiran "/paket" dihapus). Fungsi ini
  /// DIPAKAI BERSAMA oleh `_manifestSummaryRow` (Manifest) &
  /// `_destinationReceiptRow` (Tanda Terima Tujuan) -- perubahan ini
  /// SENGAJA diterapkan ke KEDUANYA (satu sumber kebenaran, bukan
  /// dobel-maintain 2 versi label yang mestinya sama) walau permintaan
  /// user menyebut "Manifest" secara spesifik. Akhiran "(N jenis)" yang
  /// SEBELUMNYA ditambahkan KHUSUS di `_manifestSummaryRow` (Tanda
  /// Terima Tujuan tidak pernah punya akhiran ini) dihapus terpisah di
  /// sana, lihat catatan di situ.
  static String _koliLabel(Map<String, dynamic> entry) {
    final itemCount = entry['itemCount'] as int? ?? 0;
    final totalQuantity = entry['totalQuantity'] as int? ?? itemCount;

    if (totalQuantity > itemCount) {
      return '$itemCount dari $totalQuantity koli';
    }
    return '$itemCount koli';
  }

  /// Kolom "Keterangan" di ujung tabel Manifest.
  ///
  /// SEBELUMNYA (23 Sep 2026) kolom ini SENGAJA dibiarkan kosong --
  /// "tambahan kolom kosong pada manifes di belakang header 'Keterangan'
  /// ... berguna untuk memberikan keterangan manual" -- murni ruang untuk
  /// sopir/petugas tulis tangan catatan manual (mis. "titip tetangga",
  /// "barang pecah").
  ///
  /// DIUBAH (13 Oktober 2026 -- permintaan user "Tambahan Fitur" poin 5:
  /// "Di manifest pada kolom keterangan: tertulis: status pembayaran
  /// tsb. Jika ada DP maka tertulis DP berapa."): kolom ini SEKARANG
  /// menampilkan status pembayaran (Bayar Tujuan/Bayar Dikantor) + nilai
  /// DP kalau ada, DAN (poin 7) nilai tagihan Bayar Tujuan HANYA kalau
  /// [entry]['isLastLoadingShipment'] true (lihat
  /// `ShipmentService._isLastLoadingShipment` -- supaya tagihan tidak
  /// dobel-tampil kalau resi terpecah ke beberapa kendaraan). Ruang
  /// kosong untuk catatan tangan TETAP disisakan di bawah teks data ini
  /// (SizedBox kecil), supaya kebutuhan lama (23 Sep 2026) tidak hilang
  /// sama sekali -- cuma lebih sempit karena sudah terisi data.
  /// Nilai "Bayar Kantor" (DP kalau ada, atau TOTAL harga resi kalau
  /// status Bayar Dikantor TANPA DP sama sekali/lunas penuh di kantor)
  /// untuk 1 resi -- `null` kalau resi ini MURNI Bayar Tujuan (tanpa DP
  /// sama sekali), artinya TIDAK ADA pembayaran di kantor untuk resi
  /// ini. SATU SUMBER KEBENARAN dipakai BERSAMA oleh kolom "Keterangan"
  /// (`_manifestKeteranganCell`, per-baris) & rekap tabel "Pembayaran di
  /// Kantor dan DP" di bawah tabel utama Manifest (`_buildKantorDpRecap`,
  /// DITAMBAHKAN 16 Oktober 2026) -- supaya kedua tempat itu TIDAK BISA
  /// beda angka (logic di-copy-paste dari `_manifestKeteranganCell` yang
  /// sudah ada sejak 14 Oktober 2026, bukan logic baru).
  static double? _bayarKantorAmount(Map<String, dynamic> entry) {
    final paymentStatus = entry['paymentStatus'] as String? ??
        ReceivingPaymentStatus.bayarTujuan;
    final dpAmount = (entry['dpAmount'] as num?)?.toDouble();
    final receivingTotalPrice =
        (entry['receivingTotalPrice'] as num?)?.toDouble() ?? 0;

    final hasDp = dpAmount != null && dpAmount > 0;
    final isBayarKantor =
        hasDp || paymentStatus == ReceivingPaymentStatus.bayarDikantor;
    if (!isBayarKantor) return null;

    return hasDp ? dpAmount! : receivingTotalPrice;
  }

  static pw.Widget _manifestKeteranganCell(Map<String, dynamic> entry) {
    final paymentStatus = entry['paymentStatus'] as String? ??
        ReceivingPaymentStatus.bayarTujuan;
    final billingAmount = (entry['billingAmount'] as num?)?.toDouble();

    final lines = <String>[ReceivingPaymentStatus.label(paymentStatus)];

    // FITUR (14 Oktober 2026 -- permintaan user eksplisit): "Pada
    // Manifest: Jika ada DP (atau bayar kantor) Pada Kolom keterangan
    // tulis Bayar Kantor : ................. Jangan ganggu total biaya
    // resi." -- MENGGANTIKAN baris "DP {amount}" yang lama (bukan
    // ditambah dobel jadi 2 baris yang isinya mirip). `billingAmount`/
    // total biaya resi di kolom "Jumlah" lain SAMA SEKALI TIDAK disentuh/
    // dihitung ulang di sini.
    final bayarKantorAmount = _bayarKantorAmount(entry);
    if (bayarKantorAmount != null) {
      lines.add('Bayar Kantor : ${formatRupiah(bayarKantorAmount)}');
    }

    if (billingAmount != null) {
      lines.add('Tagihan: ${formatRupiah(billingAmount)}');
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: pw.Alignment.centerLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          for (final line in lines)
            pw.Text(line, style: const pw.TextStyle(fontSize: 7.5)),
          // Sisa ruang kosong -- catatan tangan manual (lihat doc
          // comment di atas).
          pw.SizedBox(height: 8, width: double.infinity),
        ],
      ),
    );
  }

  /// Sel "No. Resi / Tujuan" di tabel Manifest -- permintaan user (23 Sep
  /// 2026): nama tujuan (+ No. HP kalau ada) harus LEBIH MENONJOL
  /// (diperbesar & tebal) daripada nomor resi, supaya sopir/petugas lebih
  /// gampang lihat NAMA TUJUAN dulu ketimbang nomor resi saat baca
  /// manifest. Nomor resi tetap ditampilkan (sebagai identitas resi) tapi
  /// fontnya diperkecil sedikit dan tidak bold. `destinationPhone` adalah
  /// snapshot `receiving.destination_phone`, diambil lewat
  /// `ShipmentService.getManifestPrintSummary` (kolom sudah diambil sejak
  /// `_getLoadScansWithDetails` juga dipakai `getManifestSummaryByDestination`
  /// untuk kebutuhan Tanda Terima Tujuan).
  static pw.Widget _manifestDestinationCell(
    String receiptNumber,
    String destination,
    String? destinationPhone,
  ) {
    final hasPhone = destinationPhone != null && destinationPhone.trim().isNotEmpty;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: pw.Alignment.centerLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            receiptNumber,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            destination,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5),
          ),
          if (hasPhone)
            pw.Text(
              'HP: $destinationPhone',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5),
            ),
        ],
      ),
    );
  }

  static String _manifestStatusLabel(String status) {
    switch (status) {
      case 'LOADING':
        return 'Sedang Dimuat';
      case 'DEPARTED':
        return 'Berangkat';
      case 'ARRIVED':
        return 'Tiba';
      case 'CANCELLED':
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  // ============================================================
  // DAFTAR RESI PER TUJUAN
  // ============================================================

  /// Daftar semua resi yang tujuannya sama (destination_id sama), buat
  /// dicetak petugas Receiving/Loading sebelum berangkat -- supaya kalau
  /// ada beberapa pengirim berbeda kirim ke tujuan yang sama, sopir bisa
  /// antar sekali jalan, tidak bolak-balik ke tujuan yang sama.
  ///
  /// Mengikuti layout tabel formulir fisik, TANPA QR code (beda dengan
  /// resi per-pengirim) -- ini daftar rekap, bukan bukti terima barang.
  static Future<pw.Document> buildReceivingsByDestinationDocument({
    required String destinationName,
    String? destinationAddress,
    String? destinationPhone,
    required List<ReceivingModel> receivings,
    required Map<String, String> senderNameById,
    CompanyModel? company,
  }) async {
    final doc = pw.Document();

    final logoBytes = await _fetchLogoBytes(company?.logoUrl);

    final totalQuantity =
        receivings.fold<double>(0, (sum, r) => sum + r.totalQuantity);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildCompanyHeader(
              company: company,
              logoBytes: logoBytes,
              documentTitle: 'Daftar Resi per Tujuan',
              documentNumber: destinationName,
              documentDate: DateTime.now(),
            ),
            pw.SizedBox(height: 6),
            if (destinationAddress != null && destinationAddress.isNotEmpty)
              _buildInfoRow('Alamat', destinationAddress),
            if (destinationPhone != null && destinationPhone.isNotEmpty)
              _buildInfoRow('Hp', destinationPhone),
            pw.SizedBox(height: 4),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs
          // Tujuan): kolom "Penerima" (dulu dari receiverName manual)
          // DIHAPUS dari tabel -- dokumen ini sudah dikelompokkan per
          // tujuan (nama & HP tujuan tampil sekali di kop di atas, tidak
          // perlu diulang tiap baris).
          pw.Table.fromTextArray(
            headers: ['No', 'No. Resi', 'Pengirim', 'Qty', 'Status'],
            data: [
              for (var i = 0; i < receivings.length; i++)
                [
                  '${i + 1}',
                  // FITUR (8 Oktober 2026 -- poin 7): nomor buku di
                  // belakang nomor resi kalau ada.
                  (receivings[i].nomorBuku != null &&
                          receivings[i].nomorBuku!.isNotEmpty)
                      ? '${receivings[i].receiptNumber} / ${receivings[i].nomorBuku}'
                      : receivings[i].receiptNumber,
                  senderNameById[receivings[i].senderId] ?? '-',
                  receivings[i].totalQuantity ==
                          receivings[i].totalQuantity.roundToDouble()
                      ? receivings[i].totalQuantity.toStringAsFixed(0)
                      : receivings[i].totalQuantity.toString(),
                  receivings[i].status,
                ],
            ],
            cellAlignments: {
              0: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.6),
              1: const pw.FlexColumnWidth(1.6),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(0.8),
              4: const pw.FlexColumnWidth(1.2),
            },
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total ${receivings.length} resi',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                '${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity} pcs',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  // ============================================================
  // TANDA TERIMA TUJUAN
  // ============================================================

  /// Tanda terima barang PER TUJUAN untuk satu shipment -- permintaan user
  /// (22 Sep 2026): beda dengan Manifes Barang (rekap per resi buat arsip
  /// sopir/gudang), dokumen ini dikelompokkan PER TUJUAN, untuk diserahkan
  /// & ditandatangani di lokasi tujuan masing-masing sebagai bukti serah
  /// terima barang. "Kepada" di sini BUKAN nama penerima perorangan, tapi
  /// nama tujuan (sesuai tabel tujuan/destinations) -- karena barang dalam
  /// 1 tujuan bisa berasal dari banyak resi/pengirim berbeda sekaligus.
  ///
  /// UPDATE PENTING (22 Sep 2026, permintaan susulan): SEBELUMNYA dokumen
  /// ini dicetak 1 HALAMAN PENUH PER TUJUAN (`doc.addPage()` dipanggil
  /// sekali per tujuan di dalam loop, jadi tiap tujuan SELALU mulai
  /// halaman baru walau isinya cuma 1 baris barang). User eksplisit minta
  /// ini diubah: **"jangan 1 tujuan 1 lembar"**, supaya IRIT KERTAS.
  /// Sekarang SELURUH tujuan digabung jadi **SATU `pw.MultiPage` tunggal**
  /// (satu laporan untuk satu manifest/shipment, BUKAN satu dokumen
  /// per-halaman per tujuan lagi) -- tujuan-tujuan mengalir berurutan di
  /// halaman yang sama selama masih muat, halaman baru cuma dibuat kalau
  /// kontennya benar-benar tidak muat lagi (perilaku otomatis
  /// `pw.MultiPage`, TIDAK dipaksa per tujuan). Kop dokumen (nama
  /// perusahaan + judul "Tanda Terima Tujuan" + info sopir/kendaraan)
  /// sekarang SATU KALI di bagian atas dokumen (berulang otomatis tiap
  /// halaman lewat `header:`, persis pola `buildManifestDocument`), BUKAN
  /// per tujuan lagi -- info "Kepada"/"Alamat" tiap tujuan sekarang jadi
  /// sub-judul INLINE di awal blok masing-masing tujuan
  /// (`_buildDestinationSectionHeading`), dipisahkan garis putus-putus
  /// (`_dashedDivider`, penanda visual SAJA, BUKAN pemisah halaman paksa)
  /// dari tujuan berikutnya, supaya identitas tiap tujuan tetap jelas
  /// walau beberapa tujuan berbagi 1 halaman yang sama.
  ///
  /// Isi dokumen: kop (nama/alamat/telp perusahaan + judul "Tanda Terima
  /// Tujuan" + info Sopir/Hp/Kendaraan/Status, sama seperti Manifes) ->
  /// untuk TIAP tujuan berurutan: sub-judul "Kepada"/"Alamat" -> tabel
  /// (No. Resi | Nama Barang | Jumlah Koli/Paket | Harga Satuan | Jumlah)
  /// DIGROUP PER NAMA BARANG (baris dengan nama barang sama dikelompokkan
  /// berurutan) -> total tarif per tujuan -> kolom tanda tangan
  /// "Diserahkan oleh" / "Diterima oleh" (tambahan wajar untuk dokumen
  /// serah terima, di luar spesifikasi eksplisit user) -> garis
  /// putus-putus sebelum tujuan berikutnya (tidak digambar setelah tujuan
  /// TERAKHIR).
  ///
  /// DIUBAH (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
  /// "Daftar Muatan ... yang ditampilkan adalah Nama Barang dan
  /// jumlahnya. Bukan Jenis Tarif dan jumlahnya. Semua cetakan output
  /// printout mengikuti pola tersebut."). Kolom "Jenis Tarif" SEBELUMNYA
  /// diganti jadi "Nama Barang" -- parameter `pricingTypeNameById` jadi
  /// tidak dipakai lagi di method ini (DIHAPUS, lihat
  /// `ShipmentService.getManifestSummaryByDestination` yang sekarang
  /// mengirim `itemName`/`quantityUnit` per baris, bukan `pricingTypeId`).
  ///
  /// [destinationSummaries] adalah hasil
  /// `ShipmentService.getManifestSummaryByDestination`.
  ///
  /// DIUBAH (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
  /// "2 Tanda terima tujuan per halaman kertas. Misal: 1,2 di kertas 1,
  /// 3,4 dikertas 2. Jika 1,2 ukurannya kecil maka biarkan ada sisa
  /// kosong kertas. Jika 1,2 ukurannya melebihi 1 kertas dan pindah ke
  /// halaman 2 ... tidak apa-apa."). SEBELUMNYA satu `pw.Document` berisi
  /// SATU `pw.MultiPage` untuk SEMUA tujuan (halaman baru murni otomatis
  /// kalau kehabisan tempat, tidak pernah dipaksa per tujuan) -- efeknya
  /// tujuan ke-3 BISA nyelip mengisi sisa halaman tujuan ke-1/ke-2 kalau
  /// keduanya kebetulan kecil, yang TIDAK diinginkan user (tiap pasangan
  /// harus mulai di kertas barunya sendiri).
  ///
  /// Sekarang [destinationSummaries] dipecah per PASANGAN (chunk 2), dan
  /// TIAP PASANGAN dapat `pw.MultiPage` + `doc.addPage` SENDIRI --
  /// `doc.addPage` SELALU mulai di halaman fisik baru, jadi ini otomatis
  /// memenuhi aturan "2 per halaman, sisa kosong dibiarkan" TANPA perlu
  /// hitung tinggi konten manual. Kalau 1 pasangan isinya banyak dan
  /// melebihi 1 halaman, `pw.MultiPage` bawaan tetap menyambung ke
  /// halaman fisik berikutnya SEBELUM pasangan setelahnya mulai (perilaku
  /// asli `pw.MultiPage`, tidak diubah) -- pas dengan "tidak apa-apa"
  /// yang diminta user. Hasil akhirnya tetap SATU `pw.Document` (bisa
  /// dibagikan sebagai 1 file PDF sekali share), cuma isinya sekarang
  /// beberapa `pw.MultiPage` berurutan, bukan 1.
  static Future<pw.Document> buildDestinationReceiptDocument({
    required ShipmentModel shipment,
    required VehicleModel vehicle,
    required List<Map<String, dynamic>> destinationSummaries,
    CompanyModel? company,
  }) async {
    final doc = pw.Document();

    final logoBytes = await _fetchLogoBytes(company?.logoUrl);

    if (destinationSummaries.isEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (context) => [
            pw.Text(
              'Belum ada barang untuk shipment ini.',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      );
      return doc;
    }

    // Lihat doc comment method ini: 1 chunk = 1 halaman fisik baru (lewat
    // `doc.addPage` terpisah), maksimal 2 tujuan per chunk.
    const destinationsPerPage = 2;
    for (var pageStart = 0; pageStart < destinationSummaries.length; pageStart += destinationsPerPage) {
      final pageEnd = (pageStart + destinationsPerPage > destinationSummaries.length)
          ? destinationSummaries.length
          : pageStart + destinationsPerPage;
      final pageDestinations = destinationSummaries.sublist(pageStart, pageEnd);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          // TIDAK ADA `header:` di sini -- lihat catatan (22 Sep 2026,
          // update kedua) di doc comment method ini: kop lengkap ditaruh
          // ULANG di setiap blok tujuan di dalam `build:` (bukan 1x di
          // level halaman), supaya SETIAP "tanda terima" (blok per
          // tujuan) tetap punya identitas perusahaan & sopir yang lengkap
          // walau 2 tujuan berbagi 1 chunk/halaman fisik yang sama.
          build: (context) {
            final widgets = <pw.Widget>[];

            for (var i = 0; i < pageDestinations.length; i++) {
              final destination = pageDestinations[i];
              final rows = List<Map<String, dynamic>>.from(
                destination['rows'] as List? ?? const [],
              );

              // Digroup per nama barang -- baris dengan nama barang sama jadi
              // bersebelahan, diurutkan berdasarkan nama barangnya (DIUBAH
              // 8 Oktober 2026, lanjutan lagi -- SEBELUMNYA diurutkan per
              // nama jenis tarif, lihat catatan di doc comment method ini).
              rows.sort((a, b) {
                final nameA = a['itemName']?.toString() ?? '';
                final nameB = b['itemName']?.toString() ?? '';
                return nameA.compareTo(nameB);
              });

              final totalValue = (destination['totalValue'] as num?)?.toDouble() ?? 0;
              // FITUR (8 Oktober 2026, lanjutan lagi -- "Cantumkan harga
              // diskon"): total diskon tujuan ini, MURNI informasi (lihat
              // catatan `totalDiscount` di
              // `ShipmentService.getManifestSummaryByDestination`) --
              // `totalValue` di atas SUDAH net, tidak dikurangi lagi di sini.
              final totalDiscount =
                  (destination['totalDiscount'] as num?)?.toDouble() ?? 0;
              final destinationName = destination['destinationName']?.toString() ?? '-';
              final destinationAddress =
                  destination['destinationAddress']?.toString() ?? '-';
              final destinationPhone = destination['destinationPhone']?.toString();

              // Kop LENGKAP (nama/alamat/telp perusahaan + judul dokumen +
              // info Sopir/Hp/Kendaraan/Jenis/Status) diulang di SETIAP blok
              // tujuan -- permintaan eksplisit user (22 Sep 2026, update
              // kedua): "header harusnya ada di setiap tanda terima bukan
              // hanya di kepala kertas". Dulu ini cuma 1x di `header:` level
              // halaman (jadi kalau 2+ tujuan berbagi 1 halaman, cuma tujuan
              // PERTAMA di halaman itu yang kelihatan identitas
              // perusahaan/sopirnya) -- sekarang tiap tujuan SELALU
              // membawa kop lengkapnya sendiri, supaya tiap "tanda terima"
              // tetap sah/lengkap kalau nanti dipisah fisik (gunting) per
              // tujuan.
              widgets.add(
                _buildDestinationReceiptFullHeader(
                  company: company,
                  logoBytes: logoBytes,
                  shipment: shipment,
                  vehicle: vehicle,
                ),
              );
              // Jarak antar baris & ukuran huruf di bawah ini DIKECILKAN ~20%
              // (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
              // "perkecil jarak antar baris dan kurangi besar huruf 20% pada
              // cetakan output Tanda Terima Tujuan. Agar menghemat Kertas")
              // -- HANYA di dokumen ini, lihat catatan `scale` di
              // `_buildCompanyHeader`/`_buildInfoRow` & parameter baru di
              // `_headerCell`/`_bodyCell` untuk dokumen lain yang TIDAK
              // terpengaruh.
              widgets.add(pw.SizedBox(height: 8));
              widgets.add(pw.Divider(thickness: 1));
              widgets.add(pw.SizedBox(height: 5));
              widgets.add(
                _buildDestinationSectionHeading(
                  destinationName,
                  destinationAddress,
                  destinationPhone,
                ),
              );
              widgets.add(pw.SizedBox(height: 5));

              if (rows.isEmpty) {
                widgets.add(
                  pw.Text(
                    'Belum ada barang untuk tujuan ini.',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                );
              } else {
                widgets.add(
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.6),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1.6),
                      1: pw.FlexColumnWidth(1.6),
                      2: pw.FlexColumnWidth(0.9),
                      3: pw.FlexColumnWidth(1.3),
                      4: pw.FlexColumnWidth(1.1),
                      5: pw.FlexColumnWidth(1.3),
                      // FITUR (13 Oktober 2026 -- permintaan user
                      // "Tambahan Fitur" poin 6): kolom baru paling
                      // belakang, lihat [_destinationReceiptRow].
                      6: pw.FlexColumnWidth(1.4),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8ECF5)),
                        children: [
                          _headerCell('No. Resi', fontSize: 7.6, verticalPadding: 4),
                          _headerCell('Nama Barang', fontSize: 7.6, verticalPadding: 4),
                          _headerCell(
                            'Jumlah',
                            align: pw.Alignment.center,
                            fontSize: 7.6,
                            verticalPadding: 4,
                          ),
                          _headerCell(
                            'Harga Satuan',
                            align: pw.Alignment.centerRight,
                            fontSize: 7.6,
                            verticalPadding: 4,
                          ),
                          // FITUR (8 Oktober 2026, lanjutan lagi --
                          // "Cantumkan harga diskon").
                          _headerCell(
                            'Diskon',
                            align: pw.Alignment.centerRight,
                            fontSize: 7.6,
                            verticalPadding: 4,
                          ),
                          _headerCell(
                            'Jumlah',
                            align: pw.Alignment.centerRight,
                            fontSize: 7.6,
                            verticalPadding: 4,
                          ),
                          // FITUR (13 Oktober 2026 -- permintaan user
                          // "Tambahan Fitur" poin 6: "Di Tanda terima
                          // tujuan: tambahkan 1 kolom paling belakang
                          // keterangan. Dan masukkan hal status
                          // pembayaran tersebut.").
                          _headerCell(
                            'Keterangan',
                            fontSize: 7.6,
                            verticalPadding: 4,
                          ),
                        ],
                      ),
                      for (final row in rows) _destinationReceiptRow(row),
                    ],
                  ),
                );
              }

              widgets.add(pw.SizedBox(height: 6));
              widgets.add(
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      // FITUR (8 Oktober 2026, lanjutan lagi -- "Cantumkan
                      // harga diskon"): cuma ditampilkan kalau tujuan ini
                      // benar-benar punya diskon (> 0), supaya shipment yang
                      // tidak pakai diskon sama sekali tampilannya tidak
                      // berubah dari sebelumnya.
                      if (totalDiscount > 0.5)
                        pw.Text(
                          'Diskon Tujuan Ini: -${formatRupiah(totalDiscount)}',
                          style: const pw.TextStyle(fontSize: 7.6),
                        ),
                      pw.Text(
                        'Total Tarif Tujuan Ini',
                        style: const pw.TextStyle(fontSize: 7.6),
                      ),
                      pw.Text(
                        formatRupiah(totalValue),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.4),
                      ),
                    ],
                  ),
                ),
              );
              // FITUR (14 Oktober 2026 -- permintaan user eksplisit):
              // "Pada tanda terima tujuan: Dibawah Total Harga: Masukkan:
              // DP jika ada + No Resi : ................... / Total
              // Tagihan : ............... (total kurang DP). Jika
              // terdapat beberapa resi punya DP > 0 maka cantumkan semua.
              // Resi DP 0 jangan dicantumkan." -- lihat
              // `_destinationDpNotes` untuk logic dedup per resi (BEDA
              // dari kolom Keterangan per baris barang di tabel atas,
              // yang tetap ada apa adanya/tidak disentuh permintaan ini).
              final dpNotes = _destinationDpNotes(rows);
              if (dpNotes.isNotEmpty) {
                widgets.add(pw.SizedBox(height: 8));
                widgets.add(
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (final note in dpNotes) ...[
                          // PERMINTAAN USER (14 Oktober 2026, lanjutan
                          // langsung): format sebelumnya ("DP {amount} +
                          // No Resi : {resi}") dianggap tidak informatif
                          // -- No Resi ditaruh DULUAN, DP belakangan.
                          pw.Text(
                            'NO RESI ${note['label']} '
                            'DP : ${formatRupiah(note['dpAmount'] as double)}',
                            style: const pw.TextStyle(fontSize: 7.6),
                          ),
                          pw.Text(
                            'Total Tagihan : ${formatRupiah(note['tagihan'] as double)}',
                            style: pw.TextStyle(
                              fontSize: 7.6,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (note != dpNotes.last) pw.SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                );
              }
              // FITUR (14 Oktober 2026, lanjutan lagi -- permintaan user:
              // "Dibawah [blok DP/Total Tagihan] tambahkan teks font
              // miring: Catatan: Barang Rusak/Kurang diluar tanggung
              // jawab ekspedisi. Komplain 10 hari, lebih dari itu tidak
              // dilayani."). SELALU ditampilkan (bukan cuma kalau ada
              // DP) -- ini disclaimer umum tanda terima, bukan terkait
              // status pembayaran.
              widgets.add(pw.SizedBox(height: 8));
              widgets.add(
                pw.Text(
                  'Catatan :\n'
                  'Barang Rusak/Kurang diluar tanggung jawab ekspedisi\n'
                  'Komplain 10 hari, lebih dari itu tidak dilayani.',
                  style: pw.TextStyle(
                    fontSize: 7.2,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              );
              widgets.add(pw.SizedBox(height: 19));
              widgets.add(
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _signatureBlock('Diserahkan oleh', vehicle.driverName ?? 'Sopir'),
                    _signatureBlock('Diterima oleh', destinationName),
                  ],
                ),
              );

              // Garis putus-putus pemisah antar tujuan -- PENANDA VISUAL
              // saja, HANYA antar 2 tujuan dalam chunk/halaman yang SAMA.
              // TIDAK digambar setelah tujuan TERAKHIR dalam chunk ini --
              // chunk berikutnya (kalau ada) sudah pasti mulai di halaman
              // fisik baru lewat `doc.addPage`, jadi divider di sini tidak
              // relevan lagi.
              if (i < pageDestinations.length - 1) {
                widgets.add(pw.SizedBox(height: 13));
                widgets.add(_dashedDivider());
                widgets.add(pw.SizedBox(height: 13));
              }
            }

            return widgets;
          },
        ),
      );
    }

    return doc;
  }

  /// DIUBAH (8 Oktober 2026, lanjutan lagi -- lihat catatan di doc
  /// comment `buildDestinationReceiptDocument`): kolom ke-2 sekarang
  /// "Nama Barang" (dari `row['itemName']`, dikirim
  /// `ShipmentService.getManifestSummaryByDestination`), BUKAN "Jenis
  /// Tarif" lagi -- parameter `pricingTypeNameById` DIHAPUS, tidak
  /// dipakai sama sekali di fungsi ini lagi.
  /// Daftar DP per resi UNIK (dedup by `receivingId` -- `rows` di sini
  /// adalah 1 baris PER NAMA BARANG x resi, jadi 1 resi yang punya 3
  /// barang akan muncul 3x kalau tidak dedup) untuk 1 tujuan, dipakai
  /// `buildDestinationReceiptDocument` buat baris catatan di bawah
  /// "Total Tarif Tujuan Ini" (lihat doc comment pemanggilnya untuk
  /// permintaan user lengkap). HANYA resi dengan `dpAmount > 0` yang
  /// masuk -- resi DP 0 (termasuk yang Bayar Tujuan biasa TANPA DP sama
  /// sekali) SENGAJA tidak dicantumkan sama sekali, sesuai permintaan
  /// "Resi DP 0 jangan dicantumkan".
  ///
  /// 'tagihan' = `receivingTotalPrice - dpAmount` (total resi dikurangi
  /// DP yang sudah dibayar di kantor) -- MURNI informasi tambahan di
  /// catatan ini, TIDAK mengubah `billingAmount`/kolom Keterangan atau
  /// "Total Tarif Tujuan Ini" yang sudah ada di tabel atas.
  static List<Map<String, dynamic>> _destinationDpNotes(
    List<Map<String, dynamic>> rows,
  ) {
    final seenReceivingIds = <String>{};
    final notes = <Map<String, dynamic>>[];

    for (final row in rows) {
      final receivingId = row['receivingId']?.toString();
      if (receivingId == null || seenReceivingIds.contains(receivingId)) {
        continue;
      }
      seenReceivingIds.add(receivingId);

      final dpAmount = (row['dpAmount'] as num?)?.toDouble() ?? 0;
      if (dpAmount <= 0) continue;

      final receiptNumber = row['receiptNumber']?.toString() ?? '-';
      final nomorBuku = row['nomorBuku']?.toString();
      final label = (nomorBuku != null && nomorBuku.isNotEmpty)
          ? '$receiptNumber / $nomorBuku'
          : receiptNumber;
      final receivingTotalPrice =
          (row['receivingTotalPrice'] as num?)?.toDouble() ?? 0;

      notes.add({
        'label': label,
        'dpAmount': dpAmount,
        'tagihan': (receivingTotalPrice - dpAmount).clamp(0, double.infinity),
      });
    }

    return notes;
  }

  static pw.TableRow _destinationReceiptRow(Map<String, dynamic> row) {
    final receiptNumber = row['receiptNumber']?.toString() ?? '-';
    // FITUR (8 Oktober 2026 -- poin 7): nomor buku di belakang nomor resi
    // kalau ada.
    final nomorBuku = row['nomorBuku']?.toString();
    final receiptNumberLabel = (nomorBuku != null && nomorBuku.isNotEmpty)
        ? '$receiptNumber / $nomorBuku'
        : receiptNumber;
    final itemName = row['itemName']?.toString() ?? '-';
    final unitPrice = (row['unitPrice'] as num?)?.toDouble() ?? 0;
    final totalValue = (row['totalValue'] as num?)?.toDouble() ?? 0;
    // FITUR (8 Oktober 2026, lanjutan lagi -- "Cantumkan harga diskon").
    // Lihat catatan `totalDiscount` di
    // `ShipmentService.getManifestSummaryByDestination` -- `totalValue`
    // di atas SUDAH net (dikurangi diskon ini), kolom ini MURNI
    // informasi supaya penerima tahu berapa yang sudah dipotong.
    final totalDiscount = (row['totalDiscount'] as num?)?.toDouble() ?? 0;
    final koliLabel = _koliLabel(row);
    // FITUR (13 Oktober 2026 -- poin 6/7): status pembayaran + DP + (kalau
    // ini pemuatan terakhir resi ini) nilai tagihan Bayar Tujuan -- lihat
    // catatan panjang di `PdfTemplates._manifestKeteranganCell` &
    // `ShipmentService._isLastLoadingShipment`, logic SAMA PERSIS, cuma
    // sumber datanya dari `getManifestSummaryByDestination`.
    final paymentStatus =
        row['paymentStatus'] as String? ?? ReceivingPaymentStatus.bayarTujuan;
    final dpAmount = (row['dpAmount'] as num?)?.toDouble();
    final billingAmount = (row['billingAmount'] as num?)?.toDouble();

    final keteranganLines = <String>[ReceivingPaymentStatus.label(paymentStatus)];
    if (dpAmount != null && dpAmount > 0) {
      keteranganLines.add('DP ${formatRupiah(dpAmount)}');
    }
    if (billingAmount != null) {
      keteranganLines.add('Tagihan: ${formatRupiah(billingAmount)}');
    }

    // fontSize/verticalPadding dikecilkan ~20% (lihat catatan "Jarak antar
    // baris..." di `buildDestinationReceiptDocument`) -- HANYA baris tabel
    // Tanda Terima Tujuan, `_bodyCell` dokumen lain tetap pakai default.
    return pw.TableRow(
      children: [
        _bodyCell(receiptNumberLabel, fontSize: 7.6, verticalPadding: 4),
        _bodyCell(itemName, fontSize: 7.6, verticalPadding: 4),
        _bodyCell(koliLabel, align: pw.Alignment.center, fontSize: 7.6, verticalPadding: 4),
        _bodyCell(
          formatRupiah(unitPrice),
          align: pw.Alignment.centerRight,
          fontSize: 7.6,
          verticalPadding: 4,
        ),
        _bodyCell(
          totalDiscount > 0.5 ? '-${formatRupiah(totalDiscount)}' : formatRupiah(0),
          align: pw.Alignment.centerRight,
          fontSize: 7.6,
          verticalPadding: 4,
        ),
        _bodyCell(
          formatRupiah(totalValue),
          align: pw.Alignment.centerRight,
          fontSize: 7.6,
          verticalPadding: 4,
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          alignment: pw.Alignment.centerLeft,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              for (final line in keteranganLines)
                pw.Text(line, style: const pw.TextStyle(fontSize: 7)),
            ],
          ),
        ),
      ],
    );
  }

  /// Kop LENGKAP Tanda Terima Tujuan (nama/alamat/telp perusahaan + judul
  /// dokumen + nomor/tanggal shipment + info Sopir/Hp/Kendaraan/Jenis/
  /// Status) -- SEKARANG dipanggil ULANG di setiap blok tujuan di
  /// `buildDestinationReceiptDocument` (bukan 1x sebagai `header:` level
  /// halaman lagi), supaya tiap "tanda terima" per tujuan tetap
  /// lengkap/sah identitasnya sendiri walau beberapa tujuan berbagi 1
  /// halaman fisik yang sama (permintaan user 22 Sep 2026, update kedua).
  /// Isinya SAMA PERSIS dengan kop `buildManifestDocument`, cuma judul
  /// dokumennya "Tanda Terima Tujuan".
  /// Font & jarak antar baris di kop ini DIKECILKAN ~20% (`scale: 0.8`,
  /// 8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit: "perkecil
  /// jarak antar baris dan kurangi besar huruf 20% pada cetakan output
  /// Tanda Terima Tujuan. Agar menghemat Kertas") -- HANYA dokumen ini.
  /// Kop Manifes (`buildManifestDocument`, pakai fungsi yang SAMA tanpa
  /// `scale`) TIDAK terpengaruh.
  /// BUGFIX/FITUR (16 Oktober 2026 -- permintaan user eksplisit: "Pada
  /// tanda terima tujuan : Hilangkan baris status"): baris "Status"
  /// (Sedang Dimuat/Berangkat/Tiba/Dibatalkan) DIHAPUS dari kop Tanda
  /// Terima Tujuan -- HANYA dokumen ini, `buildManifestDocument`
  /// (Manifes Barang, pakai `_manifestStatusLabel` yang SAMA) TIDAK
  /// terpengaruh, baris Status di sana TETAP ada.
  static pw.Widget _buildDestinationReceiptFullHeader({
    required CompanyModel? company,
    required Uint8List? logoBytes,
    required ShipmentModel shipment,
    required VehicleModel vehicle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildCompanyHeader(
          company: company,
          logoBytes: logoBytes,
          documentTitle: 'Tanda Terima Tujuan',
          documentNumber: shipment.shipmentNumber,
          documentDate: shipment.loadedAt ?? shipment.createdAt,
          scale: 0.8,
        ),
        pw.SizedBox(height: 6),
        _buildInfoRow('Sopir', vehicle.driverName ?? '-', scale: 0.8),
        _buildInfoRow('Hp', vehicle.driverPhone ?? '-', scale: 0.8),
        _buildInfoRow('Kendaraan', vehicle.plateNumber, scale: 0.8),
        if (vehicle.vehicleType != null)
          _buildInfoRow('Jenis', vehicle.vehicleType!, scale: 0.8),
      ],
    );
  }

  /// Sub-judul inline per tujuan di dalam Tanda Terima Tujuan -- nama &
  /// alamat tujuan, ditampilkan SETELAH kop lengkap
  /// (`_buildDestinationReceiptFullHeader`) di awal blok tiap tujuan.
  ///
  /// Update (23 Sep 2026) -- permintaan user: baris "Kepada" sekarang ikut
  /// menampilkan No. HP tujuan di belakang namanya, format persis sesuai
  /// contoh user: "Kepada : (nama tujuan) / HP : 08347583475" kalau ada
  /// nomornya, atau "Kepada : (Nama tujuan) / HP ." kalau tidak ada (data
  /// `destinationPhone` null/kosong). `destinationPhone` adalah snapshot
  /// dari `receiving.destination_phone` (sama pola snapshot yang sudah
  /// dipakai `destination`/`destination_address` di dokumen ini) --
  /// diambil per baris scan lewat `ShipmentService.getManifestSummaryByDestination`.
  static pw.Widget _buildDestinationSectionHeading(
    String destinationName,
    String destinationAddress,
    String? destinationPhone,
  ) {
    final hasPhone = destinationPhone != null && destinationPhone.trim().isNotEmpty;
    final kepadaText = hasPhone
        ? 'Kepada : $destinationName / HP : $destinationPhone'
        : 'Kepada : $destinationName / HP .';

    // fontSize dikecilkan ~20% (8 Oktober 2026, lanjutan lagi -- lihat
    // catatan "Jarak antar baris..." di `buildDestinationReceiptDocument`)
    // -- fungsi ini KHUSUS dipakai Tanda Terima Tujuan saja, jadi aman
    // diubah langsung tanpa parameter `scale`.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          kepadaText,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.2),
        ),
        pw.Text(
          'Alamat: $destinationAddress',
          style: const pw.TextStyle(fontSize: 7.6),
        ),
      ],
    );
  }

  /// Garis putus-putus sederhana -- penanda pemisah visual antar-tujuan di
  /// Tanda Terima Tujuan. Dibuat manual dari deretan kotak kecil berseling
  /// warna (bukan pakai style bawaan `pw.Divider`), supaya tidak bergantung
  /// pada dukungan border dashed/dotted di versi package `pdf` yang
  /// dipakai project ini (`pdf: ^3.12.0`).
  static pw.Widget _dashedDivider() {
    return pw.Row(
      children: List.generate(60, (index) {
        return pw.Expanded(
          child: pw.Container(
            height: 0.8,
            margin: const pw.EdgeInsets.symmetric(horizontal: 1.5),
            color: index.isEven ? PdfColors.grey600 : PdfColors.white,
          ),
        );
      }),
    );
  }

  /// Blok tanda tangan sederhana (label + garis + nama) -- dipakai di
  /// bagian bawah Tanda Terima Tujuan. Font & tinggi ruang tanda tangan
  /// dikecilkan ~20% (8 Oktober 2026, lanjutan lagi -- lihat catatan
  /// "Jarak antar baris..." di `buildDestinationReceiptDocument`) --
  /// fungsi ini KHUSUS dipakai di sini, aman diubah langsung.
  static pw.Widget _signatureBlock(String label, String name) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 7.6)),
        pw.SizedBox(height: 29),
        pw.Container(width: 140, height: 0.6, color: PdfColors.black),
        pw.SizedBox(height: 2),
        pw.Text(name, style: const pw.TextStyle(fontSize: 7.2)),
      ],
    );
  }
}
