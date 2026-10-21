import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scan_feedback.dart';
import '../../../providers/loading_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/shipment_service.dart';

/// Checklist manual "muat barang TANPA scan QR kamera" -- dipakai di 2
/// tempat: mode "Tanpa Label QR" di `LoadingScanPage` (staff loading
/// sendiri, sambil masih di lokasi muat) DAN halaman admin "Loading
/// Barang" (`AdminManualLoadPage`) -- intervensi admin kalau staff
/// lupa/tidak mencatat muatan di app padahal barangnya sudah naik ke
/// truk oleh buruh.
///
/// PERMINTAAN USER (7 Oktober 2026, eksplisit, menggantikan batasan
/// lama): daftar barangnya SEKARANG difilter cuma "sudah pernah dimuat
/// (ke shipment manapun) atau belum" -- TIDAK peduli barangnya berlabel
/// QR atau tidak. Alasan user: 1 resi bisa punya campuran barang
/// berlabel & tanpa label, dan scan QR saat loading TIDAK WAJIB -- dalam
/// situasi darurat (atau kalau memang lebih praktis) staff/admin bisa
/// langsung centang manual di sini tanpa pernah menyalakan kamera sama
/// sekali. Lihat doc comment panjang di
/// `ShipmentService.getAvailableItemsForManualLoad` untuk detail penuh &
/// riwayat (dulu, sebelum tanggal ini, mode ini HANYA menampilkan barang
/// `is_unlabeled == true`).
///
/// Diekstrak jadi widget BERSAMA (bukan diduplikasi ke 2 file terpisah)
/// supaya logic "resi mana saja yang tersedia, barang mana yang
/// sudah/belum termuat" TIDAK PERNAH dobel-maintain di tempat berbeda --
/// ini pelajaran LANGSUNG dari bug `getAvailableUnlabeledItemsForShipment`
/// sebelumnya (sempat salah di-scope per shipment, baru ketahuan setelah
/// dipakai beberapa hari di lapangan, lihat riwayat bug 7 Oktober 2026
/// pagi di project doc).
class ManualLoadChecklistView extends ConsumerStatefulWidget {
  final String shipmentId;

  /// Dicatat ke kolom `notes` tiap baris `shipment_scans` yang dibuat
  /// lewat widget ini -- beda nilai antara dipanggil dari `LoadingScanPage`
  /// ("Manual: tanpa scan QR") vs `AdminManualLoadPage` ("Admin
  /// intervensi: ...") supaya kalau nanti ada audit/komplain, asal-usul
  /// baris scan (staff loading sendiri vs campur tangan admin) tetap
  /// bisa dibedakan dari data historisnya.
  final String notesPrefix;

  const ManualLoadChecklistView({
    super.key,
    required this.shipmentId,
    this.notesPrefix = 'Manual: tanpa scan QR',
  });

  @override
  ConsumerState<ManualLoadChecklistView> createState() =>
      _ManualLoadChecklistViewState();
}

