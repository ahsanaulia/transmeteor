import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../core/services/supabase_service.dart';
import 'location_tracking_service.dart';

// Kunci penyimpanan data yang di-share antara isolate UI (main) dan
// isolate background (TaskHandler) lewat FlutterForegroundTask.saveData/
// getData -- HARUS sama persis dengan yang dipakai di
// gps_foreground_service.dart.
const kGpsTaskShipmentIdKey = 'trans_gps_shipment_id';
const kGpsTaskEmployeeIdKey = 'trans_gps_employee_id';

// Ditambahkan setelah ditemukan kasus nyata di lapangan: tracking "aktif"
// di layar Driver (notifikasi jalan terus) TAPI titik lokasi tidak pernah
// sampai ke server -- sebelumnya _sendPing() nelan semua error diam-diam
// (catch (_) {}) jadi TIDAK ADA cara buat tahu penyebabnya (izin lokasi
// ditolak, RLS Supabase, tidak ada internet, dll). Sekarang error terakhir
// disimpan lewat FlutterForegroundTask.saveData (persisten walau app
// ditutup) supaya kelihatan di kartu tracking DriverHomePage.
const kGpsLastPingErrorKey = 'trans_gps_last_ping_error';
const kGpsLastPingErrorAtKey = 'trans_gps_last_ping_error_at';

/// Callback top-level, titik masuk isolate background tempat TaskHandler
/// benar-benar jalan -- WAJIB `@pragma('vm:entry-point')` supaya tidak
/// di-strip Dart tree-shaking saat build release, dan WAJIB top-level
/// (bukan method di dalam class) karena dipanggil dari isolate terpisah
/// yang tidak share memori dengan isolate UI.
@pragma('vm:entry-point')
void gpsTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTrackingTaskHandler());
}

