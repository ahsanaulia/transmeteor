-- ============================================================
-- Perbaikan arsitektur: hilangkan ambiguitas "Penerima" (input manual)
-- vs "Tujuan" (tabel destinations) -- 22 September 2026
-- ============================================================
--
-- Latar belakang: sebelumnya form "Terima Barang" punya 2 konsep yang
-- tumpang tindih -- field "Nama Penerima"/"No. HP" yang diketik manual
-- (receiver_name/receiver_phone), DAN field "Tujuan" yang dipilih dari
-- tabel `destinations`. Ini ambigu: staff bisa mengetik nama penerima
-- yang berbeda dari nama tujuan yang dipilih, padahal keduanya
-- menggambarkan hal yang sama (siapa/kemana barang ini dikirim).
--
-- Keputusan: field manual "Nama Penerima"/"No. HP" DIHAPUS dari layar
-- input. Mulai sekarang, identitas "penerima" SEPENUHNYA diwakili oleh
-- data Tujuan (nama tujuan = `destination`, nomor HP tujuan = kolom baru
-- `destination_phone` di bawah, snapshot dari `destinations.phone` saat
-- resi dibuat -- mengikuti pola yang SUDAH ADA untuk `destination` &
-- `destination_address`, snapshot bukan live-join).
--
-- Resi LAMA yang sudah py `receiver_name`/`receiver_phone` TIDAK diubah/
-- dihapus (tetap utuh sebagai data historis) -- kolomnya cuma berhenti
-- diisi & berhenti ditampilkan di laporan/cetakan mulai sekarang.

-- 1) receiver_name tidak lagi wajib diisi -- resi BARU akan menyimpan
--    NULL di kolom ini (field manualnya sudah dihapus dari form).
alter table public.receiving
  alter column receiver_name drop not null;

-- 2) Salinan nomor HP tujuan, diisi otomatis dari destinations.phone
--    pada saat resi dibuat (kalau staff memilih tujuan dari daftar yang
--    sudah py nomor HP). Nullable -- tujuan lama/baru yang belum py
--    nomor HP tetap NULL, tidak masalah.
alter table public.receiving
  add column if not exists destination_phone text null;

notify pgrst, 'reload schema';

-- ============================================================
-- CATATAN UNTUK USER
-- ============================================================
-- - Jalankan file ini SEKALI di Supabase SQL Editor.
-- - TIDAK ADA data yang dihapus/diubah -- resi lama tetap utuh apa
--   adanya, cuma resi BARU yang mulai berperilaku beda (receiver_name
--   selalu NULL, destination_phone terisi otomatis dari tujuan yang
--   dipilih).
-- - Kolom receiver_name & receiver_phone SENGAJA TIDAK dihapus dari
--   skema (cuma berhenti dipakai) -- supaya data historis & laporan
--   lama yang mungkin masih merujuk ke kolom ini tidak rusak.
