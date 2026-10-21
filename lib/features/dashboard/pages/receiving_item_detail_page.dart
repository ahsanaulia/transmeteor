import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/item_type_model.dart';
import '../../../models/pricing_type_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/storage_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/receiving_detail_providers.dart';
import '../../receiving/widgets/receiving_detail_form_sheet.dart';

/// Halaman detail satu item barang -- dipakai dari 2 tempat: dari daftar
/// item di ReceivingDetailPage (dashboard), dan dari daftar item manifest
/// di ManifestPage (loading). Kalau dibuka dari manifest, info scan
/// (nomor box & waktu discan) ikut ditampilkan lewat parameter opsional.
///
/// Ditambahkan 21 September 2026 -- "Ubah Harga (Admin)": admin sebagai
/// otoritas tertinggi butuh bisa mengubah harga barang di resi APAPUN
/// statusnya, termasuk yang sudah "sampai" (delivered). Halaman ini dibuka
/// dari alur Monitoring Resi (dashboard) yang memang tidak pernah mengecek
/// status resi/shipment sama sekali -- jadi cukup buka
/// [ReceivingDetailFormSheet] yang sudah ada (dipakai juga oleh staff
/// Receiving) dalam mode edit dari sini. Tidak ada gate status yang perlu
/// dilepas karena memang dari awal tidak ada satupun gate seperti itu di
/// ReceivingService/ReceivingDetailFormSheet -- yang belum ada cuma
/// entry point admin-nya (staff biasanya cuma sempat edit dari halaman
/// "Detail Barang" operasional sebelum resi dikirim, jarang balik lagi ke
/// resi lama).
class ReceivingItemDetailPage extends ConsumerWidget {
  final String receivingDetailId;
  final String? scanUnitCode;
  final int? scanUnitIndex;
  final DateTime? scannedAt;

  const ReceivingItemDetailPage({
    super.key,
    required this.receivingDetailId,
    this.scanUnitCode,
    this.scanUnitIndex,
    this.scannedAt,
  });

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  String _formatDateTime(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m/${date.year} $h:$min';
  }

