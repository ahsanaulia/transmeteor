import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../services/track_shipment_service.dart';

/// Halaman PUBLIK "Telusuri Kiriman" (8 Oktober 2026 -- permintaan user
/// poin 11). Dibuka LANGSUNG dari `LoginPage` (tombol "Telusuri
/// Kiriman"), TIDAK perlu login -- customer masukkan Nomor Resi ATAU
/// Nomor Buku, lalu lihat status kirimannya (diterima / loading /
/// berangkat / tiba) + peta posisi kendaraan yang memuat barangnya
/// (kalau statusnya sudah loading/berangkat).
///
/// Keputusan arsitektur (sesuai jawaban user saat ditanya, 8 Oktober
/// 2026): "Satu app saja" -- halaman ini TETAP bagian dari app Flutter
/// yang sama (BUKAN web/app terpisah), cukup dibuka tanpa sesi login.
/// Seluruh query berat (lookup lintas tabel, agregasi quantity, cari
/// kendaraan aktif) dilakukan di sisi database lewat RPC
/// `track_shipment` (lihat `TrackShipmentService` & `add_track_shipment_
/// rpc.sql`) -- halaman ini SENGAJA tidak query tabel manapun secara
/// langsung, supaya customer anonim tidak pernah diberi akses baca
/// langsung ke data internal.
class TrackShipmentPage extends StatefulWidget {
  const TrackShipmentPage({super.key});

  @override
  State<TrackShipmentPage> createState() => _TrackShipmentPageState();
}

class _TrackShipmentPageState extends State<TrackShipmentPage> {
  final _searchController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _result;

  // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
  // header halaman menampilkan Nama Perusahaan/Alamat/No. Telepon, tampil
  // di SEBELUM maupun SETELAH pencarian (bukan bagian dari hasil
  // `trackShipment`). `null` berarti belum dimuat ATAU gagal dimuat --
  // di kedua kasus itu header cukup disembunyikan, TIDAK menghalangi
  // customer memakai form pencarian (lihat `_buildCompanyHeader`).
  Map<String, dynamic>? _companyInfo;

  @override
  void initState() {
    super.initState();
    _loadCompanyInfo();
  }

