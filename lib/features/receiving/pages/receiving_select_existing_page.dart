import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/receiving_model.dart';
import '../../../providers/dashboard_providers.dart';
import 'receiving_items_page.dart';

/// Daftar SEMUA resi (bukan cuma punya staff yang login) -- dipakai dari
/// menu "Tambah Barang ke Resi Lama" di ReceivingHomePage. Sebelum ada
/// halaman ini, satu-satunya jalan untuk isi/tambah barang ke resi ada di
/// ReceivingItemsPage yang cuma kebuka otomatis SEKALI, tepat setelah resi
/// baru dibuat (lewat SuccessResultDialog di ReceivingCreatePage) -- kalau
/// staff belum sempat isi semua barangnya saat itu (mis. barang datang
/// bertahap, atau ditinggal dulu), tidak ada cara lain untuk balik lagi ke
/// resi yang sama.
///
/// Tap satu resi di sini langsung buka ReceivingItemsPage yang SAMA persis
/// dipakai waktu resi baru dibuat -- tambah/ubah/hapus barang jalan seperti
/// biasa, TIDAK ADA gate status (resi RECEIVED lama pun tetap bisa ditambah
/// barangnya, sesuai pola "jangan mencegat flow aplikasi" yang sudah
/// dipakai di seluruh app ini).
class ReceivingSelectExistingPage extends ConsumerStatefulWidget {
  const ReceivingSelectExistingPage({super.key});

  @override
  ConsumerState<ReceivingSelectExistingPage> createState() =>
      _ReceivingSelectExistingPageState();
}

class _ReceivingSelectExistingPageState
    extends ConsumerState<ReceivingSelectExistingPage> {
  final _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openItems(ReceivingModel receiving) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceivingItemsPage(receiving: receiving),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receivingsAsync = ref.watch(allReceivingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tambah Barang ke Resi Lama',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Pilih resi yang mau ditambah/diubah barangnya',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.invalidate(allReceivingsProvider),
            icon: const Icon(Icons.refresh_rounded, color: AppColors.navy),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Resi',
                hint: 'Nomor resi / tujuan...',
                icon: Icons.search_rounded,
                onChanged: (value) => setState(() => _keyword = value.trim()),
              ),
            ),
            Expanded(
              child: receivingsAsync.when(
                data: (receivings) => _buildBody(receivings),
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar resi',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allReceivingsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<ReceivingModel> receivings) {
    // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs Tujuan):
    // pencarian receiverName dihapus (selalu null untuk resi baru) --
    // cari lewat destination (nama tujuan) saja.
    final keyword = _keyword.toLowerCase();
    final filtered = keyword.isEmpty
        ? receivings
        : receivings.where((r) {
            return r.receiptNumber.toLowerCase().contains(keyword) ||
                r.destination.toLowerCase().contains(keyword);
          }).toList();

    if (filtered.isEmpty) {
      return ErrorStateView(
        icon: Icons.receipt_long_outlined,
        title: receivings.isEmpty ? 'Belum ada resi' : 'Resi tidak ditemukan',
        message: receivings.isEmpty
            ? 'Resi akan muncul di sini setelah dibuat lewat "Terima Barang".'
            : 'Coba kata kunci lain.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final receiving = filtered[index];

        return AppCard(
          padding: const EdgeInsets.all(14),
          child: InkWell(
            onTap: () => _openItems(receiving),
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              // FITUR (8 Oktober 2026 -- poin 4): nomor
                              // buku di belakang nomor resi kalau ada.
                              (receiving.nomorBuku != null &&
                                      receiving.nomorBuku!.isNotEmpty)
                                  ? '${receiving.receiptNumber} / ${receiving.nomorBuku}'
                                  : receiving.receiptNumber,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _buildStatusChip(receiving.status),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        receiving.destinationPhone != null &&
                                receiving.destinationPhone!.isNotEmpty
                            ? '${receiving.destination} • ${receiving.destinationPhone}'
                            : receiving.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${receiving.totalQuantity} barang · '
                        '${formatRupiah(receiving.totalPrice)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Catatan: `receiving.status` sejauh ini SELALU "RECEIVED" (diisi sekali
  // saat `createReceiving()`, `updateReceivingStatus()` ada tapi belum
  // pernah dipanggil di mana pun) -- chip ini sengaja netral (satu warna),
  // BUKAN dibedakan warnanya kayak status shipment (LOADING/DEPARTED/dst),
  // supaya tidak menyesatkan kalau nanti status ini benar-benar dipakai
  // dengan nilai lain.
  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.blue.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: AppColors.blue,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
