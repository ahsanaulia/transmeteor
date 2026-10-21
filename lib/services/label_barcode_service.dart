import 'dart:math';

import '../core/services/supabase_service.dart';
import '../models/daftar_label_barcode_model.dart';

/// FITUR (21 Oktober 2026 -- Section A, "Label Barcode"). Service untuk
/// 2 halaman baru ("Stok Label Barcode" & "Scan Label") DAN untuk mode
/// "Scan Barcode" di Loading/Delivery. Lihat doc comment lengkap di
/// `migrasi_label_barcode.sql` (arsitektur) dan `ReceivingDetailModel.labelType`
/// (kaitan dengan `receiving_details`).
class LabelBarcodeService {
  static final _client = SupabaseService.client;

  // ============================================================
  // GENERATE STOK (menu "Stok Label Barcode")
  // ============================================================

  /// 12 digit angka (0-9), boleh diawali 0 -- murni string, BUKAN
  /// representasi numerik (lihat keputusan user: "12 digit angka",
  /// dikonfirmasi lewat AskUserQuestion 21 Oktober 2026). Dibangun
  /// digit-per-digit (bukan `Random().nextInt(10^12)`, yang akan
  /// kehilangan leading zero & berisiko overflow di beberapa platform)
  /// supaya distribusinya rata & panjangnya SELALU tepat 12 karakter.
  static String _randomCode() {
    final rand = Random.secure();
    return List.generate(12, (_) => rand.nextInt(10)).join();
  }

  /// Generate [count] kode baru ke stok. Kode diinsert SATU-SATU (bukan
  /// 1 batch insert) supaya kalau ada bentrok kode acak dengan yang sudah
  /// ada di tabel (SANGAT jarang -- ruang kemungkinan 10^12), baris lain
  /// yang TIDAK bentrok tidak ikut gagal -- cukup retry baris yang bentrok
  /// itu saja dengan kode baru. [createdBy] opsional (employee id staff
  /// yang generate, untuk jejak audit).
  static Future<List<DaftarLabelBarcodeModel>> generateStock({
    required int count,
    String? createdBy,
  }) async {
    if (count <= 0) {
      throw Exception('Jumlah yang digenerate harus lebih dari 0.');
    }
    if (count > 5000) {
      throw Exception(
        'Maksimal 5000 kode sekali generate -- generate bertahap untuk '
        'jumlah lebih banyak.',
      );
    }

    final generated = <DaftarLabelBarcodeModel>[];
    // Batas percobaan generous -- tabrakan kode acak di ruang 10^12
    // SANGAT jarang, batas ini murni jaring pengaman supaya tidak
    // infinite loop kalau ada masalah lain (mis. network flaky).
    final maxAttempts = count * 5 + 50;
    var attempts = 0;

    while (generated.length < count && attempts < maxAttempts) {
      attempts++;
      final code = _randomCode();

      try {
        final response = await _client
            .from('daftar_label_barcode')
            .insert({
              'barcode_code': code,
              'created_by': createdBy,
            })
            .select()
            .single();

        generated.add(
          DaftarLabelBarcodeModel.fromMap(Map<String, dynamic>.from(response)),
        );
      } catch (_) {
        // Kemungkinan besar unique_violation (kode acak bentrok) --
        // diamkan & coba lagi dengan kode baru di iterasi berikutnya.
        // Error lain (network dst) juga diperlakukan sama (retry sampai
        // batas attempts) supaya 1 hiccup tidak menggagalkan seluruh
        // batch.
        continue;
      }
    }

    if (generated.length < count) {
      throw Exception(
        'Hanya berhasil generate ${generated.length} dari $count kode -- '
        'coba generate sisanya lagi.',
      );
    }

    return generated;
  }

