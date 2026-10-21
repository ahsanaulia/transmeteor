import 'package:audioplayers/audioplayers.dart';

/// Bunyi feedback saat scan QR barang (loading & delivery). Dipisah jadi
/// helper sendiri supaya dipakai bareng oleh LoadingScanPage &
/// DeliveryResiScanPage tanpa duplikasi kode.
///
/// Kenapa perlu ini: hasil uji coba lapangan tahap 1 -- staff sering
/// bingung apakah QR sudah kebaca atau belum karena jeda antar-scan
/// kepanjangan dan tidak ada indikator suara. Sekarang tiap scan sukses
/// bunyi "ting" (pendek, naik nada), tiap scan gagal/ditolak bunyi
/// "buzz" (dua ketukan rendah) -- beda jelas biar tidak perlu lihat
/// layar tiap kali.
class ScanFeedback {
  // Satu AudioPlayer dipakai ulang (bukan bikin baru tiap scan) supaya
  // tidak ada delay alokasi/resource tiap kali bunyi diputar -- penting
  // karena scan barang bisa terjadi berkali-kali dalam hitungan detik.
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playSuccess() => _play('sounds/success.wav');

  static Future<void> playFailure() => _play('sounds/fail.wav');

  static Future<void> _play(String assetPath) async {
    try {
      // stop() dulu supaya kalau ada scan cepat berturut-turut, bunyi
      // sebelumnya tidak menumpuk/tabrakan.
      await _player.stop();
      await _player.play(AssetSource(assetPath));
    } catch (_) {
      // Kalau device tidak bisa main audio (mis. speaker bermasalah),
      // jangan sampai proses pencatatan scan ikut gagal cuma gara-gara
      // bunyi tidak bisa diputar.
    }
  }
}
