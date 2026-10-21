import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
// import '../../../core/utils/print_templates.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/receiving_model.dart';
import '../../../models/sender_model.dart';
import '../../../providers/master_data_providers.dart';
// import '../../../providers/printer_provider.dart';
import '../../../providers/receiving_detail_providers.dart';
// import '../../../services/printer_service.dart';
import '../../../services/receiving_service.dart';
// import '../../printing/widgets/printer_connect_sheet.dart';
import '../widgets/receiving_detail_form_sheet.dart';
import '../../printing/pages/label_preview_page.dart';
import '../../printing/pages/receipt_preview_page.dart';

/// Halaman daftar & kelola detail barang (receiving_details) untuk satu
/// resi. Dibuka otomatis setelah resi berhasil disimpan (tombol
/// "Tambah Barang" di SuccessResultDialog pada receiving_create_page).
class ReceivingItemsPage extends ConsumerWidget {
  final ReceivingModel receiving;

  const ReceivingItemsPage({super.key, required this.receiving});

  // ============================================================
  // ADD / EDIT / DELETE ITEM
  // ============================================================

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref) async {
    final currentItems =
        ref.read(receivingDetailsProvider(receiving.id)).value ?? [];

    final sequence = currentItems.length + 1;
    final itemCode =
        '${receiving.receiptNumber}-${sequence.toString().padLeft(2, '0')}';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceivingDetailFormSheet(
        receivingId: receiving.id,
        itemCodeForNew: itemCode,
      ),
    );

    if (saved == true) {
      ref.invalidate(receivingDetailsProvider(receiving.id));
    }
  }

  Future<void> _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    ReceivingDetailModel detail,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceivingDetailFormSheet(
        receivingId: receiving.id,
        existing: detail,
      ),
    );

    if (saved == true) {
      ref.invalidate(receivingDetailsProvider(receiving.id));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ReceivingDetailModel detail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Hapus Barang'),
          content: Text(
            'Yakin mau hapus "${detail.itemName}" dari resi ini?',
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
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ReceivingService.deleteReceivingDetail(detail.id);
      ref.invalidate(receivingDetailsProvider(receiving.id));
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menghapus barang: $e')));
    }
  }

  // ============================================================
  // PRINTER
  // ============================================================

  // ============================================================
  // PRINT PREVIEW NAVIGATION
  // ============================================================

  Future<void> _openLabelPreview(
    BuildContext context,
    WidgetRef ref,
    List<ReceivingDetailModel> items,
  ) async {
    final senders = await ref.read(sendersProvider.future);

    SenderModel? sender;
    for (final s in senders) {
      if (s.id == receiving.senderId) {
        sender = s;
        break;
      }
    }

    if (!context.mounted) return;

    // Barang "Tanpa Label QR" (23 September 2026) SENGAJA dikecualikan
    // dari label yang dicetak -- memang tujuannya tidak ada label sama
    // sekali untuk barang ini (lihat ReceivingDetailModel.isUnlabeled).
    // Filter di sini (bukan di dalam LabelPreviewPage) supaya
    // LabelPreviewPage tetap murni "render apa yang dikasih", tidak perlu
    // tahu soal konsep unlabeled.
    final labelableItems = items.where((item) => !item.isUnlabeled).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LabelPreviewPage(
          receiving: receiving,
          items: labelableItems,
          sender: sender,
        ),
      ),
    );
  }

  Future<void> _openReceiptPreview(
    BuildContext context,
    WidgetRef ref,
    List<ReceivingDetailModel> items,
  ) async {
    final senders = await ref.read(sendersProvider.future);

    SenderModel? sender;
    for (final s in senders) {
      if (s.id == receiving.senderId) {
        sender = s;
        break;
      }
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptPreviewPage(
          receiving: receiving,
          sender: sender,
          items: items,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(receivingDetailsProvider(receiving.id));
    final items = detailsAsync.value ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          icon: const Icon(Icons.close_rounded, color: AppColors.navy),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detail Barang',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              receiving.receiptNumber,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context, ref),
        backgroundColor: AppColors.blue,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Barang'),
      ),
      bottomNavigationBar: _buildPrintBar(context, ref, items),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: _buildHeaderInfoCard(ref),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: detailsAsync.when(
                data: (items) => _buildBody(context, ref, items),
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat detail barang',
                  message: error.toString(),
                  onRetry: () =>
                      ref.invalidate(receivingDetailsProvider(receiving.id)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER INFO
  // ============================================================

  Widget _buildHeaderInfoCard(WidgetRef ref) {
    final sendersAsync = ref.watch(sendersProvider);

    String senderName = 'Memuat...';

    if (sendersAsync.hasValue) {
      SenderModel? sender;
      for (final s in sendersAsync.value!) {
        if (s.id == receiving.senderId) {
          sender = s;
          break;
        }
      }
      senderName = sender?.name ?? '-';
    } else if (sendersAsync.hasError) {
      senderName = '-';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('No. Resi', receiving.receiptNumber, bold: true),
          const SizedBox(height: 8),
          _buildInfoRow('Pengirim', senderName),
          const SizedBox(height: 8),
          // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs
          // Tujuan): "Penerima" di sini sekarang bersumber dari
          // receiving.destination (nama tujuan), bukan lagi receiverName
          // manual (field itu sudah dihapus dari form input).
          _buildInfoRow('Penerima', receiving.destination),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Alamat',
            receiving.destinationAddress ?? receiving.destination,
          ),
          if (receiving.destinationPhone != null &&
              receiving.destinationPhone!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Hp', receiving.destinationPhone!),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Text(':  ', style: TextStyle(color: AppColors.textSecondary)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 15 : 13,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRINT BAR
  // ============================================================

  Widget _buildPrintBar(
    BuildContext context,
    WidgetRef ref,
    List<ReceivingDetailModel> items,
  ) {
    final hasItems = items.isNotEmpty;
    // "Tanpa Label QR" (23 September 2026) -- tombol "Cetak Label" HANYA
    // aktif kalau ada minimal 1 barang yang MEMANG perlu label (bukan
    // unlabeled). "Cetak Resi" tetap pakai hasItems biasa karena resi
    // mencakup semua barang apa pun status labelnya.
    final hasLabelableItems = items.any((item) => !item.isUnlabeled);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: hasLabelableItems
                      ? () => _openLabelPreview(context, ref, items)
                      : null,
                  icon: const Icon(Icons.label_outline_rounded),
                  label: const Text('Cetak Label'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: hasItems
                      ? () => _openReceiptPreview(context, ref, items)
                      : null,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Cetak Resi'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ITEM LIST
  // ============================================================

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<ReceivingDetailModel> items,
  ) {
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: AppColors.textSecondary.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada barang',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap "Tambah Barang" untuk mulai mencatat isi resi ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    final totalQuantity = items.fold<double>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final totalPrice = items.fold<double>(
      0,
      (sum, item) => sum + (item.totalPrice ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
      children: [
        _buildSummaryCard(items.length, totalQuantity, totalPrice),
        const SizedBox(height: 16),
        for (final item in items) ...[
          _buildItemCard(context, ref, item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(
    int itemCount,
    double totalQuantity,
    double totalPrice,
  ) {
    return AppCard(
      child: Row(
        children: [
          Expanded(child: _buildSummaryStat('Jenis Barang', '$itemCount')),
          Container(width: 1, height: 34, color: AppColors.border),
          Expanded(
            child: _buildSummaryStat(
              'Total Qty',
              totalQuantity == totalQuantity.roundToDouble()
                  ? totalQuantity.toStringAsFixed(0)
                  : totalQuantity.toString(),
            ),
          ),
          Container(width: 1, height: 34, color: AppColors.border),
          Expanded(
            child: _buildSummaryStat('Total Harga', formatRupiah(totalPrice)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    WidgetRef ref,
    ReceivingDetailModel item,
  ) {
    return AppCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openEditSheet(context, ref, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.itemName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _confirmDelete(context, ref, item),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.red,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              item.itemCode,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTag(
                  '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toStringAsFixed(0) : item.quantity} '
                  '${item.quantityUnit}',
                  AppColors.blue,
                ),
                // "Tanpa Label QR" (23 September 2026) -- penanda visual
                // supaya staff langsung tahu barang ini TIDAK ikut di
                // "Cetak Label" (lihat _openLabelPreview/_buildPrintBar),
                // dan Loading/Delivery-nya pakai tombol manual, bukan
                // scan QR.
                if (item.isUnlabeled)
                  _buildTag('Tanpa Label QR', AppColors.red),
                if (item.isBundle)
                  _buildTag(
                    'isi ${item.bundleQuantity}/${item.quantityUnit}',
                    AppColors.orange,
                  ),
                if (item.weightKg != null)
                  _buildTag('${item.weightKg} kg', AppColors.violet),
                if (item.volumeM3 != null)
                  _buildTag(
                    '${item.volumeM3!.toStringAsFixed(3)} m³',
                    AppColors.cyan,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  formatRupiah(item.unitPrice ?? 0),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  formatRupiah(item.totalPrice ?? 0),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}