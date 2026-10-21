-- ============================================================
-- KOLOM `receiving_details.flow_state` + `sisa_barang` + `selesai_barang`
-- ============================================================
-- GANTIKAN TOTAL versi SEBELUMNYA yang baru dikirim (JANGAN jalankan
-- versi lama kalau belum jalan -- kalau SUDAH terlanjur dijalankan, file
-- ini TETAP aman dijalankan lagi, semua langkah idempotent/pakai
-- `add column if not exists` & `create or replace`).
--
-- PERMINTAAN USER (17 Oktober 2026, setelah kasus RESI000311 & regresi
-- paginasi), didiktekan langsung:
--
--   "namanya kolom flow_state dan sisa_barang
--    Jika seseorang loading atau dan selesai loading ----- update kedua
--    kolom itu
--    Jika selesai jalan shipment ---- update kolom state"
--   "jadi jika diintervensi maka hanya mengupdate kolom tersebut."
--   "jika intervensi di Sopir, selesaikan. Maka selain shipment harus
--    ada di dibarang selesai"
--   "atau kita tambahkan state : 'loading sebagian' dan 'selesai
--    sebagian'" -- PENAMBAHAN: menutup kasus 1 barang berlabel
--    multi-unit yang fisiknya terpecah ke LEBIH DARI SATU shipment
--    (sebagian unit sudah "selesai" lewat shipment yang sudah kembali,
--    sebagian lagi masih di shipment lain yang belum kembali) -- tanpa
--    kolom tambahan ini, kasus itu akan salah ditandai SELESAI penuh
--    (prematur) ATAUPUN tidak pernah ditandai apa-apa.
--
-- 5 nilai `flow_state`: BELUM_DIMUAT -> LOADING_SEBAGIAN -> SUDAH_DIMUAT
-- -> SELESAI_SEBAGIAN -> SELESAI (selalu DIHITUNG ULANG dari
-- `sisa_barang`+`selesai_barang`+total unit fisik setiap kali salah
-- satu dari keduanya berubah -- lihat function di bawah -- BUKAN
-- ditulis bebas dari Dart).
--
-- SENGAJA BERBEDA dari `receiving.computed_status`
-- (`add_receiving_computed_status.sql`, TETAP dibiarkan apa adanya,
-- level RESI, trigger live dari `shipment_scans`, tidak dikomplain
-- user): kolom di sini level BARANG (1 baris `receiving_details`),
-- SENGAJA ditulis LANGSUNG oleh Flutter (`shipment_service.dart`) di 4
-- titik aksi spesifik, BUKAN dihitung ulang live dari `shipment_scans`
-- tiap kali dibaca:
--   1. Loading manual/QR (sebagian ATAUPUN selesai) -> RPC
--      `dec_sisa_barang_on_load` (`recordScan` scan_type LOAD).
--   2. Pembatalan loading -> RPC `inc_sisa_barang_on_cancel`
--      (`cancelManualLoad`, kebalikan poin 1).
--   3. Shipment selesai jalan (sopir "Sudah Kembali ke Kantor" ATAUPUN
--      dipaksa Admin di halaman Sopir) -> RPC `mark_selesai_for_shipment`
--      (`returnToOffice` & `forceCompleteByAdmin`) -- menambah
--      `selesai_barang` SEBANYAK unit fisik baris ini yang memang
--      ter-LOAD ke SHIPMENT INI SAJA (bukan вsemua unit baris ini
--      sekaligus) -- itulah yang membuat status "sebagian" akurat kalau
--      baris yang sama terpecah ke beberapa shipment berbeda.
--   4. Intervensi Admin "Selesaikan Resi" (Monitoring Resi) -> update
--      LANGSUNG `sisa_barang=0`, `selesai_barang=total`,
--      `flow_state='SELESAI'` dari Dart, TIDAK PERNAH lagi menyentuh
--      `shipment_scans` (`forceCompleteReceivingByAdmin`).
--
-- Jalankan file ini SEKALI di Supabase SQL Editor, urutan atas ke bawah.
-- ============================================================

-- 1) Kolom -- NULLABLE dulu tanpa default kolom (trigger di bawah yang
--    isi nilai awal baris BARU; `null` = "belum diisi", beda dari
--    "memang 0").
alter table receiving_details add column if not exists flow_state text;
alter table receiving_details add column if not exists sisa_barang integer;
alter table receiving_details add column if not exists selesai_barang integer;

do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'receiving_details_flow_state_check'
  ) then
    alter table receiving_details drop constraint receiving_details_flow_state_check;
  end if;

  alter table receiving_details
    add constraint receiving_details_flow_state_check
    check (flow_state in (
      'BELUM_DIMUAT', 'LOADING_SEBAGIAN', 'SUDAH_DIMUAT',
      'SELESAI_SEBAGIAN', 'SELESAI'
    ));
