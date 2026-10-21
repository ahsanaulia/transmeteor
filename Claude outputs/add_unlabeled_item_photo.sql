-- Tambah kolom untuk fitur "Opsi Kiriman Tanpa Label QR" -- untuk barang
-- yang benar-benar tidak bisa dilabeli (mis. bata ringan curah 10 kubik,
-- pasir, barang curah lain tanpa kemasan/permukaan untuk ditempel stiker
-- label). Item dengan is_unlabeled = true TIDAK digenerate label QR sama
-- sekali -- cukup 1 foto barang sebagai bukti, disimpan di photo_url.
--
-- false (default) = perilaku lama, tidak berubah (barang tetap dilabeli
-- & discan per unit seperti biasa).
ALTER TABLE receiving_details
  ADD COLUMN IF NOT EXISTS is_unlabeled boolean NOT NULL DEFAULT false;

ALTER TABLE receiving_details
  ADD COLUMN IF NOT EXISTS photo_url text;

NOTIFY pgrst, 'reload schema';
