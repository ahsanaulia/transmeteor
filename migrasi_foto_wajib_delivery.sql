-- ============================================================
-- FITUR (21 Oktober 2026 -- Section E, permintaan user eksplisit, DIPERLUAS
-- dari permintaan awal "tampilkan foto sopir saat barang tiba di web Cek
-- Resi" jadi: "Semua resi/barang harus difoto saat turun -- ada label
-- tidak ada label di barang, termasuk apakah barcode.")
-- ============================================================
--
-- Flutter-side (tab "Label QR" di `DeliveryResiScanPage`) SUDAH diubah
-- terpisah (tidak butuh migrasi SQL untuk itu -- `shipment_scans.url_foto_selesai`
-- SUDAH nullable sejak 10 Oktober 2026, cukup diisi dari Dart). Migrasi
-- INI cuma untuk bagian baca-nya: RPC publik `track_shipment` (dipakai web
-- Cek Resi TANPA login & halaman Flutter `TrackShipmentPage`) ditambah 1
-- field baru `arrivalPhotoUrl` -- ambil foto DELIVER TERBARU (manapun
-- jalurnya: scan QR, checklist manual, atau nanti Scan Barcode) milik resi
-- ini yang `url_foto_selesai`-nya tidak null. Null kalau belum ada foto
-- SAMA SEKALI (kasus LANGKA setelah perubahan ini berlaku -- cuma
-- relevan untuk resi lama sebelum fitur ini, atau status belum "tiba").
--
-- SUMBER function ASLI diambil dari `add_track_shipment_rpc.sql` (8
-- Oktober 2026) -- `create or replace function` WAJIB isi ulang SELURUH
-- body, jadi file ini adalah salinan LENGKAP fungsi itu + 1 penambahan
-- (`v_arrival_photo_url` + field `arrivalPhotoUrl`), BUKAN cuma potongan
-- diff. Tidak ada bagian lain dari function ini yang diubah.
--
-- Jalankan file ini di Supabase SQL Editor. Aman dijalankan berkali-kali
-- (create or replace + grant, keduanya idempotent).
create or replace function public.track_shipment(p_search text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receiving_id uuid;
  v_receipt_number text;
  v_nomor_buku text;
  v_destination text;
  v_destination_address text;
  v_received_at timestamptz;
  v_total_quantity numeric;
  v_loaded_quantity numeric;
  v_delivered_quantity numeric;
  v_status text;
  v_vehicles jsonb;
  v_received_items jsonb;
  -- BARU (21 Oktober 2026 -- Section E): lihat catatan di atas.
  v_arrival_photo_url text;
  v_search text := upper(trim(p_search));
begin
  if v_search is null or v_search = '' then
    return jsonb_build_object('found', false);
  end if;

  select id, receipt_number, nomor_buku, destination, destination_address, received_at
    into v_receiving_id, v_receipt_number, v_nomor_buku, v_destination,
      v_destination_address, v_received_at
  from receiving
  where upper(trim(receipt_number)) = v_search
     or upper(trim(nomor_buku)) = v_search
  limit 1;

  if v_receiving_id is null then
    return jsonb_build_object('found', false);
  end if;

  select coalesce(sum(rd.quantity), 0) into v_total_quantity
  from receiving_details rd
  where rd.receiving_id = v_receiving_id;

  select coalesce(sum(rd.quantity), 0) into v_loaded_quantity
  from receiving_details rd
  where rd.receiving_id = v_receiving_id
    and exists (
      select 1 from shipment_scans ss
      where ss.receiving_detail_id = rd.id and ss.scan_type = 'LOAD'
    );

  select coalesce(sum(rd.quantity), 0) into v_delivered_quantity
  from receiving_details rd
  where rd.receiving_id = v_receiving_id
    and exists (
      select 1 from shipment_scans ss
      where ss.receiving_detail_id = rd.id and ss.scan_type = 'DELIVER'
    );

  if v_loaded_quantity <= 0 then
    v_status := 'diterima';
  elsif v_delivered_quantity >= v_total_quantity and v_total_quantity > 0 then
    v_status := 'tiba';
  elsif exists (
    select 1
    from shipments s
    join shipment_scans ss on ss.shipment_id = s.id and ss.scan_type = 'LOAD'
    join receiving_details rd on rd.id = ss.receiving_detail_id
    where rd.receiving_id = v_receiving_id
      and s.status = 'DEPARTED'
  ) then
    v_status := 'berangkat';
  else
    v_status := 'loading';
  end if;

  -- BARU (21 Oktober 2026 -- Section E): foto DELIVER TERBARU resi ini
  -- yang punya `url_foto_selesai` (terlepas dari jalur mana -- scan QR,
  -- checklist manual, atau Scan Barcode nanti). `order by scanned_at desc
  -- limit 1` -- kalau resi terpecah ke beberapa shipment/lokasi turun,
  -- cukup ambil SALAH SATU (yang paling baru) sebagai representasi, SAMA
  -- filosofi dengan dugaan awal di dokumen arsitektur ("ambil SALAH SATU
  -- yang tidak null").
  select ss.url_foto_selesai into v_arrival_photo_url
  from shipment_scans ss
  join receiving_details rd on rd.id = ss.receiving_detail_id
  where rd.receiving_id = v_receiving_id
    and ss.scan_type = 'DELIVER'
    and ss.url_foto_selesai is not null
  order by ss.scanned_at desc
  limit 1;

  -- Kendaraan yang (pernah) memuat barang resi ini, HANYA yang statusnya
  -- masih aktif (LOADING/DEPARTED -- BUKAN ARRIVED, karena begitu
  -- kendaraan "Sudah Kembali ke Kantor" perjalanannya sudah selesai dan
  -- titik GPS lama tidak relevan lagi buat ditampilkan ke customer).
  select coalesce(jsonb_agg(v order by v.shipment_number), '[]'::jsonb)
    into v_vehicles
  from (
    select
      s.id as shipment_id,
      s.shipment_number,
      s.status as shipment_status,
      s.loaded_at,
      vh.plate_number as vehicle_plate,
      vh.driver_name,
      vh.driver_phone,
      lp.latitude,
      lp.longitude,
      lp.recorded_at,
      coalesce(items.items, '[]'::jsonb) as items
    from (
      select distinct s.id
      from shipments s
      join shipment_scans ss on ss.shipment_id = s.id and ss.scan_type = 'LOAD'
      join receiving_details rd on rd.id = ss.receiving_detail_id
      where rd.receiving_id = v_receiving_id
        and s.status in ('LOADING', 'DEPARTED')
    ) sid
    join shipments s on s.id = sid.id
    join vehicles vh on vh.id = s.vehicle_id
    left join lateral (
      select latitude, longitude, recorded_at
      from shipment_location_pings
      where shipment_id = s.id
      order by recorded_at desc
      limit 1
    ) lp on true
    left join lateral (
      select jsonb_agg(
               jsonb_build_object(
                 'itemName', grp.item_name,
                 'quantityUnit', grp.quantity_unit,
                 'loadedCount', grp.loaded_count
               )
               order by grp.item_name
             ) as items
      from (
        select rd3.item_name, rd3.quantity_unit, count(*) as loaded_count
        from shipment_scans ss3
        join receiving_details rd3 on rd3.id = ss3.receiving_detail_id
        where ss3.shipment_id = s.id
          and ss3.scan_type = 'LOAD'
          and rd3.receiving_id = v_receiving_id
        group by rd3.item_name, rd3.quantity_unit
      ) grp
    ) items on true
  ) v;

  -- "Detail Barang Resi sesuai penerimaan" -- SATU baris per
  -- `receiving_details`, SELALU dihitung terlepas dari status.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'itemName', rd.item_name,
        'quantityUnit', rd.quantity_unit,
        'quantity', rd.quantity,
        'loadedCount', coalesce(lc.cnt, 0),
        'deliveredCount', coalesce(dc.cnt, 0)
      )
      order by rd.created_at
    ),
    '[]'::jsonb
  ) into v_received_items
  from receiving_details rd
  left join lateral (
    select count(*) as cnt
    from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'LOAD'
  ) lc on true
  left join lateral (
    select count(*) as cnt
    from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'DELIVER'
  ) dc on true
  where rd.receiving_id = v_receiving_id;

  return jsonb_build_object(
    'found', true,
    'receiptNumber', v_receipt_number,
    'nomorBuku', v_nomor_buku,
    'destination', v_destination,
    'destinationAddress', v_destination_address,
    'receivedAt', v_received_at,
    'totalQuantity', v_total_quantity,
    'loadedQuantity', v_loaded_quantity,
    'deliveredQuantity', v_delivered_quantity,
    'status', v_status,
    'vehicles', v_vehicles,
    'receivedItems', v_received_items,
    'arrivalPhotoUrl', v_arrival_photo_url
  );
end;
$$;

grant execute on function public.track_shipment(text) to anon;
grant execute on function public.track_shipment(text) to authenticated;
