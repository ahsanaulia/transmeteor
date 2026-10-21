import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';

/// Satu titik marker generik untuk MultiMarkerMapCard -- beda dari
/// RouteMapCard (khusus titik tujuan warna merah), widget ini dipakai
/// untuk peta yang butuh beberapa jenis marker sekaligus (warna/ikon/label
/// beda-beda), misalnya posisi armada atau perbandingan lokasi turun vs
/// alamat resi.
class MapMarkerData {
  final double latitude;
  final double longitude;
  final Color color;
  final IconData icon;
  final String label;

  const MapMarkerData({
    required this.latitude,
    required this.longitude,
    required this.color,
    required this.icon,
    required this.label,
  });
}

class MultiMarkerMapCard extends StatelessWidget {
  final List<MapMarkerData> markers;
  final double height;
  final String emptyMessage;

  const MultiMarkerMapCard({
    super.key,
    required this.markers,
    this.height = 260,
    this.emptyMessage = 'Belum ada titik lokasi untuk ditampilkan.',
  });

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) {
      return Container(
        height: height,
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
      );
    }

    final mapMarkers = markers.map((m) {
      return Marker(
        point: LatLng(m.latitude, m.longitude),
        width: 42,
        height: 42,
        child: GestureDetector(
          onTap: () => _showInfo(context, m),
          child: Icon(m.icon, color: m.color, size: 34),
        ),
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: mapMarkers.first.point,
            initialZoom: mapMarkers.length > 1 ? 10 : 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trans.app',
            ),
            MarkerLayer(markers: mapMarkers),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, MapMarkerData marker) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(marker.label),
        content: Text(
          '${marker.latitude.toStringAsFixed(6)}, ${marker.longitude.toStringAsFixed(6)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }
}