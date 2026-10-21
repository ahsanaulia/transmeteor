import '../core/services/supabase_service.dart';

class DashboardSummary {
  final int receivingCountToday;
  final double totalQuantityToday;
  final double totalValueToday;
  final int activeShipmentCount;
  final int vehiclesInUseCount;
  final List<Map<String, dynamic>> recentReceiving;
  final List<Map<String, dynamic>> recentShipments;

  DashboardSummary({
    required this.receivingCountToday,
    required this.totalQuantityToday,
    required this.totalValueToday,
    required this.activeShipmentCount,
    required this.vehiclesInUseCount,
    required this.recentReceiving,
    required this.recentShipments,
  });
}

class DailyVolume {
  final DateTime date;
  final double totalQuantity;

  DailyVolume({required this.date, required this.totalQuantity});
}

class DashboardService {
  static final _client = SupabaseService.client;

  /// Ringkasan untuk Dashboard Overview: angka hari ini + 5 aktivitas
  /// terbaru masing-masing dari Receiving & Loading.
  static Future<DashboardSummary> getTodaySummary() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final receivingTodayResponse = await _client
        .from('receiving')
        .select('id, total_quantity, total_price')
        .gte('received_at', startOfDay.toIso8601String())
        .lt('received_at', endOfDay.toIso8601String());

    final receivingTodayRows = (receivingTodayResponse as List)
        .map((data) => Map<String, dynamic>.from(data))
        .toList();

    final totalQuantityToday = receivingTodayRows.fold<double>(
      0,
      (sum, row) => sum + ((row['total_quantity'] as num?)?.toDouble() ?? 0),
    );

    final totalValueToday = receivingTodayRows.fold<double>(
      0,
      (sum, row) => sum + ((row['total_price'] as num?)?.toDouble() ?? 0),
    );

    final activeShipmentsResponse = await _client
        .from('shipments')
        .select('id, vehicle_id')
        .inFilter('status', ['LOADING', 'DEPARTED']);

    final activeShipmentRows = (activeShipmentsResponse as List)
        .map((data) => Map<String, dynamic>.from(data))
        .toList();

    final vehiclesInUse =
        activeShipmentRows.map((row) => row['vehicle_id'] as String).toSet();

    // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs Tujuan):
    // `receiver_name` sengaja TIDAK di-select lagi (selalu null untuk
    // resi baru) -- "Resi Terbaru" di dashboard cukup nampilkan
    // `destination` (nama tujuan), sudah cukup mewakili identitas
    // penerima.
    final recentReceivingResponse = await _client
        .from('receiving')
        .select(
          'id, receipt_number, destination, total_quantity, total_price, received_at',
        )
        .order('received_at', ascending: false)
        .limit(5);

    final recentShipmentsResponse = await _client
        .from('shipments')
        .select(
          'id, shipment_number, status, destination, departed_at, created_at, vehicles(plate_number)',
        )
        .order('created_at', ascending: false)
        .limit(5);

    return DashboardSummary(
      receivingCountToday: receivingTodayRows.length,
      totalQuantityToday: totalQuantityToday,
      totalValueToday: totalValueToday,
      activeShipmentCount: activeShipmentRows.length,
      vehiclesInUseCount: vehiclesInUse.length,
      recentReceiving: (recentReceivingResponse as List)
          .map((data) => Map<String, dynamic>.from(data))
          .toList(),
      recentShipments: (recentShipmentsResponse as List)
          .map((data) => Map<String, dynamic>.from(data))
          .toList(),
    );
  }

  /// Volume barang diterima per hari, 7 hari terakhir (termasuk hari ini)
  /// -- dipakai untuk bar chart tren di Dashboard Overview.
  static Future<List<DailyVolume>> getWeeklyReceivingTrend() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 6));

    final response = await _client
        .from('receiving')
        .select('received_at, total_quantity')
        .gte('received_at', start.toIso8601String());

    final rows = (response as List)
        .map((data) => Map<String, dynamic>.from(data))
        .toList();

    final buckets = <DateTime, double>{
      for (var i = 0; i < 7; i++) start.add(Duration(days: i)): 0,
    };

    for (final row in rows) {
      final receivedAt = DateTime.parse(row['received_at']);
      final day = DateTime(receivedAt.year, receivedAt.month, receivedAt.day);

      if (buckets.containsKey(day)) {
        buckets[day] = (buckets[day] ?? 0) +
            ((row['total_quantity'] as num?)?.toDouble() ?? 0);
      }
    }

    final result = buckets.entries
        .map((e) => DailyVolume(date: e.key, totalQuantity: e.value))
        .toList();

    result.sort((a, b) => a.date.compareTo(b.date));

    return result;
  }
}