import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Helper cek izin & ambil posisi GPS sekali jalan -- dipakai di
/// DriverHomePage/HelperHomePage (tracking 15 menit), form pengeluaran
/// (lokasi otomatis saat submit), dan modul Destination (lokasi
/// petugas saat scan barang tiba).
class LocationHelper {
  /// Balikin `null` kalau service lokasi mati atau izin ditolak -- pesannya
  /// sudah ditampilkan lewat SnackBar, pemanggil cukup cek null.
  ///
  /// GPS yang baru saja diaktifkan/baru dapat izin sering butuh beberapa
  /// detik untuk "cold start" sebelum bisa memberi fix -- percobaan
  /// pertama Geolocator.getCurrentPosition() gampang timeout di kondisi
  /// ini walau GPS sebenarnya baik-baik saja. Supaya tombol tidak
  /// terasa "gagal diam-diam lalu berhasil di percobaan kedua", helper
  /// ini otomatis retry sekali dengan jeda singkat sebelum benar-benar
  /// melempar null ke pemanggil.
  static Future<Position?> getCurrentPosition(
    BuildContext context, {
    bool isRetry = false,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      _showMessage(context, 'Aktifkan GPS/Lokasi di HP dulu.');
      return null;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showMessage(context, 'Izin lokasi ditolak, tidak bisa mencatat posisi.');
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      if (!isRetry) {
        // Percobaan pertama gagal (biasanya GPS belum "warm up") --
        // beri tahu pengguna lalu coba sekali lagi otomatis, jangan
        // langsung menyerah supaya tombol tidak terasa gagal diam-diam.
        if (context.mounted) {
          _showMessage(context, 'Mencoba mengambil lokasi lagi...');
        }

        await Future.delayed(const Duration(seconds: 2));

        if (!context.mounted) return null;

        return getCurrentPosition(context, isRetry: true);
      }

      // Percobaan kedua juga gagal -- coba fallback ke lokasi terakhir
      // yang diketahui HP (kurang akurat, tapi lebih baik daripada
      // gagal total, terutama untuk titik pertama tracking perjalanan).
      final lastKnown = await Geolocator.getLastKnownPosition();

      if (lastKnown != null) {
        if (context.mounted) {
          _showMessage(
            context,
            'Pakai lokasi terakhir yang diketahui HP (GPS lambat merespons).',
          );
        }
        return lastKnown;
      }

      if (context.mounted) {
        _showMessage(context, 'Gagal mengambil lokasi: $e');
      }
      return null;
    }
  }

  /// Minta izin lokasi "Izinkan selalu" / background (`ACCESS_BACKGROUND_
  /// LOCATION`) -- WAJIB untuk tracking GPS lewat Foreground Service
  /// (lihat GpsForegroundService) supaya lokasi tetap bisa diambil walau
  /// app di-minimize/layar dikunci. Dipanggil sebelum
  /// GpsForegroundService.start() di alur "Mulai Perjalanan".
  ///
  /// CATATAN Android 11+: begitu sudah punya izin "saat digunakan"
  /// (whileInUse), OS TIDAK akan menampilkan dialog lagi untuk upgrade ke
  /// "selalu" -- pengguna wajib buka Pengaturan HP manual & pilih "Izinkan
  /// sepanjang waktu". Kalau requestPermission() balikin whileInUse
  /// (bukan always) di sini, helper otomatis buka halaman pengaturan app
  /// supaya driver tidak perlu cari sendiri.
  ///
  /// Balikin true kalau izin background berhasil didapat (atau memang
  /// sudah ada sebelumnya), false kalau belum/gagal -- pemanggil boleh
  /// tetap lanjut jalan (tracking foreground/whileInUse tetap jalan
  /// selagi app dibuka), cuma kasih tahu risikonya lewat pesan yang
  /// sudah ditampilkan helper ini.
  static Future<bool> requestBackgroundLocationPermission(
    BuildContext context,
  ) async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      // Izin dasar (whileInUse) saja belum ada -- jangan lanjut minta
      // background, biar pesannya tidak membingungkan.
      return false;
    }

    if (permission == LocationPermission.always) {
      return true;
    }

    // permission == whileInUse -- coba minta upgrade ke always. Di
    // Android 11+ ini biasanya TIDAK memunculkan dialog baru (batasan
    // OS), jadi hasilnya kemungkinan besar tetap whileInUse -- makanya
    // diarahkan ke Pengaturan HP sebagai fallback.
    permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.always) {
      return true;
    }

    if (context.mounted) {
      _showMessage(
        context,
        'Supaya lokasi tetap terkirim walau HP terkunci/aplikasi '
        'diminimize, buka Pengaturan > Izin > Lokasi lalu pilih '
        '"Izinkan sepanjang waktu".',
      );
      await Geolocator.openAppSettings();
    }

    return false;
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
