/// Pemicu "unduh [bytes] ke lokal sebagai [fileName]" -- beda
/// implementasi antara platform native (dart:io, dipakai Android/iOS/
/// desktop) dan web (dart:html, dipakai Chrome/browser lain). Barrel
/// file ini yang dipakai pemanggil (`AdministrasiPage`) supaya kode
/// UI-nya TIDAK perlu tahu/peduli platform apa yang sedang jalan --
/// Dart compiler otomatis pilih implementasi yang benar lewat
/// conditional import di bawah.
///
/// **Konteks (10 Oktober 2026)**: dibuat KHUSUS untuk menu
/// "Administrasi" > "Unduh Semua Foto Barang Sampai" -- permintaan user
/// eksplisit: "admin tidak pakai HP tetapi laptop dengan chrome", jadi
/// TIDAK BISA pakai pola `dart:io` + `share_plus` (share sheet native)
/// yang sebelumnya dipakai di percobaan pertama -- `dart:io`
/// (`File`/`Directory`/`HttpClient`) TIDAK berfungsi di Flutter Web
/// (lempar `UnsupportedError` saat runtime, walau tetap bisa
/// di-`import` tanpa error kompilasi karena Flutter Web punya shim
/// `dart:io` terbatas). Default-nya implementasi `io` (dart.library.io
/// SELALU "ada" termasuk di web lewat shim itu, jadi TIDAK bisa dipakai
/// sebagai penentu) -- override ke implementasi `web` HANYA kalau
/// `dart.library.html` tersedia (cuma benar-benar true di web).
export 'file_downloader_io.dart'
    if (dart.library.html) 'file_downloader_web.dart';
