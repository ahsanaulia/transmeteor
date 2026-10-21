import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../models/company_model.dart';

/// Profil perusahaan -- HANYA 1 baris di tabel `company` (bukan data
/// master multi-row seperti sender/destination), dipakai sebagai kop di
/// semua cetakan (resi, manifest, daftar resi per tujuan). Diisi/diubah
/// lewat halaman Admin "Profil Perusahaan".
class CompanyService {
  static final _client = SupabaseService.client;
  // (22 September 2026) SEBELUMNYA bucket ini bernama 'company-assets' --
  // sesuai catatan di create_company_table.sql, bucket itu HARUS dibuat
  // manual dulu di Supabase Dashboard (Storage -> New bucket, centang
  // Public) sebelum upload logo bisa jalan. Ternyata langkah manual itu
  // belum sempat dilakukan, jadi tiap upload logo gagal diam-diam dengan
  // error "Bucket not found" -- ini AKAR MASALAH laporan user "upload
  // logo tidak jalan". Diperbaiki dengan numpang ke bucket
  // 'expense-receipts' yang SUDAH ADA & terbukti public (dipakai fitur
  // bukti pengeluaran) -- logo disimpan di folder 'company-logos/' di
  // dalam bucket yang sama supaya tetap terpisah rapi dari bukti
  // pengeluaran, TANPA butuh bikin bucket baru lagi di Supabase.
  static const _logoBucket = 'expense-receipts';
  static const _logoFolder = 'company-logos';

  /// Ambil satu-satunya baris company. Kalau tabel masih kosong (misal
  /// SQL setup belum sempat insert default), balikin null -- pemanggil
  /// tinggal tampilkan form kosong.
  static Future<CompanyModel?> getCompany() async {
    final response = await _client
        .from('company')
        .select()
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return CompanyModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Upload logo perusahaan ke Supabase Storage, balikin URL publiknya.
  ///
  /// Numpang di bucket `expense-receipts` yang sudah PUBLIC & sudah ada
  /// (lihat catatan panjang di atas soal kenapa) -- kalau mau private,
  /// ganti getPublicUrl jadi createSignedUrl.
  static Future<String> uploadLogo(Uint8List bytes) async {
    final path = '$_logoFolder/logo-${DateTime.now().millisecondsSinceEpoch}.png';

    await _client.storage.from(_logoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/png'),
        );

    return _client.storage.from(_logoBucket).getPublicUrl(path);
  }

  /// Update baris company yang sudah ada (dari SQL setup, selalu ada 1
  /// baris default). Kalau ternyata belum ada baris sama sekali, insert
  /// baru sekali ini saja.
  static Future<CompanyModel> saveCompany({
    String? id,
    required String name,
    String? address,
    String? phone,
    String? logoUrl,
    int gpsPingIntervalSeconds = 900,
    String? companyPublicUrl,
    int resiOverdueDays = 3,
  }) async {
    final data = {
      'name': name,
      'address': address,
      'phone': phone,
      'logo_url': logoUrl,
      'gps_ping_interval_seconds': gpsPingIntervalSeconds,
      'company_public_url': companyPublicUrl,
      'resi_overdue_days': resiOverdueDays,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (id != null) {
      final response = await _client
          .from('company')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      return CompanyModel.fromMap(Map<String, dynamic>.from(response));
    }

    final response = await _client
        .from('company')
        .insert(data)
        .select()
        .single();

    return CompanyModel.fromMap(Map<String, dynamic>.from(response));
  }
}
