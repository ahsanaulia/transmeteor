import '../core/services/supabase_service.dart';
import '../models/shipment_location_ping_model.dart';

class LocationTrackingService {
  static final _client = SupabaseService.client;

  /// Menyimpan satu titik lokasi (dipanggil tiap 15 menit selama trip
  /// berjalan, dari app Driver/Helper yang lagi dibuka).
  static Future<ShipmentLocationPingModel> recordPing({
    required String shipmentId,
    required String employeeId,
    required String roleAtPing,
    required double latitude,
    required double longitude,
    double? accuracyM,
  }) async {
    final data = {
      'shipment_id': shipmentId,
      'employee_id': employeeId,
      'role_at_ping': roleAtPing,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_m': accuracyM,
    };

    final response = await _client
        .from('shipment_location_pings')
        .insert(data)
        .select()
        .single();

    return ShipmentLocationPingModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Riwayat titik lokasi satu shipment -- buat fitur tracking manifest
  /// (gambar jejak perjalanan driver/helper di peta dashboard, nanti).
  static Future<List<ShipmentLocationPingModel>> getPingsForShipment(
    String shipmentId,
  ) async {
    final response = await _client
        .from('shipment_location_pings')
        .select()
        .eq('shipment_id', shipmentId)
        .order('recorded_at', ascending: true);

    return (response as List)
        .map((data) =>
            ShipmentLocationPingModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }
}