
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/receiving_model.dart';
import '../../../providers/dashboard_providers.dart';
import '../../../providers/session_provider.dart';
import 'receiving_items_page.dart';

/// Daftar resi milik petugas Receiving yang sedang login (difilter dari
/// `received_by`) -- tap salah satu untuk buka lagi Detail Barang-nya
/// kapan saja, lalu cetak ulang label/resi dari sana.
class ReceivingPrintListPage extends ConsumerStatefulWidget {
  const ReceivingPrintListPage({super.key});

  @override
  ConsumerState<ReceivingPrintListPage> createState() =>
      _ReceivingPrintListPageState();
}

class _ReceivingPrintListPageState extends ConsumerState<ReceivingPrintListPage> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);
    final receivingsAsync = ref.watch(allReceivingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cetak Resi'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(child: _buildBody(employeeAsync, receivingsAsync)),
    );
  }

  Widget _buildBody(
    AsyncValue employeeAsync,
    AsyncValue<List<ReceivingModel>> receivingsAsync,
  ) {
    if (employeeAsync.isLoading || receivingsAsync.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    if (receivingsAsync.hasError) {
      return ErrorStateView(
        title: 'Gagal memuat daftar resi.',
        message: receivingsAsync.error.toString(),
        onRetry: () => ref.invalidate(allReceivingsProvider),
      );
    }

    final employee = employeeAsync.value;

    if (employee == null) {
      return const ErrorStateView(title: 'Data employee tidak ditemukan.');
    }

    final all = receivingsAsync.value ?? [];
    final mine = all.where((r) => r.receivedBy == employee.id).toList();

    // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs Tujuan):
    // pencarian receiverName dihapus (selalu null untuk resi baru) --
    // cari lewat destination (nama tujuan) saja.
    final keyword = _keyword.toLowerCase();
    final filtered = keyword.isEmpty
        ? mine
        : mine.where((r) {
            return r.receiptNumber.toLowerCase().contains(keyword) ||
                r.destination.toLowerCase().contains(keyword);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: TextField(
            onChanged: (value) => setState(() => _keyword = value.trim()),
            decoration: InputDecoration(
              hintText: 'Cari nomor resi / tujuan...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.fieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    mine.isEmpty
                        ? 'Belum ada resi yang Anda input.'
                        : 'Tidak ada resi ditemukan.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final receiving = filtered[index];

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReceivingItemsPage(receiving: receiving),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(13),
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
                                      Text(
                                        receiving.receiptNumber,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        receiving.destinationPhone != null &&
                                                receiving
                                                    .destinationPhone!
                                                    .isNotEmpty
                                            ? '${receiving.destination} • ${receiving.destinationPhone}'
                                            : receiving.destination,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatRupiah(receiving.totalPrice),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}