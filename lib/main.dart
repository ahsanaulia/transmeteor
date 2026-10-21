import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/supabase_service.dart';
import 'features/auth/pages/splash_page.dart';
import 'providers/realtime_sync_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wajib dipanggil di awal main() (sebelum runApp) supaya isolate UI
  // bisa terima data dari GpsTrackingTaskHandler yang jalan di isolate
  // background lewat FlutterForegroundTask.sendDataToMain() -- lihat
  // lib/services/gps_foreground_service.dart & gps_tracking_task_handler.dart.
  //
  // `flutter_foreground_task` HANYA support Android/iOS -- TIDAK ada
  // implementasi untuk web. Kalau dipanggil tanpa syarat di web (mis. build
  // web yang di-deploy ke Netlify), baris ini crash sebelum runApp() sempat
  // jalan sehingga layar tetap putih kosong (blank screen, tanpa pesan
  // error apa pun yang terlihat user -- cuma ada exception di console).
  // Makanya WAJIB di-skip di web lewat kIsWeb.
  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
  }

  await SupabaseService.initialize();

  runApp(
    const ProviderScope(
      child: TransApp(),
    ),
  );
}

class TransApp extends ConsumerWidget {
  const TransApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nyalakan sinkronisasi realtime SEKALI untuk seluruh app, di-watch
    // di root widget supaya tetap hidup selama app berjalan (bukan
    // nyala-mati tiap pindah halaman) -- lihat RealtimeSyncService untuk
    // daftar lengkap tabel & provider yang disinkronkan. Efeknya: semua
    // halaman yang pakai data dari tabel-tabel itu otomatis ter-refresh
    // begitu ada perubahan di Supabase (insert/update/delete dari device
    // lain, web, atau Supabase dashboard) -- TANPA perlu pull-to-refresh
    // manual.
    ref.watch(realtimeSyncProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TRANS LOGISTICS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}
