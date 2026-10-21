import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../models/company_model.dart';
import '../../models/receiving_detail_model.dart';
import '../../models/receiving_model.dart';
import '../../models/sender_model.dart';
import 'formatters.dart';
import 'pdf_templates.dart' show PdfTemplates;

/// Kumpulan fungsi murni yang menyusun perintah ESC/POS untuk printer
/// thermal Bluetooth, dipakai untuk 2 jenis cetakan:
/// - Label per box/unit barang (`buildItemLabelBytes`)
/// - Resi lengkap satu penerimaan barang (`buildReceiptBytes`)
///
/// Keduanya cuma menyusun `List<int>` byte -- pengiriman ke printer
/// dilakukan terpisah lewat `PrinterService.printBytes`.
///
/// =====================================================================
/// CATATAN UNTUK PENYESUAIAN SENDIRI (baca ini kalau mau ubah tampilan
/// cetakan thermal, mis. printer diganti / kertas diganti):
/// =====================================================================
///
/// 1) UKURAN KERTAS (`_paperSize`)
///    Paket `esc_pos_utils_plus` cuma sediakan 2 pilihan lebar kertas:
///    `PaperSize.mm58` (kertas thermal sempit, ~48mm area cetak efektif)
///    dan `PaperSize.mm80` (kertas kasir standar, ~72mm area cetak
///    efektif). Tidak ada pilihan "54mm" persis -- karena printer yang
///    dipakai sekarang pakai kertas 54mm, `mm58` adalah pilihan yang
///    paling mendekati (bukan mm80, karena teks/tabel akan kepotong di
///    kertas yang lebih sempit dari 80mm). Kalau nanti ganti printer ke
///    yang pakai kertas kasir 80mm biasa, cukup ubah baris di bawah ini
///    jadi `PaperSize.mm80`.
///
/// 2) TINGGI CETAKAN (kenapa tidak ada "tinggi label" di sini)
///    Beda dengan PDF (yang punya ukuran halaman tetap, panjang x
///    lebar), printer thermal ESC/POS TIDAK punya konsep "tinggi
///    halaman". Printer akan terus mencetak baris demi baris sampai
///    kita perintahkan `generator.cut()` -- jadi "tinggi" hasil cetak
///    ditentukan oleh BANYAKNYA baris/isi yang kita cetak, bukan oleh
///    angka konfigurasi. Kalau label fisik (60mm) yang dipakai adalah
///    jenis label sticker dengan sensor gap (printer otomatis berhenti
///    tepat di batas label), maka printer akan urus sendiri posisi
///    potongnya -- kita tinggal jaga supaya ISI (jumlah baris teks) nya
///    tidak lebih panjang dari tinggi fisik label, kalau tidak nanti
///    tulisan akan "meluber" ke label berikutnya. Kalau perlu ngirit
///    tinggi label, cara paling gampang adalah: kurangi jumlah baris
///    (mis. gabungkan 2 info jadi 1 baris), atau kecilkan
///    `generator.feed(n)` di bagian bawah fungsi (jarak kosong sebelum
///    potong kertas).
///
/// 3) HEADER PERUSAHAAN (`_printCompanyHeader`)
///    Dulu nama "TRANS" di-hardcode langsung di kode. Sekarang diambil
///    dari tabel `company` (lewat provider `companyProvider`, dibaca di
///    halaman preview lalu dioper ke sini lewat parameter `company`).
///    Kalau `company` null (mis. belum sempat ke-load / tabel kosong),
///    otomatis fallback ke teks 'TRANS' supaya cetakan tidak pernah
///    kosong. Untuk ganti apa saja yang tampil di header (nama / alamat
///    / telepon), edit fungsi `_printCompanyHeader` di bawah -- dipakai
///    bersama oleh Label & Resi supaya konsisten.
///
/// =====================================================================
class PrintTemplates {
  /// Ukuran kertas thermal. Printer yang dipakai sekarang: kertas 54mm,
  /// tinggi cetak label fisik 60mm -- `mm58` adalah pilihan bawaan
  /// package yang paling mendekati 54mm. Lihat catatan #1 di atas.
  static const PaperSize _paperSize = PaperSize.mm58;

