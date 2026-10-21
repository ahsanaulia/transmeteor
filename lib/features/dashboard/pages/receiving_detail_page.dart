import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/receiving_detail_model.dart';
import '../../../models/receiving_model.dart';
import '../../../models/sender_model.dart';
import '../../../models/storage_model.dart';
import '../../../providers/dashboard_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../../../providers/receiving_detail_providers.dart';
import '../../../services/receiving_service.dart';
import '../../printing/pages/receipt_preview_page.dart';
import '../../receiving/pages/receiving_item_detail_page.dart';
import '../../receiving/widgets/receiving_detail_form_sheet.dart';
import '../../receiving/widgets/receiving_edit_sheet.dart';

/// Halaman detail satu resi (dashboard) -- ringkasan angka, grafik donut
/// komposisi barang, dan daftar item yang bisa di-tap untuk lihat detail
/// per barang.
///
/// Ditambahkan (8 Oktober 2026, lanjutan lagi -- permintaan user
/// eksplisit: "cetak resi di Monitoring Resi pada admin") -- tombol
/// "Cetak Resi" di AppBar, membuka `ReceiptPreviewPage` yang SAMA PERSIS
/// dipakai staff Receiving (`ReceivingItemsPage._openReceiptPreview`),
/// BUKAN dibikin ulang dari nol -- supaya admin yang memantau lewat
/// "Monitoring Resi" bisa langsung cetak ulang/print resi tanpa harus
/// buka flow staff Receiving dulu, dan otomatis ikut konsisten kalau
/// `ReceiptPreviewPage`/`PdfTemplates` diubah lagi nanti (satu sumber
/// kebenaran, tidak ada 2 versi tampilan resi yang bisa drift).
///
/// Ditambahkan 21 September 2026 -- "Hapus Resi (Admin)": intervensi admin
/// untuk menghapus resi yang terlanjur dibuat tapi tidak jadi diisi barang
/// (mis. gara-gara bug realtime jenis tarif di atas, sebelum diperbaiki --
/// staff Receiving sempat bikin resi kosong lalu tidak jadi dipakai).
/// `ReceivingService.deleteReceiving()` sudah ada sejak awal (hard delete,
/// `receiving_details` ikut terhapus lewat ON DELETE CASCADE) -- yang
/// belum ada cuma tombolnya.
///
/// PERBAIKAN (14 Oktober 2026 -- permintaan user eksplisit: "Proses
/// penghapusan resi di Admin. Harus menghapus data loading, jika sudah
/// loading. Agar data tidak salah"). SEBELUMNYA kalau barang di resi ini
/// SUDAH PERNAH discan ke sebuah pengiriman, Postgres MENOLAK hapusnya
/// (FK violation) -- resi yang sudah loading jadi tidak bisa dihapus
/// sama sekali. SEKARANG `deleteReceiving` ikut menghapus data loading
/// (`shipment_scans`) resi ini DULU sebelum resi-nya sendiri dihapus,
/// supaya penghapusan tetap bisa jalan tanpa menyisakan data loading
/// yang menggantung/salah. Dialog konfirmasi di bawah menyesuaikan
/// peringatannya kalau resi ini terdeteksi sudah pernah loading
/// (`hasBeenLoaded`, dari `resiLoadingEventsProvider`).
class ReceivingDetailPage extends ConsumerWidget {
  final ReceivingModel receiving;

  const ReceivingDetailPage({super.key, required this.receiving});

  static const _palette = [
    AppColors.blue,
    AppColors.cyan,
    AppColors.violet,
    AppColors.green,
    AppColors.orange,
    AppColors.pink,
    AppColors.red,
    AppColors.navy,
    AppColors.lightBlue,
  ];

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  // ============================================================
  // HAPUS RESI (INTERVENSI ADMIN)
  // ============================================================

  Future<void> _confirmDeleteReceiving(
    BuildContext context,
    WidgetRef ref,
    int itemCount, {
    required bool hasBeenLoaded,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Hapus Resi Ini?'),
          content: Text(
            [
              itemCount > 0
                  ? 'Resi ${receiving.receiptNumber} beserta $itemCount '
                      'barang di dalamnya akan DIHAPUS PERMANEN. Aksi ini '
                      'tidak bisa dibatalkan.'
                  : 'Resi ${receiving.receiptNumber} (belum ada barang '
                      'diisi) akan DIHAPUS PERMANEN. Aksi ini tidak bisa '
                      'dibatalkan.',
              // PERBAIKAN (14 Oktober 2026 -- permintaan user eksplisit):
              // resi yang sudah loading SEKARANG BOLEH dihapus (tidak lagi
              // ditolak FK), tapi data loadingnya ikut terhapus -- admin
              // harus sadar ini sebelum konfirmasi.
              if (hasBeenLoaded)
                'Resi ini SUDAH PERNAH dimuat ke kendaraan -- data loading '
                    '(riwayat pemuatan & manifest) untuk resi ini akan ikut '
                    'terhapus supaya tidak ada data yang salah/menggantung.',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ReceivingService.deleteReceiving(receiving.id);

      ref.invalidate(allReceivingsProvider);
      ref.invalidate(dashboardSummaryProvider);

      if (!context.mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resi ${receiving.receiptNumber} dihapus.')),
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus resi: ${e.message}')),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menghapus resi: $e')));
    }
  }

