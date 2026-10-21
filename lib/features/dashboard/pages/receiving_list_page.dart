import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/employee_model.dart';
import '../../../models/receiving_model.dart';
import '../../../providers/dashboard_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/shipment_service.dart';
import 'receiving_detail_page.dart';

/// Status ringkas 1 resi untuk badge/filter di `ReceivingListPage` --
/// lihat doc comment lengkap di `_resiStatus()`.
enum _ResiStatus { penerimaan, masihPerjalanan, selesai }

/// Daftar semua resi (lintas staff receiving) untuk dipantau pimpinan.
/// Tap salah satu untuk buka ReceivingDetailPage -- versi read-only
/// lengkap dengan grafik komposisi barang, bukan form edit operasional.
class ReceivingListPage extends ConsumerStatefulWidget {
  const ReceivingListPage({super.key});

  @override
  ConsumerState<ReceivingListPage> createState() => _ReceivingListPageState();
}

class _ReceivingListPageState extends ConsumerState<ReceivingListPage> {
  String _keyword = '';

  // FITUR (9 Oktober 2026 -- permintaan user eksplisit): filter status
  // "Penerimaan"/"Masih Perjalanan"/"Selesai" lewat chip di atas daftar
  // (lihat `_buildStatusFilterChips`). null = tampilkan semua status.
  _ResiStatus? _statusFilter;

  // FITUR (10 Oktober 2026 -- permintaan user eksplisit): tombol
  // "Selesaikan" per resi, lihat `_confirmAndCompleteReceiving`. id resi
  // yang sedang diproses (null = tidak ada) -- dipakai nonaktifkan
  // tombol & tampilkan spinner HANYA di kartu resi itu saat prosesnya
  // berjalan, kartu resi lain tetap bisa diinteraksi.
  String? _completingReceivingId;

  // FITUR (16 Oktober 2026 -- permintaan user eksplisit): "Tambahkan di
  // monitoring resi untuk Sort. Menyusun list dari resi lama ke resi
  // baru dan sebaliknya untuk memudahkan pencarian." Diurutkan dari
  // `receiving.createdAt` (tanggal+jam INPUT resi -- field yang sama
  // yang ditampilkan di tiap kartu, BUKAN `receivedAt`). Default `false`
  // (resi BARU di atas) supaya tampilan awal SAMA seperti sebelum fitur
  // ini ada (`ReceivingService.getReceivings()` sudah `order('created_at',
  // ascending: false)` dari sisi query) -- tombol ini cuma menambah
  // kemampuan membalik urutan itu di Dart, tanpa query ulang ke server.
  bool _sortOldestFirst = false;

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  // FITUR (9 Oktober 2026 -- permintaan user eksplisit): "tambahkan
  // Informasi tentang Resi mana yang Selesai, Masih Perjalanan dan
  // Penerimaan. Sehingga halaman ini bisa jadi kontrol pimpinan resi
  // mana yang harus segera diberangkatkan."
  //
  // Status ditentukan dari progress scan (lihat
  // `MonitoringService.getReceivingProgressSummary`), DIBANDINGKAN ke
  // `receiving.total_quantity` (total koli resi ini, SEMUA barang --
  // bukan cuma yang sudah dimuat):
  //   - loaded == 0            -> Penerimaan (belum ada barang yang
  //                                dimuat ke kendaraan sama sekali,
  //                                MASIH DI GUDANG, perlu diberangkatkan)
  //   - delivered >= total     -> Selesai (SEMUA koli resi ini sudah
  //                                tercatat turun/diterima di tujuan)
  //   - selain itu             -> Masih Perjalanan (sudah ada yang
  //                                dimuat, tapi belum semua koli sampai
  //                                -- termasuk yang masih sebagian
  //                                dimuat/belum full-loaded)
  //
  // `progress == null` artinya `receivingProgressSummaryProvider` belum
  // selesai loading (bukan berarti resi-nya kosong) -- dibedakan dari
  // "belum ada entry resi ini di map" (yang memang berarti loaded=0)
  // supaya tidak sempat kelihatan "Penerimaan" keliru sesaat sebelum
  // data progress datang. Return null di kasus itu, pemanggil UI
  // menampilkan badge netral "Memuat...".
  _ResiStatus? _resiStatus(
    ReceivingModel receiving,
    Map<String, Map<String, dynamic>>? progress,
  ) {
    if (progress == null) return null;

    // BUGFIX (16 Oktober 2026 -- laporan user: "Saat resi diselesaikan
    // oleh admin, ternyata resi tersebut tetap muncul namun barangnya
    // sudah 0. Jadi Resi yang barangnya sudah 0 harus dinyatakan
    // selesai statusnya"). `receiving.totalQuantity` ikut berkurang
    // otomatis (trigger `trg_receiving_details_recalculate`) begitu
    // SEMUA baris barang resi ini dihapus satu-satu (mis. lewat "Hapus
    // Barang" di ReceivingItemDetailPage) -- begitu turun ke 0, TIDAK
    // ADA lagi barang yang perlu diberangkatkan/dilacak, jadi resi ini
    // SEHARUSNYA dianggap Selesai, BUKAN nyangkut selamanya di
    // "Penerimaan" (yang terjadi SEBELUM perbaikan ini, karena
    // pengecekan `loaded <= 0` di bawah dicek lebih dulu dan selalu
    // benar untuk resi kosong). Dicek PALING AWAL (sebelum `loaded`)
    // supaya menang dari kondisi lain apa pun.
    if (receiving.totalQuantity <= 0) return _ResiStatus.selesai;

    final entry = progress[receiving.id];
    final loaded = (entry?['loaded'] as int?) ?? 0;
    final delivered = (entry?['delivered'] as int?) ?? 0;
    if (loaded <= 0) return _ResiStatus.penerimaan;
    if (receiving.totalQuantity > 0 && delivered >= receiving.totalQuantity) {
      return _ResiStatus.selesai;
    }
    return _ResiStatus.masihPerjalanan;
  }

