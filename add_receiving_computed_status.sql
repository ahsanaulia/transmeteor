-- ============================================================
-- KOLOM `receiving.computed_status` + TRIGGER OTOMATIS
-- ============================================================
-- FITUR (16 Oktober 2026 -- laporan user: "Saat semua resi diload ...
-- seharusnya kan kita tidak mengambil sekaligus?"): Monitoring Resi
-- (Supervisor) SEBELUMNYA menghitung status (Penerimaan/Masih
-- Perjalanan/Selesai) di Dart, dari SELURUH baris `shipment_scans`
-- yang diambil sekaligus ke memori HP -- tidak bisa dipakai utk
-- filter/pencarian SERVER-SIDE + pagination sungguhan, karena status
-- bukan kolom di database sama sekali.
--
-- Migrasi ini memindahkan PERHITUNGAN status ke database lewat kolom
-- BARU `computed_status`, dijaga tetap akurat otomatis oleh trigger
-- (pola SAMA dengan `receiving_totals_trigger.sql` yang sudah ada utk
-- `total_quantity`/`total_price`) -- supaya aplikasi Flutter bisa query
-- `WHERE computed_status = '...'` + `.range()` langsung ke Supabase,
-- TANPA perlu ambil semua resi & semua shipment_scans ke memori lagi.
--
-- PENTING: kolom `receiving.status` yang SUDAH ADA SEBELUMNYA adalah
-- kolom LAIN (isinya SELALU 'RECEIVED', tidak pernah diubah, dipakai di
-- beberapa layar Admin lain seperti label netral) -- TIDAK disentuh
-- sama sekali oleh migrasi ini. `computed_status` adalah kolom BARU,
-- terpisah total, isinya 'PENERIMAAN' / 'MASIH_PERJALANAN' / 'SELESAI'
-- (logika SAMA PERSIS dengan `_resiStatus()` di
-- `supervisor_resi_tab.dart`).
--
-- Jalankan file ini SEKALI di Supabase SQL Editor (Database > SQL
-- Editor), urutan dari atas ke bawah (sudah idempotent, aman dijalankan
-- ulang kalau perlu).
-- ============================================================

-- 1) Kolom baru + constraint nilai yang valid.
alter table receiving
  add column if not exists computed_status text not null default 'PENERIMAAN';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'receiving_computed_status_check'
  ) then
    alter table receiving
      add constraint receiving_computed_status_check
      check (computed_status in ('PENERIMAAN', 'MASIH_PERJALANAN', 'SELESAI'));
  end if;
end $$;

-- 2) Function yang menghitung ULANG status 1 resi, dipanggil dari 2
--    trigger di bawah (SAMA formula dengan `_resiStatus()` Dart):
--      - total_quantity <= 0                        -> SELESAI (barang
--        semua sudah dihapus, lihat BUGFIX 16 Oktober 2026 sebelumnya).
--      - loaded (baris shipment_scans scan_type LOAD) <= 0 -> PENERIMAAN
--      - delivered >= total_quantity                 -> SELESAI
--      - selain itu                                   -> MASIH_PERJALANAN
create or replace function recalculate_receiving_status(p_receiving_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_quantity numeric;
  v_loaded int;
  v_delivered int;
  v_status text;
begin
  select total_quantity into v_total_quantity
  from receiving
  where id = p_receiving_id;

  -- Resi sudah tidak ada (dihapus) -- tidak ada yang perlu diupdate.
  if v_total_quantity is null then
    return;
  end if;

  select
    count(*) filter (where ss.scan_type = 'LOAD'),
    count(*) filter (where ss.scan_type = 'DELIVER')
  into v_loaded, v_delivered
  from shipment_scans ss
  join receiving_details rd on rd.id = ss.receiving_detail_id
  where rd.receiving_id = p_receiving_id
    and ss.scan_type in ('LOAD', 'DELIVER');

  if v_total_quantity <= 0 then
    v_status := 'SELESAI';
  elsif coalesce(v_loaded, 0) <= 0 then
    v_status := 'PENERIMAAN';
  elsif coalesce(v_delivered, 0) >= v_total_quantity then
    v_status := 'SELESAI';
  else
    v_status := 'MASIH_PERJALANAN';
  end if;

  update receiving
  set computed_status = v_status
  where id = p_receiving_id
    and computed_status is distinct from v_status;
end;
$$;

-- 3) Trigger #1 -- saat barang (`receiving_details`) ditambah/diubah/
--    dihapus, SAMA PERSIS momen `receiving_totals_trigger.sql` (total
--    quantity) jalan, status ikut dihitung ulang di momen yang sama
--    (resi bisa langsung "Selesai" begitu barang terakhirnya dihapus).
create or replace function recalculate_receiving_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receiving_id uuid;
  v_total_quantity numeric;
  v_total_price numeric;