  /// Ringkasan stok -- jumlah kode yang belum dipakai & sudah dipakai,
  /// plus nomor urut (sequence_no) tertinggi yang pernah digenerate
  /// (dipakai halaman "Stok Label Barcode" untuk menyarankan rentang
  /// default saat admin mau reprint). Dihitung dari panjang list hasil
  /// `select('id')` (bukan `.count()` Postgrest -- SENGAJA menghindari
  /// API itu, tidak ada pemakaian lain di codebase ini yang membuktikan
  /// kompatibel dengan versi `supabase_flutter` yang terkunci sekarang),
  /// konsisten dengan pola hitung yang sudah dipakai di seluruh service
  /// lain (`(response as List).length`).
  static Future<({int belumDipakai, int terpakai, int maxSequenceNo})>
      getStockSummary() async {
    final belumDipakaiResponse = await _client
        .from('daftar_label_barcode')
        .select('id')
        .eq('status', LabelBarcodeStatus.belumDipakai);
    final terpakaiResponse = await _client
        .from('daftar_label_barcode')
        .select('id')
        .eq('status', LabelBarcodeStatus.terpakai);

    final maxRow = await _client
        .from('daftar_label_barcode')
        .select('sequence_no')
        .order('sequence_no', ascending: false)
        .limit(1)
        .maybeSingle();

    return (
      belumDipakai: (belumDipakaiResponse as List).length,
      terpakai: (terpakaiResponse as List).length,
      maxSequenceNo: maxRow != null ? (maxRow['sequence_no'] as num).toInt() : 0,
    );
  }

