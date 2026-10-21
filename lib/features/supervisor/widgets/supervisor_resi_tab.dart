import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/receiving_model.dart';
import '../../../models/sender_model.dart';
import '../../../providers/dashboard_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../../../providers/receiving_detail_providers.dart';
import '../../../services/receiving_service.dart';
import '../supervisor_ui_kit.dart';

/// Tab 1 "Monitoring Resi" -- Dashboard Supervisor (16 Oktober 2026).
///
/// Permintaan user: "Pencarian resi" + "Daftar resi lengkap dengan
/// informasinya (seperti daftar resi pada monitoring resi di admin tanpa
/// editing)". TIDAK ada tombol "Selesaikan (Bypass)", TIDAK ada navigasi
/// tap-ke-halaman-edit -- SEBAGAI GANTINYA, tiap kartu resi bisa
/// di-expand di tempat supaya Supervisor bisa lihat SEMUA 12 field
/// kelengkapan informasi tanpa pindah halaman sama sekali:
///   1. Siapa pengirimnya      -> nama sender (senderId)
///   2. Tanggal+jam diterima   -> receivedAt
///   3. Siapa menerima         -> tujuan
///   4+5. Apa barang & jumlah  -> `receivingDetailsProvider(id)`
///   6. Diedit kapan & siapa   -> `updatedBy`/`updatedAt`
///   7+8. Loading kapan+siapa  -> `receivingProgressProvider(id)`
///   9+10. Mobil & sopir       -> `receivingProgressProvider(id)`
///   11. Tanggal penyelesaian  -> `receivingProgressProvider(id)`
///   12. Diselesaikan paksa?   -> `receivingProgressProvider(id)`
///
/// FITUR (16 Oktober 2026 -- lazy-load + pencarian server-side,
/// permintaan user: "Saat semua resi diload (saat ini resi nomor 1000)
/// dan akan menuju resi nomor 100000, seharusnya kan kita tidak
/// mengambil sekaligus?"): tab ini TIDAK LAGI pakai `allReceivingsProvider`
/// (ambil SEMUA resi ke memori HP sekaligus) -- sekarang infinite-scroll
/// per HALAMAN (`ReceivingService.getReceivingsPage`, 30 resi/halaman),
/// dengan kata kunci pencarian & filter status DIKIRIM ke query Supabase
/// (`.or`/`.eq`), BUKAN disaring belakangan di Dart dari data yang sudah
/// ter-load. Status resi (Penerimaan/Masih Perjalanan/Selesai) dibaca
/// LANGSUNG dari kolom `computed_status` (lihat `ReceivingComputedStatus`
/// di `receiving_model.dart` + migrasi `add_receiving_computed_status.sql`)
/// -- dijaga OTOMATIS oleh trigger database, BUKAN dihitung lagi di Dart
/// dari seluruh `shipment_scans` seperti sebelumnya. Field progress
/// (Loading/Mobil & Sopir/Penyelesaian) ikut dibuat lazy -- HANYA
/// di-fetch per-resi saat kartunya di-expand (`receivingProgressProvider`,
/// pola sama dgn `receivingDetailsProvider` utk barang, lihat BUGFIX
/// PERFORMA 16 Oktober 2026 sebelumnya).
///
/// SCOPE: baru diterapkan di SINI (Supervisor), BELUM di Admin
/// `ReceivingListPage` -- keputusan user supaya perubahannya bertahap/
/// risikonya lebih kecil. Admin MASIH pakai `allReceivingsProvider` +
/// `receivingProgressSummaryProvider` lama, TIDAK terpengaruh sama
/// sekali oleh perubahan di file ini.
class SupervisorResiTab extends ConsumerStatefulWidget {
  const SupervisorResiTab({super.key});

  @override
  ConsumerState<SupervisorResiTab> createState() => _SupervisorResiTabState();
}

class _SupervisorResiTabState extends ConsumerState<SupervisorResiTab> {
  static const _pageSize = 30;

  final _scrollController = ScrollController();
  final List<ReceivingModel> _items = [];

  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  String _keyword = '';
  Timer? _debounce;
  // null = filter "Semua", selain itu salah satu `ReceivingComputedStatus.*`.
  String? _statusFilter;

