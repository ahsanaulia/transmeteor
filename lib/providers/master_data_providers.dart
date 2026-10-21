import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/company_model.dart';
import '../models/destination_model.dart';
import '../models/employee_model.dart';
import '../models/employee_role_model.dart';
import '../models/item_type_model.dart';
import '../models/package_type_model.dart';
import '../models/pricing_type_model.dart';
import '../models/representative_model.dart';
import '../models/route_pricing_model.dart';
import '../models/sender_model.dart';
import '../models/storage_model.dart';
import '../services/company_service.dart';
import '../services/destination_service.dart';
import '../services/employee_service.dart';
import '../services/item_type_service.dart';
import '../services/package_type_service.dart';
import '../services/pricing_type_service.dart';
import '../services/representative_service.dart';
import '../services/role_service.dart';
import '../services/route_pricing_service.dart';
import '../services/sender_service.dart';
import '../services/storage_service.dart';

/// Provider untuk data master yang dipakai berulang kali di banyak
/// halaman (dropdown/picker item type, pricing type, package type, dst).
///
/// Riverpod meng-cache hasilnya -- begitu satu halaman memanggil salah
/// satu provider ini, halaman lain yang butuh data yang sama tidak
/// fetch ulang ke Supabase selama provider-nya belum di-invalidate.
///
/// Kalau datanya baru saja diubah (habis create/update/deactivate di
/// halaman CRUD modul terkait), panggil `ref.invalidate(xxxProvider)`
/// supaya halaman lain ikut melihat data terbaru.

final sendersProvider = FutureProvider<List<SenderModel>>((ref) {
  return SenderService.getSenders();
});

final itemTypesProvider = FutureProvider<List<ItemTypeModel>>((ref) {
  return ItemTypeService.getItemTypes();
});

final pricingTypesProvider = FutureProvider<List<PricingTypeModel>>((ref) {
  return PricingTypeService.getPricingTypes();
});

final packageTypesProvider = FutureProvider<List<PackageTypeModel>>((ref) {
  return PackageTypeService.getPackageTypes();
});

final routePricingsProvider = FutureProvider<List<RoutePricingModel>>((ref) {
  return RoutePricingService.getRoutePricings();
});

final employeeRolesProvider = FutureProvider<List<EmployeeRoleModel>>((ref) {
  return RoleService.getRoles();
});

/// Employee dengan role DRIVER -- dipakai untuk picker sopir (form
/// kendaraan & assignment sopir/helper saat mulai muat).
final driverEmployeesProvider = FutureProvider<List<EmployeeModel>>((ref) {
  return EmployeeService.getEmployeesByRoleCode('DRIVER');
});

/// Employee dengan role HELPER -- dipakai untuk picker helper (opsional,
/// cuma diisi kalau helper itu ikut perjalanan).
final helperEmployeesProvider = FutureProvider<List<EmployeeModel>>((ref) {
  return EmployeeService.getEmployeesByRoleCode('HELPER');
});

/// SEMUA employee (aktif maupun nonaktif) -- dipakai di halaman admin
/// "Kelola Pegawai".
final allEmployeesProvider = FutureProvider<List<EmployeeModel>>((ref) {
  return EmployeeService.getAllEmployees();
});

/// SEMUA jenis harga (aktif maupun nonaktif) -- dipakai di halaman admin
/// "Kelola Jenis Harga" supaya admin bisa tambah jenis harga baru untuk
/// jenis kiriman baru, edit, atau nonaktifkan yang sudah tidak dipakai.
final allPricingTypesProvider = FutureProvider<List<PricingTypeModel>>((ref) {
  return PricingTypeService.getAllPricingTypes();
});

/// SEMUA tujuan (aktif maupun nonaktif) -- dipakai di halaman admin
/// "Kelola Daftar Tujuan" supaya admin bisa tambah tujuan baru duluan
/// (sebelum dipakai di lapangan), edit, atau nonaktifkan yang sudah
/// tidak dipakai. Field pencarian tujuan di form input resi (Receiving)
/// TIDAK pakai provider ini -- dia query langsung ke Supabase tiap kali
/// mengetik (lihat SearchPickField/DestinationService.searchDestinations)
/// supaya selalu realtime tanpa perlu invalidate provider apa pun.
final allDestinationsProvider = FutureProvider<List<DestinationModel>>((ref) {
  return DestinationService.getAllDestinations();
});

/// SEMUA pengirim (aktif maupun nonaktif) -- dipakai di halaman admin
/// "Daftar Pengirim Langganan" (permintaan user, 6 Oktober 2026
/// lanjutan). Field pencarian pengirim di form input resi TIDAK pakai
/// provider ini -- dia query langsung ke Supabase tiap kali mengetik
/// lewat SearchPickField/SenderService.searchSenders, sama seperti
/// catatan di [allDestinationsProvider].
final allSendersProvider = FutureProvider<List<SenderModel>>((ref) {
  return SenderService.getAllSenders();
});

/// SEMUA perwakilan (aktif maupun nonaktif) -- dipakai di halaman admin
/// "Daftar Perwakilan" (permintaan user, 6 Oktober 2026 lanjutan: "Butuh
/// tabel perwakilan" untuk fitur "Selesaikan di Perwakilan" di aplikasi
/// sopir). Pencarian perwakilan saat sopir menitip barang TIDAK pakai
/// provider ini -- tetap query langsung lewat
/// SearchPickField/RepresentativeService.searchRepresentatives, sama
/// seperti catatan di [allDestinationsProvider].
final allRepresentativesProvider = FutureProvider<List<RepresentativeModel>>((ref) {
  return RepresentativeService.getAllRepresentatives();
});

/// SEMUA jenis barang (aktif maupun nonaktif) -- dipakai di halaman admin
/// "Kelola Jenis Barang" (8 Oktober 2026 -- SEBELUMNYA jenis barang cuma
/// bisa didaftarkan "numpang" lewat form input resi, belum ada halaman
/// CRUD admin terpusat). Field picker jenis barang di form input resi
/// TETAP pakai [itemTypesProvider] (hanya yang aktif).
final allItemTypesProvider = FutureProvider<List<ItemTypeModel>>((ref) {
  return ItemTypeService.getAllItemTypes();
});

/// Zona Storage yang AKTIF saja -- dipakai picker "Zona Penyimpanan" di
/// form input detail barang (Receiving) & tampilan info zona di checklist
/// Loading (8 Oktober 2026, permintaan user poin 1/3/6).
final storagesProvider = FutureProvider<List<StorageModel>>((ref) {
  return StorageService.getStorages();
});

/// SEMUA zona storage (aktif maupun nonaktif) -- dipakai halaman admin
/// "Zona Storage" supaya admin bisa tambah/edit/nonaktifkan.
final allStoragesProvider = FutureProvider<List<StorageModel>>((ref) {
  return StorageService.getAllStorages();
});

/// Profil perusahaan (nama/alamat/logo) -- 1 baris saja, dipakai sebagai
/// kop di semua cetakan (resi, manifest, daftar resi per tujuan). Diisi
/// lewat halaman admin "Profil Perusahaan"; panggil
/// `ref.invalidate(companyProvider)` setelah disimpan supaya cetakan
/// berikutnya langsung pakai data terbaru.
final companyProvider = FutureProvider<CompanyModel?>((ref) {
  return CompanyService.getCompany();
});
