import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/realtime_sync_service.dart';

/// Provider tunggal yang menyalakan [RealtimeSyncService] untuk seluruh
/// aplikasi. Sengaja `Provider` biasa (bukan autoDispose) supaya sekali
/// dinyalakan, koneksi realtime-nya HIDUP TERUS selama app berjalan
/// (di-watch sekali di root widget `TransApp`, lihat lib/main.dart) --
/// bukan nyala-mati tiap kali pindah halaman.
final realtimeSyncProvider = Provider<RealtimeSyncService>((ref) {
  final service = RealtimeSyncService(ref);
  service.start();

  ref.onDispose(service.dispose);

  return service;
});