end $$;

-- 2) Helper -- total unit fisik 1 baris (formula SAMA PERSIS
--    `ShipmentService._physicalUnitCodes` di Dart, JANGAN pernah
--    berbeda dari situ).
create or replace function receiving_detail_total_unit(
  p_is_unlabeled boolean, p_quantity numeric
) returns int language sql immutable as $$
  select case
    when p_is_unlabeled then 1
    else greatest(1, least(999, round(p_quantity)::int))
  end;
$$;

-- 3) Helper -- tentukan `flow_state` dari (`sisa_barang`,
--    `selesai_barang`, total) -- SATU tempat dipakai semua function di
--    bawah supaya logikanya tidak pernah bercabang beda-beda.
create or replace function receiving_detail_flow_state(
  p_total int, p_sisa int, p_selesai int
) returns text language sql immutable as $$
  select case
    when p_total <= 0 then 'BELUM_DIMUAT'
    when p_selesai >= p_total then 'SELESAI'
    when p_selesai > 0 then 'SELESAI_SEBAGIAN'
    when p_sisa <= 0 then 'SUDAH_DIMUAT'
    when p_sisa < p_total then 'LOADING_SEBAGIAN'
    else 'BELUM_DIMUAT'
  end;
$$;

-- 4) Trigger BEFORE INSERT -- isi nilai AWAL baris BARU (resi baru
--    ATAUPUN baris hasil split
--    `ReceivingService.splitReceivingDetailForPartialLoad`) kalau Dart
--    tidak mengisi eksplisit.
create or replace function trg_receiving_details_set_flow_defaults()
returns trigger language plpgsql as $$
declare
  v_total int;
begin
  v_total := receiving_detail_total_unit(new.is_unlabeled, new.quantity);

  if new.sisa_barang is null then
    new.sisa_barang := v_total;
  end if;
  if new.selesai_barang is null then
    new.selesai_barang := 0;
  end if;
  if new.flow_state is null then
    new.flow_state := receiving_detail_flow_state(v_total, new.sisa_barang, new.selesai_barang);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_receiving_details_flow_defaults on receiving_details;

create trigger trg_receiving_details_flow_defaults
before insert on receiving_details
for each row
execute function trg_receiving_details_set_flow_defaults();

-- 5) RPC -- aksi #1 (loading, 1 unit per panggilan, SAMA granularitas
--    dengan `recordScan` yang dipanggil 1x per unit_code): kurangi
--    `sisa_barang` 1, hitung ulang `flow_state`.
create or replace function dec_sisa_barang_on_load(p_detail_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_total int; v_sisa int; v_selesai int;
begin
  select
    receiving_detail_total_unit(is_unlabeled, quantity),
    greatest(0, coalesce(sisa_barang, 0) - 1),
    coalesce(selesai_barang, 0)
  into v_total, v_sisa, v_selesai
  from receiving_details where id = p_detail_id;

  update receiving_details
  set
    sisa_barang = v_sisa,
    flow_state = receiving_detail_flow_state(v_total, v_sisa, v_selesai),
    updated_at = now()
  where id = p_detail_id;
end;
$$;

-- 6) RPC -- aksi #2 (pembatalan loading, kebalikan #1): kembalikan
--    `sisa_barang` sebanyak unit yang dibatalkan, hitung ulang
--    `flow_state`.
create or replace function inc_sisa_barang_on_cancel(p_detail_id uuid, p_count int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_total int; v_sisa int; v_selesai int;
begin
  select
    receiving_detail_total_unit(is_unlabeled, quantity),
    coalesce(sisa_barang, 0) + p_count,
    coalesce(selesai_barang, 0)
  into v_total, v_sisa, v_selesai
  from receiving_details where id = p_detail_id;

  update receiving_details
  set
    sisa_barang = v_sisa,
    flow_state = receiving_detail_flow_state(v_total, v_sisa, v_selesai),
    updated_at = now()
  where id = p_detail_id;
end;
$$;

-- 7) RPC -- aksi #3 (shipment selesai jalan, sopir ATAUPUN dipaksa
--    Admin): untuk SEMUA baris `receiving_details` yang punya scan LOAD
--    di shipment [p_shipment_id], tambah `selesai_barang` SEBANYAK unit
--    fisik baris itu yang ter-LOAD ke SHIPMENT INI SAJA (bukan semua
--    unit baris itu) -- kalau baris yang sama juga punya unit lain di
--    shipment LAIN yang belum selesai jalan, hasilnya otomatis
--    `SELESAI_SEBAGIAN` (bukan langsung `SELESAI` penuh, bukan juga
--    `BELUM_DIMUAT`/diam saja, yang berarti tidak semua unit baris itu
--    langsung dianggap tuntas sekaligus).
--
-- CATATAN IDEMPOTENT: dipanggil [ShipmentService] HANYA SEKALI per
-- shipment (dijaga di sisi Dart -- `returnToOffice`/`forceCompleteByAdmin`
-- cuma memanggil ini kalau status SEBELUM update BUKAN `ARRIVED`) --
-- JANGAN panggil manual berulang untuk shipment yang SAMA, karena
-- function ini tidak bisa membedakan "shipment ini sudah pernah
-- dihitung selesai sebelumnya" -- memanggil 2x untuk shipment yang sama
-- akan menghitung ganda `selesai_barang`.
create or replace function mark_selesai_for_shipment(p_shipment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_total int; v_sisa int; v_selesai int;
begin
  for r in
    select receiving_detail_id, count(*) as cnt
    from shipment_scans
    where shipment_id = p_shipment_id and scan_type = 'LOAD'
    group by receiving_detail_id
  loop
    select
      receiving_detail_total_unit(is_unlabeled, quantity),
      coalesce(sisa_barang, 0),
      least(
        receiving_detail_total_unit(is_unlabeled, quantity),
        coalesce(selesai_barang, 0) + r.cnt
      )
    into v_total, v_sisa, v_selesai
    from receiving_details where id = r.receiving_detail_id;

    update receiving_details
    set
      selesai_barang = v_selesai,
      flow_state = receiving_detail_flow_state(v_total, v_sisa, v_selesai),
      updated_at = now()
    where id = r.receiving_detail_id;
  end loop;
end;
$$;

-- 8) Index -- dipakai filter `WHERE sisa_barang > 0` di
--    `ShipmentService.getAvailableItemsForManualLoad`.
create index if not exists idx_receiving_details_sisa_barang
  on receiving_details (sisa_barang)
  where sisa_barang > 0;

