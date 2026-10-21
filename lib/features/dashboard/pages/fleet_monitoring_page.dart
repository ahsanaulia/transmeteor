import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../providers/driver_providers.dart';
import '../../../providers/monitoring_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../services/shipment_service.dart';

/// Peta posisi kendaraan (Monitoring Vehicles & Driver).
///
/// PENTING: peta HANYA menampilkan kendaraan yang di-tap dari daftar di
/// bawahnya -- BUKAN semua kendaraan sekaligus. Sebelumnya semua marker
/// kendaraan digambar bersamaan di satu peta, yang bikin peta penuh dan
/// membingungkan begitu armada makin banyak (apalagi marker saling
/// tumpuk kalau beberapa kendaraan sedang di area berdekatan). Sekarang
/// admin harus pilih dulu kendaraan mana yang mau dilihat lokasinya.
///
/// Begitu kendaraan dipilih & sedang bawa shipment aktif, di bawah peta
/// juga muncul ringkasan "berapa resi sudah sampai / belum" (lihat
/// `_buildResiSummaryCard`) -- MURNI informasi buat admin, TIDAK
/// menghalangi kendaraan itu dipakai/disiapkan ulang untuk trip
/// berikutnya walau masih ada resi yang belum tercatat sampai.
class FleetMonitoringPage extends ConsumerStatefulWidget {
  const FleetMonitoringPage({super.key});

  @override
  ConsumerState<FleetMonitoringPage> createState() => _FleetMonitoringPageState();
}

class _FleetMonitoringPageState extends ConsumerState<FleetMonitoringPage> {
  // vehicleId (bukan shipmentId) -- dipakai sebagai kunci pilihan karena
  // kendaraan yang lagi idle di kantor tidak punya shipmentId, tapi tetap
  // harus bisa di-tap (untuk lihat statusnya, walau tidak ada lokasi).
  String? _selectedVehicleId;
  bool _isForceCompleting = false;
  bool _isForceCompletingDestination = false;
  bool _isForceStartingTrip = false;

  Color _statusColor(Map<String, dynamic> vehicle) {
    final shipmentId = vehicle['shipmentId'];
    final status = vehicle['shipmentStatus'] as String?;
    final hasLocation = vehicle['latitude'] != null;

    if (shipmentId == null) return AppColors.textSecondary;
    if (status == 'LOADING') return AppColors.orange;
    if (status == 'DEPARTED') return hasLocation ? AppColors.green : AppColors.blue;
    return AppColors.textSecondary;
  }

  String _statusLabel(Map<String, dynamic> vehicle) {
    final shipmentId = vehicle['shipmentId'];
    final status = vehicle['shipmentStatus'] as String?;
    final hasLocation = vehicle['latitude'] != null;

    if (shipmentId == null) return 'Idle di Kantor';
    if (status == 'LOADING') return 'Sedang Dimuat';
    if (status == 'DEPARTED') return hasLocation ? 'Dalam Perjalanan' : 'Berangkat';
    return status ?? '-';
  }