  Future<void> _loadCompanyInfo() async {
    try {
      final info = await TrackShipmentService.getPublicCompanyInfo();
      if (!mounted) return;
      setState(() => _companyInfo = info);
    } catch (_) {
      // Diamkan dengan sengaja -- header ini pelengkap, bukan fitur
      // inti. Gagal muat TIDAK boleh menghalangi customer mencari status
      // kirimannya.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final search = _searchController.text.trim();

    if (search.isEmpty) {
      setState(() {
        _errorMessage = 'Masukkan Nomor Resi atau Nomor Buku dulu.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = await TrackShipmentService.trackShipment(search);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        if (result['found'] == true) {
          _result = result;
        } else {
          _errorMessage =
              'Nomor Resi/Nomor Buku "$search" tidak ditemukan. '
              'Periksa kembali nomornya.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memeriksa status kiriman. Coba lagi nanti.';
      });
    }
  }

  void _searchAgain() {
    setState(() {
      _result = null;
      _errorMessage = null;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Telusuri Kiriman',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Nama Perusahaan/Alamat/No. Telepon -- tampil di
              // SEBELUM maupun SETELAH pencarian (lihat doc comment
              // `_companyInfo` di atas).
              _buildCompanyHeader(),
              _result != null ? _buildResult(_result!) : _buildSearchForm(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER PERUSAHAAN
  // ============================================================
  //
  // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
  // "tambahkan header: Nama Company kita, Alamat, No Telepon". Data dari
  // `TrackShipmentService.getPublicCompanyInfo()` (RPC publik, lihat doc
  // comment di sana) -- kalau belum dimuat/gagal/belum ada baris
  // `company`, widget ini SENGAJA kosong (`SizedBox.shrink()`) daripada
  // menampilkan placeholder kosong atau error yang mengganggu.

  Widget _buildCompanyHeader() {
    final info = _companyInfo;
    if (info == null) return const SizedBox.shrink();

    final name = info['name']?.toString();
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    final address = info['address']?.toString();
    final phone = info['phone']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.navy,
              // Diperbesar (8 Oktober 2026, lanjutan lagi -- "perbesar
              // semua demi keterbacaan"): 17 -> 19.
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              address,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                // Diperbesar: 12 -> 14.
                fontSize: 14,
              ),
            ),
          ],
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              phone,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                // Diperbesar: 12 -> 14.
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.border),
        ],
      ),
    );
  }

  // ============================================================
  // FORM PENCARIAN
  // ============================================================

  Widget _buildSearchForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navy, AppColors.blue, AppColors.cyan],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Masukkan Nomor Resi atau Nomor Buku untuk melihat status '
                  'kiriman Anda.',
                  style: TextStyle(color: Colors.white, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppTextField(
          controller: _searchController,
          label: 'Nomor Resi / Nomor Buku',
          hint: 'Contoh: RESI000123',
          icon: Icons.search_rounded,
          enabled: !_isLoading,
          onSubmitted: (_) => _search(),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          InfoBanner(
            variant: InfoBannerVariant.error,
            message: _errorMessage!,
            onDismiss: () => setState(() => _errorMessage = null),
          ),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Cari Status Kiriman',
          loadingLabel: 'Mencari...',
          isLoading: _isLoading,
          icon: Icons.search_rounded,
          onPressed: _search,
        ),
      ],
    );
  }

  // ============================================================
  // HASIL
  // ============================================================

  Widget _buildResult(Map<String, dynamic> result) {
    final receiptNumber = result['receiptNumber']?.toString() ?? '-';
    final nomorBuku = result['nomorBuku']?.toString();
    final destination = result['destination']?.toString() ?? '-';
    // BARU (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
    // Alamat tujuan, dari field RPC baru `destinationAddress` (lihat
    // `add_track_shipment_rpc.sql`).
    final destinationAddress = result['destinationAddress']?.toString();
    final receivedAtRaw = result['receivedAt']?.toString();
    final receivedAt = receivedAtRaw != null ? DateTime.tryParse(receivedAtRaw) : null;
    final totalQuantity = (result['totalQuantity'] as num?)?.toDouble() ?? 0;
    final loadedQuantity = (result['loadedQuantity'] as num?)?.toDouble() ?? 0;
    final status = result['status']?.toString() ?? 'diterima';
    final vehicles = (result['vehicles'] as List?) ?? const [];
    // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
    // "Detail Barang Resi sesuai penerimaan" -- daftar PER JENIS BARANG
    // seperti yang dicatat saat resi diterima, SELALU ditampilkan terlepas
    // dari status (beda dari `vehicles`/"Detail Pemuatan" yang cuma
    // tampil saat loading/berangkat) -- supaya kalau satu jenis barang
    // ternyata dimuat/diterima BERTAHAP (sebagian jalan duluan, sisanya
    // menyusul), ketahuan dari progress per baris, bukan cuma dari angka
    // total yang menimpali semua jenis barang.
    final receivedItems = (result['receivedItems'] as List?) ?? const [];

    final statusInfo = _statusInfo(status);
    final isPartial = loadedQuantity < totalQuantity;
    final pendingQuantity = totalQuantity - loadedQuantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _searchAgain,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Cari Nomor Lain'),
        ),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (nomorBuku != null && nomorBuku.isNotEmpty)
                    ? '$receiptNumber / $nomorBuku'
                    : receiptNumber,
                style: const TextStyle(
                  // Diperbesar (8 Oktober 2026, lanjutan lagi -- "perbesar
                  // semua demi keterbacaan"): 18 -> 20.
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user
                // eksplisit): font Nama Tujuan dibesarkan SAMA besar
                // dengan font Nama Sopir di "Detail Pemuatan". Diperbesar
                // LAGI (lanjutan "perbesar semua demi keterbacaan"):
                // 14 -> 16.
                'Tujuan: $destination',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              if (destinationAddress != null && destinationAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  // Alamat -- SAMA besar/tebal dengan Nama Tujuan di atas.
                  'Alamat: $destinationAddress',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
              if (receivedAt != null) ...[
                const SizedBox(height: 2),
                Text(
                  // FITUR (8 Oktober 2026, lanjutan poin 11 -- permintaan
                  // user eksplisit): tanggal DAN jam diterima, bukan cuma
                  // tanggal saja seperti sebelumnya. Diperbesar (lanjutan
                  // "perbesar semua demi keterbacaan"): 12 -> 14.
                  'Diterima: ${formatDateId(receivedAt)}, pukul '
                  '${formatTimeId(receivedAt)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: statusInfo.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(statusInfo.icon, color: statusInfo.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusInfo.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            // Diperbesar (8 Oktober 2026, lanjutan lagi --
                            // "perbesar semua demi keterbacaan"): 15 -> 17.
                            fontSize: 17,
                            color: statusInfo.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusInfo.description,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            // Diperbesar: 12 -> 14.
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isPartial && totalQuantity > 0) ...[
                const SizedBox(height: 12),
                InfoBanner(
                  variant: InfoBannerVariant.info,
                  message:
                      '${loadedQuantity == loadedQuantity.roundToDouble() ? loadedQuantity.toStringAsFixed(0) : loadedQuantity} '
                      'dari ${totalQuantity == totalQuantity.roundToDouble() ? totalQuantity.toStringAsFixed(0) : totalQuantity} '
                      'barang sudah dimuat -- sisanya '
                      '(${pendingQuantity == pendingQuantity.roundToDouble() ? pendingQuantity.toStringAsFixed(0) : pendingQuantity}) '
                      'masih berada di kantor/perwakilan, belum berangkat.',
                ),
              ],
            ],
          ),
        ),
        // "Detail Barang Resi sesuai penerimaan" -- SELALU tampil (lihat
        // catatan di atas soal `receivedItems`), ditaruh SEBELUM "Detail
        // Pemuatan" supaya customer bisa bandingkan: barang apa saja yang
        // diterima, lalu (kalau sudah jalan) berapa dari tiap jenis yang
        // sudah benar-benar dimuat ke kendaraan.
        if (receivedItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Detail Barang (Sesuai Penerimaan)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              // Ditambahkan fontSize eksplisit (8 Oktober 2026, lanjutan
              // lagi -- "perbesar semua demi keterbacaan"); sebelumnya
              // tidak ada fontSize eksplisit (ikut default ~14, kecil).
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < receivedItems.length; i++) ...[
                  if (i > 0) const Divider(height: 18),
                  _buildReceivedItemRow(
                    Map<String, dynamic>.from(receivedItems[i] as Map),
                  ),
                ],
              ],
            ),
          ),
        ],
        // FITUR (8 Oktober 2026, lanjutan poin 11 -- permintaan user
        // eksplisit): "jika dalam perjalanan maka harus ada data: tanggal
        // & jam loading, nama sopir, no HP driver, detail barang sesuai
        // manifest". `vehicles` SELALU kosong untuk status diterima/tiba
        // (lihat filter `s.status in ('LOADING','DEPARTED')` di
        // `track_shipment` SQL), jadi blok ini otomatis cuma tampil saat
        // status loading/berangkat tanpa perlu cek status lagi di sini.
        if (vehicles.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Detail Pemuatan',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              // Ditambahkan fontSize eksplisit (lanjutan "perbesar semua
              // demi keterbacaan").
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...vehicles.map(
            (v) => _buildVehicleDetailCard(Map<String, dynamic>.from(v as Map)),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Posisi Kendaraan',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            // Ditambahkan fontSize eksplisit (lanjutan "perbesar semua
            // demi keterbacaan").
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _buildMap(status, vehicles),
      ],
    );
  }

  /// Satu baris "Detail Barang (Sesuai Penerimaan)" -- nama barang +
  /// jumlah SEPERTI DICATAT SAAT RESI DIBUAT, plus catatan progress
  /// (belum dimuat / dimuat sebagian -- "dikirim bertahap" / sudah dimuat
  /// semua / sudah tiba semua) dihitung dari `loadedCount`/`deliveredCount`
  /// yang dikirim RPC `track_shipment` (lihat `UPDATE 2` di
  /// `add_track_shipment_rpc.sql`). SENGAJA per JENIS BARANG (bukan
  /// digabung jadi satu angka seperti `loadedQuantity`/`totalQuantity`
  /// agregat di atas) supaya kalau cuma SEBAGIAN jenis barang yang jalan
  /// duluan, itu kelihatan jelas per baris -- ini yang dimaksud user
  /// "agar ketahuan jika ternyata barangnya dikirim bertahap".
  Widget _buildReceivedItemRow(Map<String, dynamic> item) {
    final itemName = item['itemName']?.toString() ?? '-';
    final unit = item['quantityUnit']?.toString() ?? '';
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
    final loadedCount = (item['loadedCount'] as num?)?.toDouble() ?? 0;
    final deliveredCount = (item['deliveredCount'] as num?)?.toDouble() ?? 0;

    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    String progressText;
    Color progressColor;
    if (quantity <= 0) {
      progressText = '-';
      progressColor = AppColors.textSecondary;
    } else if (deliveredCount >= quantity) {
      progressText = 'Sudah tiba semua di tujuan.';
      progressColor = AppColors.green;
    } else if (loadedCount >= quantity) {
      progressText = 'Sudah dimuat semua, sedang dalam perjalanan.';
      progressColor = AppColors.blue;
    } else if (loadedCount > 0) {
      progressText =
          '${fmt(loadedCount)} dari ${fmt(quantity)} sudah dimuat -- '
          'sisanya (${fmt(quantity - loadedCount)}) masih di kantor/'
          'perwakilan (dikirim bertahap).';
      progressColor = AppColors.orange;
    } else {
      progressText = 'Belum dimuat, masih di kantor/perwakilan.';
      progressColor = AppColors.textSecondary;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$itemName -- ${fmt(quantity)} $unit',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            // Diperbesar (8 Oktober 2026, lanjutan lagi -- "Daftar barang
            // juga terlalu kecil hurufnya... perbesar semua demi
            // keterbacaan"): 13 -> 15.
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          progressText,
          style: TextStyle(
            color: progressColor,
            // Diperbesar: 12 -> 13.
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Kartu detail satu kendaraan yang (sedang) memuat resi ini: kapan
  /// mulai loading, siapa sopirnya + No. HP, dan daftar barang yang SUDAH
  /// discan LOAD ke kendaraan itu (sumber data SAMA dengan Manifest --
  /// lihat catatan di `add_track_shipment_rpc.sql`), supaya kalau resi ini
  /// terpecah ke beberapa kendaraan, customer lihat detail per kendaraan
  /// dengan jelas (bukan digabung jadi satu daftar yang membingungkan).
  Widget _buildVehicleDetailCard(Map<String, dynamic> v) {
    final plate = v['vehicle_plate']?.toString() ?? '-';
    final driverName = v['driver_name']?.toString();
    final driverPhone = v['driver_phone']?.toString();
    final loadedAtRaw = v['loaded_at']?.toString();
    final loadedAt = loadedAtRaw != null ? DateTime.tryParse(loadedAtRaw) : null;
    final items = (v['items'] as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_shipping_rounded,
                  size: 18,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  plate,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    // Diperbesar (8 Oktober 2026, lanjutan lagi --
                    // "perbesar semua demi keterbacaan"): 14 -> 16.
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (loadedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Mulai dimuat: ${formatDateId(loadedAt)}, pukul '
                '${formatTimeId(loadedAt)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  // Diperbesar: 12.5 -> 14.
                  fontSize: 14,
                ),
              ),
            ],
            if (driverName != null && driverName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                // FITUR (8 Oktober 2026, lanjutan lagi -- permintaan user
                // eksplisit): font Nama Sopir & No. HP dibesarkan SAMA
                // besar dengan font Plat Mobil di atas. Diperbesar LAGI
                // bersama Plat Mobil (lanjutan "perbesar semua demi
                // keterbacaan"): 14 -> 16.
                (driverPhone != null && driverPhone.isNotEmpty)
                    ? 'Sopir: $driverName ($driverPhone)'
                    : 'Sopir: $driverName',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Barang yang dimuat:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  // Diperbesar: 12 -> 13.
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              ...items.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final itemName = item['itemName']?.toString() ?? '-';
                final unit = item['quantityUnit']?.toString() ?? '';
                final count = item['loadedCount'];
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '• $itemName -- $count $unit',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      // FITUR (8 Oktober 2026, lanjutan lagi --
                      // "Daftar barang juga terlalu kecil hurufnya...
                      // perbesar semua demi keterbacaan" -- ini persis
                      // elemen yang dimaksud user): 12.5 -> 14.
                      fontSize: 14,
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMap(String status, List vehicles) {
    // Peta HANYA aktif kalau status sudah loading/berangkat (permintaan
    // eksplisit user poin 11: "Peta ini hanya berfungsi jika barang
    // statusnya sudah loading... jika belum dimuat maka peta kosong
    // dengan informasi teks dibawahnya.").
    if (status == 'diterima') {
      return const _EmptyMapNote(
        message:
            'Barang masih diterima di kantor, belum dimuat ke kendaraan -- '
            'peta posisi akan muncul setelah barang mulai dimuat.',
      );
    }

    if (status == 'tiba') {
      return const _EmptyMapNote(
        message: 'Barang sudah tiba di tujuan -- perjalanan selesai.',
      );
    }

    final markers = <MapMarkerData>[];
    for (final v in vehicles) {
      final map = Map<String, dynamic>.from(v as Map);
      final lat = (map['latitude'] as num?)?.toDouble();
      final lng = (map['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null) continue;

      final plate = map['vehicle_plate']?.toString() ?? '-';
      markers.add(
        MapMarkerData(
          latitude: lat,
          longitude: lng,
          color: AppColors.blue,
          icon: Icons.local_shipping_rounded,
          label: plate,
        ),
      );
    }

    return MultiMarkerMapCard(
      markers: markers,
      emptyMessage:
          'Kendaraan belum mengirim titik lokasi terbaru. Coba cek lagi '
          'beberapa saat lagi.',
    );
  }

  _StatusInfo _statusInfo(String status) {
    switch (status) {
      case 'loading':
        return _StatusInfo(
          label: 'Sedang Dimuat',
          description: 'Barang sedang dimuat ke kendaraan.',
          icon: Icons.inventory_rounded,
          color: AppColors.orange,
        );
      case 'berangkat':
        return _StatusInfo(
          label: 'Dalam Perjalanan',
          description: 'Barang sedang dalam perjalanan ke tujuan.',
          icon: Icons.local_shipping_rounded,
          color: AppColors.blue,
        );
      case 'tiba':
        return _StatusInfo(
          label: 'Sudah Tiba',
          description: 'Barang sudah tiba di tujuan.',
          icon: Icons.check_circle_rounded,
          color: AppColors.green,
        );
      case 'diterima':
      default:
        return _StatusInfo(
          label: 'Diterima di Kantor',
          description: 'Barang sudah diterima, menunggu dimuat.',
          icon: Icons.inventory_2_outlined,
          color: AppColors.navy,
        );
    }
  }
}

class _StatusInfo {
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const _StatusInfo({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _EmptyMapNote extends StatelessWidget {
  final String message;

  const _EmptyMapNote({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        // Diperbesar (8 Oktober 2026, lanjutan lagi -- "perbesar semua
        // demi keterbacaan"): 12.5 -> 14.
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
    );
  }
}
