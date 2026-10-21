import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../providers/monitoring_providers.dart';
import 'resi_delivery_detail_page.dart';

/// Status pengiriman semua resi (Monitoring Resi Sampai) -- tap salah
/// satu untuk lihat detail item & lokasi turun vs alamat resi di peta.
class ResiDeliveryMonitoringPage extends ConsumerWidget {
  const ResiDeliveryMonitoringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resiAsync = ref.watch(resiDeliveryMonitoringProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Monitoring Resi Sampai'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: () async {
          ref.invalidate(resiDeliveryMonitoringProvider);
          await ref.read(resiDeliveryMonitoringProvider.future);
        },
        child: resiAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Belum ada resi yang sudah dimuat ke kendaraan.',
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
                final totalItems = group['totalItems'] as int;
                final deliveredItems = group['deliveredItems'] as int;
                final isComplete = totalItems > 0 && deliveredItems >= totalItems;
                final isPartial = deliveredItems > 0 && !isComplete;
                // Resi ini dimuat terpecah ke lebih dari 1 kendaraan (mis.
                // resi 15 kubik dimuat 2 truk 7,5 kubik masing-masing) --
                // JANGAN tampilkan 1 nama sopir tunggal kalau begini, bisa
                // menyesatkan (kelihatan seolah semua barang ada di 1 truk).
                final shipments =
                    (group['shipments'] as List? ?? const []).cast<Map<String, dynamic>>();
                final isSplit = group['isSplitAcrossShipments'] == true;

                final color =
                    isComplete ? AppColors.green : (isPartial ? AppColors.orange : AppColors.textSecondary);
                final label = isComplete ? 'Semua Sampai' : (isPartial ? 'Sebagian Sampai' : 'Belum Turun');

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(
                        isComplete ? Icons.check_circle_rounded : Icons.local_shipping_outlined,
                        color: color,
                      ),
                    ),
                    title: Text('${group['receiptNumber'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${group['destination'] ?? '-'}'
                          '${!isSplit && group['driverName'] != null ? ' • ${group['driverName']}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        if (isSplit)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '⚠ Terpecah ke ${shipments.length} kendaraan',
                              style: const TextStyle(
                                color: AppColors.orange,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            '$deliveredItems/$totalItems',
                            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(label, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ResiDeliveryDetailPage(resi: group)),
                      );
                    },
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
          error: (error, _) => ErrorStateView(
            title: 'Gagal memuat monitoring resi.',
            message: error.toString(),
            onRetry: () => ref.invalidate(resiDeliveryMonitoringProvider),
          ),
        ),
      ),
    );
  }
}