begin
  if tg_op = 'DELETE' then
    v_receiving_id := old.receiving_id;
  else
    v_receiving_id := new.receiving_id;
  end if;

  select
    coalesce(sum(quantity), 0),
    coalesce(sum(total_price), 0)
  into v_total_quantity, v_total_price
  from receiving_details
  where receiving_id = v_receiving_id;

  update receiving
  set
    total_quantity = v_total_quantity::int,
    total_price = v_total_price,
    updated_at = now()
  where id = v_receiving_id;

  perform recalculate_receiving_status(v_receiving_id);

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_receiving_details_recalculate on receiving_details;

create trigger trg_receiving_details_recalculate
after insert or update or delete on receiving_details
for each row
execute function recalculate_receiving_totals();

-- 4) Trigger #2 -- BARU, saat scan LOAD/DELIVER dicatat/dihapus di
--    `shipment_scans` (resi pindah dari Penerimaan -> Masih Perjalanan
--    -> Selesai lewat sini).
create or replace function recalculate_receiving_status_from_scan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receiving_id uuid;
  v_detail_id uuid;
begin
  if tg_op = 'DELETE' then
    v_detail_id := old.receiving_detail_id;
  else
    v_detail_id := new.receiving_detail_id;
  end if;

  select receiving_id into v_receiving_id
  from receiving_details
  where id = v_detail_id;

  if v_receiving_id is not null then
    perform recalculate_receiving_status(v_receiving_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_shipment_scans_recalculate_status on shipment_scans;

create trigger trg_shipment_scans_recalculate_status
after insert or update or delete on shipment_scans
for each row
execute function recalculate_receiving_status_from_scan();

-- 5) Index -- dipakai query filter status & urutan terbaru/terlama dari
--    Flutter (`ReceivingService.getReceivingsPage`), supaya tetap cepat
--    walau tabel `receiving` sudah besar.
create index if not exists idx_receiving_computed_status
  on receiving (computed_status);

create index if not exists idx_receiving_created_at_id
  on receiving (created_at desc, id desc);

-- 6) BACKFILL -- hitung status SEMUA resi yang SUDAH ADA (sebelum
--    trigger di atas aktif). WAJIB dijalankan 1x supaya resi lama tidak
--    nyangkut di default 'PENERIMAAN'. Aman dijalankan ulang kapan pun
--    kalau ragu datanya belum konsisten (idempotent).
do $$
declare
  r record;
begin
  for r in select id from receiving loop
    perform recalculate_receiving_status(r.id);
  end loop;
end $$;

-- ============================================================
-- CATATAN
-- ============================================================
-- 1. `security definer` dipakai supaya function & trigger bisa meng-
--    update tabel `receiving` walaupun RLS policy user yang login tidak
--    mengizinkan UPDATE langsung ke tabel tersebut -- SAMA alasan
--    dengan `receiving_totals_trigger.sql`.
-- 2. Setelah migrasi ini jalan, kolom `computed_status` SELALU dijaga
--    otomatis oleh database -- aplikasi Flutter TIDAK PERNAH menulis
--    kolom ini secara langsung (hanya membaca), supaya tidak ada 2
--    sumber kebenaran yang bisa beda.
-- 3. Backfill (langkah #6) jalan per-baris (loop biasa, BUKAN batch) --
--    untuk ~1000 resi saat ini prosesnya cepat (hitungan detik). Kalau
--    nanti dijalankan lagi saat data sudah jauh lebih besar (puluhan
--    ribu+), wajar kalau makan waktu lebih lama (puluhan detik/beberapa
--    menit) -- itu normal, biarkan sampai selesai, cukup dijalankan
--    SEKALI saja (trigger yang menjaga konsistensi seterusnya).