  /// Daftar kode dalam rentang [from]..[to] (inklusif, berdasarkan
  /// `sequence_no` INTERNAL -- lihat doc comment di model) -- dipakai
  /// fitur "cetak ulang dari nomor urut sekian sampai sekian".
  static Future<List<DaftarLabelBarcodeModel>> getBySequenceRange({
    required int from,
    required int to,
  }) async {
    final response = await _client
        .from('daftar_label_barcode')
        .select()
        .gte('sequence_no', from)
        .lte('sequence_no', to)
        .order('sequence_no');

    return (response as List)
        .map((e) => DaftarLabelBarcodeModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ============================================================
  // SCAN LABEL (mengikat kode ke barang -- menu "Scan Label")
  // ============================================================

  /// Cari 1 kode -- dipakai baik saat "Scan Label" (cek kode ini masih
  /// `BELUM_DIPAKAI` sebelum diikat) maupun saat mode "Scan Barcode" di
  /// Loading/Delivery (cek kode ini SUDAH `TERPAKAI` & terikat ke barang
  /// mana). `null` kalau kode tidak ditemukan di stok sama sekali (belum
  /// pernah digenerate, atau salah ketik/scan).
  static Future<DaftarLabelBarcodeModel?> lookupByCode(
    String barcodeCode,
  ) async {
    final response = await _client
        .from('daftar_label_barcode')
        .select()
        .eq('barcode_code', barcodeCode.trim())
        .maybeSingle();

    if (response == null) return null;

    return DaftarLabelBarcodeModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Ikat 1 kode barcode (dari stok, harus masih `BELUM_DIPAKAI`) ke 1
  /// baris `receiving_details` -- dipanggil tiap kali staff scan 1 kode
  /// blanko yang sudah ditempel fisik ke 1 koli barang, di menu "Scan
  /// Label". [noResi]/[kodeBarang] murni SNAPSHOT (untuk tampilan cepat
  /// di halaman "Stok Label Barcode" tanpa perlu join) -- SUMBER
  /// KEBENARAN hubungan tetap `receivingDetailId` (FK terstruktur).
  ///
  /// Melempar [Exception] kalau kode tidak ditemukan atau SUDAH
  /// `TERPAKAI` (baik oleh barang ini sendiri atau barang lain -- staff
  /// harus pakai kode lain atau `unbind` dulu kalau memang salah scan).
  static Future<void> bindToReceivingDetail({
    required String barcodeCode,
    required String receivingDetailId,
    required String noResi,
    required String kodeBarang,
    String? assignedBy,
  }) async {
    final row = await lookupByCode(barcodeCode);

    if (row == null) {
      throw Exception(
        'Kode barcode "$barcodeCode" tidak ditemukan di stok -- pastikan '
        'sudah digenerate lewat menu "Stok Label Barcode".',
      );
    }

    if (row.isUsed) {
      throw Exception(
        'Kode barcode "$barcodeCode" sudah terpakai untuk resi '
        '${row.noResi ?? '-'} (${row.kodeBarang ?? '-'}).',
      );
    }

    await _client.from('daftar_label_barcode').update({
      'status': LabelBarcodeStatus.terpakai,
      'no_resi': noResi,
      'kode_barang': kodeBarang,
      'receiving_detail_id': receivingDetailId,
      'assigned_at': DateTime.now().toIso8601String(),
      'assigned_by': assignedBy,
    }).eq('id', row.id);
  }

  /// true kalau kode ini SUDAH pernah tercatat di `shipment_scans`
  /// (Loading/Delivery mode "Scan Barcode") -- dipakai halaman "Scan
  /// Label" untuk MENOLAK tombol unbind pada kode yang sudah pernah
  /// discan (lihat doc comment [unbind] di bawah; kalau diizinkan
  /// unbind, `unit_code` di riwayat scan jadi tidak jelas asalnya karena
  /// kodenya balik `BELUM_DIPAKAI` padahal sudah tercatat jalan).
  static Future<bool> isCodeScanned(String barcodeCode) async {
    final response = await _client
        .from('shipment_scans')
        .select('id')
        .eq('unit_code', barcodeCode.trim())
        .limit(1);

    return (response as List).isNotEmpty;
  }

  /// Lepas ikatan 1 kode (balik jadi `BELUM_DIPAKAI`, kosongkan snapshot
  /// & `receiving_detail_id`) -- jalan keluar kalau staff salah scan saat
  /// "Scan Label". TIDAK menyentuh `shipment_scans` apa pun -- kode yang
  /// SUDAH pernah dipakai scan Loading/Delivery (lihat mode "Scan
  /// Barcode") sebaiknya TIDAK di-unbind lagi (akan membuat unit_code di
  /// riwayat scan jadi tidak jelas asalnya) -- pemanggil (UI) WAJIB cek
  /// [isCodeScanned] dulu & menolak unbind kalau hasilnya true (lihat
  /// `ScanLabelPage._confirmUnbind`).
  static Future<void> unbind(String barcodeCode) async {
    await _client.from('daftar_label_barcode').update({
      'status': LabelBarcodeStatus.belumDipakai,
      'no_resi': null,
      'kode_barang': null,
      'receiving_detail_id': null,
      'assigned_at': null,
      'assigned_by': null,
    }).eq('barcode_code', barcodeCode.trim());
  }

  /// Semua kode yang SUDAH terikat ke 1 baris `receiving_details` --
  /// dipakai halaman "Scan Label" (menampilkan progress "sudah diikat
  /// berapa dari berapa") & basis unit fisik barang BARCODE (lihat
  /// `ShipmentService._attachBarcodeCodes`/`_physicalUnitCodes`).
  static Future<List<DaftarLabelBarcodeModel>> getBoundToDetail(
    String receivingDetailId,
  ) async {
    final response = await _client
        .from('daftar_label_barcode')
        .select()
        .eq('receiving_detail_id', receivingDetailId)
        .order('assigned_at');

    return (response as List)
        .map((e) => DaftarLabelBarcodeModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Versi BATCH dari [getBoundToDetail] -- SATU query untuk banyak
  /// `receiving_detail_id` sekaligus (bukan N+1), hasilnya
  /// `{receivingDetailId: [barcode_code, ...]}`. Dipakai
  /// `ShipmentService._attachBarcodeCodes`.
  static Future<Map<String, List<String>>> getBoundCodesByDetailIds(
    List<String> receivingDetailIds,
  ) async {
    if (receivingDetailIds.isEmpty) return {};

    final response = await _client
        .from('daftar_label_barcode')
        .select('barcode_code, receiving_detail_id')
        .inFilter('receiving_detail_id', receivingDetailIds);

    final result = <String, List<String>>{};
    for (final row in (response as List)) {
      final map = Map<String, dynamic>.from(row);
      final detailId = map['receiving_detail_id'] as String?;
      if (detailId == null) continue;
      result.putIfAbsent(detailId, () => []).add(map['barcode_code'] as String);
    }
    return result;
  }
}
