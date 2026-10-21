import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_downloader.dart';
import '../../../core/widgets/widgets.dart';
import '../../../services/shipment_service.dart';

/// Halaman "Administrasi" -- daftar menu untuk tugas administratif
/// berkala yang tidak masuk kategori operasional/monitoring (permintaan
/// user eksplisit, 10 Oktober 2026). Menu PERTAMA: "Unduh Semua Foto
/// Barang Sampai" -- bucket Storage Supabase gratis cuma 500 MB, jadi
/// foto bukti penyelesaian manual (`url_foto_selesai`, fitur #15) perlu
/// diunduh admin lalu DIHAPUS dari Supabase secara berkala supaya
/// storage tidak penuh. Dibuat sebagai halaman daftar menu tersendiri
/// (bukan 1 tombol langsung di Dashboard) supaya menu administratif
/// lain yang mungkin ditambahkan nanti punya tempat yang jelas.
///
/// **PLATFORM (klarifikasi user eksplisit): "admin tidak pakai HP tetapi
/// laptop dengan chrome ... admin buka web versi. Jadi mengenai HPnya
/// tidak masalah"** -- halaman ini SELALU dipakai dari browser desktop,
/// JADI unduh file lewat `triggerBrowserDownload` (lihat
/// `core/utils/file_downloader.dart`, implementasi web via Blob + `<a
/// download>`), BUKAN lewat share sheet native (`share_plus`) yang
/// cuma relevan di HP. Karena browser TIDAK pernah kasih callback
/// "berhasil disimpan" ke JS, konfirmasi "file sudah benar-benar
/// tersimpan" dimintakan MANUAL ke admin lewat dialog SEBELUM lanjut
/// menghapus apa pun dari Supabase -- lihat `_confirmFilesSaved`.
class AdministrasiPage extends StatefulWidget {
  const AdministrasiPage({super.key});

  @override
  State<AdministrasiPage> createState() => _AdministrasiPageState();
}

class _AdministrasiPageState extends State<AdministrasiPage> {
  bool _isBusy = false;
  String? _busyMessage;

  // ============================================================
  // UNDUH SEMUA FOTO BARANG SAMPAI -> HAPUS DARI SUPABASE
  // ============================================================

