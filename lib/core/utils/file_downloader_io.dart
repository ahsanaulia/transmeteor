import 'dart:io';
import 'dart:typed_data';

/// Implementasi NATIVE (Android/iOS/desktop) -- fallback jaga-jaga.
/// Admin SEKARANG SELALU pakai web/Chrome (permintaan user eksplisit,
/// 10 Oktober 2026), jadi jalur ini TIDAK terpakai saat ini. Disiapkan
/// sekadar supaya `AdministrasiPage` tetap aman dikompilasi/dijalankan
/// kalau suatu saat halaman ini dibuka dari build native juga -- tulis
/// [bytes] ke file [fileName] di folder temp OS (TIDAK ada "folder
/// Download browser" di native, jadi cuma ditaruh temp; belum ada
/// mekanisme lanjutan seperti share_plus di sini karena memang belum
/// dibutuhkan).
Future<void> triggerBrowserDownload(String fileName, Uint8List bytes) async {
  final tempDir = await Directory.systemTemp.createTemp('trans_admin_download_');
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes);
}
