-- ============================================================
-- MIGRASI (21 Oktober 2026): kolom `vehicles.is_loading` + status
-- "SEDANG_DIMUAT" di Monitoring Resi + perbaikan gap "Selesaikan Resi"
-- tidak pernah otomatis jadi SELESAI.
-- ============================================================
-- Permintaan user:
-- 1. "sebaiknya tambahkan kolom is_loading. Artinya: admin saat
--    menyiapkan kendaraan sekaligus is_loading jadi true. Jika admin
--    berangkatkan kendaraan is_loading jadi false."
-- 2. Monitoring Resi (Admin+Supervisor): tambah status "Sedang Dimuat"
--    (konsisten dengan wording Monitoring Kendaraan dan Sopir),
--    ditentukan dari `vehicles.is_loading` kendaraan yang memuat resi
--    itu (BUKAN dari `shipments.status` langsung -- lebih sederhana &
--    sesuai permintaan user di atas).
-- 3. Perbaikan gap: resi yang diselesaikan lewat "Selesaikan Resi"
--    (`forceCompleteReceivingByAdmin`, redesain Tambahan #51) tidak
--    pernah membuat baris `shipment_scans`, jadi `computed_status`
--    nyangkut selamanya di Penerimaan/Masih Perjalanan -- sekarang resi
--    JUGA dianggap SELESAI kalau SEMUA baris `receiving_details`-nya
--    sudah `flow_state = 'SELESAI'`.
--
-- Jalankan SEKALI di Supabase SQL Editor, urutan dari atas ke bawah.
-- Idempotent -- aman dijalankan ulang.
-- ============================================================

-- 1) Kolom baru `vehicles.is_loading`.
alter table vehicles
  add column if not exists is_loading boolean not null default false;

-- Backfill: kendaraan yang SEDANG aktif (is_active=true) & TIDAK punya
-- shipment yang sudah DEPARTED/ARRIVED dianggap masih "Sedang Dimuat"
-- (belum diberangkatkan) -- selaras dengan 2 titik aksi yang akan
-- menjaga kolom ini ke depan (`prepareVehicle`/"Berangkatkan Kendaraan").
update vehicles v
set is_loading = true
where v.is_active = true
  and not exists (
    select 1 from shipments s
    where s.vehicle_id = v.id
      and s.status in ('DEPARTED', 'ARRIVED')
  );

-- 2) Perluas constraint `computed_status` -- tambah nilai baru
--    'SEDANG_DIMUAT' (di antara PENERIMAAN & MASIH_PERJALANAN).
alter table receiving drop constraint if exists receiving_computed_status_check;
alter table receiving
  add constraint receiving_computed_status_check
  check (computed_status in ('PENERIMAAN', 'SEDANG_DIMUAT', 'MASIH_PERJALANAN', 'SELESAI'));

-- 3) Function utama -- DIGANTI total, sekarang juga:
--    - cek flow_state semua barang (gap "Selesaikan Resi", poin 3 di atas)
--    - bedakan SEDANG_DIMUAT vs MASIH_PERJALANAN lewat `vehicles.is_loading`
--      kendaraan dari scan LOAD PALING AWAL resi ini (representative,
--      pola SAMA dengan `MonitoringService.getReceivingProgressSummary`
--      yang sudah ada di sisi Dart utk plat/sopir).
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
  v_all_flow_selesai boolean;
  v_vehicle_is_loading boolean;