class _ManualLoadChecklistViewState
    extends ConsumerState<ManualLoadChecklistView> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedReceivingId;
  final Set<String> _checkedItemIds = {};
  bool _isSubmitting = false;

  // FITUR (17 Oktober 2026, permintaan user eksplisit: isian jumlah
  // barang, bukan cuma centang -- lihat doc comment
  // [ShipmentService.recordManualLoad]). 1 controller per baris barang
  // (key = `receiving_details.id`), dibuat lazy saat baris itu pertama
  // kali dirender, diisi default JUMLAH MAKSIMAL yang masih tersisa
  // ([_maxQtyFor]) -- jadi perilaku lama ("centang = muat semua sisa")
  // masih jalan apa adanya kalau usernya tidak mengubah angkanya.
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Jumlah MAKSIMAL yang boleh dimuat sekarang untuk 1 baris [item]:
  ///  - Tanpa label/curah: nilai `quantity` baris ini (bisa desimal) --
  ///    sisa SELALU utuh 100% selama baris itu ditampilkan di sini (1
  ///    baris = 1 unit sintetis, lihat doc comment
  ///    [ShipmentService.recordManualLoad]/`_physicalUnitCodes`).
  ///  - Berlabel QR: `remainingCount` (jumlah UNIT yang belum dimuat).
  num _maxQtyFor(Map<String, dynamic> item) {
    if (item['is_unlabeled'] == true) {
      return item['quantity'] as num;
    }
    return item['remainingCount'] as int? ?? 1;
  }

  String _formatQty(num value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  TextEditingController _qtyControllerFor(Map<String, dynamic> item) {
    final id = item['id'] as String;
    return _qtyControllers.putIfAbsent(
      id,
      () => TextEditingController(text: _formatQty(_maxQtyFor(item))),
    );
  }

  /// Jumlah yang BENAR-BENAR dipakai saat submit -- hasil parse isian
  /// user, dengan fallback ke jumlah maksimal ([_maxQtyFor]) kalau
  /// kosong/tidak valid/melebihi maksimal (supaya tidak mungkin
  /// memasukkan jumlah yang tidak ada fisiknya).
  num _resolveQty(Map<String, dynamic> item) {
    final max = _maxQtyFor(item);
    final controller = _qtyControllers[item['id']];
    if (controller == null) return max;

    final parsed = num.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || parsed > max) return max;
    return parsed;
  }

  List<Map<String, dynamic>> _groupByReceiving(
    List<Map<String, dynamic>> items,
  ) {
    final groups = <String, Map<String, dynamic>>{};

    for (final item in items) {
      final receivingId = item['receiving_id'] as String?;
      if (receivingId == null) continue;

      final receiving = item['receiving'] as Map<String, dynamic>?;

      final group = groups.putIfAbsent(
        receivingId,
        () => {
          'receivingId': receivingId,
          'receiptNumber': receiving?['receipt_number']?.toString() ?? '-',
          // FITUR (8 Oktober 2026 -- poin 5): nomor buku, kosong kalau
          // tidak ada.
          'nomorBuku': receiving?['nomor_buku']?.toString(),
          'destination': receiving?['destination']?.toString() ?? '-',
          'destinationAddress': receiving?['destination_address']?.toString(),
          'items': <Map<String, dynamic>>[],
        },
      );

      (group['items'] as List<Map<String, dynamic>>).add(item);
    }

    final list = groups.values.toList();
    list.sort(
      (a, b) => (a['receiptNumber'] as String)
          .compareTo(b['receiptNumber'] as String),
    );
    return list;
  }

  /// Catat 1 baris barang sebagai sudah naik, SEJUMLAH [_resolveQty] --
  /// lihat doc comment [ShipmentService.recordManualLoad] untuk arti
  /// `qty` per jenis barang (berlabel = jumlah unit, curah = jumlah
  /// quantity, otomatis di-split kalau sebagian). Kalau sebagian unit
  /// gagal (mis. race condition, staff lain barengan memuat unit yang
  /// sama), unit lain yang berhasil TETAP tersimpan -- tidak di-rollback.
  Future<String?> _loadItem(Map<String, dynamic> item, String employeeId) {
    return ShipmentService.recordManualLoad(
      item: item,
      qty: _resolveQty(item),
      shipmentId: widget.shipmentId,
      scannedBy: employeeId,
      notes: widget.notesPrefix,
    );
  }

  Future<void> _submitChecked(List<Map<String, dynamic>> groupItems) async {
    final toSubmit = groupItems
        .where((item) => _checkedItemIds.contains(item['id']))
        .toList();

    if (toSubmit.isEmpty) return;

    final employee = await ref.read(currentEmployeeProvider.future);
    if (employee == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data employee tidak ditemukan, tidak bisa mencatat.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    var successCount = 0;
    final failures = <String>[];

    for (final item in toSubmit) {
      final itemName = item['item_name']?.toString() ?? 'Barang';
      final error = await _loadItem(item, employee.id);

      if (error == null) {
        successCount++;
      } else {
        failures.add('$itemName ($error)');
      }
    }

    ref.invalidate(shipmentScansProvider(widget.shipmentId));
    ref.invalidate(availableManualLoadItemsProvider);

    if (successCount > 0) {
      ScanFeedback.playSuccess();
    } else {
      ScanFeedback.playFailure();
    }

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      // Baris yang sudah disubmit (berhasil maupun gagal) dibuang
      // controller qty-nya -- kalau baris itu muncul lagi (mis. curah
      // yang baru di-split, sisanya balik ke checklist dengan id BARU),
      // defaultnya dihitung ulang dari jumlah maksimal yang baru.
      for (final item in toSubmit) {
        _qtyControllers.remove(item['id'])?.dispose();
      }
      _checkedItemIds.clear();
      // Balik ke daftar resi supaya staff/admin bisa lanjut pilih resi lain.
      _selectedReceivingId = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    if (failures.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$successCount barang berhasil dicatat naik.'),
          backgroundColor: AppColors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$successCount berhasil, ${failures.length} gagal: '
            '${failures.join(', ')}',
          ),
          backgroundColor: AppColors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(availableManualLoadItemsProvider);

    return Container(
      color: AppColors.background,
      child: itemsAsync.when(
        data: (items) {
          final groups = _groupByReceiving(items);

          final selectedGroup = _selectedReceivingId == null
              ? null
              : groups.firstWhere(
                  (g) => g['receivingId'] == _selectedReceivingId,
                  orElse: () => <String, dynamic>{},
                );

          if (selectedGroup != null && selectedGroup.isNotEmpty) {
            return _buildChecklist(selectedGroup);
          }

          // Resi yang tadi dipilih sudah tidak ada lagi barangnya (semua
          // sudah dimuat/berubah) -- balik otomatis ke daftar resi.
          if (_selectedReceivingId != null) {
            _selectedReceivingId = null;
          }

          return _buildResiList(groups);
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
    );
  }

  /// Langkah 1: cari/masukkan no resi, lalu pilih dari daftar resi yang
  /// masih punya barang (berlabel QR maupun tidak) menunggu dimuat ke
  /// kendaraan MANAPUN (bukan cuma kendaraan/shipment yang sedang dibuka
  /// ini -- lihat doc comment di atas kenapa SENGAJA global, bukan
  /// di-scope per shipment).
  Widget _buildResiList(List<Map<String, dynamic>> groups) {
    final query = _query.trim().toLowerCase();

    final filtered = query.isEmpty
        ? groups
        : groups.where((g) {
            final receiptNumber = (g['receiptNumber'] as String).toLowerCase();
            final destination = (g['destination'] as String).toLowerCase();
            return receiptNumber.contains(query) || destination.contains(query);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              labelText: 'Masukkan / Cari No. Resi',
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
        if (groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Daftar di bawah berisi SEMUA resi (barang berlabel QR '
                      'maupun tanpa label) yang masih ada barang belum '
                      'dimuat ke kendaraan manapun -- BUKAN cuma milik '
                      'kendaraan ini. Pastikan nomor resi, tujuan & barang '
                      'benar sebelum memilih.',
                      style: TextStyle(
                        color: AppColors.orange,
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
                      groups.isEmpty
                          ? 'Tidak ada resi yang masih punya barang '
                              'menunggu dimuat.'
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
                    final group = filtered[index];
                    final itemCount = (group['items'] as List).length;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.blue.withOpacity(0.08)),
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: AppColors.orange),
                        ),
                        title: Text(
                          // FITUR (8 Oktober 2026 -- poin 5): nomor buku
                          // di belakang nomor resi kalau ada.
                          (group['nomorBuku'] != null &&
                                  (group['nomorBuku'] as String).isNotEmpty)
                              ? '${group['receiptNumber']} / ${group['nomorBuku']}'
                              : group['receiptNumber'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${group['destination']} • $itemCount barang',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          setState(() {
                            _selectedReceivingId = group['receivingId'] as String;
                            _checkedItemIds.clear();
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

  /// Langkah 2: resi sudah dipilih -- centang barang mana saja yang naik
  /// ke kendaraan ini, lalu submit sekali untuk semua yang dicentang.
  /// Tiap baris diberi label kecil "Berlabel QR" / "Tanpa Label" supaya
  /// staff/admin tetap sadar statusnya, meski keduanya SEKARANG tampil
  /// bercampur di daftar yang sama.
  Widget _buildChecklist(Map<String, dynamic> group) {
    final items = group['items'] as List<Map<String, dynamic>>;
    final allChecked = items.every(
      (item) => _checkedItemIds.contains(item['id']),
    );

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (group['nomorBuku'] != null &&
                              (group['nomorBuku'] as String).isNotEmpty)
                          ? '${group['receiptNumber']} / ${group['nomorBuku']}'
                          : group['receiptNumber'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    Text(
                      group['destination'] as String,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedReceivingId = null;
                    _checkedItemIds.clear();
                  });
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Ganti Resi'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: CheckboxListTile(
            value: allChecked,
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _checkedItemIds.addAll(
                    items.map((item) => item['id'] as String),
                  );
                } else {
                  _checkedItemIds.clear();
                }
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text(
              'Pilih Semua',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),
        // FITUR (17 Oktober 2026, permintaan user eksplisit): penjelasan
        // singkat soal kolom "Jumlah naik" yang baru -- terutama perilaku
        // split untuk barang tanpa label/curah, supaya staff/admin tidak
        // bingung kalau baris yang sama muncul lagi dengan jumlah lebih
        // kecil setelah dimuat sebagian.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Isi "Jumlah naik" kalau cuma SEBAGIAN yang dimuat '
                    'sekarang. Barang tanpa label/curah yang dimuat '
                    'sebagian otomatis terbagi -- sisanya tetap muncul di '
                    'sini, menunggu dimuat lain waktu.',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final id = item['id'] as String;
              final itemName = item['item_name']?.toString() ?? '-';
              final quantity = item['quantity'];
              final quantityUnit = item['quantity_unit']?.toString() ?? '';
              final isUnlabeled = item['is_unlabeled'] == true;
              final remainingCount = item['remainingCount'] as int? ?? 1;
              final totalUnitCount = item['totalUnitCount'] as int? ?? 1;
              final checked = _checkedItemIds.contains(id);

              // FITUR (8 Oktober 2026 -- poin 6, Zona Storage): zona
              // tempat barang ini diletakkan, supaya petugas loading tahu
              // di mana mencarinya. Null kalau belum diisi saat
              // pencatatan resi (lihat `ReceivingDetailFormSheet`).
              final zona = (item['storages']
                  as Map<String, dynamic>?)?['nama_zona']?.toString();

              final subtitle = !isUnlabeled && remainingCount != totalUnitCount
                  ? 'Sisa $remainingCount dari $totalUnitCount unit • $quantity $quantityUnit'
                  : '$quantity $quantityUnit';

              final maxQty = _maxQtyFor(item);
              final qtyController = _qtyControllerFor(item);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: checked
                        ? AppColors.orange.withOpacity(0.5)
                        : AppColors.blue.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _checkedItemIds.add(id);
                          } else {
                            _checkedItemIds.remove(id);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              itemName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isUnlabeled ? AppColors.textSecondary : AppColors.blue)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isUnlabeled ? 'Tanpa Label' : 'Berlabel QR',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isUnlabeled ? AppColors.textSecondary : AppColors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(subtitle),
                          // FITUR (8 Oktober 2026 -- poin 6): info zona
                          // storage, cuma tampil kalau diisi.
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
                    // FITUR (17 Oktober 2026, permintaan user eksplisit:
                    // "Perbaiki bagian loading Tanpa Label agar ada isian
                    // jumlah barang. Bukan hanya centang... Jadi loading
                    // tanpa QR bisa split barang"). Isian jumlah -- default
                    // = jumlah maksimal yang masih tersisa ([_maxQtyFor]),
                    // bisa diturunkan untuk memuat SEBAGIAN saja. Dibiarkan
                    // bisa diedit terlepas dari status centang supaya
                    // staff/admin bisa atur jumlah dulu baru centang.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.numbers_rounded,
                            size: 15,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Jumlah naik:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 68,
                            height: 34,
                            child: TextField(
                              controller: qtyController,
                              textAlign: TextAlign.center,
                              keyboardType: isUnlabeled
                                  ? const TextInputType.numberWithOptions(decimal: true)
                                  : TextInputType.number,
                              inputFormatters: isUnlabeled
                                  ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))]
                                  : [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                              ),
                              onChanged: (_) {
                                // Mengetik jumlah = niatnya mau memuat baris
                                // ini -- otomatis centang supaya tidak perlu
                                // 2 ketukan (isi jumlah LALU centang).
                                if (!_checkedItemIds.contains(id)) {
                                  setState(() => _checkedItemIds.add(id));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isUnlabeled
                                  ? 'dari maks ${_formatQty(maxQty)} $quantityUnit'
                                  : 'dari maks ${_formatQty(maxQty)} unit tersisa',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                qtyController.text = _formatQty(maxQty);
                                _checkedItemIds.add(id);
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(44, 28),
                            ),
                            child: const Text(
                              'Maks',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _checkedItemIds.isEmpty || _isSubmitting
                    ? null
                    : () => _submitChecked(items),
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(
                  _checkedItemIds.isEmpty
                      ? 'Pilih barang yang naik'
                      : 'Muat ${_checkedItemIds.length} Barang Terpilih',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
