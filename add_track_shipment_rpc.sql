-- ============================================================
-- FITUR "TELUSURI KIRIMAN" (8 Oktober 2026 -- permintaan user poin 11)
-- ============================================================
--
-- Fungsi PUBLIK (bisa dipanggil TANPA login, lewat anon key) untuk
-- customer melacak status kirimannya sendiri pakai Nomor Resi ATAU
-- Nomor Buku. SENGAJA dibuat sebagai function SECURITY DEFINER (bukan
-- query langsung dari Flutter ke tabel `receiving`/`shipment_scans`/dst)
-- supaya:
--   1. Customer anonim TIDAK PERNAH diberi akses baca langsung ke
--      tabel-tabel internal (yang isinya ada data sensitif: harga,
--      nomor HP pengirim, dll) -- cuma field yang di-whitelist di
--      `jsonb_build_object` di bawah yang keluar.
--   2. Berlaku konsisten TERLEPAS dari RLS tabel-tabel itu nanti
--      diaktifkan/tidak -- SECURITY DEFINER jalan dengan privilege
--      pemilik function (bypass RLS), jadi lookup tetap jalan kapan pun.
--
-- Status disederhanakan jadi 4 tahap sesuai permintaan user: diterima /
-- loading / berangkat / tiba. Dihitung dari AGREGAT quantity per resi
-- (bukan unit-level seperti ManualLoadChecklist) -- cukup presisi untuk
-- halaman status customer, SAMA level presisi dengan
-- `getManifestGroupedByReceiving` yang sudah dipakai di tempat lain.
--
-- Jalankan file ini di Supabase SQL Editor SETELAH
-- `add_storage_nomor_buku_company_track.sql` (fungsi ini butuh kolom
-- `receiving.nomor_buku` yang dibuat di situ).
--
-- UPDATE (8 Oktober 2026, lanjutan permintaan user poin 11): tiap
-- kendaraan di `vehicles` sekarang juga menyertakan `loaded_at` (tanggal
-- & jam shipment itu mulai dimuat -- diisi `ShipmentService.createShipment`
-- SAAT shipment dibuat, jadi representasinya "mulai loading"), `driver_
-- phone` (selain `driver_name` yang sudah ada), dan `items` (daftar
-- barang -- `item_name`/`quantity_unit`/jumlah koli yang BENAR-BENAR
-- sudah discan LOAD ke kendaraan itu untuk resi ini, SESUAI data yang
-- juga dipakai Manifest -- lihat `ShipmentService._getLoadScansWithDetails`
-- -- bukan angka direka ulang). `receivedAt` (sudah ada sejak awal) juga
-- sekarang ditampilkan dengan jam di halaman (bukan cuma tanggal) --
-- TIDAK perlu perubahan SQL untuk itu, field-nya sudah timestamptz utuh.
--
-- UPDATE 2 (8 Oktober 2026, lanjutan lagi): tambah field top-level baru
-- `receivedItems` -- daftar barang PER BARIS `receiving_details` SESUAI
-- PENERIMAAN (bukan per kendaraan seperti `vehicles[].items`), masing-
-- masing dengan `quantity` (total koli diterima), `loadedCount` (berapa
-- dari koli itu yang SUDAH discan LOAD -- ke kendaraan APAPUN, aktif
-- maupun sudah ARRIVED), dan `deliveredCount` (berapa yang sudah DELIVER).
-- Field ini SELALU dihitung & dikirim terlepas dari status (beda dari
-- `vehicles` yang kosong kalau status diterima/tiba) -- permintaan user
-- eksplisit: "Detail Barang Resi sesuai penerimaan" harus selalu ada,
-- supaya kalau `loadedCount` suatu barang < `quantity`-nya SAAT status
-- sudah berangkat/tiba, customer (dan staff) langsung ketahuan barang itu
-- dikirim BERTAHAP (sebagian sudah jalan, sisanya menyusul lain waktu),
-- bukan cuma lihat angka agregat `loadedQuantity`/`totalQuantity` yang
-- menimpali semua jenis barang jadi satu angka.
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
  -- BARU (8 Oktober 2026, lanjutan lagi -- permintaan user eksplisit):
  -- "Nama Tujuan dan Alamat juga perlu diperbesar seperti Nama Sopir" --
  -- ternyata Alamat tujuan belum SAMA SEKALI dikirim RPC ini sebelumnya
  -- (cuma nama tujuan). Ditambahkan di sini supaya halaman punya datanya
  -- untuk ditampilkan.
  v_destination_address text;
  v_received_at timestamptz;
  v_total_quantity numeric;
  v_loaded_quantity numeric;
  v_delivered_quantity numeric;
  v_status text;
  v_vehicles jsonb;
  v_received_items jsonb;
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

  -- Kendaraan yang (pernah) memuat barang resi ini, HANYA yang statusnya
  -- masih aktif (LOADING/DEPARTED -- BUKAN ARRIVED, karena begitu
  -- kendaraan "Sudah Kembali ke Kantor" perjalanannya sudah selesai dan
  -- titik GPS lama tidak relevan lagi buat ditampilkan ke customer).
  --
  -- Dipecah jadi: (a) subquery `sid` cuma cari ID shipment yang relevan
  -- (distinct di level ID SAJA, supaya join berikutnya tidak perlu
  -- distinct lagi dan lebih mudah ditambah lateral join), lalu (b)
  -- lateral join `lp` (titik GPS terakhir) dan `items` (rekap barang yang
  -- dimuat KE SHIPMENT INI SAJA untuk resi ini) per shipment.
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
    -- Rekap barang yang SUDAH discan LOAD ke shipment ini, untuk resi ini
    -- saja -- dikelompokkan per nama barang & satuan (SAMA sumber data
    -- dengan Manifest: `shipment_scans` x `receiving_details`), supaya
    -- "Detail Barangnya" di halaman customer konsisten dengan yang
    -- tercetak di Manifest, bukan dihitung ulang dengan cara berbeda.
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

  -- "Detail Barang Resi sesuai penerimaan" (lihat UPDATE 2 di catatan
  -- atas) -- SATU baris per `receiving_details`, SELALU dihitung
  -- terlepas dari status, supaya pengiriman bertahap per jenis barang
  -- kelihatan (loadedCount/deliveredCount < quantity-nya sendiri).
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
    'receivedItems', v_received_items
  );
end;
$$;

-- Izinkan dipanggil TANPA login (anon) DAN sudah login (authenticated) --
-- keduanya butuh akses yang sama persis, fungsinya sendiri yang menjaga
-- field apa saja yang keluar (lihat whitelist di jsonb_build_object di
-- atas).
grant execute on function public.track_shipment(text) to anon;
grant execute on function public.track_shipment(text) to authenticated;