begin
  select total_quantity into v_total_quantity
  from receiving
  where id = p_receiving_id;

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

  -- Poin 3: semua barang resi ini sudah flow_state SELESAI (mis. lewat
  -- "Selesaikan Resi") -> resi ini SELESAI juga, walau shipment_scans-nya
  -- kosong/tidak pernah nyentuh delivered>=total.
  select
    exists (select 1 from receiving_details where receiving_id = p_receiving_id)
    and not exists (
      select 1 from receiving_details
      where receiving_id = p_receiving_id and flow_state <> 'SELESAI'
    )
  into v_all_flow_selesai;

  if v_total_quantity <= 0 then
    v_status := 'SELESAI';
  elsif v_all_flow_selesai then
    v_status := 'SELESAI';
  elsif coalesce(v_loaded, 0) <= 0 then
    v_status := 'PENERIMAAN';
  elsif coalesce(v_delivered, 0) >= v_total_quantity then
    v_status := 'SELESAI';
  else
    -- loaded>0, belum semua selesai -- Sedang Dimuat vs Masih Perjalanan,
    -- ditentukan dari is_loading kendaraan pembawa (scan LOAD PALING AWAL).
    select v.is_loading into v_vehicle_is_loading
    from shipment_scans ss
    join receiving_details rd on rd.id = ss.receiving_detail_id
    join shipments s on s.id = ss.shipment_id
    join vehicles v on v.id = s.vehicle_id
    where rd.receiving_id = p_receiving_id
      and ss.scan_type = 'LOAD'
    order by ss.scanned_at asc
    limit 1;

    if coalesce(v_vehicle_is_loading, false) then
      v_status := 'SEDANG_DIMUAT';
    else
      v_status := 'MASIH_PERJALANAN';
    end if;
  end if;

  update receiving
  set computed_status = v_status
  where id = p_receiving_id
    and computed_status is distinct from v_status;
end;
$$;

-- 4) Trigger BARU -- saat `vehicles.is_loading` berubah (admin
--    berangkatkan kendaraan / siapkan ulang), resi yang kendaraan itu
--    muat perlu dihitung ulang (Sedang Dimuat <-> Masih Perjalanan).
create or replace function recalculate_receiving_status_from_vehicle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  if new.is_loading is distinct from old.is_loading then
    for r in
      select distinct rd.receiving_id
      from shipment_scans ss
      join receiving_details rd on rd.id = ss.receiving_detail_id
      join shipments s on s.id = ss.shipment_id
      where s.vehicle_id = new.id
        and ss.scan_type = 'LOAD'
    loop
      perform recalculate_receiving_status(r.receiving_id);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_vehicles_recalculate_receiving_status on vehicles;

create trigger trg_vehicles_recalculate_receiving_status
after update on vehicles
for each row
execute function recalculate_receiving_status_from_vehicle();

-- 5) BACKFILL -- hitung ulang status SEMUA resi dengan logic baru di
--    atas (wajib sekali, supaya resi yang kena gap poin 3 & yang
--    kendaraannya sekarang is_loading langsung ter-update).
do $$
declare
  r record;
begin
  for r in select id from receiving loop
    perform recalculate_receiving_status(r.id);
  end loop;
end $$;

-- 6) Verifikasi.
select computed_status, count(*) as jumlah_resi
from receiving
group by computed_status
order by computed_status;

-- ============================================================
-- CATATAN
-- ============================================================
-- 1. Kolom `vehicles.is_loading` DIJAGA dari sisi Flutter di 2 titik
--    (SAMA seperti permintaan user): `VehicleService.prepareVehicle`
--    (set true) dan "Berangkatkan Kendaraan" di `shipment_dispatch_page.dart`
--    + `ShipmentService.forceStartTripByAdmin` (set false) -- lihat
--    perubahan Dart terpisah. Trigger di poin 4 di atas HANYA
--    menghitung ulang status resi, TIDAK pernah mengubah is_loading itu
--    sendiri (searah, bukan 2 arah).
-- 2. `is_loading` SENGAJA terpisah dari `is_active` -- `is_active`
--    menjawab "boleh muncul di Pilih Kendaraan Loading?" (gate lama,
--    13 Oktober 2026), `is_loading` menjawab "kendaraan ini masih
--    loading atau sudah berangkat?" (BARU, 21 Oktober 2026). Kendaraan
--    "Dalam Perjalanan" TETAP is_active=true (sengaja, supaya staff bisa
--    lanjut tambah muatan) TAPI is_loading=false begitu diberangkatkan.
