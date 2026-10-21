import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/receiving_detail_model.dart';
import '../services/receiving_service.dart';

/// Provider per-resi (family) untuk daftar detail barang (receiving_details)
/// milik satu receiving tertentu.
final receivingDetailsProvider =
    FutureProvider.family<List<ReceivingDetailModel>, String>(
  (ref, receivingId) {
    return ReceivingService.getReceivingDetails(receivingId);
  },
);

/// Satu baris receiving_details berdasarkan id-nya -- dipakai di halaman
/// detail per-barang (ReceivingItemDetailPage), baik dibuka dari daftar
/// item resi maupun dari daftar item manifest.
final receivingDetailByIdProvider =
    FutureProvider.family<ReceivingDetailModel?, String>((ref, id) {
  return ReceivingService.getReceivingDetailById(id);
});

/// FITUR (8 Oktober 2026, lanjutan lagi -- "Editing di sisi Admin ...
/// tidak boleh ada loading ulang"): jumlah unit fisik 1 baris
/// receiving_details yang SUDAH discan LOAD ke kendaraan apa pun --
/// dipakai `ReceivingItemDetailPage` untuk membatasi "Ubah Jumlah" & tombol
/// "Hapus Barang". Lihat `ReceivingService.getLoadedUnitCount`.
final loadedUnitCountProvider =
    FutureProvider.family<int, String>((ref, detailId) {
  return ReceivingService.getLoadedUnitCount(detailId);
});