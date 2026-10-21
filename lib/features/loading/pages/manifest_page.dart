import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pdf_templates.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/shipment_service.dart';
import '../../receiving/pages/receiving_item_detail_page.dart';

/// Halaman manifest -- daftar muatan yang terbentuk otomatis dari hasil
/// scan loading. Diakses dari 2 tempat: otomatis setelah "Selesai Muat",
/// atau dibuka lagi kapan saja lewat ShipmentListPage. Tiap baris barang
/// bisa di-tap untuk buka detail lengkapnya (ReceivingItemDetailPage).
class ManifestPage extends ConsumerStatefulWidget {
  final ShipmentModel shipment;
  final VehicleModel vehicle;

  const ManifestPage({
    super.key,
    required this.shipment,
    required this.vehicle,
  });

  @override
  ConsumerState<ManifestPage> createState() => _ManifestPageState();
}

class _ManifestPageState extends ConsumerState<ManifestPage> {
  bool _isBusy = false;

  /// Bagikan PDF Manifes Barang -- DIGROUP PER RESI (bukan per barang
  /// satuan seperti daftar di layar), sesuai perbaikan permintaan user
  /// (22 Sep 2026). Ambil rekapnya lewat
  /// `ShipmentService.getManifestPrintSummary`, BUKAN dari [scans] mentah
  /// yang cuma dipakai buat daftar tap-to-detail di layar.
  ///
  /// CATATAN: method ini SEMPAT (22 Sep -- 16 Oktober 2026) menampilkan
  /// dialog "Diagnostik Manifest (sementara)" sebelum generate PDF asli,
  /// dipakai investigasi 2 bug berbeda (manifest kosong gara-gara
  /// `pw.Page` -> sudah diperbaiki jadi `pw.MultiPage`; tabel "Pembayaran
  /// di Kantor dan DP" dikira hilang -- ternyata memang tidak ada resi
  /// Bayar Kantor/DP di shipment yang dicoba, BUKAN bug). Dialog
  /// diagnostik itu SUDAH DIHAPUS (16 Oktober 2026, permintaan user
  /// eksplisit "hapus dulu diagnostik itu") setelah kedua investigasi
  /// selesai -- kalau nanti perlu lagi, lihat riwayat di project doc
  /// arsitektur-flutter.md (Tambahan #41) untuk contoh pola yang pernah
  /// dipakai (`ShipmentService.debugManifestDiagnostics` + hitung ulang
  /// `_bayarKantorAmount` dari `getManifestPrintSummary`).
  Future<void> _sharePdf() async {
    setState(() => _isBusy = true);

    try {
      final company = await ref.read(companyProvider.future);

      final resiSummaries = await ShipmentService.getManifestPrintSummary(
        widget.shipment.id,
      );

      final doc = await PdfTemplates.buildManifestDocument(
        shipment: widget.shipment,
        vehicle: widget.vehicle,
        resiSummaries: resiSummaries,
        company: company,
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'manifest-${widget.shipment.shipmentNumber}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'LOADING':
        return 'Sedang Dimuat';
      case 'DEPARTED':
        return 'Berangkat';
      case 'ARRIVED':
        return 'Tiba';
      case 'CANCELLED':
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  /// Buka detail 1 barang dari baris manifest yang SUDAH DIGROUP (lihat
  /// `_groupScansByDetail`) -- tidak lagi mengacu ke 1 scan tertentu (bisa
  /// mewakili banyak scan sekaligus kalau quantity-nya >1), jadi dibuka
  /// TANPA scanUnitCode/scanUnitIndex/scannedAt (parameter itu memang
  /// opsional di ReceivingItemDetailPage -- null berarti tampilkan info
  /// barang + tombol edit/hapus admin seperti biasa, bukan "info scan").
  void _openItemDetailById(String detailId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceivingItemDetailPage(receivingDetailId: detailId),
      ),
    );
  }

  /// **DIUBAH (10 Oktober 2026, permintaan user eksplisit)**: "Daftar
  /// Manifest tadi yang memuat barang: jika barangnya 10 semua 10 barang
  /// tersebut tampil ... Diubah menjadi cukup barang dan jumlahnya saja.
  /// Bukan per label lagi (jika berdasarkan label) untuk preview." --
  /// SEBELUMNYA 1 baris scan LOAD = 1 baris tampilan (jadi barang
  /// berlabel dengan quantity 10 tampil 10 baris identik). Sekarang
  /// di-group per `receiving_detail_id` -- 1 baris barang = 1 baris
  /// tampilan dengan hitungan "x jumlah unit sudah dimuat" di
  /// belakangnya. Scan kamera (`LoadingScanPage`/checklist manual) TETAP
  /// per-label/per-unit seperti biasa -- grouping ini CUMA di preview
  /// layar manifest ini, tidak mengubah cara pencatatan data sama sekali.
  List<Map<String, dynamic>> _groupScansByDetail(
    List<Map<String, dynamic>> scans,
  ) {
    final order = <String>[];
    final groups = <String, Map<String, dynamic>>{};

    for (final scan in scans) {
      final detail = scan['receiving_details'] as Map?;
      final detailId = detail?['id'] as String?;
      // Fallback (seharusnya tidak pernah terjadi -- setiap scan selalu
      // tertaut receiving_detail_id) supaya barang tanpa detail tetap
      // tampil sebagai baris sendiri-sendiri, tidak hilang/numpang grup.
      final key = detailId ?? 'scan-${scan['id']}';

      final group = groups.putIfAbsent(key, () {
        order.add(key);
        final receiving = detail?['receiving'] as Map?;
        return {
          'detailId': detailId,
          'detail': detail,
          'receiptNumber': receiving?['receipt_number'],
          'destination': receiving?['destination'],
          'sampleUnitCode': scan['unit_code'],
          'count': 0,
        };
      });

      group['count'] = (group['count'] as int) + 1;
    }

    return order.map((key) => groups[key]!).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scansAsync = ref.watch(shipmentScansProvider(widget.shipment.id));
    // Manifest TIDAK dicetak thermal (sesuai keputusan) -- hanya kop
    // 'TRANS' di preview layar & PDF yang perlu ikut data company.
    final companyAsync = ref.watch(companyProvider);
    final company = companyAsync.value;

    final pricingTypesAsync = ref.watch(pricingTypesProvider);
    final pricingTypeNameById = PdfTemplates.pricingTypeNameMap(
      pricingTypesAsync.value ?? const [],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Manifest Muatan',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      body: scansAsync.when(
        data: (scans) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 140),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      company?.name ?? 'TRANS',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    if (company?.address != null &&
                        company!.address!.isNotEmpty)
                      Text(
                        company.address!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (company?.phone != null && company!.phone!.isNotEmpty)
                      Text(
                        'Hp. ${company.phone}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    const Text(
                      'MANIFEST MUATAN',
                      style: TextStyle(fontSize: 11, letterSpacing: 0.5),
                    ),
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No. Shipment : ${widget.shipment.shipmentNumber}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text('Kendaraan    : ${widget.vehicle.plateNumber}'),
                          if (widget.vehicle.vehicleType != null)
                            Text('Jenis        : ${widget.vehicle.vehicleType}'),
                          if (widget.vehicle.driverName != null)
                            Text('Sopir        : ${widget.vehicle.driverName}'),
                          Text(
                            'Status       : ${_statusLabel(widget.shipment.status)}',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 24),
                    if (scans.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Belum ada barang yang discan untuk shipment ini.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      for (final entry in _groupScansByDetail(scans)
                          .asMap()
                          .entries)
                        _buildGroupedItemRow(
                          entry.key,
                          entry.value,
                          pricingTypeNameById,
                        ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Barang',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${scans.length}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    QrImageView(
                      data: widget.shipment.shipmentNumber,
                      version: QrVersions.auto,
                      size: 140,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (error, stackTrace) => ErrorStateView(
          title: 'Gagal memuat manifest.',
          message: error.toString(),
          onRetry: () => ref.invalidate(shipmentScansProvider(widget.shipment.id)),
        ),
      ),
      bottomNavigationBar: scansAsync.maybeWhen(
        data: (scans) => Container(
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
            label: 'Bagikan PDF',
            loadingLabel: 'Menyiapkan PDF...',
            isLoading: _isBusy,
            icon: Icons.picture_as_pdf_outlined,
            onPressed: _sharePdf,
          ),
        ),
        orElse: () => null,
      ),
    );
  }

  /// Satu baris = 1 barang (receiving_detail), bukan 1 scan lagi -- lihat
  /// `_groupScansByDetail`. [group] berisi `detail`/`receiptNumber`/
  /// `destination`/`sampleUnitCode`/`count` (jumlah unit yang sudah
  /// dimuat untuk barang ini).
  Widget _buildGroupedItemRow(
    int index,
    Map<String, dynamic> group,
    Map<String, String> pricingTypeNameById,
  ) {
    final detail = group['detail'] as Map?;
    final detailId = group['detailId'] as String?;
    final count = group['count'] as int;

    final rawItemName = detail?['item_name']?.toString() ??
        group['sampleUnitCode']?.toString() ??
        '-';
    final pricingTypeId = detail?['pricing_type_id'] as String?;
    final itemName = PdfTemplates.itemDisplayLabel(
      rawItemName,
      pricingTypeId,
      pricingTypeNameById,
    );
    final quantityUnit = detail?['quantity_unit']?.toString();
    final receiptNumber = group['receiptNumber'];
    final destination = group['destination'];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: detailId == null ? null : () => _openItemDetailById(detailId),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text('${index + 1}.')),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${itemName.toString()} x $count'
                      '${quantityUnit != null && quantityUnit.isNotEmpty ? ' $quantityUnit' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        if (receiptNumber != null) 'Resi $receiptNumber',
                        if (destination != null) 'Tujuan $destination',
                      ].join(' • '),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (detailId != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}