  // FITUR (16 Oktober 2026 -- permintaan user eksplisit, lihat doc
  // comment `resiOverdueDays` di `build()`): true kalau resi ini HARUS
  // ditandai kotak merah -- klarifikasi user ("hanya resi yang
  // statusnya belum loading atau penerimaan") membatasi ini KHUSUS resi
  // yang masih `_ResiStatus.penerimaan` (belum pernah di-loading sama
  // sekali). Resi "Masih Perjalanan"/"Selesai" TIDAK PERNAH dianggap
  // terlambat di sini, berapa pun lama `receivedAt`-nya.
  bool _isResiOverdue(
    ReceivingModel receiving,
    _ResiStatus? resiStatus,
    int overdueDays,
  ) {
    if (resiStatus != _ResiStatus.penerimaan) return false;
    return DateTime.now().difference(receiving.receivedAt).inDays >
        overdueDays;
  }

  String _statusLabel(_ResiStatus? status) {
    switch (status) {
      case _ResiStatus.penerimaan:
        return 'Penerimaan';
      case _ResiStatus.masihPerjalanan:
        return 'Masih Perjalanan';
      case _ResiStatus.selesai:
        return 'Selesai';
      case null:
        return 'Memuat...';
    }
  }

  Color _statusColor(_ResiStatus? status) {
    switch (status) {
      case _ResiStatus.penerimaan:
        return AppColors.violet;
      case _ResiStatus.masihPerjalanan:
        return AppColors.orange;
      case _ResiStatus.selesai:
        return AppColors.green;
      case null:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIcon(_ResiStatus? status) {
    switch (status) {
      case _ResiStatus.penerimaan:
        return Icons.inventory_2_outlined;
      case _ResiStatus.masihPerjalanan:
        return Icons.local_shipping_outlined;
      case _ResiStatus.selesai:
        return Icons.check_circle_rounded;
      case null:
        return Icons.hourglass_empty_rounded;
    }
  }

  // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
  // "Masukkan data Siapa Nama Pegawai Yang menginput ... Untuk track
  // pelaksana". `ReceivingModel.receivedBy` sudah ada sejak awal (id
  // employee yang menginput resi, diisi staff Receiving saat bikin
  // resi), TAPI belum pernah ditampilkan sebagai NAMA di mana pun --
  // cuma dipakai buat filter "resi milik saya" di `ReceivingPrintListPage`/
  // `ReceivingReportPage`. Resolusi id -> nama dilakukan di SINI (bukan
  // nambah kolom nama baru di tabel `receiving`), lewat `allEmployeesProvider`
  // (SUDAH ADA, dipakai halaman admin "Kelola Pegawai") -- SENGAJA pakai
  // yang "ALL" (bukan cuma aktif) supaya pegawai yang sudah dinonaktifkan
  // tetap kelihatan namanya di riwayat lama, bukan jadi "-"/kosong.
  String _employeeName(List<EmployeeModel>? employees, String employeeId) {
    if (employees == null) return 'Memuat...';
    for (final e in employees) {
      if (e.id == employeeId) return e.fullName;
    }
    return '-';
  }

  // FITUR (10 Oktober 2026 -- permintaan user eksplisit): "pada admin
  // Monitoring Resi ... tambahkan tombol disetiap resi: Selesaikan. Dan
  // meskipun resi itu belum diload. Bisa dipass agar selesai." --
  // tombol ini memaksa SEMUA barang resi ini tercatat sudah dimuat &
  // diterima di tujuan (lihat `ShipmentService.forceCompleteReceivingByAdmin`),
  // TANPA PEDULI resi ini sudah pernah disentuh Loading atau belum sama
  // sekali -- dipakai untuk simulasi/koreksi data, BUKAN alur kerja
  // normal. SENGAJA dibuat tidak gampang kepencet tidak sengaja: dialog
  // konfirmasi eksplisit + alasan wajib diisi (jejak audit, sama pola
  // dengan "Selesaikan Paksa" di Monitoring Kendaraan & Sopir).
  Future<void> _confirmAndCompleteReceiving(ReceivingModel receiving) async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;

          return AlertDialog(
            title: const Text('Selesaikan Resi (Bypass)?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ini akan menandai SEMUA barang resi ${receiving.receiptNumber} '
                  'sudah dimuat & sudah diterima di tujuan -- MESKIPUN resi ini '
                  'belum pernah disentuh Loading sama sekali. Dipakai HANYA untuk '
                  'simulasi/koreksi data, bukan alur kerja normal. Aksi ini tidak '
                  'bisa dibatalkan.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Alasan (wajib diisi)',
                    hintText: 'mis. Simulasi awal, resi ini tidak jadi dimuat',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  if (noteController.text.trim().isEmpty) {
                    setDialogState(() => errorText = 'Alasan wajib diisi.');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                child: const Text('Ya, Selesaikan'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final note = noteController.text.trim();
    if (note.isEmpty) return;

    setState(() => _completingReceivingId = receiving.id);

    try {
      final employee = await ref.read(currentEmployeeProvider.future);
      if (employee == null) {
        throw Exception('Data employee admin tidak ditemukan.');
      }

      final createdCount = await ShipmentService.forceCompleteReceivingByAdmin(
        receivingId: receiving.id,
        adminEmployeeId: employee.id,
        note: note,
      );

      ref.invalidate(receivingProgressSummaryProvider);
      ref.invalidate(unloadedZoneItemsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            createdCount > 0
                ? 'Resi ${receiving.receiptNumber} ditandai Selesai.'
                : 'Resi ${receiving.receiptNumber} sudah lengkap sebelumnya.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyelesaikan resi: $e')),
      );
    } finally {
      if (mounted) setState(() => _completingReceivingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receivingsAsync = ref.watch(allReceivingsProvider);
    final employeesAsync = ref.watch(allEmployeesProvider);
    final progressAsync = ref.watch(receivingProgressSummaryProvider);
    // FITUR (16 Oktober 2026 -- permintaan user eksplisit: "Pada daftar
    // Resi ... harus berwarna Merah (kotaknya) atau garis kotaknya jika
    // Resi tersebut lewat dari xx hari dari hari ini. xx hari adalah
    // nilai yang diinput di tabel company") -- ambang hari dibaca dari
    // `CompanyModel.resiOverdueDays` (diinput admin lewat "Profil
    // Perusahaan"), dipakai di `_isResiOverdue` di bawah. Fallback 3
    // kalau provider belum selesai loading, supaya tidak keliru
    // menganggap SEMUA resi lama terlambat sesaat sebelum data company
    // datang (lebih aman daripada 0, yang akan menandai hampir semua
    // resi langsung merah).
    final resiOverdueDays = ref.watch(companyProvider).value?.resiOverdueDays ?? 3;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Monitoring Resi'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: receivingsAsync.when(
        data: (receivings) {
          // `progress == null` selama `receivingProgressSummaryProvider`
          // masih loading/error -- `_resiStatus` menangani null ini
          // (balikin null juga, badge jadi "Memuat...") daripada salah
          // nebak "Penerimaan" untuk semua resi sesaat.
          final progress = progressAsync.value;

          final keyword = _keyword.toLowerCase();
          // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs
          // Tujuan): pencarian receiverName dihapus (selalu null untuk
          // resi baru) -- cari lewat destination (nama tujuan) saja.
          var filtered = keyword.isEmpty
              ? receivings
              : receivings.where((r) {
                  return r.receiptNumber.toLowerCase().contains(keyword) ||
                      r.destination.toLowerCase().contains(keyword);
                }).toList();

          // FITUR (9 Oktober 2026): filter tambahan per status, lewat
          // chip `_buildStatusFilterChips`. Diterapkan SETELAH filter
          // kata kunci supaya keduanya bisa dipakai bersamaan.
          if (_statusFilter != null) {
            filtered = filtered
                .where((r) => _resiStatus(r, progress) == _statusFilter)
                .toList();
          }

          // FITUR (16 Oktober 2026 -- Sort): diterapkan TERAKHIR, setelah
          // filter kata kunci & status, supaya urutan tetap konsisten
          // berapa pun hasil filter-nya. `filtered` di titik ini SELALU
          // list baru (hasil `.where(...).toList()` di atas, atau
          // `receivings` asli kalau kedua filter kosong) -- buat salinan
          // dulu sebelum `.sort()` (in-place) kalau kebetulan masih
          // referensi ke `receivings` supaya list provider tidak
          // ter-mutasi.
          filtered = List<ReceivingModel>.from(filtered)
            ..sort((a, b) => _sortOldestFirst
                ? a.createdAt.compareTo(b.createdAt)
                : b.createdAt.compareTo(a.createdAt));

          final totalQuantity =
              receivings.fold<double>(0, (s, r) => s + r.totalQuantity);
          final totalValue =
              receivings.fold<double>(0, (s, r) => s + r.totalPrice);

          // Hitung jumlah resi per status (dari SEMUA resi, bukan hasil
          // filter kata kunci) -- dipakai angka di tiap chip filter,
          // supaya pimpinan langsung lihat berapa banyak resi yang
          // "harus segera diberangkatkan" (status Penerimaan) tanpa
          // perlu scroll/filter dulu.
          final statusCounts = <_ResiStatus, int>{
            _ResiStatus.penerimaan: 0,
            _ResiStatus.masihPerjalanan: 0,
            _ResiStatus.selesai: 0,
          };
          var loadingStatusCount = 0;
          for (final r in receivings) {
            final status = _resiStatus(r, progress);
            if (status == null) {
              loadingStatusCount++;
            } else {
              statusCounts[status] = (statusCounts[status] ?? 0) + 1;
            }
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        'Total Resi',
                        '${receivings.length}',
                        AppColors.blue,
                        Icons.receipt_long_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatChip(
                        'Total Barang',
                        _formatQuantity(totalQuantity),
                        AppColors.cyan,
                        Icons.inventory_2_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatChip(
                        'Total Nilai',
                        formatRupiah(totalValue),
                        AppColors.green,
                        Icons.payments_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _keyword = value.trim()),
                        decoration: InputDecoration(
                          hintText: 'Cari nomor resi / penerima / tujuan...',
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
                    const SizedBox(width: 8),
                    _buildSortButton(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildStatusFilterChips(statusCounts, loadingStatusCount),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Tidak ada resi ditemukan.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final receiving = filtered[index];

                          final resiStatus = _resiStatus(receiving, progress);
                          final isCompleting =
                              _completingReceivingId == receiving.id;

                          // FITUR (13 Oktober 2026 -- permintaan user
                          // "Penambahan informasi pada MONITORING RESI"):
                          // plat/sopir/tanggal loading/tanggal tiba,
                          // diambil dari `receivingProgressSummaryProvider`
                          // yang SUDAH diperluas bawa info ini sekalian
                          // (lihat doc comment
                          // `MonitoringService.getReceivingProgressSummary`)
                          // -- TIDAK ada query tambahan per kartu resi di
                          // sini.
                          final progressEntry = progress?[receiving.id];
                          final vehiclePlateNumber =
                              progressEntry?['vehiclePlateNumber'] as String?;
                          final driverName =
                              progressEntry?['driverName'] as String?;
                          final loadedAt =
                              progressEntry?['loadedAt'] as DateTime?;
                          final deliveredAt =
                              progressEntry?['deliveredAt'] as DateTime?;
                          final loadedByName =
                              progressEntry?['loadedByName'] as String?;
                          // BUGFIX TAMPILAN (14 Oktober 2026 -- lihat doc
                          // comment `isBypassAdmin` di
                          // `MonitoringService.getReceivingProgressSummary`):
                          // resi yang diselesaikan lewat tombol
                          // "Selesaikan (Bypass)" TIDAK PERNAH punya sopir/
                          // kendaraan asli -- jangan tampilkan plat
                          // placeholder "DISELESAIKAN ADMIN" (SEBELUMNYA
                          // "BYPASS-SIMULASI", lihat `VehicleService.
                          // getOrCreateBypassVehicle`) seolah plat sungguhan.
                          final isBypassAdmin =
                              progressEntry?['isBypassAdmin'] as bool? ?? false;

                          // FITUR (16 Oktober 2026 -- lihat doc comment
                          // `_isResiOverdue`): resi Penerimaan yang sudah
                          // lewat `resiOverdueDays` hari ditandai kotak
                          // merah tegas, menggantikan border biru netral
                          // bawaan kartu.
                          final isOverdue = _isResiOverdue(
                            receiving,
                            resiStatus,
                            resiOverdueDays,
                          );

                          return Container(
                            decoration: BoxDecoration(
                              color: isOverdue
                                  ? AppColors.red.withOpacity(0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isOverdue
                                    ? AppColors.red
                                    : AppColors.blue.withOpacity(0.10),
                                width: isOverdue ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ReceivingDetailPage(receiving: receiving),
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
                                              // FITUR (8 Oktober 2026 --
                                              // poin 4): nomor buku di
                                              // belakang nomor resi kalau
                                              // ada. FITUR (13 Oktober 2026
                                              // -- permintaan user): tanggal
                                              // + jam input resi (created
                                              // date) ikut ditambahkan di
                                              // belakang nomor, HURUF SAMA
                                              // (fontSize/fontWeight) dengan
                                              // nomor resi.
                                              '${(receiving.nomorBuku != null && receiving.nomorBuku!.isNotEmpty) ? '${receiving.receiptNumber} / ${receiving.nomorBuku}' : receiving.receiptNumber} • '
                                              '${formatDateId(receiving.createdAt)}, ${formatTimeId(receiving.createdAt)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            // FITUR (13 Oktober 2026 --
                                            // permintaan user): "Perbesar
                                            // huruf Tujuan sebagaimana
                                            // besarnya huruf No Resi/No
                                            // buku" -- fontSize disamakan
                                            // (15) dengan Text nomor resi di
                                            // atas, warna/berat huruf tetap
                                            // dibedakan (secondary/normal)
                                            // supaya nomor resi tetap jadi
                                            // fokus utama visual.
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
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            // FITUR (8 Oktober 2026, lanjutan
                                            // lagi -- permintaan user
                                            // eksplisit): nama pegawai yang
                                            // menginput resi ini, "untuk
                                            // track pelaksana". FITUR (13
                                            // Oktober 2026 -- permintaan
                                            // user): "Perbesar sedikit huruf
                                            // diinput Oleh" -- fontSize
                                            // dinaikkan dari 11 -> 12.5.
                                            Text(
                                              'Diinput: ${_employeeName(employeesAsync.value, receiving.receivedBy)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12.5,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            // FITUR (13 Oktober 2026 --
                                            // permintaan user): "Tambahkan
                                            // Tanggal Input" -- berpasangan
                                            // dengan baris "Diinput" di
                                            // atas (siapa + kapan), huruf
                                            // sama besar (12.5).
                                            Text(
                                              'Tanggal Input: ${formatDateId(receiving.createdAt)}, pukul ${formatTimeId(receiving.createdAt)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12.5,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 132,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            // FITUR (9 Oktober 2026 --
                                            // permintaan user eksplisit):
                                            // badge status per resi, lihat
                                            // doc comment `_resiStatus`.
                                            // FITUR (13 Oktober 2026 --
                                            // permintaan user): "Perbesar
                                            // Huruf status resi" -- lihat
                                            // `_buildStatusBadge` (fontSize
                                            // dinaikkan 9.5 -> 12).
                                            _buildStatusBadge(resiStatus),
                                            const SizedBox(height: 4),
                                            // FITUR (13 Oktober 2026 --
                                            // permintaan user): "Pada
                                            // Belakang Nilai Uang Tambahkan
                                            // Status : Bayar Kantor atau
                                            // bayar tujuan ... dengan huruf
                                            // sama besarnya nilai" -- label
                                            // dari `ReceivingPaymentStatus.
                                            // label()` (field yang SUDAH
                                            // ada sejak #21), DIGABUNG ke
                                            // Text yang SAMA dengan nilai
                                            // uang supaya style-nya
                                            // (fontWeight/fontSize) persis
                                            // sama, bukan dibuat Text
                                            // terpisah.
                                            Text(
                                              '${formatRupiah(receiving.totalPrice)} • '
                                              '${ReceivingPaymentStatus.label(receiving.paymentStatus)}',
                                              textAlign: TextAlign.right,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                            // FITUR (13 Oktober 2026 --
                                            // permintaan user): "tambahkan
                                            // Plat kendaraan dan Nama Sopir
                                            // (kosong jika masih status
                                            // Penerimaan) & Tanggal Loading
                                            // ... dan Tanggal Tiba (kosong
                                            // jika belum selesai)" --
                                            // ditampilkan di sini (kanan
                                            // ujung kartu, di bawah badge
                                            // status).
                                            ..._buildShipmentInfoLines(
                                              resiStatus: resiStatus,
                                              vehiclePlateNumber: vehiclePlateNumber,
                                              driverName: driverName,
                                              loadedAt: loadedAt,
                                              loadedByName: loadedByName,
                                              deliveredAt: deliveredAt,
                                              isBypassAdmin: isBypassAdmin,
                                            ),
                                          ],
                                        ),
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
                                // FITUR (10 Oktober 2026 -- permintaan
                                // user eksplisit): tombol "Selesaikan"
                                // di SETIAP resi -- lihat doc comment
                                // `_confirmAndCompleteReceiving`. Tetap
                                // tampil walau resi sudah "Selesai"
                                // (dinonaktifkan/label beda), supaya
                                // posisi tombol konsisten di semua
                                // kartu.
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: AppColors.fieldFill, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: (resiStatus == _ResiStatus.selesai ||
                                              isCompleting)
                                          ? null
                                          : () => _confirmAndCompleteReceiving(receiving),
                                      icon: isCompleting
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.task_alt_rounded, size: 16),
                                      label: Text(
                                        resiStatus == _ResiStatus.selesai
                                            ? 'Sudah Selesai'
                                            : (isCompleting ? 'Memproses...' : 'Selesaikan'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: resiStatus == _ResiStatus.selesai
                                            ? AppColors.textSecondary
                                            : AppColors.red,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat daftar resi.',
          message: error.toString(),
          onRetry: () {
            ref.invalidate(allReceivingsProvider);
            ref.invalidate(receivingProgressSummaryProvider);
          },
        ),
      ),
    );
  }

  // FITUR (16 Oktober 2026 -- Sort): tombol toggle urutan resi
  // Baru->Lama / Lama->Baru, lihat doc comment `_sortOldestFirst`.
  // Bentuknya SAMA TINGGI dengan `TextField` pencarian di sebelahnya
  // (`Container` kotak, bukan `IconButton` bulat biasa) supaya sejajar
  // rapi dalam 1 baris.
  Widget _buildSortButton() {
    return Tooltip(
      message: _sortOldestFirst
          ? 'Urutan: Resi Lama ke Baru (tap untuk balik)'
          : 'Urutan: Resi Baru ke Lama (tap untuk balik)',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _sortOldestFirst = !_sortOldestFirst),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _sortOldestFirst
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            color: AppColors.blue,
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.navy),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // FITUR (9 Oktober 2026 -- permintaan user eksplisit): badge kecil di
  // tiap kartu resi, nunjukin status Penerimaan/Masih Perjalanan/Selesai
  // (lihat doc comment `_resiStatus`).
  Widget _buildStatusBadge(_ResiStatus? status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            _statusLabel(status),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  // FITUR (13 Oktober 2026 -- permintaan user "Penambahan informasi pada
  // MONITORING RESI"): baris tambahan di kanan-bawah badge status --
  // "Plat kendaraan dan Nama Sopir (kosong jika masih status
  // penerimaan)" & "Tanggal Loading ... dan Tanggal Tiba (kosong jika
  // belum selesai)". Datanya dari `MonitoringService.
  // getReceivingProgressSummary` (sudah diperluas, lihat doc comment di
  // sana) -- TIDAK ada query tambahan per kartu di sini.
  //
  // Gerbang tampil SENGAJA dari `resiStatus` (bukan null-check langsung
  // ke `vehiclePlateNumber`/`loadedAt`), supaya konsisten SATU sumber
  // kebenaran dengan badge status di atasnya:
  //   - resiStatus == penerimaan -> baris kendaraan & Loading TIDAK
  //     ditampilkan sama sekali (resi belum pernah dimuat).
  //   - resiStatus == selesai -> baris Tiba ikut ditampilkan (deliveredAt
  //     DIJAMIN terisi persis saat status jadi Selesai -- lihat doc
  //     comment `getReceivingProgressSummary`, 'deliveredAt' = scan
  //     DELIVER terakhir).
  List<Widget> _buildShipmentInfoLines({
    required _ResiStatus? resiStatus,
    required String? vehiclePlateNumber,
    required String? driverName,
    required DateTime? loadedAt,
    required String? loadedByName,
    required DateTime? deliveredAt,
    required bool isBypassAdmin,
  }) {
    if (resiStatus == null || resiStatus == _ResiStatus.penerimaan) {
      return const [];
    }

    Widget line(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          text,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // BUGFIX TAMPILAN (14 Oktober 2026 -- laporan user: resi yang
    // diselesaikan lewat tombol "Selesaikan (Bypass)" tampil "Loading:
    // {tanggal} • Tasman" padahal RESI INI TIDAK PERNAH benar-benar
    // dimuat -- cuma di-bypass). `loadedAt`/`loadedByName`/`deliveredAt`
    // di sini SAH secara data (baris scan LOAD+DELIVER memang ada di
    // `shipment_scans`), TAPI baris itu SINTETIS, dibuat otomatis oleh
    // `ShipmentService.forceCompleteReceivingByAdmin` pada SAAT tombol
    // Bypass ditekan (BUKAN scan fisik sungguhan) -- memakai label
    // "Loading"/"Tiba"/plat kendaraan di sini jadi MENYESATKAN (seolah
    // barang benar-benar naik kendaraan & sampai tujuan). Kalau
    // `isBypassAdmin`, SENGAJA diganti 1 baris jujur yang pakai kata
    // "Bypass"/"Simulasi", BUKAN "Loading"/"Tiba"/plat placeholder
    // "BYPASS-SIMULASI" -- `loadedAt`/`loadedByName` tetap dipakai
    // (waktu & siapa yang MENEKAN tombol Bypass, bukan loading
    // sungguhan).
    // PERMINTAAN USER (14 Oktober 2026, lanjutan langsung): "jika dia
    // bypass bukan loading seharusnya jangan ada kata loading disitu.
    // Cukup bypass tanggal berapa." -- disederhanakan jadi "Bypass:
    // {tanggal}" (tanpa kata "Loading"/"Admin"/"Simulasi"). LALU user
    // minta lagi: "tetap siapa yang Bypass" -- nama pegawai
    // (`loadedByName`, dari `scanned_by`) ditambahkan balik di belakang
    // tanggal.
    if (isBypassAdmin) {
      final who = (loadedByName != null && loadedByName.isNotEmpty)
          ? ' • $loadedByName'
          : '';
      return [
        line(
          loadedAt != null
              ? 'Bypass: ${formatDateId(loadedAt)}$who'
              : 'Bypass$who',
        ),
      ];
    }

    final vehicleLabel = [
      if (vehiclePlateNumber != null && vehiclePlateNumber.isNotEmpty)
        vehiclePlateNumber,
      if (driverName != null && driverName.isNotEmpty) driverName,
    ].join(' • ');

    // FITUR (13 Oktober 2026 -- permintaan user: "Tambahkan dibelakang
    // tanggal Loading : nama Pegawai yang loading dari tabel employee"):
    // nama PEGAWAI yang MELAKUKAN scan LOAD (`loadedByName`, dari
    // `scanned_by`) -- SENGAJA ditampilkan terpisah dari `driverName` di
    // baris kendaraan di atas, karena bisa beda orang (mis. admin yang
    // loading manual, bukan sopir resmi shipment).
    final loadingLine = loadedAt == null
        ? null
        : 'Loading: ${formatDateId(loadedAt)}, ${formatTimeId(loadedAt)}'
            '${(loadedByName != null && loadedByName.isNotEmpty) ? ' • $loadedByName' : ''}';

    return [
      if (vehicleLabel.isNotEmpty) line(vehicleLabel),
      if (loadingLine != null) line(loadingLine),
      if (resiStatus == _ResiStatus.selesai && deliveredAt != null)
        line('Tiba: ${formatDateId(deliveredAt)}, ${formatTimeId(deliveredAt)}'),
    ];
  }

  // FITUR (9 Oktober 2026 -- permintaan user eksplisit): "Sehingga
  // halaman ini bisa jadi kontrol pimpinan resi mana yang harus segera
  // diberangkatkan" -- chip filter ini (bukan cuma badge pasif di tiap
  // kartu) yang jawab kebutuhan itu: tap "Penerimaan" langsung
  // menyaring daftar jadi CUMA resi yang belum diberangkatkan sama
  // sekali, tanpa perlu scroll manual cari satu-satu.
  Widget _buildStatusFilterChips(
    Map<_ResiStatus, int> counts,
    int loadingCount,
  ) {
    Widget chip(String label, _ResiStatus? value, Color color, int count) {
      final selected = _statusFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) {
            setState(() => _statusFilter = selected ? null : value);
          },
          label: Text('$label ($count)'),
          labelStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : color,
          ),
          avatar: Icon(
            _statusIcon(value),
            size: 14,
            color: selected ? Colors.white : color,
          ),
          selectedColor: color,
          backgroundColor: color.withOpacity(0.10),
          side: BorderSide(color: color.withOpacity(selected ? 0 : 0.25)),
          showCheckmark: false,
        ),
      );
    }

    final totalCount =
        counts.values.fold<int>(0, (s, v) => s + v) + loadingCount;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Semua', null, AppColors.blue, totalCount),
          chip(
            'Penerimaan',
            _ResiStatus.penerimaan,
            AppColors.violet,
            counts[_ResiStatus.penerimaan] ?? 0,
          ),
          chip(
            'Masih Perjalanan',
            _ResiStatus.masihPerjalanan,
            AppColors.orange,
            counts[_ResiStatus.masihPerjalanan] ?? 0,
          ),
          chip(
            'Selesai',
            _ResiStatus.selesai,
            AppColors.green,
            counts[_ResiStatus.selesai] ?? 0,
          ),
        ],
      ),
    );
  }
}