import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';

/// Halaman penuh buat pilih titik koordinat tujuan secara manual -- tap
/// di peta buat naruh pin, geser/zoom peta buat cari lokasi yang tepat,
/// lalu konfirmasi lewat tombol di bawah. Dipakai sebagai fallback kalau
/// geocoding otomatis dari teks alamat tidak akurat / tidak ketemu.
class DestinationPickerMapPage extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const DestinationPickerMapPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<DestinationPickerMapPage> createState() =>
      _DestinationPickerMapPageState();
}

class _DestinationPickerMapPageState extends State<DestinationPickerMapPage> {
  // Default: tengah Indonesia, dipakai kalau belum ada titik awal sama sekali.
  static const _defaultCenter = LatLng(-2.5, 118.0);

  late LatLng _picked;

  @override
  void initState() {
    super.initState();
    _picked = (widget.initialLatitude != null && widget.initialLongitude != null)
        ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
        : _defaultCenter;
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initialLatitude != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Titik Tujuan'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: hasInitial ? 14 : 4.5,
              onTap: (tapPosition, point) {
                setState(() => _picked = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trans.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _picked,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_on, color: AppColors.red, size: 40),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Tap di peta untuk menaruh titik lokasi tujuan.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: PrimaryButton(
            label: 'Gunakan Titik Ini',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(_picked),
          ),
        ),
      ),
    );
  }
}