  Future<void> _confirmAndDownloadCompletionPhotos() async {
    List<Map<String, dynamic>> photos;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Memeriksa foto yang tersimpan...';
    });

    try {
      photos = await ShipmentService.getCompletionPhotosToArchive();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showSnackBar('Gagal memeriksa daftar foto: $e', AppColors.red);
      return;
    }

    if (!mounted) return;
    setState(() => _isBusy = false);

    if (photos.isEmpty) {
      _showSnackBar(
        'Tidak ada Foto Barang Sampai yang tersimpan di Supabase saat ini.',
        AppColors.blue,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unduh Semua Foto Barang Sampai?'),
        content: Text(
          'Ditemukan ${photos.length} foto bukti penyelesaian ("Barang '
          'Sampai") yang masih tersimpan di Supabase Storage.\n\n'
          'Setiap foto akan diunduh otomatis ke folder Download browser '
          'Anda (nama file = nomor resi). Kalau Chrome menampilkan izin '
          '"download beberapa file", pilih Izinkan supaya semua foto '
          'terunduh.\n\n'
          'SETELAH diunduh, foto-foto ini akan DIHAPUS PERMANEN dari '
          'Supabase -- penyimpanan gratis Supabase cuma 500 MB, jadi '
          'harus dibersihkan berkala. Riwayat scan (jam, lokasi, siapa '
          'yang mencatat) TIDAK ikut terhapus, cuma file fotonya.\n\n'
          'Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Ya, Unduh & Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _downloadAndArchive(photos);
  }

  Future<void> _downloadAndArchive(List<Map<String, dynamic>> photos) async {
    setState(() {
      _isBusy = true;
      _busyMessage = 'Mengunduh 0/${photos.length} foto...';
    });

    final usedNames = <String>{};
    // url Supabase -> nama file yang berhasil dipicu unduhannya, dipakai
    // menentukan foto mana saja yang boleh dihapus setelah admin
    // konfirmasi manual semuanya benar-benar tersimpan.
    final downloaded = <String, String>{};
    final failed = <String>[];

    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final url = photo['url'] as String;
      final receiptNumber = photo['receiptNumber']?.toString();

      if (mounted) {
        setState(() {
          _busyMessage = 'Mengunduh ${i + 1}/${photos.length} foto...';
        });
      }

      final fileName = await _downloadOne(
        url: url,
        preferredBaseName: (receiptNumber == null || receiptNumber.isEmpty)
            ? 'BARANG_SAMPAI_${i + 1}'
            : receiptNumber,
        usedNames: usedNames,
      );

      if (fileName == null) {
        failed.add(receiptNumber ?? url);
      } else {
        downloaded[url] = fileName;
      }
    }

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _busyMessage = null;
    });

    if (downloaded.isEmpty) {
      _showSnackBar(
        'Semua foto gagal diunduh (${failed.length} gagal) -- tidak ada '
        'yang dihapus dari Supabase.',
        AppColors.red,
      );
      return;
    }

    // Browser TIDAK kasih callback "berhasil disimpan" ke kode ini --
    // jadi konfirmasi terakhir dimintakan MANUAL ke admin, SEBELUM
    // lanjut menghapus apa pun dari Supabase. Lihat doc comment kelas
    // di atas.
    final filesSaved = await _confirmFilesSaved(downloaded.length, failed);
    if (filesSaved != true) {
      _showSnackBar(
        'Tidak dihapus. ${downloaded.length} foto TETAP ada di Supabase -- '
        'ulangi menu ini nanti kalau sudah siap.',
        AppColors.orange,
      );
      return;
    }

    await _deleteFromSupabase(downloaded, photos, failed);
  }

  Future<bool?> _confirmFilesSaved(int downloadedCount, List<String> failed) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File sudah tersimpan?'),
        content: Text(
          '$downloadedCount file foto sudah dikirim ke folder Download '
          'browser Anda (atau dialog "Simpan Sebagai", sesuai setting '
          'Chrome).\n\n'
          'Cek dulu folder Download -- pastikan semua file benar-benar '
          'ada sebelum lanjut.'
          '${failed.isNotEmpty ? '\n\n${failed.length} foto GAGAL diunduh '
              '(${failed.join(', ')}) -- foto itu TIDAK akan dihapus dari '
              'Supabase, cuma yang berhasil diunduh.' : ''}'
          '\n\nKalau sudah yakin tersimpan, lanjutkan hapus $downloadedCount '
          'foto ini dari Supabase?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Belum, Jangan Hapus'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Sudah, Hapus dari Supabase'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromSupabase(
    Map<String, String> downloaded,
    List<Map<String, dynamic>> photos,
    List<String> failedDownloads,
  ) async {
    setState(() {
      _isBusy = true;
      _busyMessage = 'Menghapus foto dari Supabase...';
    });

    var deletedCount = 0;
    final deleteFailed = <String>[];

    for (final entry in downloaded.entries) {
      final url = entry.key;
      final receiptNumber = photos.firstWhere(
        (p) => p['url'] == url,
        orElse: () => const {},
      )['receiptNumber']?.toString();

      try {
        await ShipmentService.deleteCompletionPhoto(url);
        deletedCount++;
      } catch (e) {
        deleteFailed.add(receiptNumber ?? url);
      }
    }

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _busyMessage = null;
    });

    final messageParts = <String>[
      '$deletedCount foto berhasil diunduh & dihapus dari Supabase.',
    ];
    if (failedDownloads.isNotEmpty) {
      messageParts.add(
        '${failedDownloads.length} gagal diunduh: ${failedDownloads.join(', ')}.',
      );
    }
    if (deleteFailed.isNotEmpty) {
      messageParts.add(
        '${deleteFailed.length} gagal dihapus dari Supabase (sudah '
        'terunduh, coba lagi nanti): ${deleteFailed.join(', ')}.',
      );
    }

    _showSnackBar(
      messageParts.join(' '),
      failedDownloads.isEmpty && deleteFailed.isEmpty
          ? AppColors.green
          : AppColors.orange,
      durationSeconds: 6,
    );
  }

  /// Unduh 1 foto lewat `http` (cross-platform, dipakai lewat XHR/fetch
  /// di web -- TIDAK pakai `dart:io` sama sekali di halaman ini) lalu
  /// picu browser menyimpannya lewat `triggerBrowserDownload`. Nama
  /// file = NOMOR RESI (permintaan user eksplisit), dibersihkan dari
  /// karakter tidak valid. Kalau beberapa foto kebetulan dari resi yang
  /// sama (resi yang diselesaikan lewat beberapa kali submit terpisah),
  /// file berikutnya diberi suffix `_2`, `_3`, dst supaya tidak saling
  /// menimpa di folder Download. Return nama file yang berhasil
  /// dipakai, atau null kalau unduhannya gagal.
  Future<String?> _downloadOne({
    required String url,
    required String preferredBaseName,
    required Set<String> usedNames,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final ext = url.toLowerCase().endsWith('.png') ? 'png' : 'jpg';

      var baseName = preferredBaseName.replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '_');
      if (baseName.isEmpty) baseName = 'BARANG_SAMPAI';

      var fileName = '$baseName.$ext';
      var suffix = 2;
      while (usedNames.contains(fileName)) {
        fileName = '${baseName}_$suffix.$ext';
        suffix++;
      }
      usedNames.add(fileName);

      await triggerBrowserDownload(fileName, response.bodyBytes);

      return fileName;
    } catch (_) {
      return null;
    }
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
          'Administrasi',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(18),
              children: [
                MenuActionCard(
                  icon: Icons.cloud_download_rounded,
                  title: 'Unduh Semua Foto Barang Sampai',
                  subtitle:
                      'Unduh ke komputer lalu hapus dari Supabase (storage '
                      'gratis cuma 500 MB)',
                  accentColor: AppColors.red,
                  dense: true,
                  onTap: _isBusy ? null : _confirmAndDownloadCompletionPhotos,
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
}
