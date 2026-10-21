import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/item_type_model.dart';
import '../../../models/pricing_type_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/receiving_detail_providers.dart';
import '../../../services/receiving_service.dart';
import '../widgets/receiving_detail_form_sheet.dart';

/// Halaman detail satu item barang -- dipakai dari 2 tempat: dari daftar
/// item di ReceivingDetailPage (dashboard), dan dari daftar item manifest
/// di ManifestPage (loading). Kalau dibuka dari manifest, info scan
/// (nomor box & waktu discan) ikut ditampilkan lewat parameter opsional.
///
/// Ditambahkan 21 September 2026 -- "Ubah Harga (Admin)": admin sebagai
/// otoritas tertinggi butuh bisa mengubah harga barang di resi APAPUN
/// statusnya, termasuk yang sudah "sampai" (delivered). CATATAN PENTING
/// (supaya tidak salah edit lagi): file INI (`lib/features/receiving/
/// pages/receiving_item_detail_page.dart`) adalah yang BENERAN dipakai
/// (di-import oleh `receiving_detail_page.dart` dashboard DAN
/// `manifest_page.dart` loading). Ada file duplikat TIDAK TERPAKAI di
/// `lib/features/dashboard/pages/receiving_item_detail_page.dart` --
/// jangan tertukar edit di situ lagi, tidak ada satupun import yang
/// menunjuk ke sana.
///
/// DIPERLUAS (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
/// "Editing di sisi Admin ... Saya ingin bisa mengubah dan menghapus
/// barang: Mengubah Nama Barang (interfensi admin) / Mengubah Jumlah /
/// Mengubah Harga / dan Menambah Barang Baru"). Tombol "Ubah Harga" yang
/// lama SEBENARNYA sudah membuka form LENGKAP (`ReceivingDetailFormSheet`
/// -- nama, jumlah, harga semua bisa diubah), cuma labelnya menyesatkan
/// (seolah cuma harga) & belum ada tombol hapus -- makanya di sini
/// labelnya diganti "Edit Barang" & ditambah tombol "Hapus Barang".
/// "Menambah Barang Baru" SENGAJA ditaruh di `ReceivingDetailPage`
/// (dashboard, pemilik daftar "Daftar Barang"), BUKAN di sini -- karena
/// aksi tambah tidak terikat ke satu barang yang sedang dilihat.
///
/// KONSTRAIN PENTING dari user: "barang ini sudah dimuat diloading. Jadi
/// tidak boleh ada loading ulang" -- lihat `ReceivingService.
/// getLoadedUnitCount`/`loadedUnitCountProvider`. Kalau SEBAGIAN unit
/// fisik barang ini sudah discan LOAD ke kendaraan: (a) jumlah tidak
/// boleh dikurangi di bawah angka itu (ditegakkan di
/// `ReceivingDetailFormSheet._save` lewat `minQuantity`), dan (b) baris
/// ini tidak boleh dihapus sama sekali (dicegah di `_confirmDeleteItem`
/// di bawah, DAN ditegakkan ganda oleh database lewat FK violation --
/// `shipment_scans.receiving_detail_id` menolak hapus baris yang masih
/// direferensikan). Nama & harga TETAP bebas diubah kapan pun, karena
/// mengubahnya tidak membuat scan yang sudah ada jadi tidak valid.
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

  // ============================================================
  // EDIT BARANG (ADMIN) -- lihat doc comment class di atas.
  // ============================================================

  Future<void> _openAdminEditSheet(
    BuildContext context,
    WidgetRef ref,
    ReceivingDetailModel item,
  ) async {
    // Ambil angka "sudah dimuat" LANGSUNG dari server di saat tombol
    // ditekan (bukan dari provider yang di-watch, yang bisa saja masih
    // `loading`/belum invalidate) -- supaya guard "tidak boleh loading
    // ulang" di ReceivingDetailFormSheet selalu pakai data paling baru.
    int loadedCount = 0;
    try {
      loadedCount = await ReceivingService.getLoadedUnitCount(item.id);
    } catch (_) {
      // Gagal ambil angka ini TIDAK boleh menghalangi admin mengubah
      // nama/harga sama sekali (lihat aturan standing "admin harus punya
      // fungsi tertinggi") -- anggap 0 (tidak ada guard tambahan), toh
      // database tetap jadi jaring pengaman terakhir untuk hapus.
      loadedCount = 0;
    }

    if (!context.mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceivingDetailFormSheet(
        receivingId: item.receivingId,
        existing: item,
        allowTotalOverride: true,
        minQuantity: loadedCount.toDouble(),
      ),
    );

    if (saved == true) {
      ref.invalidate(receivingDetailByIdProvider(receivingDetailId));
      ref.invalidate(receivingDetailsProvider(item.receivingId));
      ref.invalidate(loadedUnitCountProvider(receivingDetailId));
    }
  }

  // ============================================================
  // HAPUS BARANG (ADMIN) -- lihat doc comment class di atas.
  // ============================================================

  Future<void> _confirmDeleteItem(
    BuildContext context,
    WidgetRef ref,
    ReceivingDetailModel item,
  ) async {
    int loadedCount = 0;
    try {
      loadedCount = await ReceivingService.getLoadedUnitCount(item.id);
    } catch (_) {
      loadedCount = 0;
    }

    if (!context.mounted) return;

    if (loadedCount > 0) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Tidak Bisa Dihapus'),
          content: Text(
            '$loadedCount unit dari "${item.itemName}" sudah dimuat ke '
            'kendaraan. Barang yang sudah discan tidak boleh dihapus '
            '(riwayat manifest tidak boleh hilang) -- nama/jumlah/harga '
            'masih bisa diubah lewat "Edit Barang".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus Barang Ini?'),
        content: Text(
          '"${item.itemName}" (${_formatQuantity(item.quantity)} '
          '${item.quantityUnit}) akan DIHAPUS PERMANEN dari resi ini. Aksi '
          'ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ReceivingService.deleteReceivingDetail(item.id);

      ref.invalidate(receivingDetailsProvider(item.receivingId));

      if (!context.mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.itemName}" dihapus.')),
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;

      final isForeignKeyViolation = e.code == '23503';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isForeignKeyViolation
                ? 'Barang ini tidak bisa dihapus karena sudah pernah '
                    'discan ke sebuah pengiriman (riwayat manifest tidak '
                    'boleh hilang).'
                : 'Gagal menghapus barang: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menghapus barang: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(receivingDetailByIdProvider(receivingDetailId));
    final itemTypesAsync = ref.watch(itemTypesProvider);
    final pricingTypesAsync = ref.watch(pricingTypesProvider);
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
          if (currentItem != null && scanUnitCode == null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _openAdminEditSheet(context, ref, currentItem),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit Barang'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  backgroundColor: AppColors.blue.withOpacity(0.10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                tooltip: 'Hapus Barang',
                onPressed: () => _confirmDeleteItem(context, ref, currentItem),
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
              ),
            ),
          ],
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
          // FITUR (8 Oktober 2026, lanjutan lagi -- "tidak boleh ada
          // loading ulang"): tampilkan DI BADAN HALAMAN juga (bukan cuma
          // di dalam sheet edit) kalau sebagian barang ini sudah dimuat --
          // supaya admin tahu batasannya SEBELUM menekan "Edit Barang"/
          // "Hapus Barang", bukan baru ketahuan setelah ditolak.
          final loadedCountAsync =
              ref.watch(loadedUnitCountProvider(receivingDetailId));
          final loadedCount = loadedCountAsync.value ?? 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            children: [
              _buildHeaderCard(item),
              const SizedBox(height: 16),
              if (scanUnitCode != null) ...[
                _buildScanInfoCard(),
                const SizedBox(height: 16),
              ],
              if (scanUnitCode == null && loadedCount > 0) ...[
                InfoBanner(
                  variant: InfoBannerVariant.warning,
                  message:
                      '$loadedCount dari ${_formatQuantity(item.quantity)} '
                      '${item.quantityUnit} barang ini sudah dimuat ke '
                      'kendaraan -- tidak bisa dihapus, dan jumlahnya tidak '
                      'bisa dikurangi di bawah $loadedCount.',
                ),
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
          // FITUR (8 Oktober 2026, lanjutan lagi -- diskon per barang,
          // "Pada Monitoring Resi bagian Editing"). Baris ini cuma
          // tampil kalau barang ini memang punya diskon (> 0) -- barang
          // tanpa diskon (mayoritas, termasuk SEMUA resi lama dari
          // sebelum fitur ini ada) tampilannya tidak berubah sama sekali.
          if (item.discountAmount > 0.5) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.discountPercent > 0
                      ? 'Diskon (${_formatQuantity(item.discountPercent)}%)'
                      : 'Diskon',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                ),
                Text(
                  '-${formatRupiah(item.discountAmount)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
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