  // FITUR (16 Oktober 2026 -- permintaan user eksplisit, sama dengan
  // `ReceivingListPage` admin): toggle urutan resi Baru->Lama (default,
  // `false`) / Lama->Baru, lihat doc comment `_buildSortButton`.
  bool _sortOldestFirst = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || _loadingInitial) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
    });
    try {
      final rows = await ReceivingService.getReceivingsPage(
        keyword: _keyword,
        status: _statusFilter,
        sortOldestFirst: _sortOldestFirst,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final rows = await ReceivingService.getReceivingsPage(
        keyword: _keyword,
        status: _statusFilter,
        sortOldestFirst: _sortOldestFirst,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat resi berikutnya: $e')),
      );
    }
  }

  void _onKeywordChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final trimmed = value.trim();
      if (trimmed == _keyword) return;
      setState(() => _keyword = trimmed);
      _loadInitial();
    });
  }

  void _onStatusFilterChanged(String? value) {
    final next = _statusFilter == value ? null : value;
    setState(() => _statusFilter = next);
    _loadInitial();
  }

  void _onSortToggled() {
    setState(() => _sortOldestFirst = !_sortOldestFirst);
    _loadInitial();
  }

  String _statusLabel(String status) {
    switch (status) {
      case ReceivingComputedStatus.penerimaan:
        return 'Penerimaan';
      case ReceivingComputedStatus.masihPerjalanan:
        return 'Masih Perjalanan';
      case ReceivingComputedStatus.selesai:
        return 'Selesai';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case ReceivingComputedStatus.penerimaan:
        return AppColors.violet;
      case ReceivingComputedStatus.masihPerjalanan:
        return AppColors.orange;
      case ReceivingComputedStatus.selesai:
        return AppColors.green;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case ReceivingComputedStatus.penerimaan:
        return Icons.inventory_2_outlined;
      case ReceivingComputedStatus.masihPerjalanan:
        return Icons.local_shipping_outlined;
      case ReceivingComputedStatus.selesai:
        return Icons.check_circle_rounded;
      default:
        return Icons.hourglass_empty_rounded;
    }
  }

  String _employeeName(List<EmployeeModel>? employees, String? employeeId) {
    if (employeeId == null) return '-';
    if (employees == null) return 'Memuat...';
    for (final e in employees) {
      if (e.id == employeeId) return e.fullName;
    }
    return '-';
  }

  String _senderName(List<SenderModel>? senders, String senderId) {
    if (senders == null) return 'Memuat...';
    for (final s in senders) {
      if (s.id == senderId) return s.name;
    }
    return '-';
  }

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(allEmployeesProvider);
    final sendersAsync = ref.watch(allSendersProvider);
    final statusCountsAsync = ref.watch(receivingStatusCountsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  onChanged: _onKeywordChanged,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Cari nomor resi / nomor buku / tujuan...',
                    hintStyle: const TextStyle(fontSize: 16),
                    prefixIcon: const Icon(Icons.search_rounded, size: 26),
                    filled: true,
                    fillColor: AppColors.fieldFill,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildSortButton(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: _buildStatusFilterChips(statusCountsAsync.value),
        ),
        Expanded(
          child: _buildBody(employeesAsync.value, sendersAsync.value),
        ),
      ],
    );
  }

  Widget _buildBody(
    List<EmployeeModel>? employees,
    List<SenderModel>? senders,
  ) {
    if (_loadingInitial) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.blue));
    }

    if (_error != null) {
      return ErrorStateView(
        title: 'Gagal memuat daftar resi.',
        message: _error!,
        onRetry: _loadInitial,
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada resi ditemukan.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    // FITUR (16 Oktober 2026 -- "3 kolom untuk Resi ... dan tinggi
    // ditambah"): grid 3 kolom lewat `Wrap` + `LayoutBuilder` (BUKAN
    // `GridView`, supaya kartu yang di-expand boleh lebih tinggi tanpa
    // memaksa kartu sebelahnya ikut setinggi itu). `_scrollController`
    // dipasang di `SingleChildScrollView` ini -- dipantau `_onScroll`
    // utk memicu `_loadMore()` saat sudah dekat dasar (infinite scroll).
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 16.0;
              const columns = 3;
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final receiving in _items)
                    SizedBox(
                      width: cardWidth,
                      child: _ResiCard(
                        key: ValueKey(receiving.id),
                        receiving: receiving,
                        statusLabel: _statusLabel(receiving.computedStatus),
                        statusColor: _statusColor(receiving.computedStatus),
                        statusIcon: _statusIcon(receiving.computedStatus),
                        senderName: _senderName(senders, receiving.senderId),
                        receivedByName:
                            _employeeName(employees, receiving.receivedBy),
                        updatedByName:
                            _employeeName(employees, receiving.updatedBy),
                        formatQuantity: _formatQuantity,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (_loadingMore)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.blue),
              ),
            )
          else if (!_hasMore)
            const Center(
              child: Text(
                '— Semua resi sudah dimuat —',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // FITUR (16 Oktober 2026 -- Sort): tombol toggle urutan resi, lihat
  // doc comment `_sortOldestFirst`. Dibesarkan (56x56, ikon 28) supaya
  // sejajar dengan TextField pencarian yang juga sudah dibesarkan di
  // dashboard Supervisor ini.
  Widget _buildSortButton() {
    return Tooltip(
      message: _sortOldestFirst
          ? 'Urutan: Resi Lama ke Baru (tap untuk balik)'
          : 'Urutan: Resi Baru ke Lama (tap untuk balik)',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _onSortToggled,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _sortOldestFirst
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            color: AppColors.blue,
            size: 28,
          ),
        ),
      ),
    );
  }

  // FITUR (16 Oktober 2026 -- lazy-load): angka di tiap chip sekarang
  // dari `receivingStatusCountsProvider` (query ringan terpisah, SEKALI
  // per buka tab -- lihat `ReceivingService.getReceivingStatusCounts`),
  // BUKAN dihitung dari daftar resi yang sudah ter-load di layar (yang
  // sekarang cuma sebagian/1 halaman, bukan semua resi lagi).
  Widget _buildStatusFilterChips(Map<String, int>? counts) {
    Widget chip(String label, String? value, Color color) {
      final selected = _statusFilter == value;
      final count = counts == null
          ? null
          : (value == null ? counts['TOTAL'] : counts[value]) ?? 0;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => _onStatusFilterChanged(value),
          label: Text(count == null ? label : '$label ($count)'),
          labelStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : color,
          ),
          avatar: Icon(_statusIcon(value ?? ''), size: 18,
              color: selected ? Colors.white : color),
          selectedColor: color,
          backgroundColor: color.withOpacity(0.10),
          side: BorderSide(color: color.withOpacity(selected ? 0 : 0.25)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          showCheckmark: false,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Semua', null, AppColors.blue),
          chip('Penerimaan', ReceivingComputedStatus.penerimaan,
              AppColors.violet),
          chip('Masih Perjalanan', ReceivingComputedStatus.masihPerjalanan,
              AppColors.orange),
          chip('Selesai', ReceivingComputedStatus.selesai, AppColors.green),
        ],
      ),
    );
  }
}

