import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/receiving_model.dart';
import '../services/dashboard_service.dart';
import '../services/receiving_service.dart';

/// Ringkasan angka untuk Dashboard Overview (hari ini + aktivitas terbaru).
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) {
  return DashboardService.getTodaySummary();
});

/// Tren volume barang 7 hari terakhir -- untuk bar chart di Overview.
final weeklyReceivingTrendProvider = FutureProvider<List<DailyVolume>>((ref) {
  return DashboardService.getWeeklyReceivingTrend();
});

/// Semua resi -- dipakai di halaman Monitoring Resi ADMIN
/// (`ReceivingListPage`). Monitoring Resi SUPERVISOR (`SupervisorResiTab`)
/// TIDAK LAGI pakai provider ini sejak 16 Oktober 2026 (lazy-load +
/// pencarian server-side, lihat `ReceivingService.getReceivingsPage`) --
/// provider ini SENGAJA dipertahankan apa adanya utk Admin, scope
/// perubahan baru Supervisor dulu (lihat Tambahan #39 dokumentasi).
final allReceivingsProvider = FutureProvider<List<ReceivingModel>>((ref) {
  return ReceivingService.getReceivings();
});

/// Jumlah resi per status (`computed_status`) -- badge angka di chip
/// filter status `SupervisorResiTab`. Lihat doc comment
/// `ReceivingService.getReceivingStatusCounts`.
final receivingStatusCountsProvider = FutureProvider<Map<String, int>>((ref) {
  return ReceivingService.getReceivingStatusCounts();
});