/// TaskHandler yang jalan di dalam Android Foreground Service --
/// INI YANG MENGGANTIKAN `Timer.periodic` lama di DriverHomePage.
///
/// Kenapa perlu diganti: `Timer.periodic` biasa cuma hidup selama widget
/// Flutter-nya ada di foreground. Begitu app di-minimize atau layar HP
/// dikunci, Android men-suspend/mem-freeze isolate Dart-nya -- timer
/// berhenti jalan diam-diam. Ini akar masalah "update lokasi mobil bisa
/// sampai 12 jam" dari hasil uji coba lapangan tahap 1. Foreground
/// Service (lewat notifikasi persisten) adalah cara resmi Android
/// supaya proses background tetap dikasih waktu CPU & tidak dibunuh.
///
/// shipmentId/employeeId TIDAK disimpan sebagai parameter constructor
/// karena instance class ini bisa dibuat ulang oleh plugin di isolate
/// baru (mis. kalau Android sempat mematikan lalu menghidupkan ulang
/// service-nya) -- makanya dibaca dari `FlutterForegroundTask.getData()`
/// (persisten, disimpan plugin sendiri) tiap kali `onStart` dipanggil.
class GpsTrackingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // PENTING -- AKAR MASALAH nyata yang ditemukan 7 September 2026:
    // `gpsTrackingCallback()` di atas adalah entry point isolate BARU,
    // TERPISAH TOTAL dari isolate UI yang menjalankan `main()` /
    // `SupabaseService.initialize()`. Isolate baru ini tidak mewarisi
    // apa pun dari isolate UI -- termasuk singleton `Supabase.instance`.
    // Sebelum baris ini ditambahkan, `LocationTrackingService.recordPing()`
    // (lewat `SupabaseService.client` -> `Supabase.instance.client`)
    // langsung lempar `LateInitializationError: Field 'client' has not
    // been initialized` di isolate ini -- karena `Supabase.initialize()`
    // memang belum pernah dipanggil sama sekali di isolate ini. Errornya
    // ADA (bukan ping gagal karena RLS/lokasi), tapi sebelumnya ditelan
    // diam-diam oleh `catch (_) {}` lama sehingga tidak pernah kelihatan.
    //
    // `Supabase.initialize()` aman dipanggil ulang di isolate BARU
    // (bukan isolate yang sama dengan yang UI pakai) -- sesi login yang
    // sudah tersimpan otomatis ke-restore dari local storage (disk),
    // JADI insert ping tetap tercatat sebagai user yang sedang login
    // (bukan anon), sesuai kebutuhan policy RLS `to authenticated`.
    //
    // Dibungkus try/catch supaya kalau ternyata GAGAL (jangan sampai
    // terjadi, tapi jaga-jaga), `onStart` tidak crash tak tertangani --
    // `_sendPing()` di bawah tetap akan mencoba jalan & pesan errornya
    // (kalau ada) tetap tertangkap+tersimpan oleh catch block di sana.
    try {
      await SupabaseService.initialize();
    } catch (_) {
      // Diamkan di sini -- _sendPing() akan gagal lagi kalau client
      // memang belum siap, dan KALI ITU errornya tertangkap+disimpan.
    }

    // Titik pertama langsung dikirim saat service mulai jalan, jangan
    // nunggu interval repeat pertama -- sama seperti perilaku
    // Timer.periodic lama (_startTrackingTimer memanggil _sendPing
    // sebelum Timer.periodic-nya sendiri jalan).
    await _sendPing();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Dipanggil otomatis tiap 15 menit sesuai `ForegroundTaskOptions.
    // eventAction` yang di-set di GpsForegroundService.init().
    _sendPing();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Sengaja TIDAK menghapus data shipmentId/employeeId di sini --
    // penghapusan hanya lewat GpsForegroundService.stop() (dipanggil
    // saat driver benar-benar menekan "Sudah Kembali ke Kantor"), supaya
    // kalau service ini mati sendiri karena error/dibunuh sistem, data
    // trip yang sedang berjalan tidak ikut hilang percuma.
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}

  Future<void> _sendPing() async {
    // BUG NYATA KEDUA yang ditemukan (9 September 2026, lewat kotak error
    // merah yang sama): `shipmentId`/`employeeId` DULU cuma dibaca SEKALI
    // di `onStart()` lalu disimpan di field instance -- tapi kalau
    // service ini SUDAH JALAN dari trip sebelumnya (belum sempat
    // benar-benar berhenti/`onStart` tidak dipanggil ulang) saat sopir
    // mulai trip BARU, `GpsForegroundService.start()` cuma memperbarui
    // data PERSISTEN (`FlutterForegroundTask.saveData`) tanpa me-restart
    // service -- field instance yang lama TETAP terpakai (comment lama di
    // situ bilang "TaskHandler otomatis pakai nilai baru", TAPI kodenya
    // sendiri tidak pernah benar-benar baca ulang, jadi klaim itu salah).
    // Akibatnya: ping dikirim terus pakai `shipment_id` dari trip LAMA
    // (bisa jadi sudah tidak ada lagi / diganti trip baru), Supabase
    // menolak dengan `PostgrestException ... violates foreign key
    // constraint ... shipment_id ... is not present in table "shipments"`.
    // Fix: baca ulang dari data PERSISTEN di SETIAP ping (bukan cuma
    // sekali di onStart), supaya selalu ikut shipment/employee TERBARU
    // yang di-saveData oleh GpsForegroundService.start().
    final shipmentId =
        await FlutterForegroundTask.getData<String>(key: kGpsTaskShipmentIdKey);
    final employeeId =
        await FlutterForegroundTask.getData<String>(key: kGpsTaskEmployeeIdKey);
    if (shipmentId == null || employeeId == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );

      await LocationTrackingService.recordPing(
        shipmentId: shipmentId,
        employeeId: employeeId,
        roleAtPing: 'DRIVER',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
      );

      // Ping ini berhasil -- hapus catatan error terakhir (kalau ada dari
      // ping sebelumnya yang gagal) supaya kartu tracking tidak terus
      // menampilkan error lama padahal sekarang sudah normal lagi.
      await FlutterForegroundTask.removeData(key: kGpsLastPingErrorKey);
      await FlutterForegroundTask.removeData(key: kGpsLastPingErrorAtKey);

      // Kirim balik ke isolate UI (kalau app-nya lagi dibuka) supaya
      // kartu tracking di DriverHomePage bisa update jam "Titik terakhir
      // dikirim pukul ..." tanpa perlu polling sendiri. Lihat
      // GpsForegroundService & DriverHomePage._listenTrackingUpdates.
      FlutterForegroundTask.sendDataToMain({
        'type': 'ping_sent',
        'timestampMillis': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      // PENTING: dulu error di sini ditelan diam-diam (catch (_) {}), jadi
      // kalau ping gagal terus-menerus (izin lokasi dicabut, RLS Supabase
      // menolak insert, tidak ada internet, dll) TIDAK ADA cara untuk tahu
      // kenapa -- notifikasi tracking tetap terlihat "aktif" padahal tidak
      // ada satu pun titik yang sampai ke server. Sekarang pesan errornya
      // disimpan (persisten, lewat saveData) supaya DriverHomePage bisa
      // menampilkannya ke sopir/kelihatan saat didiagnosis dari jarak jauh.
      final timestampMillis = DateTime.now().millisecondsSinceEpoch;
      await FlutterForegroundTask.saveData(
        key: kGpsLastPingErrorKey,
        value: e.toString(),
      );
      await FlutterForegroundTask.saveData(
        key: kGpsLastPingErrorAtKey,
        value: timestampMillis,
      );

      FlutterForegroundTask.sendDataToMain({
        'type': 'ping_failed',
        'error': e.toString(),
        'timestampMillis': timestampMillis,
      });
      // Tetap tidak fatal -- service jalan terus, coba lagi di ping
      // berikutnya (sama seperti perilaku lama).
    }
  }
}