  String _formatPingTime(dynamic recordedAt) {
    if (recordedAt == null) return 'Lokasi belum diketahui';

    final dt = DateTime.parse(recordedAt.toString());
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _selectVehicle(String vehicleId) {
    setState(() {
      // Tap kendaraan yang sama lagi -- batalkan pilihan (toggle),
      // supaya ada cara balik ke state "belum pilih" tanpa tombol lain.
      _selectedVehicleId = _selectedVehicleId == vehicleId ? null : vehicleId;
    });
  }

  /// "Intervensi Admin: Mulai Paksa Perjalanan" -- permintaan eksplisit
  /// user (22 September 2026): sopir kadang lupa menekan "Mulai
  /// Perjalanan" di aplikasinya padahal kendaraan sudah fisik
  /// meninggalkan gudang, jadi tracking GPS tidak pernah aktif. Beda dari
  /// [_confirmForceComplete] (ujung AKHIR perjalanan) -- ini ujung AWAL.
  ///
  /// Begitu ditekan, `trip_started_at` diisi lewat
  /// `ShipmentService.forceStartTripByAdmin` -- HP sopir otomatis RESUME
  /// tracking GPS sendiri lewat realtime sync begitu online (lihat catatan
  /// lengkap di doc comment method itu), TANPA sopir perlu tap apa pun.
  Future<void> _confirmForceStartTrip(Map<String, dynamic> vehicle) async {
    final shipmentId = vehicle['shipmentId'] as String?;
    if (shipmentId == null) return;

    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;

          return AlertDialog(
            title: const Text('Intervensi Admin: Mulai Paksa Perjalanan?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ini akan menandai perjalanan ${vehicle['shipmentNumber'] ?? 'shipment ini'} '
                  'SUDAH DIMULAI (trip_started_at terisi sekarang) dan tracking GPS '
                  '${vehicle['plateNumber']} akan otomatis aktif di HP sopir begitu online -- '
                  'TANPA konfirmasi dari sopir. Gunakan kalau sopir lupa menekan "Mulai '
                  'Perjalanan" padahal kendaraan sudah fisik meninggalkan gudang.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Alasan (wajib diisi)',
                    hintText: 'mis. sopir lupa klik, dikonfirmasi lewat telepon sudah jalan',
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
                style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
                child: const Text('Ya, Berangkatkan Paksa'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final note = noteController.text.trim();
    if (note.isEmpty) return;

    setState(() => _isForceStartingTrip = true);

    try {
      await ShipmentService.forceStartTripByAdmin(shipmentId: shipmentId, note: note);

      ref.invalidate(fleetPositionsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perjalanan ditandai berangkat -- tracking GPS akan aktif sendiri di HP sopir.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memberangkatkan paksa: $e')),
      );
    } finally {
      if (mounted) setState(() => _isForceStartingTrip = false);
    }
  }

  /// "Intervensi Admin: Selesaikan Perjalanan" -- OPSI 1 dari 2 pilihan
  /// "Intervensi Penyelesaian" (permintaan eksplisit user, 9 September
  /// 2026, direstruktur jadi 2 opsi pada 23 September 2026 -- lihat
  /// `_buildForceCompleteSection`): admin sebagai otoritas tertinggi perlu
  /// jalan keluar kalau sopir mengalami kendala aplikasi di lapangan (HP
  /// rusak/hilang/baterai habis/tidak ada sinyal) sehingga tidak bisa
  /// menekan "Sudah Kembali ke Kantor" sendiri -- tanpa ini, kendaraan itu
  /// tertahan permanen (tidak bisa disiapkan ulang untuk trip berikutnya).
  /// Ini menyelesaikan SELURUH manifest/shipment sekaligus (status ->
  /// ARRIVED) -- beda dari OPSI 2 ([_confirmForceCompleteDestination])
  /// yang cuma menyusulkan status "sudah discan" PER TUJUAN tanpa
  /// menyelesaikan shipment-nya.
  ///
  /// SENGAJA dibuat berat/tidak gampang kepencet tidak sengaja: dialog
  /// konfirmasi eksplisit menyebut konsekuensinya, DAN alasan wajib diisi
  /// (disimpan sebagai `admin_completion_note` buat jejak audit -- lihat
  /// `ShipmentService.forceCompleteByAdmin`).
  Future<void> _confirmForceComplete(Map<String, dynamic> vehicle) async {
    final shipmentId = vehicle['shipmentId'] as String?;
    if (shipmentId == null) return;

    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;

          return AlertDialog(
            title: const Text('Intervensi Admin: Selesaikan Perjalanan?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ini akan menandai ${vehicle['shipmentNumber'] ?? 'shipment ini'} '
                  'SELESAI (ARRIVED) dan membebaskan ${vehicle['plateNumber']} untuk '
                  'disiapkan/dimuat lagi -- TANPA konfirmasi dari sopir. Gunakan HANYA '
                  'kalau sopir benar-benar tidak bisa menyelesaikan lewat aplikasinya '
                  'sendiri (HP rusak/hilang/baterai habis/tidak ada sinyal). Aksi ini '
                  'tidak bisa dibatalkan.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Alasan (wajib diisi)',
                    hintText: 'mis. HP sopir rusak, dikonfirmasi lewat telepon sudah sampai',
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
                child: const Text('Ya, Selesaikan Paksa'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final note = noteController.text.trim();
    if (note.isEmpty) return;

    setState(() => _isForceCompleting = true);

    try {
      await ShipmentService.forceCompleteByAdmin(shipmentId: shipmentId, note: note);

      // Shipment ini sudah ARRIVED -- otomatis hilang dari daftar aktif,
      // jadi pilihan lama sudah tidak relevan lagi.
      ref.invalidate(fleetPositionsProvider);
      setState(() => _selectedVehicleId = null);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perjalanan ditandai selesai oleh admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyelesaikan paksa: $e')),
      );
    } finally {
      if (mounted) setState(() => _isForceCompleting = false);
    }
  }

  /// "Intervensi Admin: Selesaikan Per Tujuan" -- OPSI 2 dari 2 pilihan
  /// "Intervensi Penyelesaian" (permintaan eksplisit user, 23 September
  /// 2026). BEDA dari OPSI 1 ([_confirmForceComplete], yang memaksa
  /// SELURUH manifest/shipment jadi ARRIVED): ini untuk skenario yang
  /// LEBIH SEMPIT -- sopir sebenarnya masih bisa pakai aplikasi & sudah
  /// menurunkan barang dengan benar secara fisik, TAPI LUPA scan turun
  /// (DELIVER) untuk satu/beberapa TUJUAN tertentu saja. Admin pilih
  /// tujuan mana (dikelompokkan SAMA PERSIS dengan PDF "Tanda Terima
  /// Tujuan" -- lihat `ShipmentService.getManifestGroupedByDestination`,
  /// satu tujuan bisa gabungan beberapa resi) yang mau "disusulkan" status
  /// sudah-discan-nya -- status shipment/perjalanan TIDAK diubah sama
  /// sekali di sini, kendaraan tetap jalan normal untuk tujuan lain yang
  /// belum sampai.
  ///
  /// Tujuan yang sudah 100% lengkap (`deliveredItems >= totalItems`)
  /// ditampilkan tapi checkbox-nya dikunci (tidak ada yang perlu
  /// disusulkan) -- murni supaya admin tetap lihat konteks lengkap
  /// manifestnya, bukan cuma daftar yang bermasalah.
  Future<void> _confirmForceCompleteDestination(Map<String, dynamic> vehicle) async {
    final shipmentId = vehicle['shipmentId'] as String?;
    if (shipmentId == null) return;

    List<Map<String, dynamic>> destinations;
    try {
      destinations = await ShipmentService.getManifestGroupedByDestination(shipmentId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat daftar tujuan: $e')),
      );
      return;
    }

    if (!mounted) return;

    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada tujuan di manifest shipment ini.')),
      );
      return;
    }

    final noteController = TextEditingController();
    final selectedKeys = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;

          return AlertDialog(
            title: const Text('Intervensi Admin: Selesaikan Per Tujuan?'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih tujuan yang barangnya SUDAH benar-benar diturunkan sopir '
                    'tapi LUPA discan turun di aplikasi. Barang yang belum discan di '
                    'tujuan terpilih akan ditandai sudah turun -- status perjalanan '
                    '${vehicle['shipmentNumber'] ?? 'shipment ini'} TIDAK berubah.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: destinations.length,
                      itemBuilder: (context, index) {
                        final dest = destinations[index];
                        final key = dest['destinationKey'] as String;
                        final name = (dest['destinationName'] ?? '-').toString();
                        final total = dest['totalItems'] as int;
                        final delivered = dest['deliveredItems'] as int;
                        final isComplete = total > 0 && delivered >= total;

                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: isComplete ? true : selectedKeys.contains(key),
                          onChanged: isComplete
                              ? null
                              : (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      selectedKeys.add(key);
                                    } else {
                                      selectedKeys.remove(key);
                                    }
                                  });
                                },
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          subtitle: Text(
                            isComplete
                                ? '$delivered/$total barang -- sudah lengkap'
                                : '$delivered/$total barang sudah discan turun',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isComplete ? AppColors.green : AppColors.orange,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Alasan (wajib diisi)',
                      hintText: 'mis. dikonfirmasi lewat telepon sudah diturunkan semua',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedKeys.isEmpty) {
                    setDialogState(() => errorText = 'Pilih minimal 1 tujuan.');
                    return;
                  }
                  if (noteController.text.trim().isEmpty) {
                    setDialogState(() => errorText = 'Alasan wajib diisi.');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                child: const Text('Ya, Tandai Sudah Turun'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final note = noteController.text.trim();
    if (note.isEmpty || selectedKeys.isEmpty) return;

    final receivingIds = <String>{};
    for (final dest in destinations) {
      if (selectedKeys.contains(dest['destinationKey'])) {
        receivingIds.addAll((dest['receivingIds'] as List).cast<String>());
      }
    }

    setState(() => _isForceCompletingDestination = true);

    try {
      final employee = await ref.read(currentEmployeeProvider.future);
      if (employee == null) {
        throw Exception('Data employee admin tidak ditemukan.');
      }

      final created = await ShipmentService.forceCompleteDestinationByAdmin(
        shipmentId: shipmentId,
        receivingIds: receivingIds.toList(),
        scannedBy: employee.id,
        note: note,
      );

      // Shipment TIDAK diubah statusnya -- cuma progress scan DELIVER-nya,
      // jadi cukup invalidate provider manifest/scan (bukan
      // fleetPositionsProvider, kendaraan ini tetap aktif seperti semula).
      ref.invalidate(shipmentManifestByReceivingProvider(shipmentId));
      ref.invalidate(shipmentManifestByDestinationProvider(shipmentId));
      ref.invalidate(shipmentDeliverScansProvider(shipmentId));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created > 0
                ? '$created barang ditandai sudah turun untuk ${selectedKeys.length} tujuan.'
                : 'Tidak ada barang tersisa yang perlu ditandai (mungkin sudah discan semua).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyelesaikan per tujuan: $e')),
      );
    } finally {
      if (mounted) setState(() => _isForceCompletingDestination = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(fleetPositionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Monitoring Kendaraan & Sopir'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: () async {
          ref.invalidate(fleetPositionsProvider);
          await ref.read(fleetPositionsProvider.future);
        },
        child: fleetAsync.when(
          data: (vehicles) {
            Map<String, dynamic>? selectedVehicle;
            for (final v in vehicles) {
              if (v['vehicleId'] == _selectedVehicleId) {
                selectedVehicle = v;
                break;
              }
            }

            // Hanya 1 marker -- punya kendaraan yang sedang dipilih, dan
            // cuma kalau kendaraan itu sudah punya titik lokasi.
            final markers = <MapMarkerData>[];
            if (selectedVehicle != null &&
                selectedVehicle['latitude'] != null &&
                selectedVehicle['longitude'] != null) {
              markers.add(MapMarkerData(
                latitude: (selectedVehicle['latitude'] as num).toDouble(),
                longitude: (selectedVehicle['longitude'] as num).toDouble(),
                color: _statusColor(selectedVehicle),
                icon: Icons.local_shipping_rounded,
                label:
                    '${selectedVehicle['plateNumber']} • ${selectedVehicle['driverName'] ?? 'Belum ada sopir'}',
              ));
            }

            final String emptyMessage;
            if (selectedVehicle == null) {
              emptyMessage = 'Ketuk salah satu kendaraan di bawah untuk melihat lokasinya di peta.';
            } else if (markers.isEmpty) {
              emptyMessage =
                  '${selectedVehicle['plateNumber']} belum punya titik lokasi (belum berangkat atau belum ada ping GPS masuk).';
            } else {
              emptyMessage = 'Belum ada titik lokasi untuk ditampilkan.';
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                MultiMarkerMapCard(
                  markers: markers,
                  emptyMessage: emptyMessage,
                ),
                // Ringkasan resi kendaraan yang dipilih -- HANYA muncul
                // begitu satu kendaraan di-tap (bukan dihitung di muka
                // untuk semua kendaraan sekaligus, biar tidak berat) DAN
                // kendaraan itu memang lagi bawa shipment. Ini MURNI info
                // (berapa resi sudah sampai/belum) -- SENGAJA TIDAK ada
                // validasi/gate apa pun di sini yang memblokir apa-apa;
                // kendaraan tetap boleh dimuat ulang oleh Loading berapa
                // pun resi yang belum sampai (lihat komentar panjang di
                // `_buildResiSummaryCard`).
                if (selectedVehicle != null && selectedVehicle['shipmentId'] != null)
                  _buildResiSummaryCard(selectedVehicle),
                // Muncul HANYA kalau shipment aktif TAPI sopir belum
                // pernah menekan "Mulai Perjalanan" sama sekali
                // (tripStartedAt masih null) -- persis skenario "sopir
                // lupa klik berangkat".
                if (selectedVehicle != null &&
                    selectedVehicle['shipmentId'] != null &&
                    selectedVehicle['tripStartedAt'] == null &&
                    (selectedVehicle['shipmentStatus'] == 'LOADING' ||
                        selectedVehicle['shipmentStatus'] == 'DEPARTED'))
                  _buildForceStartTripSection(selectedVehicle),
                if (selectedVehicle != null &&
                    selectedVehicle['shipmentId'] != null &&
                    (selectedVehicle['shipmentStatus'] == 'LOADING' ||
                        selectedVehicle['shipmentStatus'] == 'DEPARTED'))
                  _buildForceCompleteSection(selectedVehicle),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${vehicles.length} Kendaraan',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (selectedVehicle != null)
                      TextButton.icon(
                        onPressed: () => setState(() => _selectedVehicleId = null),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Batalkan Pilihan'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final vehicle in vehicles)
                  _buildVehicleTile(
                    vehicle,
                    isSelected: vehicle['vehicleId'] == _selectedVehicleId,
                    onTap: () => _selectVehicle(vehicle['vehicleId'] as String),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
          error: (error, _) => ErrorStateView(
            title: 'Gagal memuat posisi kendaraan.',
            message: error.toString(),
            onRetry: () => ref.invalidate(fleetPositionsProvider),
          ),
        ),
      ),
    );
  }

  /// Ringkasan resi (manifest) yang dibawa shipment aktif kendaraan yang
  /// dipilih -- "berapa resi sudah sampai, berapa belum" (bukan berapa
  /// SHIPMENT/trip, karena satu shipment/trip = satu perjalanan kendaraan
  /// yang bisa membawa BANYAK resi tujuan berbeda sekaligus).
  ///
  /// PENTING (permintaan eksplisit user, 9 September 2026): kartu ini
  /// MURNI informasi, BUKAN validasi. Sengaja TIDAK ADA logic yang
  /// mengunci apa pun berdasarkan angka "belum sampai" di sini --
  /// kendaraan boleh saja disiapkan ulang & dimuat lagi oleh Loading
  /// walau masih ada resi trip sebelumnya yang belum tercatat sampai.
  /// JANGAN tambahkan validasi "wajib semua resi sampai dulu" di mana
  /// pun terkait fitur ini -- itu akan mencegat/memblokir alur kerja
  /// normal (kendaraan sering dipakai lagi sebelum semua resi trip
  /// sebelumnya beres dicatat "sampai" oleh driver/helper).
  Widget _buildResiSummaryCard(Map<String, dynamic> vehicle) {
    final shipmentId = vehicle['shipmentId'] as String;
    final manifestAsync = ref.watch(shipmentManifestByReceivingProvider(shipmentId));

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: manifestAsync.when(
          data: (resiList) {
            final totalResi = resiList.length;
            final sudahSampai = resiList.where((r) {
              final total = r['totalItems'] as int;
              final delivered = r['deliveredItems'] as int;
              return total > 0 && delivered >= total;
            }).length;
            final belumSampai = totalResi - sudahSampai;

            if (totalResi == 0) {
              return const Text(
                'Belum ada resi dimuat di perjalanan ini.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              );
            }

            return Row(
              children: [
                Expanded(
                  child: Text(
                    '${vehicle['shipmentNumber'] ?? '-'} • $totalResi Resi Dimuat',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                ),
                _resiStatChip('$sudahSampai Sampai', AppColors.green),
                const SizedBox(width: 6),
                _resiStatChip('$belumSampai Belum', AppColors.orange),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 18,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
              ),
            ),
          ),
          error: (_, __) => const Text(
            'Gagal memuat ringkasan resi.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      ),
    );
  }

  /// Tombol "Intervensi Admin: Mulai Paksa Perjalanan" -- HANYA muncul
  /// kalau shipment aktif TAPI `tripStartedAt` masih null (sopir belum
  /// pernah menekan "Mulai Perjalanan"). Sengaja bergaya biru (bukan
  /// merah seperti Selesaikan Paksa) -- ini override yang jauh lebih
  /// ringan/reversibel (cuma menandai perjalanan sudah mulai, bukan
  /// menutup paksa), tapi tetap wajib diisi alasan buat jejak audit.
  Widget _buildForceStartTripSection(Map<String, dynamic> vehicle) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.blue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.blue.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: AppColors.blue, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Sopir lupa menekan "Mulai Perjalanan"?',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.blue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Kendaraan ini belum ada titik lokasi sama sekali (tracking GPS belum '
              'aktif). Pakai kalau sudah dikonfirmasi kendaraan sebenarnya sudah '
              'berangkat -- tracking GPS akan otomatis aktif sendiri di HP sopir.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isForceStartingTrip ? null : () => _confirmForceStartTrip(vehicle),
                icon: _isForceStartingTrip
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
                      )
                    : const Icon(Icons.north_east_rounded, size: 18),
                label: Text(_isForceStartingTrip ? 'Memproses...' : 'Berangkatkan Paksa (Intervensi Admin)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  side: const BorderSide(color: AppColors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Intervensi Penyelesaian" -- HANYA muncul kalau kendaraan yang
  /// dipilih sedang bawa shipment aktif (LOADING/DEPARTED). Sengaja
  /// bergaya "danger" (merah, border, ikon peringatan) supaya beda jelas
  /// dari kartu info biasa -- ini aksi override, bukan aksi rutin.
  ///
  /// Direstruktur jadi 2 OPSI terpisah (permintaan eksplisit user, 23
  /// September 2026) -- sebelumnya cuma ada 1 tombol ("Selesaikan Paksa")
  /// yang langsung memaksa SELURUH manifest/shipment jadi ARRIVED, padahal
  /// ada 2 skenario intervensi yang beda kebutuhannya:
  /// 1. **Penyelesaian Seluruh Manifest** ([_confirmForceComplete]) --
  ///    sopir benar-benar tidak bisa pakai aplikasinya sama sekali (HP
  ///    rusak/hilang/baterai habis/tidak ada sinyal), jadi seluruh
  ///    perjalanan dipaksa selesai (ARRIVED) dari sini.
  /// 2. **Penyelesaian Per Tujuan** ([_confirmForceCompleteDestination])
  ///    -- sopir LUPA scan turun (DELIVER) untuk tujuan tertentu saja
  ///    walau barangnya sudah benar-benar diturunkan & aplikasinya masih
  ///    bisa dipakai normal -- admin cuma menyusulkan status sudah-discan
  ///    PER TUJUAN (sesuai pengelompokan "Tanda Terima Tujuan"), TANPA
  ///    memaksa shipment-nya selesai.
  Widget _buildForceCompleteSection(Map<String, dynamic> vehicle) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.red.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: AppColors.red, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Intervensi Penyelesaian',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pilih salah satu opsi di bawah sesuai kondisi sopir di lapangan.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 12),

            // OPSI 1: Penyelesaian Seluruh Manifest.
            const Text(
              '1. Penyelesaian Seluruh Manifest',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.red),
            ),
            const SizedBox(height: 3),
            const Text(
              'Pakai HANYA kalau sopir benar-benar tidak bisa pakai aplikasinya '
              'sama sekali (HP rusak/hilang/tidak ada sinyal) -- ini menandai '
              'SELURUH perjalanan selesai tanpa konfirmasi dari sopir.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isForceCompleting ? null : () => _confirmForceComplete(vehicle),
                icon: _isForceCompleting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.red),
                      )
                    : const Icon(Icons.flag_circle_rounded, size: 18),
                label: Text(_isForceCompleting ? 'Memproses...' : 'Selesaikan Paksa (Seluruh Manifest)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                ),
              ),
            ),

            const SizedBox(height: 14),
            Divider(color: AppColors.red.withOpacity(0.2), height: 1),
            const SizedBox(height: 14),

            // OPSI 2: Penyelesaian Per Tujuan (sopir lupa scan).
            const Text(
              '2. Penyelesaian Per Tujuan (Jika Sopir Lupa Scan)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.orange),
            ),
            const SizedBox(height: 3),
            const Text(
              'Barang sudah benar-benar diturunkan dengan benar tapi sopir LUPA '
              'scan turun di aplikasi untuk tujuan tertentu -- pilih tujuannya di '
              'sini, TANPA menyelesaikan seluruh perjalanan.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isForceCompletingDestination
                    ? null
                    : () => _confirmForceCompleteDestination(vehicle),
                icon: _isForceCompletingDestination
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
                      )
                    : const Icon(Icons.pin_drop_rounded, size: 18),
                label: Text(
                  _isForceCompletingDestination ? 'Memproses...' : 'Selesaikan Per Tujuan',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: const BorderSide(color: AppColors.orange),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resiStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10.5),
      ),
    );
  }

  Widget _buildVehicleTile(
    Map<String, dynamic> vehicle, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final color = _statusColor(vehicle);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.blue : AppColors.border,
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.blue.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.local_shipping_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${vehicle['plateNumber']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        '${vehicle['driverName'] ?? 'Belum ada sopir'}'
                        '${vehicle['shipmentNumber'] != null ? ' • ${vehicle['shipmentNumber']}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatPingTime(vehicle['lastPingAt']),
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    _statusLabel(vehicle),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10.5),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: isSelected ? AppColors.blue : AppColors.textSecondary.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
