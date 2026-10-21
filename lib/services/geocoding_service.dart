import 'package:geocoding/geocoding.dart';

/// Wrapper tipis di atas package `geocoding` (layanan geocoding bawaan
/// Android/iOS -- gratis, tanpa API key). Mengubah teks alamat tujuan
/// jadi koordinat lat/long buat digambar di peta rute driver.
class GeocodingService {
  /// Balikin null kalau alamat tidak ketemu / layanan lagi error -- jangan
  /// sampai proses simpan resi gagal total gara-gara ini. Staff selalu bisa
  /// isi titik manual di peta sebagai fallback.
  static Future<Location?> geocodeAddress(String address) async {
    try {
      final results = await locationFromAddress(address);
      if (results.isEmpty) return null;
      return results.first;
    } catch (_) {
      return null;
    }
  }
}