  String? _findItemTypeName(List<ItemTypeModel>? items, String id) {
    if (items == null) return null;
    for (final item in items) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  String? _findPricingTypeName(List<PricingTypeModel>? items, String id) {
    if (items == null) return null;
    for (final item in items) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  // FITUR (13 Oktober 2026, permintaan user "Tambahan Fitur" poin 1):
  // lookup nama zona storage -- pakai [allStoragesProvider] (bukan cuma
  // yang aktif) supaya zona yang sudah dinonaktifkan tetap bisa
  // ditampilkan namanya untuk barang lama (history lokasi barang).
  String? _findStorageName(List<StorageModel>? storages, String? id) {
    if (storages == null || id == null) return null;
    for (final storage in storages) {
      if (storage.id == id) return storage.namaZona;
    }
    return null;
  }

  // ============================================================
  // UBAH HARGA (ADMIN) -- lihat doc comment class di atas.
  // ============================================================

  Future<void> _openAdminEditSheet(
    BuildContext context,
    WidgetRef ref,
    ReceivingDetailModel item,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceivingDetailFormSheet(
        receivingId: item.receivingId,
        existing: item,
      ),
    );

    if (saved == true) {
      ref.invalidate(receivingDetailByIdProvider(receivingDetailId));
      ref.invalidate(receivingDetailsProvider(item.receivingId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(receivingDetailByIdProvider(receivingDetailId));
    final itemTypesAsync = ref.watch(itemTypesProvider);
    final pricingTypesAsync = ref.watch(pricingTypesProvider);
    final storagesAsync = ref.watch(allStoragesProvider);
    final currentItem = detailAsync.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detail Barang'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // scanUnitCode terisi cuma kalau halaman ini dibuka dari
          // ManifestPage (Loading) -- tombol admin ini sengaja HANYA
          // ditampilkan kalau dibuka dari alur dashboard (Monitoring Resi),
          // bukan dari alur loading/manifest staff biasa.
          if (currentItem != null && scanUnitCode == null)
            IconButton(
              tooltip: 'Ubah Harga (Admin)',
              onPressed: () => _openAdminEditSheet(context, ref, currentItem),
              icon: const Icon(Icons.edit_rounded, color: AppColors.blue),
            ),
        ],
      ),
      body: detailAsync.when(
        data: (item) {
          if (item == null) {
            return const ErrorStateView(title: 'Data barang tidak ditemukan.');
          }

          final itemTypeName = _findItemTypeName(itemTypesAsync.value, item.itemTypeId);
          final pricingTypeName =
              _findPricingTypeName(pricingTypesAsync.value, item.pricingTypeId);
          final storageName = _findStorageName(storagesAsync.value, item.storageId);

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            children: [
              _buildHeaderCard(item),
              const SizedBox(height: 16),
              if (scanUnitCode != null) ...[
                _buildScanInfoCard(),
                const SizedBox(height: 16),
              ],
              _buildSection(
                icon: Icons.category_rounded,
                color: AppColors.blue,
                title: 'Identitas Barang',
                rows: [
                  _InfoRow('Kode Barang', item.itemCode),
                  _InfoRow('Jenis Barang', itemTypeName ?? '-'),
                  _InfoRow('Tipe Harga', pricingTypeName ?? '-'),
                  _InfoRow(
                    'Kuantitas',
                    '${_formatQuantity(item.quantity)} ${item.quantityUnit}',
                  ),
                  // FITUR (13 Oktober 2026, poin 1): zona storage sebagai
                  // history lokasi barang -- SELALU tampil kalau
                  // storage_id terisi, terlepas dari status resi saat
                  // ini (diterima/loading/tiba).
                  _InfoRow(
                    'Zona Storage',
                    item.storageId == null
                        ? 'Belum ditentukan'
                        : (storageName ?? 'Zona tidak ditemukan'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (item.weightKg != null ||
                  item.lengthCm != null ||
                  item.widthCm != null ||
                  item.heightCm != null ||
                  item.volumeM3 != null) ...[
                _buildSection(
                  icon: Icons.straighten_rounded,
                  color: AppColors.cyan,
                  title: 'Ukuran & Berat',
                  rows: [
                    if (item.weightKg != null) _InfoRow('Berat', '${item.weightKg} kg'),
                    if (item.lengthCm != null || item.widthCm != null || item.heightCm != null)
                      _InfoRow(
                        'Dimensi (P×L×T)',
                        '${item.lengthCm ?? '-'} × ${item.widthCm ?? '-'} × ${item.heightCm ?? '-'} cm',
                      ),
                    if (item.volumeM3 != null) _InfoRow('Volume', '${item.volumeM3} m³'),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              _buildPriceCard(item),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat detail barang.',
          message: error.toString(),
          onRetry: () => ref.invalidate(receivingDetailByIdProvider(receivingDetailId)),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ReceivingDetailModel item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue, AppColors.cyan],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              item.itemCode,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.itemName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatQuantity(item.quantity)} ${item.quantityUnit}',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildScanInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.orange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: AppColors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scanUnitIndex != null && scanUnitIndex! > 1
                      ? 'Box ke-$scanUnitIndex • $scanUnitCode'
                      : scanUnitCode ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                if (scannedAt != null)
                  Text(
                    'Discan ${_formatDateTime(scannedAt!)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color color,
    required String title,
    required List<_InfoRow> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(row.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  Expanded(
                    child: Text(row.value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(ReceivingDetailModel item) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF172B67), Color(0xFF2469D8)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Harga', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Harga Satuan', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
              Text(
                formatRupiah(item.unitPrice ?? 0),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Harga', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              Text(
                formatRupiah(item.totalPrice ?? 0),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;

  _InfoRow(this.label, this.value);
}