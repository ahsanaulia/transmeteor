import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/shipment_model.dart';
import '../../../models/vehicle_model.dart';
import '../widgets/manual_load_cancel_checklist.dart';
import '../widgets/manual_load_checklist.dart';

/// Halaman Admin "Loading Barang" -- INTERVENSI manual (permintaan user
/// eksplisit, 7 Oktober 2026): kadang staff loading lupa/tidak mencatat
/// muatan di app padahal barangnya SUDAH naik ke truk (dimuat buruh).
/// Admin butuh cara mencatatkan itu sendiri, tanpa harus pinjam akun
/// staff loading atau minta staff balik ke lapangan.
///
/// **PERUBAHAN ALUR MASUK (7 Oktober 2026 lanjutan lagi, permintaan user
/// eksplisit)**: SEBELUMNYA halaman ini HANYA bisa dibuka dari tile
/// shipment yang SUDAH ADA di `ShipmentDispatchPage` ("Daftar Muatan") --
/// artinya admin BARU bisa intervensi setelah staff loading sendiri lebih
/// dulu membuka kendaraan itu di app (shipment-nya baru tercipta begitu
/// staff buka `VehicleSelectPage`). User eksplisit minta ini diubah: admin
/// HARUS bisa melakukan ini TOTAL INDEPENDEN dari staff loading -- lewat
/// menu standalone "Loading Barang" di Dashboard (`dashboard_home_page.dart`,
/// section Operasional, TERPISAH dari "Daftar Muatan"), yang membuka
/// `VehicleSelectPage` (dipakai ulang, BUKAN halaman pilih-kendaraan
/// terpisah -- lihat doc comment class itu) supaya admin bisa pilih
/// kendaraan yang sudah disiapkan & SEKALIGUS membuat/melanjutkan
/// shipment-nya sendiri (`ShipmentService.resolveOrCreateShipmentForVehicle`),
/// baru kemudian masuk ke halaman checklist INI. `ShipmentDispatchPage`
/// TIDAK LAGI punya tombol/akses ke halaman ini sama sekali.
///
/// `vehicle` masih nullable (defensif, jaga-jaga provider belum resolve)
/// tapi di alur SAAT INI selalu terisi -- `VehicleSelectPage` baru masuk
/// ke sini setelah `vehicle` & `shipment` keduanya pasti ada.
///
/// Isinya dipakaikan `ManualLoadChecklistView` (tab "Tambah"), SAMA
/// PERSIS dengan mode "Tanpa Label QR" di `LoadingScanPage` (resi mana
/// saja yang tersedia, cara memuat -- TIDAK ADA logic terpisah/dobel).
/// Bedanya cuma `notesPrefix` yang dicatat ke `shipment_scans.notes`,
/// supaya baris yang dicatat admin lewat sini tetap bisa dibedakan dari
/// yang dicatat staff loading sendiri kalau nanti ada audit/komplain.
///
/// **TAMBAHAN (14 Oktober 2026, permintaan user eksplisit)**: "Pembatalan
/// Loading. Di admin bisa dibatalkan loading. Dengan cara menghilangkan
/// centangnya. Jadi kalau diadmin barang yang diloading tidak hilang
/// dari layar tetapi patokannya centang. Beda dengan bagian loading.
/// Barang sudah diloading hilang dari layar." -- halaman ini SEKARANG
/// punya 2 tab: "Tambah" (checklist lama, tidak diubah) dan "Batalkan
/// Loading" (`ManualLoadCancelChecklistView`, BARU) -- lihat doc comment
/// panjang widget itu & `ShipmentService.getManualLoadCancelItems` untuk
/// detail kenapa perilakunya SENGAJA beda dari tab "Tambah" (barang
/// TIDAK hilang dari layar setelah ditoggle, checkbox = status riil di
/// database, bukan "draft" sebelum submit).
class AdminManualLoadPage extends StatelessWidget {
  final ShipmentModel shipment;
  final VehicleModel? vehicle;

  const AdminManualLoadPage({
    super.key,
    required this.shipment,
    required this.vehicle,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          title: Text(
            'Loading Barang',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          bottom: TabBar(
            labelColor: AppColors.blue,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.blue,
            tabs: const [
              Tab(text: 'Tambah'),
              Tab(text: 'Batalkan Loading'),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shipment.shipmentNumber,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        Text(
                          vehicle != null
                              ? '${vehicle!.plateNumber}'
                                  '${vehicle!.driverName != null ? ' • ${vehicle!.driverName}' : ''}'
                              : 'Kendaraan tidak diketahui',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Intervensi admin: catat barang yang sudah dimuat '
                          'buruh tapi belum tercatat di app, atau batalkan '
                          'loading yang salah catat.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ManualLoadChecklistView(
                    shipmentId: shipment.id,
                    notesPrefix:
                        'Admin intervensi: barang sudah dimuat buruh, dicatat manual oleh admin',
                  ),
                  ManualLoadCancelChecklistView(shipmentId: shipment.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
