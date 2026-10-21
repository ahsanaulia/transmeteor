import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';

/// Detail satu resi: info tujuan, peta perbandingan lokasi (titik biru =
/// alamat resi terdaftar, titik hijau = lokasi barang saat discan turun),
/// dan daftar barang yang sudah turun.
class ResiDeliveryDetailPage extends StatelessWidget {
  final Map<String, dynamic> resi;

  const ResiDeliveryDetailPage({super.key, required this.resi});

  @override
  Widget build(BuildContext context) {
    final deliveries = (resi['deliveries'] as List).cast<Map<String, dynamic>>();
    final totalItems = resi['totalItems'] as int;
    final deliveredItems = resi['deliveredItems'] as int;
    final shipments = (resi['shipments'] as List? ?? const []).cast<Map<String, dynamic>>();
    final isSplit = shipments.length > 1;

    final markers = <MapMarkerData>[];

    if (resi['destinationLatitude'] != null && resi['destinationLongitude'] != null) {
      markers.add(MapMarkerData(
        latitude: (resi['destinationLatitude'] as num).toDouble(),
        longitude: (resi['destinationLongitude'] as num).toDouble(),
        color: AppColors.blue,
        icon: Icons.flag_rounded,
        label: 'Alamat Resi: ${resi['destination'] ?? '-'}',
      ));
    }

    for (final d in deliveries) {
      if (d['latitude'] == null || d['longitude'] == null) continue;

      markers.add(MapMarkerData(
        latitude: (d['latitude'] as num).toDouble(),
        longitude: (d['longitude'] as num).toDouble(),
        color: AppColors.green,
        icon: Icons.location_on_rounded,
        label: 'Turun: ${d['itemName'] ?? '-'}',
      ));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${resi['receiptNumber'] ?? '-'}'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildInfoCard(),
          const SizedBox(height: 16),
          const Text('Peta Lokasi', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary, fontSize: 15)),
          const SizedBox(height: 4),
          const Text(
            'Titik biru = alamat resi yang terdaftar. Titik hijau = lokasi barang saat discan turun.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          MultiMarkerMapCard(markers: markers, height: 240),
          const SizedBox(height: 16),
          Text(
            'Barang ($deliveredItems/$totalItems sudah turun)',
            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (deliveries.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: const Text('Belum ada barang dari resi ini yang discan turun.', style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            for (final d in deliveries) _buildDeliveryTile(d, isSplit),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final shipments = (resi['shipments'] as List? ?? const []).cast<Map<String, dynamic>>();
    final isSplit = shipments.length > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF172B67), Color(0xFF2469D8)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${resi['destination'] ?? '-'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          if (resi['destinationAddress'] != null) ...[
            const SizedBox(height: 4),
            Text('${resi['destinationAddress']}', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          // Resi bisa dimuat terpecah ke lebih dari 1 kendaraan (mis. resi
          // 15 kubik dimuat 2 truk 7,5 kubik masing-masing) -- TAMPILKAN
          // SEMUA kendaraan yang bawa bagian resi ini, JANGAN cuma 1,
          // supaya admin tidak salah kira seluruh resi ada di 1 truk.
          if (isSplit)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_split_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Resi ini terpecah ke ${shipments.length} kendaraan',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          if (shipments.isEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (resi['shipmentNumber'] != null) _buildInfoChip(Icons.local_shipping_rounded, '${resi['shipmentNumber']}'),
                if (resi['vehiclePlateNumber'] != null) _buildInfoChip(Icons.directions_car_rounded, '${resi['vehiclePlateNumber']}'),
                if (resi['driverName'] != null) _buildInfoChip(Icons.person_rounded, '${resi['driverName']}'),
              ],
            )
          else
            for (final s in shipments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s['shipmentNumber'] != null) _buildInfoChip(Icons.local_shipping_rounded, '${s['shipmentNumber']}'),
                    if (s['vehiclePlateNumber'] != null) _buildInfoChip(Icons.directions_car_rounded, '${s['vehiclePlateNumber']}'),
                    if (s['driverName'] != null) _buildInfoChip(Icons.person_rounded, '${s['driverName']}'),
                    _buildInfoChip(Icons.inventory_2_rounded, '${s['itemCount']} barang'),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildDeliveryTile(Map<String, dynamic> delivery, bool isSplit) {
    // Kalau resi ini terpecah ke beberapa kendaraan, tunjukkan barang ini
    // turun dari kendaraan yang mana -- supaya tidak membingungkan kalau
    // ternyata beda kendaraan dengan yang tampil di kartu info di atas.
    final vehicleLabel = delivery['vehiclePlateNumber'] ?? delivery['shipmentNumber'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.green.withOpacity(0.10))),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.check_rounded, color: AppColors.green, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${delivery['itemName'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${delivery['itemCode'] ?? '-'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                if (isSplit && vehicleLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Turun dari: $vehicleLabel',
                      style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}