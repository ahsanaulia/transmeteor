import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scan_feedback.dart';
import '../../../core/utils/unit_code.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/shipment_service.dart';

/// Checklist "Pembatalan Loading" (ADMIN) -- FITUR (14 Oktober 2026,
/// permintaan user eksplisit): "Pembatalan Loading. Di admin bisa
/// dibatalkan loading. Dengan cara menghilangkan centangnya. Jadi kalau
/// diadmin barang yang diloading tidak hilang dari layar tetapi
/// patokannya centang. Beda dengan bagian loading. Barang sudah
/// diloading hilang dari layar."
///
/// BEDA PALING MENDASAR dari `ManualLoadChecklistView` ("Tambah" --
/// mode muat barang biasa):
/// - Daftar barang di sini TIDAK PERNAH memfilter baris yang sudah
///   termuat keluar dari layar -- SEMUA barang 1 resi SELALU tampil,
///   baik yang sudah dimuat ke kendaraan ini maupun belum (lihat doc
///   comment `ShipmentService.getManualLoadCancelItems`).
/// - Centang di sini BUKAN "pilih dulu, baru submit sekaligus" --
///   SETIAP toggle langsung dieksekusi SAAT ITU JUGA (langsung memuat
///   kalau dicentang, langsung membatalkan kalau centangnya
///   dihilangkan), supaya status centang SELALU mencerminkan data riil
///   di database (`isLoadedToThisShipment`), tidak pernah jadi status
///   "draft" yang bisa beda dari server.
/// - Resi yang bisa dipilih di langkah 1 DIBATASI ke resi yang SUDAH
///   ada muatannya di shipment ini (`receivingsLoadedOnShipmentProvider`)
///   -- BEDA dari daftar resi global di `ManualLoadChecklistView`,
///   karena pembatalan cuma relevan untuk resi yang memang sudah ada di
///   manifest kendaraan ini.
class ManualLoadCancelChecklistView extends ConsumerStatefulWidget {
  final String shipmentId;

  const ManualLoadCancelChecklistView({
    super.key,
    required this.shipmentId,
  });

  @override
  ConsumerState<ManualLoadCancelChecklistView> createState() =>
      _ManualLoadCancelChecklistViewState();
}

