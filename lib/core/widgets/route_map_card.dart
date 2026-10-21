import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';

/// Peta OpenStreetMap nampilin titik-titik tujuan dari manifest satu
/// shipment -- dipakai driver/helper buat lihat area mana yang perlu
/// dituju supaya rute perjalanan lebih efisien.
class RouteMapCard extends StatelessWidget {
  final List<Map<String, dynamic>> points;

  const RouteMapCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final markerPoints = points
        .where((p) => p['latitude'] != null && p['longitude'] != null)
        .toList();

    if (markerPoints.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'Belum ada titik koordinat tujuan. Alamat resi di manifest ini '
          'belum ke-geocode / belum diisi manual titiknya.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
      );
    }

    final markers = markerPoints.map((p) {
      return Marker(
        point: LatLng(
          (p['latitude'] as num).toDouble(),
          (p['longitude'] as num).toDouble(),
        ),
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on, color: AppColors.red, size: 36),
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: markers.first.point,
            initialZoom: markers.length > 1 ? 10 : 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trans.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }
}