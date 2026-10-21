-- ============================================================
-- FITUR (21 Oktober 2026 -- Section A, "Label Barcode") -- pilihan ke-3
-- yang SALING EKSKLUSIF dengan "Pakai Label QR"/"Tanpa Label QR".
-- Desain SUDAH dikonfirmasi lengkap lewat AskUserQuestion & instruksi
-- eksplisit user sepanjang sesi 17-21 Oktober 2026 -- lihat Section A di
-- `arsitektur-tambahan` (Claude Project) untuk latar belakang lengkap.
-- ============================================================
--
-- Jalankan file ini SEKALI di Supabase SQL Editor. Aman dijalankan
-- berkali-kali (semua statement idempotent lewat IF NOT EXISTS/pengecekan
-- kolom, KECUALI blok migrasi `is_unlabeled` -> `label_type` di bawah yang
-- punya guard tersendiri supaya tidak dobel-jalan).

-- ------------------------------------------------------------
-- 1. Kolom `label_type` di `receiving_details` -- MENGGANTIKAN
--    `is_unlabeled` sebagai sumber kebenaran, TAPI `is_unlabeled`
--    DIPERTAHANKAN sebagai GENERATED COLUMN (bukan dihapus) supaya
--    SELURUH query/trigger/kode lama yang masih membaca `is_unlabeled`
--    (ada puluhan tempat di app Flutter) TETAP JALAN tanpa perlu diubah
--    satu-satu -- cuma SUMBER NILAInya yang berubah (dulu ditulis
--    langsung, sekarang diturunkan otomatis dari `label_type`).
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'receiving_details'
      and column_name = 'label_type'
  ) then
    -- Kolom sementara dulu (belum generated) supaya bisa dibackfill dari
    -- `is_unlabeled` yang masih ada.
    alter table public.receiving_details add column label_type text;

    update public.receiving_details
    set label_type = case when is_unlabeled then 'TANPA_LABEL' else 'QR' end;

    alter table public.receiving_details
      alter column label_type set default 'QR',
      alter column label_type set not null;

    alter table public.receiving_details
      add constraint receiving_details_label_type_check
      check (label_type in ('QR', 'TANPA_LABEL', 'BARCODE'));

    -- Ganti `is_unlabeled` jadi GENERATED COLUMN (turunan dari
    -- `label_type`, tidak bisa ditulis langsung lagi -- lihat
    -- `ReceivingService.createReceivingDetail`/`updateReceivingDetail`
    -- yang SEKARANG menulis `label_type`, bukan `is_unlabeled`).
    alter table public.receiving_details drop column is_unlabeled;
    alter table public.receiving_details
      add column is_unlabeled boolean
      generated always as (label_type = 'TANPA_LABEL') stored;
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. Tabel `daftar_label_barcode` -- stok blanko kode barcode (pool),
--    di-generate admin LEBIH DULU (menu "Stok Label Barcode") sebelum
--    ditempel & diikat ke barang (menu "Scan Label").
-- ------------------------------------------------------------
create table if not exists public.daftar_label_barcode (
  id uuid primary key default gen_random_uuid(),
  -- Internal, TIDAK PERNAH dicetak/di-scan -- cuma dipakai admin untuk
  -- "cetak ulang dari nomor urut sekian sampai sekian" (reprint range).
  sequence_no bigint generated always as identity,
  -- Nilai ACAK (12 digit angka) yang BENAR-BENAR dicetak & discan --
  -- SENGAJA tidak berurutan (permintaan user: "agar tidak mudah
  -- dimanipulasi").
  barcode_code text not null unique,
  status text not null default 'BELUM_DIPAKAI'
    check (status in ('BELUM_DIPAKAI', 'TERPAKAI')),
  -- Diisi SAAT "diikat" lewat menu "Scan Label" (BUKAN saat generate).
  no_resi text,
  kode_barang text,
  receiving_detail_id uuid references public.receiving_details(id) on delete set null,
  assigned_at timestamptz,
  assigned_by uuid references public.employees(id),
  created_at timestamptz not null default now(),
  created_by uuid references public.employees(id)
);

create index if not exists idx_daftar_label_barcode_detail
  on public.daftar_label_barcode (receiving_detail_id);

create index if not exists idx_daftar_label_barcode_status
  on public.daftar_label_barcode (status);

-- Daftarkan ke publication realtime -- mengikuti pola
-- `add_representatives_table.sql` -- supaya menu "Stok Label Barcode"
-- (jumlah BELUM_DIPAKAI/TERPAKAI) & "Scan Label" ikut realtime tanpa
-- refresh manual kalau staff lain generate/pakai stok di waktu yang
-- hampir bersamaan.
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.daftar_label_barcode;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

notify pgrst, 'reload schema';

-- ============================================================
-- CATATAN UNTUK USER
-- ============================================================
-- - TIDAK ada RLS yang diaktifkan di sini -- mengikuti pola tabel lain di
--   app ini.
-- - `kode_barang` BOLEH dobel di beberapa baris (beda filosofi dari skema
--   QR yang pakai `unit_index` per barang) -- pool kode acak, bukan deret
--   deterministik per barang, sesuai keputusan user.
-- - Setelah migrasi ini, field `isUnlabeled`/`is_unlabeled` di SELURUH
--   kode Flutter TETAP BERFUNGSI SAMA PERSIS seperti sebelumnya (dibaca
--   dari generated column) -- TIDAK ADA perubahan perilaku untuk barang
--   QR/Tanpa Label yang sudah ada. Yang baru hanya opsi ke-3 "BARCODE".
