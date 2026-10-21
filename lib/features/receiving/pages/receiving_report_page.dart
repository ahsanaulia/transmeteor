import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/pdf_templates.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/receiving_model.dart';
import '../../../providers/dashboard_providers.dart';
import '../../../providers/session_provider.dart';

/// Laporan rekap resi harian milik petugas Receiving yang sedang login
/// (difilter dari `received_by`, bukan resi semua staff) -- pilih
/// tanggal (default hari ini), tampil dulu di layar (jumlah resi/qty/
/// nilai + daftarnya), baru dibagikan sebagai PDF. Tidak ada versi cetak
/// thermal karena tabelnya kelebaran buat kertas struk 80mm.
class ReceivingReportPage extends ConsumerStatefulWidget {
  const ReceivingReportPage({super.key});

  @override
  ConsumerState<ReceivingReportPage> createState() =>
      _ReceivingReportPageState();
}

class _ReceivingReportPageState extends ConsumerState<ReceivingReportPage> {
  DateTime _selectedDate = DateTime.now();
  bool _isSharing = false;

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _sharePdf(String staffName, List<ReceivingModel> receivings) async {
    setState(() => _isSharing = true);

    try {
      final doc = await PdfTemplates.buildDailyReceivingReportDocument(
        date: _selectedDate,
        staffName: staffName,
        receivings: receivings,
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename:
            'laporan-resi-${_selectedDate.year}${_selectedDate.month.toString().padLeft(2, '0')}${_selectedDate.day.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);
    final receivingsAsync = ref.watch(allReceivingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cetak Laporan'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(child: _buildBody(employeeAsync, receivingsAsync)),
      bottomNavigationBar: _buildActionBar(employeeAsync, receivingsAsync),
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
        title: 'Gagal memuat data resi.',
        message: receivingsAsync.error.toString(),
        onRetry: () => ref.invalidate(allReceivingsProvider),
      );
    }

    final employee = employeeAsync.value;

    if (employee == null) {
      return const ErrorStateView(
        title: 'Data employee tidak ditemukan.',
      );
    }

    final all = receivingsAsync.value ?? [];
    final filtered = all
        .where((r) =>
            r.receivedBy == employee.id && _isSameDate(r.receivedAt, _selectedDate))
        .toList();

    final totalQuantity =
        filtered.fold<double>(0, (sum, r) => sum + r.totalQuantity);
    final totalValue = filtered.fold<double>(0, (sum, r) => sum + r.totalPrice);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 140),
      children: [
        _buildDatePickerCard(),
        const SizedBox(height: 16),
        _buildSummaryCard(filtered.length, totalQuantity, totalValue),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 56,
                  color: AppColors.textSecondary.withOpacity(0.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Belum ada resi yang Anda input pada tanggal ini.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          )
        else
          for (final r in filtered) ...[
            _buildReceivingTile(r),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget? _buildActionBar(
    AsyncValue employeeAsync,
    AsyncValue<List<ReceivingModel>> receivingsAsync,
  ) {
    final employee = employeeAsync.value;
    final all = receivingsAsync.value;

    if (employee == null || all == null) return null;

    final filtered = all
        .where((r) =>
            r.receivedBy == employee.id && _isSameDate(r.receivedAt, _selectedDate))
        .toList();

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
        child: PrimaryButton(
          label: 'Bagikan PDF (${filtered.length} resi)',
          loadingLabel: 'Menyiapkan PDF...',
          isLoading: _isSharing,
          icon: Icons.picture_as_pdf_outlined,
          onPressed: filtered.isEmpty || _isSharing
              ? null
              : () => _sharePdf(employee.fullName, filtered),
        ),
      ),
    );
  }

  Widget _buildDatePickerCard() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.blue.withOpacity(0.10)),
        ),
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
                Icons.calendar_month_rounded,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tanggal Laporan',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDateId(_selectedDate),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(int count, double totalQuantity, double totalValue) {
    return AppCard(
      child: Row(
        children: [
          Expanded(child: _buildSummaryStat('Total Resi', '$count')),
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
          Expanded(child: _buildSummaryStat('Total Nilai', formatRupiah(totalValue))),
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
            fontSize: 14,
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

  Widget _buildReceivingTile(ReceivingModel r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  r.destinationPhone != null && r.destinationPhone!.isNotEmpty
                      ? '${r.destination} • ${r.destinationPhone}'
                      : r.destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            formatRupiah(r.totalPrice),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}