  static Future<Generator> _generator() async {
    final profile = await CapabilityProfile.load();
    return Generator(_paperSize, profile);
  }

  /// Cetak blok header perusahaan (nama, dan opsional alamat + telepon).
  /// Dipakai bersama oleh Label & Resi supaya kop cetakan konsisten.
  ///
  /// Alamat & telepon perusahaan WAJIB tampil baik di Label maupun Resi
  /// (identitas pengirim resmi). Parameter [includeAddressPhone] tetap
  /// disediakan (default true) kalau suatu saat kamu sendiri ingin
  /// menyembunyikannya lagi di salah satu cetakan untuk hemat baris --
  /// tinggal panggil dengan `includeAddressPhone: false` di pemanggilnya.
  static List<int> _printCompanyHeader(
    Generator generator,
    CompanyModel? company, {
    bool includeAddressPhone = true,
    // Label di depan nomor telepon perusahaan. Resi pakai 'Hp.' (default),
    // Label pakai 'WA.' -- lihat pemanggilan di buildItemLabelBytes.
    String phoneLabel = 'Hp.',
  }) {
    List<int> bytes = [];

    bytes += generator.text(
      company?.name ?? 'TRANS',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    if (includeAddressPhone) {
      if (company?.address != null && company!.address!.isNotEmpty) {
        bytes += generator.text(
          company.address!,
          styles: const PosStyles(align: PosAlign.center),
        );
      }

      if (company?.phone != null && company!.phone!.isNotEmpty) {
        bytes += generator.text(
          '$phoneLabel ${company.phone}',
          styles: const PosStyles(align: PosAlign.center),
        );
      }
    }

    return bytes;
  }

  /// Label satu box/unit barang. Kalau quantity item > 1, dipanggil
  /// berkali-kali oleh pemanggil (satu kali per box) dengan [unitIndex] &
  /// [unitTotal] berbeda -- untuk item yang di-bundle (lihat
  /// `ReceivingDetailModel.bundleQuantity`), [unitTotal] = jumlah BUNDLE
  /// (mis. 4 ikat), BUKAN jumlah barang fisik (4 ikat x isi 5 = 20 barang
  /// tapi cuma 4 label yang dicetak) -- ini sengaja, supaya stiker label
  /// tidak cepat habis (per keputusan setelah uji coba lapangan: label
  /// 50mm sempat habis untuk 3 resi padahal operasional bisa sampai 30
  /// resi).
  ///
  /// NOTE: skema sekarang cuma simpan 1 baris per jenis barang (bukan per
  /// box fisik), jadi untuk quantity > 1, QR-nya dikasih akhiran
  /// `-U{unitIndex}` (mis. RESI000001-01-U1, -U2) supaya tiap box bisa
  /// dibedakan pas discan -- ini penanda tampilan saja, belum ada baris
  /// database tersendiri per box.
  ///
  /// [sender] TIDAK dipakai lagi di isi label (lihat catatan isi di
  /// bawah) -- parameternya tetap ada supaya pemanggil (label_preview_page)
  /// tidak perlu diubah kalau nanti mau ditambah balik.
  ///
  /// ====================================================================
  /// ISI LABEL (persis 4 baris + QR -- keputusan setelah uji coba
  /// lapangan, supaya tinggi label bisa dipangkas ~50% dari versi
  /// sebelumnya). Kalau mau ubah lagi nanti, edit langsung di bawah:
  ///   1) Nama perusahaan + No. WA (SATU baris gabung, TANPA alamat)
  ///   2) Nama tujuan + alamat tujuan (SATU baris gabung, pemisah " - ")
  ///   3) Nama barang + status satuan/bundle (pakai
  ///      `PdfTemplates.labelItemStatusLine`, contoh: "Ban Motor Batlax
  ///      1 ikat (isi 5)")
  ///   4) QR + kode di bawahnya
  /// Nomor resi (sebagai teks terpisah), "Box X/Y", data pengirim, HP
  /// penerima, alamat perusahaan, dan rute SENGAJA tidak dicetak lagi di
  /// label (masih ada semua di Resi, cuma dihilangkan dari Label).
  /// ====================================================================
  ///
  /// [cutAfter] (default true) -- KAPAN kertas benar-benar dipotong.
  /// Sejak perubahan "1 resi = 1 halaman cetak" (hasil uji coba
  /// lapangan: dulu tiap label dianggap 1 halaman sendiri-sendiri
  /// sehingga printer nyisain jeda/area kosong tiap ganti label di
  /// tengah satu resi), pemanggil yang mencetak BANYAK label sekaligus
  /// untuk satu resi (`LabelPreviewPage._printToThermal`) WAJIB kirim
  /// `cutAfter: false` untuk semua unit KECUALI unit yang paling
  /// terakhir dalam resi itu -- supaya kertas cuma benar-benar terpotong
  /// SATU KALI di paling akhir, dan seluruh label dalam 1 resi tercetak
  /// menyambung tanpa jeda. Kalau dipanggil satuan (bukan lewat loop
  /// banyak unit), biarkan default `true`.
  static Future<List<int>> buildItemLabelBytes({
    required ReceivingModel receiving,
    required ReceivingDetailModel item,
    required int unitIndex,
    required int unitTotal,
    SenderModel? sender,
    CompanyModel? company,
    bool cutAfter = true,
  }) async {
    final generator = await _generator();
    List<int> bytes = [];

    final qrCode =
        unitTotal > 1 ? '${item.itemCode}-U$unitIndex' : item.itemCode;

    // 1) Nama perusahaan + No. WA -- satu baris, TANPA alamat (beda
    // dengan Resi yang masih menampilkan alamat perusahaan).
    final companyLine = [
      company?.name ?? 'TRANS',
      if (company?.phone != null && company!.phone!.isNotEmpty)
        company.phone!,
    ].join(' ');

    bytes += generator.text(
      companyLine,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );

    // 2) Nama tujuan + alamat tujuan -- satu baris.
    final destinationLine = [
      receiving.destination,
      if (receiving.destinationAddress != null &&
          receiving.destinationAddress!.isNotEmpty)
        receiving.destinationAddress!,
    ].join(' - ');

    bytes += generator.text(
      destinationLine,
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.hr();

    // 3) Nama barang + status satuan/bundle. SENGAJA tidak size2 (double
    // besar) supaya teks gabungan (mis. "Ban Motor Batlax 1 ikat (isi
    // 5)") tetap muat 1 baris di kertas 54mm, tidak wrap ke banyak baris.
    bytes += generator.text(
      PdfTemplates.labelItemStatusLine(item),
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );

    bytes += generator.feed(1);

    // 4) QR + kode di bawahnya.
    bytes += generator.qrcode(qrCode, size: QRSize.size6);

    bytes += generator.text(
      qrCode,
      styles: const PosStyles(align: PosAlign.center),
    );

    if (cutAfter) {
      // Jarak kosong sebelum potong dikecilkan dari feed(2) -> feed(1),
      // bagian dari pemangkasan tinggi label ~50%. Kalau ternyata label
      // fisikmu masih kepotong/nempel ke label berikutnya, besarkan lagi
      // di sini. Lihat juga catatan #2 di atas kelas soal cara kerja
      // tinggi cetakan thermal.
      bytes += generator.feed(1);
      bytes += generator.cut();
    } else {
      // MODE KONTINYU (1 resi = 1 halaman) -- SENGAJA TIDAK cut() di
      // sini, supaya label berikutnya dalam resi yang sama langsung
      // menyambung tanpa printer nyisain jeda/area kosong. Garis putus2
      // dicetak sebagai penanda batas antar-label (bukan potongan
      // fisik) supaya tetap gampang dibedakan pas digunting manual.
      bytes += generator.hr(ch: '-');
      bytes += generator.feed(1);
    }

    return bytes;
  }

  /// Resi lengkap: info pengirim/penerima + daftar semua barang + total.
  /// Beda dengan Label, Resi tetap mencetak Rute (kalau ada) karena
  /// ruang di resi lebih longgar dan itu memang bagian dari Manifest
  /// perjalanan barang.
  static Future<List<int>> buildReceiptBytes({
    required ReceivingModel receiving,
    required SenderModel? sender,
    required List<ReceivingDetailModel> items,
    CompanyModel? company,
    Map<String, String> pricingTypeNameById = const {},
  }) async {
    final generator = await _generator();
    List<int> bytes = [];

    // Header lengkap (nama + alamat + telepon perusahaan) -- resi
    // berfungsi sebagai bukti resmi jadi identitas perusahaan perlu
    // lengkap.
    bytes += _printCompanyHeader(generator, company, includeAddressPhone: true);

    bytes += generator.text(
      'RESI PENERIMAAN BARANG',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.hr();

    // FITUR (8 Oktober 2026 -- poin 7: "pada semua cetakan printout
    // dibelakang nomor resi tambahkan nomor buku jika ada").
    bytes += generator.text(
      (receiving.nomorBuku != null && receiving.nomorBuku!.isNotEmpty)
          ? 'No. Resi : ${receiving.receiptNumber} / ${receiving.nomorBuku}'
          : 'No. Resi : ${receiving.receiptNumber}',
      styles: const PosStyles(bold: true),
    );

    bytes += generator.text('Tanggal  : ${formatDateId(receiving.receivedAt)}');

    bytes += generator.text('Pengirim : ${sender?.name ?? '-'}');

    if (sender?.phone != null) {
      bytes += generator.text('No. HP   : ${sender!.phone}');
    }

    // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs Tujuan):
    // baris "Penerima" terpisah (dulu dari receiverName manual) DIHAPUS
    // -- sudah diwakili baris "Tujuan" di bawah (satu-satunya sumber
    // data sekarang). "No. HP" sekarang dari destinationPhone (snapshot
    // data Tujuan), bukan receiverPhone manual lagi.
    bytes += generator.text('Tujuan   : ${receiving.destination}');

    if (receiving.destinationAddress != null) {
      bytes += generator.text('Alamat   : ${receiving.destinationAddress}');
    }

    if (receiving.destinationPhone != null &&
        receiving.destinationPhone!.isNotEmpty) {
      bytes += generator.text('No. HP   : ${receiving.destinationPhone}');
    }

    if (receiving.route != null) {
      bytes += generator.text('Rute     : ${receiving.route}');
    }

    bytes += generator.hr();

    // TIDAK ADA kolom/info harga sama sekali (permintaan user, 3 Oktober
    // 2026) -- resi ini dipegang/dilihat pihak luar (pengirim/tujuan),
    // harga per barang & totalnya adalah info internal yang tidak perlu
    // mereka lihat. Harus SAMA PERSIS dengan versi PDF
    // (`PdfTemplates.buildReceiptDocument`) & preview on-screen
    // (`ReceiptPreviewPage`) -- 3 tempat itu harus selalu konsisten.
    bytes += generator.row([
      PosColumn(
        text: 'Barang',
        width: 8,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'Qty',
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    for (final item in items) {
      // Nama barang digabung dengan nama tipe harganya (mis. "Air
      // Mineral" + "Perdus" -> "Air Mineral Perdus") -- tidak ada kolom
      // terpisah untuk tipe harga. Sama seperti versi PDF, lihat
      // `PdfTemplates.itemDisplayLabel` di pdf_templates.dart.
      final itemLabel = PdfTemplates.itemDisplayLabel(
        item.itemName,
        item.pricingTypeId,
        pricingTypeNameById,
      );

      bytes += generator.row([
        PosColumn(text: itemLabel, width: 8),
        PosColumn(
          text: item.quantity == item.quantity.roundToDouble()
              ? '${item.quantity.toStringAsFixed(0)} ${item.quantityUnit}'
              : '${item.quantity} ${item.quantityUnit}',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr();

    final totalQuantity = items.fold<double>(0, (sum, i) => sum + i.quantity);

    bytes += generator.row([
      PosColumn(
        text: 'Total (${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity} pcs)',
        width: 12,
        styles: const PosStyles(bold: true),
      ),
    ]);

    bytes += generator.feed(1);

    bytes += generator.qrcode(receiving.receiptNumber, size: QRSize.size6);

    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }
}
