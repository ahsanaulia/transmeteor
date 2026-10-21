import 'dart:html' as html;
import 'dart:typed_data';

/// Implementasi WEB (Chrome/browser lain) -- dipakai admin, SELALU
/// lewat laptop + Chrome (permintaan user eksplisit, 10 Oktober 2026:
/// "admin buka web versi. Jadi mengenai HPnya tidak masalah").
///
/// Picu browser men-download [bytes] sebagai file bernama [fileName]
/// lewat Blob + elemen `<a download>` sementara (dibuat, diklik,
/// langsung dibuang) -- cara standar trigger download di web TANPA
/// server, tidak perlu endpoint/backend khusus. Hasilnya file masuk ke
/// folder Download default Chrome, ATAU memunculkan dialog "Simpan
/// Sebagai" bawaan OS kalau setting "Ask where to save each file"
/// Chrome admin aktif.
///
/// TIDAK ADA callback "berhasil disimpan" yang bisa dibaca JS biasa
/// dari sini (keterbatasan browser, bukan keterbatasan kode ini) --
/// begitu `anchor.click()` jalan tanpa exception, browser DIANGGAP
/// sudah menerima perintah unduh. Pemanggil (`AdministrasiPage`) yang
/// bertanggung jawab minta konfirmasi manual ke admin SEBELUM lanjut
/// menghapus data di Supabase, lihat dialog "File sudah tersimpan?" di
/// sana.
Future<void> triggerBrowserDownload(String fileName, Uint8List bytes) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);
}