class _ManualLoadCancelChecklistViewState
    extends ConsumerState<ManualLoadCancelChecklistView> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedReceivingId;

  /// detailId yang sedang diproses (lagi memuat/membatalkan) -- dipakai
  /// supaya checkbox baris itu nonaktif sementara & tampil spinner kecil,
  /// MENCEGAH double-tap memicu 2 aksi bertabrakan untuk baris yang sama.
  final Set<String> _processingDetailIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _combinedKey =>
      '${widget.shipmentId}::${_selectedReceivingId ?? ''}';

  /// Memuat SEMUA unit fisik yang masih tersisa dari 1 baris barang --
  /// SAMA PERSIS logika `ManualLoadChecklistView._loadItem`, diduplikasi
  /// sengaja (bukan diekstrak bersama) karena konteks pemanggilannya beda
  /// total: di sini dipanggil LANGSUNG per-toggle (bukan lewat submit
  /// batch), dan errornya ditangani per baris, bukan dikumpulkan.
  Future<String?> _loadItem(Map<String, dynamic> item) async {
    final detailId = item['id'] as String;
    final remainingCodes =
        ((item['remainingUnitCodes'] as List?) ?? const []).cast<String>();

    if (remainingCodes.isEmpty) {
      return 'tidak ada unit tersisa untuk dimuat (mungkin sudah termuat semua)';
    }

    final employee = await ref.read(currentEmployeeProvider.future);
    if (employee == null) {
      return 'Data employee tidak ditemukan, tidak bisa mencatat.';
    }

    var successCount = 0;
    final errors = <String>[];

    for (final code in remainingCodes) {
      try {
        final parsed = UnitCodeParser.parse(code);

        await ShipmentService.recordScan(
          shipmentId: widget.shipmentId,
          receivingDetailId: detailId,
          unitCode: code,
          unitIndex: parsed.unitIndex,
          scannedBy: employee.id,
          notes: 'Admin intervensi: dicentang manual lewat Pembatalan Loading',
        );

        successCount++;
      } on DuplicateScanException {
        errors.add('sudah tercatat dimuat (mungkin oleh staff lain)');
      } catch (e) {
        errors.add('gagal dicatat: $e');
      }
    }

    if (errors.isEmpty) return null;
    if (successCount == 0) return errors.first;
    return '$successCount unit berhasil, ${errors.length} unit gagal';
  }

  Future<void> _toggleItem(Map<String, dynamic> item, bool checkNow) async {
    final detailId = item['id'] as String;
    final itemName = item['item_name']?.toString() ?? 'Barang';

    if (!checkNow) {
      // Uncentang -- BATALKAN loading yang sudah tercatat. Ditolak lebih
      // dulu di sisi UI kalau barangnya sudah ter-DELIVER (lihat
      // `canCancel`, dihitung server di
      // `ShipmentService.getManualLoadCancelItems`) -- jaring pengaman
      // keduanya ada di `ShipmentService.cancelManualLoad`
      // (`LoadAlreadyDeliveredException`) kalau ada yang lolos sampai sini.
      final canCancel = item['canCancel'] as bool? ?? true;
      if (!canCancel) {
        ScanFeedback.playFailure();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$itemName sudah tercatat tiba (DELIVER) -- loading tidak '
              'bisa dibatalkan.',
            ),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
    }

    setState(() => _processingDetailIds.add(detailId));

    String? error;
    try {
      if (checkNow) {
        error = await _loadItem(item);
      } else {
        await ShipmentService.cancelManualLoad(
          shipmentId: widget.shipmentId,
          detailId: detailId,
        );
      }
    } on LoadAlreadyDeliveredException catch (e) {
      error = e.toString();
    } catch (e) {
      error = 'gagal: $e';
    }

    ref.invalidate(manualLoadCancelItemsProvider(_combinedKey));
    ref.invalidate(receivingsLoadedOnShipmentProvider(widget.shipmentId));
    ref.invalidate(shipmentScansProvider(widget.shipmentId));
    ref.invalidate(availableManualLoadItemsProvider);

    if (!mounted) return;

    setState(() => _processingDetailIds.remove(detailId));

    if (error == null) {
      ScanFeedback.playSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            checkNow
                ? '$itemName dicatat naik ke kendaraan ini.'
                : 'Loading $itemName dibatalkan.',
          ),
          backgroundColor: AppColors.green,
        ),
      );
    } else {
      ScanFeedback.playFailure();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$itemName: $error'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _filterReceivings(
    List<Map<String, dynamic>> receivings,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return receivings;

    return receivings.where((r) {
      final receiptNumber = (r['receiptNumber'] as String).toLowerCase();
      final destination = (r['destination'] as String).toLowerCase();
      return receiptNumber.contains(query) || destination.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final receivingsAsync =
        ref.watch(receivingsLoadedOnShipmentProvider(widget.shipmentId));

    return Container(
      color: AppColors.background,
      child: receivingsAsync.when(
        data: (receivings) {
          if (_selectedReceivingId != null) {
            final stillExists = receivings
                .any((r) => r['receivingId'] == _selectedReceivingId);
            if (!stillExists) {
              // Resi yang tadi dipilih sudah tidak ada barang yang
              // termuat di shipment ini lagi (semua barangnya baru
              // dibatalkan) -- balik otomatis ke daftar resi.
              _selectedReceivingId = null;
            } else {
              return _buildChecklist();
            }
          }

          return _buildResiList(receivings);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Gagal memuat daftar resi: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.red),
            ),
          ),
        ),
      ),
    );
  }

  /// Langkah 1: pilih resi yang SUDAH ada muatannya di kendaraan ini.
  Widget _buildResiList(List<Map<String, dynamic>> receivings) {
    final filtered = _filterReceivings(receivings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              labelText: 'Cari No. Resi',
              hintText: 'Contoh: RESI000123',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        if (receivings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hanya resi yang sudah ada muatannya di kendaraan ini '
                      'yang tampil. Pilih resi, lalu hilangkan centang '
                      'barang yang mau dibatalkan loading-nya.',
                      style: TextStyle(
                        color: AppColors.red,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      receivings.isEmpty
                          ? 'Belum ada barang yang dimuat ke kendaraan ini.'
                          : 'Tidak ada resi yang cocok dengan pencarian.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final r = filtered[index];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.red.withOpacity(0.10)),
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.red.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: AppColors.red,
                          ),
                        ),
                        title: Text(
                          (r['nomorBuku'] != null &&
                                  (r['nomorBuku'] as String).isNotEmpty)
                              ? '${r['receiptNumber']} / ${r['nomorBuku']}'
                              : r['receiptNumber'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          r['destination'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          setState(() {
                            _selectedReceivingId = r['receivingId'] as String;
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Langkah 2: resi sudah dipilih -- SEMUA barang resi ini tampil,
  /// centang mencerminkan status riil "sudah dimuat ke kendaraan ini"
  /// atau belum. Toggle langsung dieksekusi (bukan submit batch).
  Widget _buildChecklist() {
    final itemsAsync =
        ref.watch(manualLoadCancelItemsProvider(_combinedKey));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Barang resi ini',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _selectedReceivingId = null);
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Ganti Resi'),
              ),
            ],
          ),
        ),
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Resi ini tidak punya barang.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final id = item['id'] as String;
                  final itemName = item['item_name']?.toString() ?? '-';
                  final quantity = item['quantity'];
                  final quantityUnit = item['quantity_unit']?.toString() ?? '';
                  final isUnlabeled = item['is_unlabeled'] == true;
                  final checked = item['isLoadedToThisShipment'] as bool;
                  final canCancel = item['canCancel'] as bool? ?? true;
                  final isProcessing = _processingDetailIds.contains(id);

                  final zona = (item['storages']
                      as Map<String, dynamic>?)?['nama_zona']?.toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: checked
                            ? AppColors.green.withOpacity(0.5)
                            : AppColors.blue.withOpacity(0.08),
                      ),
                    ),
                    child: CheckboxListTile(
                      value: checked,
                      onChanged: isProcessing
                          ? null
                          : (v) => _toggleItem(item, v == true),
                      activeColor: AppColors.green,
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isUnlabeled
                                      ? AppColors.textSecondary
                                      : AppColors.blue)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isUnlabeled ? 'Tanpa Label' : 'Berlabel QR',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isUnlabeled
                                    ? AppColors.textSecondary
                                    : AppColors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$quantity $quantityUnit'),
                          Text(
                            checked
                                ? (canCancel
                                    ? 'Sudah dimuat ke kendaraan ini'
                                    : 'Sudah dimuat & SUDAH TIBA -- '
                                        'tidak bisa dibatalkan')
                                : 'Belum dimuat ke kendaraan ini',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: checked
                                  ? (canCancel ? AppColors.green : AppColors.red)
                                  : AppColors.textSecondary,
                            ),
                          ),
                          if (zona != null && zona.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.warehouse_outlined,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Zona: $zona',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat daftar barang: $error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
