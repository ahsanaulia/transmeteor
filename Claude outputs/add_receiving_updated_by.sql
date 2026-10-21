-- Dashboard Supervisor (16 Oktober 2026) -- field "Jika diedit kapan
-- diperbarui datanya dan oleh siapa" butuh tahu SIAPA yang mengedit resi
-- (updated_at saja sudah ada sejak awal, tapi tidak ada "siapa").
--
-- Jalankan sekali di Supabase SQL Editor.

ALTER TABLE public.receiving
  ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES public.employees(id);

-- Resi lama otomatis NULL (belum pernah di-"Edit Resi") -- sesuai desain,
-- dashboard Supervisor menampilkan "Belum pernah diedit" untuk baris
-- NULL, bukan dianggap error.
