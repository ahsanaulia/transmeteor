-- Tambah kolom interval kirim lokasi GPS ke tabel `company`, supaya bisa
-- diatur dari aplikasi (halaman "Profil Perusahaan") tanpa perlu ubah kode
-- & build ulang tiap kali mau uji coba.
--
-- Kenapa dibutuhkan: interval kirim lokasi (GpsForegroundService) tadinya
-- di-hardcode 15 menit (900 detik) di kode Flutter. Untuk uji coba lapangan
-- itu kelamaan (harus nunggu 15 menit tiap kali mau lihat apakah titik
-- lokasi baru masuk). Sekarang admin bisa ganti sendiri lewat halaman
-- Profil Perusahaan -- isi kecil (mis. 10 detik) untuk uji coba, lalu
-- balikin ke 900 (15 menit) untuk pemakaian produksi sehari-hari supaya
-- baterai HP sopir & kuota data tidak boros.

ALTER TABLE "public"."company"
  ADD COLUMN IF NOT EXISTS "gps_ping_interval_seconds" integer NOT NULL DEFAULT 900;

ALTER TABLE "public"."company"
  ADD CONSTRAINT "company_gps_ping_interval_seconds_positive"
  CHECK ("gps_ping_interval_seconds" > 0);