-- 9) BACKFILL -- hitung `flow_state`/`sisa_barang`/`selesai_barang`
--    SEMUA baris LAMA dari riwayat `shipment_scans` yang sudah ada
--    sekarang (`selesai_barang` dari jumlah scan DELIVER, karena
--    historisnya belum ada konsep "per-shipment" seperti RPC #7 di
--    atas -- buat data LAMA ini wajar/cukup akurat). WAJIB dijalankan
--    1x. Aman idempotent -- TAPI JANGAN dijalankan lagi setelah Flutter
--    mulai menulis kolom ini sendiri (akan menimpa hasil intervensi
--    Admin "Selesaikan Resi" yang sejak redesain ini TIDAK membuat baris
--    `shipment_scans` baru).
do $$
begin
  with scan_counts as (
    select
      rd.id as detail_id,
      receiving_detail_total_unit(rd.is_unlabeled, rd.quantity) as total_unit,
      count(*) filter (where ss.scan_type = 'LOAD') as loaded,
      count(*) filter (where ss.scan_type = 'DELIVER') as delivered
    from receiving_details rd
    left join shipment_scans ss
      on ss.receiving_detail_id = rd.id
      and ss.scan_type in ('LOAD', 'DELIVER')
    group by rd.id, rd.is_unlabeled, rd.quantity
  )
  update receiving_details rd
  set
    sisa_barang = greatest(0, sc.total_unit - sc.loaded),
    selesai_barang = least(sc.total_unit, sc.delivered),
    -- CATATAN BUGFIX: `count(*) filter (...)` di CTE atas menghasilkan
    -- `bigint` (`sc.loaded`/`sc.delivered`), jadi `sc.total_unit -
    -- sc.loaded` dkk juga `bigint` -- `receiving_detail_flow_state`
    -- dideklarasikan menerima `int`, dan resolusi argumen fungsi SQL
    -- (beda dari assignment ke variabel plpgsql/kolom tabel) TIDAK
    -- otomatis mempersempit `bigint` ke `int`, jadi WAJIB `::int`
    -- eksplisit di sini (lihat error "function
    -- receiving_detail_flow_state(integer, bigint, bigint) does not
    -- exist" kalau cast ini dihapus).
    flow_state = receiving_detail_flow_state(
      sc.total_unit::int,
      greatest(0, sc.total_unit - sc.loaded)::int,
      least(sc.total_unit, sc.delivered)::int
    ),
    updated_at = now()
  from scan_counts sc
  where sc.detail_id = rd.id;
end $$;

-- 10) Verifikasi -- ringkasan jumlah baris per flow_state.
select flow_state, count(*) as jumlah_baris,
  sum(sisa_barang) as total_sisa_barang,
  sum(selesai_barang) as total_selesai_barang
from receiving_details
group by flow_state
order by flow_state;
