import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pdf_templates.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/shipment_service.dart';

/// Preview PDF "Tanda Terima Tujuan" SEBELUM dibagikan -- permintaan user
/// (22 September 2026): "sebelum kirim pdf sebaiknya memang ada preview
/// disitu". Sebelumnya tombol "Tanda Terima Tujuan" (baik di
/// `ShipmentDispatchPage` maupun `ShipmentDepartedSearchPage`) langsung
/// generate & share PDF begitu ditekan, TANPA kesempatan lihat isinya
/// dulu -- beda dari pola preview-dulu yang dipakai HAMPIR SEMUA fitur
/// cetak lain di app ini (label, resi, laporan, manifest).
///
/// SENGAJA pakai widget `PdfPreview` dari package `printing` (BUKAN bikin
/// UI custom yang meniru tampilan PDF, seperti pola di
/// ManifestPage/ReceiptPreviewPage) -- alasannya: `PdfPreview` merender
/// BYTES PDF ASLI yang SAMA PERSIS akan dibagikan, jadi preview ini TIDAK
/// PERNAH bisa "beda" dari hasil cetakan sungguhan (nol risiko drift
/// antara tampilan preview & PDF asli kalau
/// `PdfTemplates.buildDestinationReceiptDocument` diubah lagi nanti).
/// Ini penting khususnya untuk dokumen ini karena sudah pernah ditegaskan
/// user: cetakan/reprint harus tetap bisa dipercaya persis sama untuk
/// keperluan komplain -- lihat doc comment di
/// `ShipmentDepartedSearchPage`.
///
/// PDF-nya sendiri digenerate LANGSUNG di sini (lewat `_buildPdf`, isinya
/// PERSIS PANGGILAN YANG SAMA seperti sebelumnya di
/// `_printDestinationReceipt` yang lama) -- kalau nanti user minta
/// preview serupa untuk dokumen lain, method `_buildPdf` + `PdfPreview`
/// ini bisa dicontoh langsung, tidak perlu bikin UI custom dari nol.
class DestinationReceiptPreviewPage extends ConsumerWidget {
  final ShipmentModel shipment;
  final VehicleModel vehicle;

  const DestinationReceiptPreviewPage({
    super.key,
    required this.shipment,
    required this.vehicle,
  });

  Future<Uint8List> _buildPdf(WidgetRef ref) async {
    final company = await ref.read(companyProvider.future);

    final destinationSummaries =
        await ShipmentService.getManifestSummaryByDestination(shipment.id);

    // DIUBAH (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit:
    // "Daftar Muatan ... yang ditampilkan adalah Nama Barang dan
    // jumlahnya. Bukan Jenis Tarif dan jumlahnya."). Tabel di cetakan ini
    // sekarang digroup per Nama Barang (datang langsung dari
    // `destinationSummaries`), jadi TIDAK PERLU lagi memuat
    // `pricingTypesProvider`/`pricingTypeNameById` di sini -- lihat
    // `PdfTemplates.buildDestinationReceiptDocument`.
    final doc = await PdfTemplates.buildDestinationReceiptDocument(
      shipment: shipment,
      vehicle: vehicle,
      destinationSummaries: destinationSummaries,
      company: company,
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Preview Tanda Terima Tujuan',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
      ),
      // `PdfPreview` sudah punya toolbar bawaan (bagikan/cetak) + loading
      // indicator sendiri selagi `build` berjalan -- tidak perlu bikin
      // tombol "Bagikan PDF" custom lagi di sini seperti pola
      // ManifestPage (yang preview-nya UI custom, bukan PDF asli).
      body: PdfPreview(
        build: (format) => _buildPdf(ref),
        allowSharing: true,
        allowPrinting: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfFileName: 'tanda-terima-tujuan-${shipment.shipmentNumber}.pdf',
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: AppColors.blue),
        ),
      ),
    );
  }
}
//LoadingBy