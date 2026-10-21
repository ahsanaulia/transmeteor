import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'company_service.dart';
import 'gps_tracking_task_handler.dart';

/// Wrapper kontrol Android Foreground Service tracking GPS, dipanggil
/// dari isolate UI (DriverHomePage). Logika PENGAMBILAN LOKASI &
/// PENGIRIMAN PING sendiri ada di [GpsTrackingTaskHandler] yang jalan
/// di isolate background terpisah -- lihat file itu untuk penjelasan
/// lengkap kenapa arsitektur ini diperlukan.
class GpsForegroundService {
  /// Interval default (detik) kalau data company belum sempat kebaca /
  /// belum ada baris company sama sekali -- 900 detik = 15 menit, nilai
  /// aman untuk produksi (hemat baterai & kuota data sopir).
  static const int _defaultIntervalSeconds = 900;

  /// Konfigurasi `FlutterForegroundTask` (channel notifikasi + interval
  /// repeat). AMAN dipanggil berkali-kali -- ini cuma menyetel opsi
  /// statis untuk `startService()` berikutnya, tidak benar-benar
  /// menyalakan apa pun sendiri. Sengaja dipanggil ULANG tiap kali
  /// [start] dijalankan (baca komentar di [start]) supaya perubahan
  /// interval di halaman "Profil Perusahaan" bisa langsung kepakai
  /// tanpa perlu restart aplikasi.
  static void _configure(int intervalSeconds) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'trans_gps_tracking',
        channelName: 'Tracking Perjalanan TRANS',
        channelDescription:
            'Notifikasi ini muncul selama perjalanan berlangsung, supaya '
            'lokasi kendaraan tetap terkirim otomatis walau aplikasi '
            'diminimize atau layar HP terkunci.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Interval kirim lokasi -- dulu di-hardcode 900 detik (15 menit)
        // langsung di kode. Sekarang dibaca dari kolom
        // `company.gps_ping_interval_seconds` (lihat _resolveIntervalSeconds)
        // supaya admin bisa isi angka kecil (mis. 1/10 detik) lewat
        // halaman "Profil Perusahaan" khusus untuk uji coba lapangan,
        // tanpa perlu ubah kode & build ulang tiap kali mau uji coba.
        eventAction: ForegroundTaskEventAction.repeat(intervalSeconds * 1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Ambil interval (detik) dari data company terbaru. Kalau gagal
  /// fetch (mis. tidak ada koneksi internet pas mau mulai perjalanan)
  /// atau kolomnya belum ke-set, fallback ke [_defaultIntervalSeconds]
  /// -- JANGAN sampai gagal fetch bikin tracking gagal total.
  static Future<int> _resolveIntervalSeconds() async {
    try {
      final company = await CompanyService.getCompany();
      final seconds = company?.gpsPingIntervalSeconds;

      if (seconds != null && seconds > 0) return seconds;
    } catch (_) {
      // Fallback ke default di bawah.
    }

    return _defaultIntervalSeconds;
  }

  /// Dipanggil di `DriverHomePage.initState()` -- pasang konfigurasi
  /// AWAL (pakai interval default) secepatnya supaya
  /// `FlutterForegroundTask` sudah siap sebelum data company sempat
  /// kebaca. Interval SEBENARNYA yang dipakai saat tracking betulan
  /// mulai selalu di-refresh lagi di [start] (baca komentar di sana).
  static void init() => _configure(_defaultIntervalSeconds);

  /// Minta izin notifikasi (Android 13+) & minta pengguna mematikan
  /// battery optimization untuk app ini. Keduanya perlu supaya Android
  /// tidak "membekukan" service tracking di tengah jalan. Izin LOKASI
  /// (termasuk "izinkan selalu"/background) ditangani terpisah lewat
  /// LocationHelper.requestBackgroundLocationPermission -- dipanggil
  /// sebelum method ini di alur "Mulai Perjalanan" DriverHomePage.
  static Future<void> requestPermissions() async {
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  /// Mulai (atau lanjutkan) tracking GPS untuk satu shipment. Dipanggil
  /// saat driver menekan "Mulai Perjalanan", dan juga dipanggil ulang
  /// dari DriverHomePage._resumeTrackingIfNeeded kalau ternyata
  /// perjalanan sudah aktif tapi halaman baru dibuka/dibuka ulang --
  /// dicek dulu apa service sudah jalan, kalau sudah cukup update data
  /// shipment/employee-nya saja tanpa restart notifikasi.
  static Future<void> start({
    required String shipmentId,
    required String employeeId,
  }) async {
    // Baca interval TERBARU dari company tiap kali mau mulai/resume --
    // supaya kalau admin baru saja ubah "Interval Kirim Lokasi" di
    // halaman Profil Perusahaan (mis. dari 900 detik produksi jadi 10
    // detik buat uji coba), PERJALANAN BERIKUTNYA langsung pakai nilai
    // baru tanpa perlu restart aplikasi.
    //
    // CATATAN PENTING: kalau service SUDAH jalan (perjalanan sedang
    // berlangsung saat pengaturan diubah), konfigurasi baru ini TIDAK
    // mengubah jadwal service yang sudah telanjur start -- Android
    // foreground service yang sedang aktif tetap pakai interval saat dia
    // pertama kali di-start. Interval baru baru betul-betul kepakai di
    // perjalanan berikutnya ("Sudah Kembali ke Kantor" lalu "Mulai
    // Perjalanan" lagi).
    final intervalSeconds = await _resolveIntervalSeconds();
    _configure(intervalSeconds);

    await FlutterForegroundTask.saveData(
      key: kGpsTaskShipmentIdKey,
      value: shipmentId,
    );
    await FlutterForegroundTask.saveData(
      key: kGpsTaskEmployeeIdKey,
      value: employeeId,
    );

    if (await FlutterForegroundTask.isRunningService) {
      // Sudah jalan -- data barusan sudah diperbarui di atas, TaskHandler
      // otomatis pakai nilai baru di ping berikutnya. Tidak perlu
      // restart notifikasi/service (lihat catatan interval di atas).
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 2025,
      notificationTitle: 'Tracking perjalanan aktif',
      notificationText: 'Lokasi kendaraan terkirim otomatis tiap $intervalSeconds detik.',
      serviceTypes: const [ForegroundServiceTypes.location],
      callback: gpsTrackingCallback,
    );
  }

  /// Hentikan tracking -- dipanggil saat driver menekan
  /// "Sudah Kembali ke Kantor".
  static Future<void> stop() async {
    await FlutterForegroundTask.removeData(key: kGpsTaskShipmentIdKey);
    await FlutterForegroundTask.removeData(key: kGpsTaskEmployeeIdKey);
    await FlutterForegroundTask.stopService();
  }
}