  // ============================================================
  // CETAK RESI (ADMIN -- dari "Monitoring Resi")
  // ============================================================
  //
  // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
  // buka `ReceiptPreviewPage` yang SAMA PERSIS dipakai staff Receiving
  // (lihat doc comment kelas di atas) -- tombol ini cukup NAVIGASI, tidak
  // generate PDF/thermal apa pun sendiri di sini, supaya tampilan resi
  // yang dicetak admin dari "Monitoring Resi" TIDAK PERNAH bisa beda dari
  // yang dicetak staff Receiving (termasuk otomatis ikut perbaikan "Nama
  // Barang" terbaru di `PdfTemplates`/`PrintTemplates`, karena sumbernya
  // SATU widget yang sama).
  void _openReceiptPreview(
    BuildContext context,
    SenderModel? sender,
    List<ReceivingDetailModel> items,
  ) {
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
  // TAMBAH BARANG BARU (ADMIN) -- permintaan user eksplisit 8 Oktober
  // 2026, lanjutan lagi: "Editing di sisi Admin ... dan Menambah Barang
  // Baru" (lihat juga doc comment `ReceivingItemDetailPage` untuk
  // edit/hapus 1 barang yang sudah ada). Dipakai mis. untuk memecah
  // "Tegel 100 Karton" yang keliru digabung jadi 2 baris baru yang benar
  // (10x10 30 Karton + 40x60 70 Karton) TANPA menyentuh baris lama yang
  // mungkin sudah sebagian dimuat.
  //
  // Kode item baru digenerate dengan pola SAMA PERSIS yang dipakai
  // `ReceivingItemsPage._openAddSheet` (alur staff Receiving bikin resi
  // baru) -- supaya tidak ada 2 skema penomoran item_code yang berbeda
  // untuk resi yang sama.
  Future<void> _openAddItemSheet(
    BuildContext context,
    WidgetRef ref,
    List<ReceivingDetailModel> currentItems,
  ) async {
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

  // ============================================================
  // EDIT RESI (ADMIN) -- FITUR (13 Oktober 2026, permintaan user
  // "Tambahan Fitur" poin 2-4, dikonfirmasi ulang: "Bukan dibagian edit.
  // Tetapi di Resi. Edit Resi"). SATU-SATUNYA tempat admin menginput
  // status pembayaran (Bayar Tujuan/Bayar Dikantor) & DP.
  // ============================================================
  //
  // `receiving` di halaman ini adalah parameter widget biasa (snapshot
  // saat halaman dibuka), BUKAN di-watch dari provider -- jadi setelah
  // sheet edit berhasil simpan, halaman ini di-pushReplacement dengan
  // data resi yang sudah di-fetch ulang dari server, supaya semua
  // tampilan (header, kartu, dll) langsung ikut berubah tanpa perlu
  // keluar-masuk halaman manual.
  Future<void> _openEditResiSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceivingEditSheet(existing: receiving),
    );

    if (saved != true) return;

    try {
      final updated = await ReceivingService.getReceivingById(receiving.id);

      if (!context.mounted) return;

      ref.invalidate(allReceivingsProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(receivingDetailsProvider(receiving.id));

      if (updated == null) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReceivingDetailPage(receiving: updated),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Resi berhasil diubah, tapi gagal memuat ulang tampilan: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(receivingDetailsProvider(receiving.id));
    final sendersAsync = ref.watch(sendersProvider);
    final loadingEventsAsync = ref.watch(resiLoadingEventsProvider(receiving.id));
    // FITUR (13 Oktober 2026, permintaan user "Tambahan Fitur" poin 1):
    // tampilkan zona storage per barang sebagai history lokasi barang
    // (diterima/loading/tiba). Pakai [allStoragesProvider] (BUKAN
    // [storagesProvider] yang cuma aktif) -- supaya zona yang SUDAH
    // dinonaktifkan tetap bisa ditampilkan namanya untuk barang lama
    // (history jangan tiba-tiba jadi "-" cuma karena zonanya dinonaktifkan
    // admin belakangan).
    final storagesAsync = ref.watch(allStoragesProvider);
    final storageNameById = <String, String>{};
    for (final storage in storagesAsync.value ?? const <StorageModel>[]) {
      storageNameById[storage.id] = storage.namaZona;
    }

    String? senderName;
    SenderModel? senderModel;
    final senders = sendersAsync.value;
    if (senders != null) {
      for (final sender in senders) {
        if (sender.id == receiving.senderId) {
          senderModel = sender;
          senderName = sender.name;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(receiving.receiptNumber),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Tambah Barang Baru',
            onPressed: itemsAsync.value == null
                ? null
                : () => _openAddItemSheet(
                      context,
                      ref,
                      itemsAsync.value!,
                    ),
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.green),
          ),
          IconButton(
            tooltip: 'Cetak Resi',
            onPressed: itemsAsync.value == null
                ? null
                : () => _openReceiptPreview(
                      context,
                      senderModel,
                      itemsAsync.value!,
                    ),
            icon: const Icon(Icons.print_rounded, color: AppColors.blue),
          ),
          IconButton(
            tooltip: 'Edit Resi',
            onPressed: () => _openEditResiSheet(context, ref),
            icon: const Icon(Icons.edit_note_rounded, color: AppColors.orange),
          ),
          IconButton(
            tooltip: 'Hapus Resi (Admin)',
            onPressed: () => _confirmDeleteReceiving(
              context,
              ref,
              itemsAsync.value?.length ?? 0,
              hasBeenLoaded: loadingEventsAsync.value?.isNotEmpty ?? false,
            ),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
          ),
        ],
      ),
      body: itemsAsync.when(
        data: (items) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            children: [
              _buildHeaderCard(senderName, loadingEventsAsync),
              const SizedBox(height: 16),
              _buildStatsRow(items),
              const SizedBox(height: 16),
              _buildCompositionChart(items),
              const SizedBox(height: 16),
              _buildItemListCard(context, items, storageNameById),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat detail resi.',
          message: error.toString(),
          onRetry: () => ref.invalidate(receivingDetailsProvider(receiving.id)),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    String? senderName,
    AsyncValue<List<Map<String, dynamic>>> loadingEventsAsync,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.blue],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            receiving.receiptNumber,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          // NOTE (22 Sep 2026 -- perbaikan ambiguitas Penerima vs
          // Tujuan): baris "Penerima" terpisah (dulu receiverName
          // manual) dihapus -- sudah diwakili "Tujuan" di bawah (satu-
          // satunya sumber data sekarang). "Hp" sekarang dari
          // destinationPhone (snapshot data Tujuan).
          _headerLine('Pengirim', senderName ?? '-'),
          _headerLine('Tujuan', receiving.destination),
          if (receiving.destinationPhone != null &&
              receiving.destinationPhone!.isNotEmpty)
            _headerLine('Hp', receiving.destinationPhone!),
          if (receiving.route != null) _headerLine('Rute', receiving.route!),
          _headerLine('Status', receiving.status),
          // FITUR (13 Oktober 2026, permintaan user "Tambahan Fitur"
          // poin 2-4): status pembayaran selalu tampil (resi lama tanpa
          // migrasi otomatis dianggap Bayar Tujuan, lihat default di
          // `ReceivingModel`/migrasi SQL). Baris DP cuma tampil kalau
          // benar-benar ada nilainya (>0).
          _headerLine(
            'Pembayaran',
            ReceivingPaymentStatus.label(receiving.paymentStatus),
          ),
          if (receiving.dpAmount != null && receiving.dpAmount! > 0)
            _headerLine('DP', formatRupiah(receiving.dpAmount!)),
          // **DITAMBAHKAN (13 Oktober 2026, permintaan user eksplisit)**:
          // "Diterima kapan dan jamnya" -- SELALU tampil (resi pasti
          // punya receivedAt). Baris "Dimuat"/"Tiba" di bawah menyusul
          // HANYA kalau resi ini sudah pernah disentuh Loading sama
          // sekali (lihat `_buildLoadingEventsSection`).
          _headerLine(
            'Diterima',
            '${formatDateId(receiving.receivedAt)}, pukul '
                '${formatTimeId(receiving.receivedAt)}',
          ),
          _buildLoadingEventsSection(loadingEventsAsync),
        ],
      ),
    );
  }

  /// "Jika sudah berangkat atau tiba (dalam perjalanan atau sudah
  /// selesai). Maka ditambahkan: Kapan dimuat, di mobil mana No Plat dan
  /// Sopirnya. Jika terdapat 2 atau 3 pemuatan atas resi yang sama
  /// muncul kesemuanya. Jika tiba tertulis tanggal selesainya." --
  /// permintaan user eksplisit 13 Oktober 2026.
  ///
  /// `loadingEventsAsync` KOSONG berarti resi ini belum pernah disentuh
  /// Loading sama sekali (masih status "Penerimaan") -- blok ini TIDAK
  /// tampil sama sekali, konsisten dengan baris "Status" di atas yang
  /// sudah bilang "Penerimaan". Satu entri PER KENDARAAN yang pernah
  /// memuat bagian resi ini (lihat doc comment
  /// `MonitoringService.getLoadingEventsForReceiving`) -- kalau resi
  /// terpecah ke 2-3 kendaraan, SEMUA entri tampil, tidak cuma yang
  /// pertama ketemu.
  Widget _buildLoadingEventsSection(
    AsyncValue<List<Map<String, dynamic>>> loadingEventsAsync,
  ) {
    return loadingEventsAsync.when(
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();

        final isSplit = events.length > 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Divider(color: Colors.white.withOpacity(0.2), height: 17),
            for (var i = 0; i < events.length; i++) ...[
              if (isSplit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, top: 2),
                  child: Text(
                    'Kendaraan ${i + 1} dari ${events.length}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              _buildLoadingEventLines(events[i]),
              if (i < events.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
      // Loading/error ditahan senyap -- baris "Diterima"/"Status" di atas
      // tetap tampil normal, blok ini cuma tambahan, bukan blocker.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLoadingEventLines(Map<String, dynamic> event) {
    final plate = event['vehiclePlateNumber']?.toString();
    final driverName = event['driverName']?.toString();
    final loadedAt = event['loadedAt'] as DateTime?;
    final arrivedAt = event['arrivedAt'] as DateTime?;

    final vehicleLabel = [
      if (plate != null && plate.isNotEmpty) plate,
      if (driverName != null && driverName.isNotEmpty) driverName,
    ].join(' • ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vehicleLabel.isNotEmpty) _headerLine('Kendaraan', vehicleLabel),
        if (loadedAt != null)
          _headerLine(
            'Dimuat',
            '${formatDateId(loadedAt)}, pukul ${formatTimeId(loadedAt)}',
          ),
        if (arrivedAt != null)
          _headerLine(
            'Tiba',
            '${formatDateId(arrivedAt)}, pukul ${formatTimeId(arrivedAt)}',
          ),
      ],
    );
  }

  Widget _headerLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(List<ReceivingDetailModel> items) {
    final totalQuantity = items.fold<double>(0, (s, i) => s + i.quantity);
    final totalPrice = items.fold<double>(0, (s, i) => s + (i.totalPrice ?? 0));

    final stats = [
      _StatData('Jumlah Item', '${items.length}', AppColors.blue, Icons.category_rounded),
      _StatData(
        'Total Barang',
        _formatQuantity(totalQuantity),
        AppColors.cyan,
        Icons.inventory_2_rounded,
      ),
      _StatData('Total Nilai', formatRupiah(totalPrice), AppColors.green, Icons.payments_rounded),
    ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _buildStatCard(stats[i])),
        ],
      ],
    );
  }

  Widget _buildStatCard(_StatData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: data.color, size: 18),
          const SizedBox(height: 8),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompositionChart(List<ReceivingDetailModel> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    final totalPrice = items.fold<double>(0, (s, i) => s + (i.totalPrice ?? 0));
    final useQuantity = totalPrice <= 0;

    final sections = <PieChartSectionData>[];
    final legend = <Widget>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final value = useQuantity ? item.quantity : (item.totalPrice ?? 0);
      if (value <= 0) continue;

      final color = _palette[i % _palette.length];

      sections.add(
        PieChartSectionData(color: color, value: value, title: '', radius: 54),
      );

      legend.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            useQuantity ? 'Komposisi Barang (Kuantitas)' : 'Komposisi Nilai Barang',
            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 30),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: legend),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemListCard(
    BuildContext context,
    List<ReceivingDetailModel> items,
    Map<String, String> storageNameById,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.blue.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daftar Barang',
            style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text('Belum ada barang.', style: TextStyle(color: AppColors.textSecondary))
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _palette[i % _palette.length].withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceivingItemDetailPage(
                            receivingDetailId: items[i].id,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _palette[i % _palette.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  items[i].itemName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                Text(
                                  '${_formatQuantity(items[i].quantity)} ${items[i].quantityUnit}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                ),
                                // FITUR (13 Oktober 2026, poin 1): zona
                                // storage sebagai history lokasi barang --
                                // tampil terlepas dari status resi saat ini
                                // (diterima/loading/tiba), SELALU kalau
                                // storage_id terisi.
                                if (items[i].storageId != null) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_outlined,
                                        size: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        storageNameById[items[i].storageId] ??
                                            'Zona tidak ditemukan',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            formatRupiah(items[i].totalPrice ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                          const SizedBox(width: 6),
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
              ),
        ],
      ),
    );
  }
}

class _StatData {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  _StatData(this.label, this.value, this.color, this.icon);
}