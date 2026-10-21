import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../providers/driver_providers.dart';
import 'delivery_resi_scan_page.dart';
import 'representative_handoff_page.dart';

/// Daftar resi (tujuan) dalam manifest satu shipment, lengkap badge
/// progress berapa barang yang sudah diturunkan dari tiap resi. Satu
/// manifest bisa berisi beberapa resi tujuan berbeda -- driver/helper
/// harus pilih 1 resi dulu sebelum mulai scan turun.
class DeliveryManifestPage extends ConsumerWidget {
  final ShipmentModel shipment;

  const DeliveryManifestPage({super.key, required this.shipment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync = ref.watch(shipmentManifestByReceivingProvider(shipment.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text('Barang Sampai -- ${shipment.shipmentNumber}'),
        actions: [
          // "Selesaikan di Perwakilan" (6 Oktober 2026 lanjutan) --
          // dipakai kalau tujuan asli tutup/tidak bisa dijangkau sopir,
          // jadi barang dititip dulu di perwakilan/agen. Sengaja
          // ditaruh di app bar (bukan di dalam tiap tile resi) karena
          // mode "Per Tujuan"-nya mencakup BEBERAPA resi sekaligus --
          // lihat `RepresentativeHandoffPage`.
          IconButton(
            tooltip: 'Selesaikan di Perwakilan',
            icon: const Icon(Icons.storefront_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RepresentativeHandoffPage(shipment: shipment),
                ),
              );

              ref.invalidate(shipmentManifestByReceivingProvider(shipment.id));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: () async {
          ref.invalidate(shipmentManifestByReceivingProvider(shipment.id));
          await ref.read(shipmentManifestByReceivingProvider(shipment.id).future);
        },
        child: manifestAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Belum ada resi di manifest shipment ini.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];

                final receivingId = group['receivingId'] as String;
                final receiptNumber = (group['receiptNumber'] ?? '-').toString();
                final destination = (group['destination'] ?? '-').toString();
                final destinationAddress = group['destinationAddress'] as String?;
                final totalItems = group['totalItems'] as int;
                final deliveredItems = group['deliveredItems'] as int;
                final isComplete = totalItems > 0 && deliveredItems >= totalItems;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (isComplete ? AppColors.green : AppColors.orange)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isComplete ? Icons.check_circle_rounded : Icons.local_shipping_outlined,
                        color: isComplete ? AppColors.green : AppColors.orange,
                      ),
                    ),
                    title: Text(
                      receiptNumber,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [
                        destination,
                        if (destinationAddress != null && destinationAddress.isNotEmpty)
                          destinationAddress,
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isComplete ? AppColors.green : AppColors.blue)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$deliveredItems/$totalItems',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isComplete ? AppColors.green : AppColors.blue,
                        ),
                      ),
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeliveryResiScanPage(
                            shipment: shipment,
                            receivingId: receivingId,
                            receiptNumber: receiptNumber,
                            destination: destination,
                            destinationAddress: destinationAddress,
                            totalItems: totalItems,
                          ),
                        ),
                      );

                      ref.invalidate(shipmentManifestByReceivingProvider(shipment.id));
                    },
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
          error: (error, _) => ErrorStateView(
            title: 'Gagal memuat manifest.',
            message: error.toString(),
            onRetry: () => ref.invalidate(shipmentManifestByReceivingProvider(shipment.id)),
          ),
        ),
      ),
    );
  }
}