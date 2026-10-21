import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/supabase_config.dart';
import '../core/services/supabase_service.dart';

/// Pembuatan akun pegawai BARU oleh ADMIN (8 Oktober 2026, permintaan
/// user poin 8: "Pada login, hilangkan register pengguna baru. Pada
/// admin pastikan admin bisa membuat user baru untuk dibagikan kepada
/// pegawai dengan passwordnya").
///
/// --- KENAPA TIDAK PAKAI `SupabaseService.client.auth.signUp()` ---
/// `AuthService.register()` (dipakai `RegisterPage` lama, self-register)
/// memanggil `signUp()` di `SupabaseService.client` -- client SINGLETON
/// yang SAMA dipakai untuk sesi admin yang sedang login. Satu
/// `SupabaseClient`/`GoTrueClient` cuma bisa pegang SATU sesi aktif --
/// begitu `signUp()` dipanggil (dan auto-confirm email AKTIF di project
/// ini, terbukti dari self-register lama yang langsung bisa login tanpa
/// konfirmasi email), SDK otomatis MENGGANTI sesi lokal jadi sesi user
/// BARU yang baru dibuat. Kalau ini dipanggil selagi admin sedang login
/// dari menu "Buat User Pegawai", efeknya admin TIBA-TIBA ter-logout &
/// "berubah" jadi pegawai baru itu -- bug fatal yang HARUS dihindari,
/// sesuai aturan standing "telusuri kemungkinan kesalahan sebelum
/// kirim kode" di project ini.
///
/// --- SOLUSI ---
/// Panggil REST API Auth Supabase (`POST /auth/v1/signup`) LANGSUNG lewat
/// `http.post` biasa -- BUKAN lewat SDK `SupabaseClient` apa pun. Request
/// HTTP polos ini sama sekali tidak menyentuh `Supabase.instance`/sesi
/// lokal mana pun, jadi sesi admin yang sedang login di app TIDAK
/// TERGANGGU sama sekali, apa pun hasilnya. Setelah akun Auth berhasil
/// dibuat, baris `employees` diinsert lewat `SupabaseService.client`
/// (sesi ADMIN yang masih aktif -- aman, admin yang insert, bukan user
/// baru itu).
class AdminAuthService {
  /// Buat akun Auth + baris employee untuk pegawai baru. Balikin
  /// `userId` (uuid auth.users) yang baru dibuat -- dipakai pemanggil
  /// kalau perlu, tapi biasanya tidak perlu dipakai lagi.
  static Future<String> createEmployeeAccount({
    required String employeeNumber,
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String roleId,
  }) async {
    final uri = Uri.parse('${SupabaseConfig.url}/auth/v1/signup');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.publishableKey,
        'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Respons tidak terduga dari server Auth (status ${response.statusCode}).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body['msg'] ?? body['message'] ?? body['error_description'];
      throw Exception(message?.toString() ?? 'Gagal membuat akun (status ${response.statusCode}).');
    }

    // Bentuk respons GoTrue `/signup` bisa 2 macam tergantung setting
    // auto-confirm: (a) auto-confirm AKTIF -> balikin Session (ada key
    // 'user' nested + 'access_token'), (b) auto-confirm NONAKTIF ->
    // balikin User langsung (key 'id' di level atas). Tangani keduanya
    // supaya tidak diam-diam gagal ambil id kalau setting project
    // berubah di kemudian hari.
    final userMap = body['user'] as Map<String, dynamic>? ?? body;
    final userId = userMap['id'] as String?;

    if (userId == null) {
      throw Exception('Akun Auth terbuat tapi user id tidak ditemukan di respons.');
    }

    // Insert baris employee lewat SESI ADMIN yang masih aktif (client
    // singleton SupabaseService -- TIDAK terganggu oleh signup di atas
    // karena signup dilakukan lewat HTTP polos, bukan SDK client ini).
    await SupabaseService.client.from('employees').insert({
      'id': userId,
      'employee_number': employeeNumber,
      'full_name': fullName,
      'phone': phone.isEmpty ? null : phone,
      'role_id': roleId,
      'is_active': true,
    });

    return userId;
  }
}