/// Kartu 1 resi -- bisa di-expand (tap header) supaya 12 field
/// kelengkapan bisa dilihat di tempat tanpa pindah halaman (lihat doc
/// comment kelas tab di atas).
///
/// BUGFIX (16 Oktober 2026 -- laporan user "Bottom Overflow dibawah chip
/// status"): SEBELUMNYA pakai `ExpansionTile` (leading/title/subtitle/
/// trailing bawaan `ListTile`) -- begitu judul resi dibesarkan (23px) +
/// ada subtitle + trailing 2 baris (chip status + harga) sekaligus,
/// `ListTile` menghitung tinggi tile dari title+subtitle SAJA (bukan
/// dari trailing), jadi kalau trailing lebih tinggi dari situ ->
/// overflow. Diganti header custom (`Column`/`Row`/`Wrap` biasa, TANPA
/// `ListTile`) yang tingginya otomatis mengikuti isi -- tidak ada lagi
/// slot dengan tinggi "dihitung dari yang lain" seperti itu.
class _ResiCard extends ConsumerStatefulWidget {
  final ReceivingModel receiving;
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;
  final String senderName;
  final String receivedByName;
  final String updatedByName;
  final String Function(double) formatQuantity;

  const _ResiCard({
    super.key,
    required this.receiving,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
    required this.senderName,
    required this.receivedByName,
    required this.updatedByName,
    required this.formatQuantity,
  });

  @override
  ConsumerState<_ResiCard> createState() => _ResiCardState();
}

