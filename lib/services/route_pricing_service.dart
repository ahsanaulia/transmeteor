import '../core/services/supabase_service.dart';
import '../models/route_pricing_model.dart';

class RoutePricingService {
  static final _client = SupabaseService.client;

  static Future<List<RoutePricingModel>>
      getRoutePricings() async {
    final response = await _client
        .from('route_pricing')
        .select()
        .eq('is_active', true)
        .order('route_name', ascending: true);

    return (response as List)
        .map(
          (data) => RoutePricingModel.fromMap(
            Map<String, dynamic>.from(data),
          ),
        )
        .toList();
  }

  static Future<RoutePricingModel?> getRoutePricingById(
    String id,
  ) async {
    final response = await _client
        .from('route_pricing')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return RoutePricingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<RoutePricingModel?> getRoutePricingByCode(
    String routeCode,
  ) async {
    final response = await _client
        .from('route_pricing')
        .select()
        .eq('route_code', routeCode)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return RoutePricingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<RoutePricingModel> createRoutePricing({
    required String routeCode,
    required String routeName,
    required double price,
  }) async {
    final response = await _client
        .from('route_pricing')
        .insert({
          'route_code': routeCode,
          'route_name': routeName,
          'price': price,
          'is_active': true,
        })
        .select()
        .single();

    return RoutePricingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<RoutePricingModel> updateRoutePricing({
    required String id,
    required String routeCode,
    required String routeName,
    required double price,
  }) async {
    final response = await _client
        .from('route_pricing')
        .update({
          'route_code': routeCode,
          'route_name': routeName,
          'price': price,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();

    return RoutePricingModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deactivateRoutePricing(
    String id,
  ) async {
    await _client
        .from('route_pricing')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }
}