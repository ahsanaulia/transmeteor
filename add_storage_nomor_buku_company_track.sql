-- Migrasi gabungan untuk 3 fitur baru (8 Oktober 2026, permintaan user):
--   1. Tabel baru "storages" (Zona Storage) -- master data lokasi
--      penyimpanan barang di gudang.
--   2. Kolom baru receiving.nomor_buku (opsional) -- nomor buku fisik
--      pencatatan resi (beda dari nomor resi digital).
--   3. Kolom baru receiving_details.storage_id -- zona TEMPAT barang itu
--      diletakkan di gudang, dipakai staff Loading supaya tahu di zona
--      mana harus mengambil barangnya.
--   4. Kolom baru company.company_track -- link/host publik halaman
--      "Telusuri Kiriman" SAAT INI, supaya admin bisa ganti kapan saja
--      (misal domain Netlify berubah) TANPA build ulang app.
--
-- Semua statement idempotent (aman dijalankan berkali-kali).

-- ============================================================
-- 1. Tabel "storages" (Zona Storage)
-- ============================================================
-- Struktur SAMA PERSIS pola `representatives`/`destinations` (CRUD admin
-- sederhana: nama + deskripsi + aktif/nonaktif), TANPA lat/long -- user
-- cuma minta "id, nama_zona, deskripsi".
create table if not exists public.storages (
  id uuid primary key default gen_random_uuid(),
  nama_zona text not null,
  deskripsi text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 2. receiving.nomor_buku
-- ============================================================
-- Nomor buku fisik pencatatan resi (dicatat manual di buku kertas
-- sebelum/bersamaan dengan input digital) -- OPSIONAL, banyak resi tidak
-- punya ini (resi lama, atau alur yang tidak pakai buku fisik).
alter table public.receiving
  add column if not exists nomor_buku text;

-- ============================================================
-- 3. receiving_details.storage_id
-- ============================================================
-- Zona TEMPAT barang (per baris detail, BUKAN per resi -- 1 resi bisa
-- berisi barang yang diletakkan di zona berbeda-beda) diletakkan di
-- gudang. Nullable -- barang lama/barang yang belum ditentukan zonanya
-- tetap sah, cuma tidak tampil info zona di checklist Loading.
alter table public.receiving_details
  add column if not exists storage_id uuid
  references public.storages (id)
  on delete set null;

-- ============================================================
-- 4. company.company_track
-- ============================================================
alter table public.company
  add column if not exists company_track text;

-- ============================================================
-- Realtime -- supaya CRUD Zona Storage & perubahan nomor_buku/zona
-- langsung tersebar tanpa refresh manual, konsisten dengan tabel master
-- lain (lihat RealtimeSyncService).
-- ============================================================
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.storages;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

notify pgrst, 'reload schema';

-- ============================================================
-- CATATAN UNTUK USER
-- ============================================================
-- - Jalankan file ini SEKALI di Supabase SQL Editor.
-- - TIDAK ada RLS yang diaktifkan di `storages` -- mengikuti pola tabel
--   master lain di app ini (destinations, representatives, senders,
--   dst), supaya tidak ada gate tambahan yang memblokir operasional.
-- - Setelah ini jalan, WAJIB `flutter pub get` TIDAK diperlukan (tidak
--   ada dependency baru) -- cukup rebuild/hot-reload setelah kode Flutter
--   dikirim.
