-- Tambah kolom bundle_quantity ke receiving_details, untuk fitur
-- "qty bulk" (mis. "4 ikat isi 5") supaya label yang dicetak lebih
-- sedikit -- 1 label per bundle, bukan 1 label per barang fisik.
--
-- null / kosong = TIDAK bundle (perilaku lama, tidak berubah).
ALTER TABLE receiving_details
  ADD COLUMN IF NOT EXISTS bundle_quantity integer;

NOTIFY pgrst, 'reload schema';