class _ResiCardState extends ConsumerState<_ResiCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final receiving = widget.receiving;
    final statusColor = widget.statusColor;

    // FITUR (16 Oktober 2026 -- permintaan user eksplisit: "Pada daftar
    // Resi ... harus berwarna Merah (kotaknya) atau garis kotaknya jika
    // Resi tersebut lewat dari xx hari dari hari ini", xx dari
    // `CompanyModel.resiOverdueDays`, lihat juga Admin
    // `ReceivingListPage._isResiOverdue`). Klarifikasi user ("hanya
    // resi yang statusnya belum loading atau penerimaan") membatasi ini
    // KHUSUS resi `ReceivingComputedStatus.penerimaan` -- resi "Masih
    // Perjalanan"/"Selesai" TIDAK PERNAH dianggap terlambat di sini.
    // Fallback 3 hari kalau `companyProvider` belum selesai loading.
    final resiOverdueDays =
        ref.watch(companyProvider).value?.resiOverdueDays ?? 3;
    final isOverdue =
        receiving.computedStatus == ReceivingComputedStatus.penerimaan &&
            DateTime.now().difference(receiving.receivedAt).inDays >
                resiOverdueDays;

    // FITUR (16 Oktober 2026 -- "berwarna setiap resi ... warna pastel"):
    // `SupervisorAccentCard` menggantikan Container putih polos, lihat
    // doc comment lengkap di `supervisor_ui_kit.dart`. Kalau `isOverdue`,
    // warna aksen kartu (strip atas + border + tint badan) DIPAKSA
    // merah menggantikan warna status asli -- badge status di dalam
    // kartu (lihat `widget.statusLabel`/`widget.statusColor` di bawah)
    // TETAP memakai warna status asli (violet "Penerimaan"), supaya
    // teksnya tidak membingungkan, HANYA bingkai kartunya yang berubah
    // merah sebagai sinyal "sudah terlambat".
    return SupervisorAccentCard(
      color: isOverdue ? AppColors.red : statusColor,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            // FITUR (16 Oktober 2026 -- "tinggi ditambah"): padding
            // header dilonggarkan (10 -> 18 vertikal) supaya kartu
            // terasa lebih lega/tinggi dibanding sebelumnya.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(widget.statusIcon,
                            color: statusColor, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // FITUR (16 Oktober 2026 -- "tulisan nomor
                            // Resi Bold tebal dan Tegas"): dibesarkan
                            // 18 -> 23 + letterSpacing.
                            Text(
                              (receiving.nomorBuku != null &&
                                      receiving.nomorBuku!.isNotEmpty)
                                  ? '${receiving.receiptNumber} / ${receiving.nomorBuku}'
                                  : receiving.receiptNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 23,
                                letterSpacing: 0.2,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // FITUR (16 Oktober 2026 -- permintaan user:
                            // "Nama TUJUAN diperbesar sehingga sebesar
                            // hurufnya dengan nomor Resi, warnanya ubah
                            // jadi abu2"): ukuran disamakan dgn nomor
                            // resi (23px), warna abu2 (`textSecondary`).
                            Text(
                              receiving.destination,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        formatRupiah(receiving.totalPrice),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 14),
                  // FITUR (16 Oktober 2026 -- "semua nomor dihilangkan
                  // depan label", "Label perbesar sedikit, dan valuenya
                  // perbesar", "Antara label berikan sekat yang jelas"):
                  // `SupervisorField` menggantikan `_field` lama, lebar
                  // dibuat penuh (`double.infinity`) karena kartu
                  // sekarang 1/3 lebar layar (grid 3 kolom) -- lihat
                  // `supervisor_ui_kit.dart`.
                  SupervisorField(
                    label: 'Pengirim',
                    value: widget.senderName,
                    width: double.infinity,
                  ),
                  SupervisorField(
                    label: 'Diterima',
                    value: '${formatDateId(receiving.receivedAt)}, '
                        '${formatTimeId(receiving.receivedAt)}',
                    width: double.infinity,
                  ),
                  SupervisorField(
                    label: 'Diterima Oleh (Tujuan)',
                    value: receiving.destinationPhone != null &&
                            receiving.destinationPhone!.isNotEmpty
                        ? '${receiving.destination} • ${receiving.destinationPhone}'
                        : receiving.destination,
                    width: double.infinity,
                  ),
                  SupervisorField(
                    label: 'Diinput Oleh',
                    value: widget.receivedByName,
                    width: double.infinity,
                  ),
                  SupervisorField(
                    label: 'Diperbarui',
                    value: receiving.updatedBy != null
                        ? '${formatDateId(receiving.updatedAt)}, '
                            '${formatTimeId(receiving.updatedAt)} • ${widget.updatedByName}'
                        : 'Belum pernah diedit',
                    width: double.infinity,
                  ),
                  // BUGFIX PERFORMA (16 Oktober 2026 -- lanjutan
                  // "lambat proses menampilkan dan pengambilan data
                  // Resi"): field Loading/Mobil & Sopir/Penyelesaian
                  // SEBELUMNYA datang dari `receivingProgressSummaryProvider`
                  // (1 query GLOBAL yang ambil progress SEMUA resi
                  // sekaligus). Sekarang pakai `receivingProgressProvider`
                  // (per-resi, SAMA pola lazy dgn `receivingDetailsProvider`
                  // di bawah) -- HANYA fetch saat kartu ini di-expand.
                  Builder(builder: (context) {
                    final progressAsync = ref
                        .watch(receivingProgressProvider(receiving.id));
                    return progressAsync.when(
                      data: (progress) {
                        final p = progress ?? const <String, dynamic>{};
                        final loadedAt = p['loadedAt'] as DateTime?;
                        final loadedByName = p['loadedByName'] as String?;
                        final deliveredAt = p['deliveredAt'] as DateTime?;
                        final vehiclePlateNumber =
                            p['vehiclePlateNumber'] as String?;
                        final driverName = p['driverName'] as String?;
                        final isBypassAdmin =
                            (p['isBypassAdmin'] as bool?) ?? false;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SupervisorField(
                              label: 'Loading',
                              value: isBypassAdmin
                                  ? (loadedAt != null
                                      ? 'Bypass: ${formatDateId(loadedAt)}'
                                          '${(loadedByName != null && loadedByName.isNotEmpty) ? ' • $loadedByName' : ''}'
                                      : 'Bypass oleh admin')
                                  : (loadedAt != null
                                      ? '${formatDateId(loadedAt)}, ${formatTimeId(loadedAt)}'
                                          '${(loadedByName != null && loadedByName.isNotEmpty) ? ' • $loadedByName' : ''}'
                                      : 'Belum diloading'),
                              width: double.infinity,
                            ),
                            SupervisorField(
                              label: 'Mobil & Sopir',
                              value: () {
                                if (isBypassAdmin) return '-';
                                final parts = [
                                  if (vehiclePlateNumber != null &&
                                      vehiclePlateNumber.isNotEmpty)
                                    vehiclePlateNumber,
                                  if (driverName != null &&
                                      driverName.isNotEmpty)
                                    driverName,
                                ];
                                return parts.isEmpty
                                    ? '-'
                                    : parts.join(' • ');
                              }(),
                              width: double.infinity,
                            ),
                            SupervisorField(
                              label: 'Tanggal Penyelesaian',
                              value: deliveredAt != null
                                  ? '${formatDateId(deliveredAt)}, ${formatTimeId(deliveredAt)}'
                                  : 'Belum selesai',
                              width: double.infinity,
                            ),
                            SupervisorField(
                              label: 'Diselesaikan Paksa?',
                              value: isBypassAdmin
                                  ? 'Ya, oleh ${(loadedByName != null && loadedByName.isNotEmpty) ? loadedByName : '-'}'
                                  : 'Tidak',
                              valueColor:
                                  isBypassAdmin ? AppColors.red : null,
                              width: double.infinity,
                            ),
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, __) => Text(
                        'Gagal memuat progres: $e',
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 13),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 10),
                  const Text(
                    'BARANG',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // BUGFIX PERFORMA (16 Oktober 2026 -- laporan user
                  // "lambat proses menampilkan dan pengambilan data
                  // Resi"): `receivingDetailsProvider(id)` HANYA
                  // di-watch (jadi HANYA fetch) di sini, saat kartu ini
                  // benar-benar di-expand -- bukan utk semua kartu yang
                  // sekadar tampil di layar.
                  Builder(builder: (context) {
                    final detailsAsync =
                        ref.watch(receivingDetailsProvider(receiving.id));
                    return detailsAsync.when(
                      data: (details) => _buildItemList(details),
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, __) => Text(
                        'Gagal memuat barang: $e',
                        style:
                            const TextStyle(color: AppColors.red, fontSize: 13),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemList(List<ReceivingDetailModel> details) {
    if (details.isEmpty) {
      return const Text(
        'Belum ada barang tercatat.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in details)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 16, color: AppColors.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.itemName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${widget.formatQuantity(d.totalPhysicalQuantity)} ${d.quantityUnit}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
