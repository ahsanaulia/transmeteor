-- Tabel "Perwakilan" -- lokasi titipan barang kalau tujuan asli
-- tutup/tidak bisa dijangkau sopir (permintaan user eksplisit, 6 Oktober
-- 2026 lanjutan: "Ada kasus dimana barang tidak diselesaikan di tujuan...
-- sehingga driver/sopir menurunkan barang diperwakilan").
--
-- Struktur SAMA PERSIS pola `destinations` (name/phone/address/is_active)
-- TAPI TANPA latitude/longitude -- permintaan user cuma minta "menulis
-- nama perwakilan dan alamatnya", tidak minta titik peta seperti
-- Tujuan. Bisa ditambah lat/long belakangan kalau memang dibutuhkan,
-- tidak ada yang bergantung pada ketidakadaannya sekarang.
create table if not exists public.representatives (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Jejak "barang ini turun di PERWAKILAN mana" -- kolom baru di
-- `shipment_scans` (nullable, TIDAK mengubah/mewajibkan apa pun untuk
-- scan DELIVER biasa langsung ke tujuan asli -- kolom ini NULL untuk
-- semua scan lama & scan DELIVER normal baru).
--
-- KEPUTUSAN ARSITEKTUR: dibuat kolom FK terstruktur (bukan cuma dititipkan
-- di kolom `notes` yang sudah ada) supaya ke depan BISA direkap/dicari
-- "barang apa saja yang pernah dititip di perwakilan X" lewat query biasa
-- (join), bukan parsing teks notes. `notes` tetap SEKALIGUS diisi teks
-- deskriptif saat handoff (lihat `ShipmentService
-- .recordRepresentativeHandoffForReceiving`) sebagai jejak yang gampang
-- dibaca manusia di manifest/riwayat scan -- representative_id untuk query
-- terstruktur, notes untuk dibaca langsung.
alter table public.shipment_scans
  add column if not exists representative_id uuid
  references public.representatives (id)
  on delete set null;

-- Daftarkan ke publication realtime -- mengikuti pola
-- `enable_realtime_all_tables.sql` (lihat `RealtimeSyncService`), supaya
-- halaman admin "Daftar Perwakilan" & pencarian perwakilan di aplikasi
-- sopir ikut realtime tanpa perlu refresh manual begitu representatives
-- baru ditambahkan staff lain.
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.representatives;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

notify pgrst, 'reload schema';

-- ============================================================
-- CATATAN UNTUK USER
-- ============================================================
-- - Jalankan file ini SEKALI di Supabase SQL Editor (aman dijalankan
--   berkali-kali -- semua statement pakai IF NOT EXISTS / pengecekan
--   idempotent).
-- - TIDAK ada RLS yang diaktifkan di sini -- mengikuti pola tabel master
--   lain di app ini (destinations, senders, company, dst juga tidak
--   mengaktifkan RLS lewat migrasi terpisah), supaya tidak ada gate
--   tambahan yang bisa memblokir operasional.
