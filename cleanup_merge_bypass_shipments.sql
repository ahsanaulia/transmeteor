-- Gabungkan SEMUA shipment placeholder "Selesaikan Resi" (bypass admin)
-- jadi SATU shipment saja -- 16 Oktober 2026, laporan user: "tetapi
-- saat ini banyak sekali shipment muncul di daftar shipment."
--
-- SEBAB: sebelum perbaikan Tambahan #44 (lihat project doc
-- arsitektur-flutter.md), tombol "Selesaikan" per resi di Monitoring
-- Resi admin SELALU membuat 1 baris BARU di tabel `shipments` setiap
-- kali diklik -- walau semuanya pakai kendaraan placeholder yang SAMA
-- ("BYPASS-SIMULASI", sekarang diganti nama jadi "DISELESAIKAN ADMIN",
-- lihat Tambahan #45). Kode Flutter SUDAH diperbaiki (tidak menambah
-- shipment baru lagi) -- script ini membereskan data LAMA yang SUDAH
-- TERLANJUR menumpuk SEBELUM perbaikan itu.
--
-- APA YANG DILAKUKAN:
-- 1) Cari kendaraan placeholder-nya (dukung nama lama MAUPUN baru,
--    jaga-jaga kalau aplikasi belum sempat rename otomatis).
-- 2) Pilih SATU shipment milik kendaraan itu sebagai "keeper" (yang
--    paling awal dibuat).
-- 3) Pindahkan SEMUA baris terkait (shipment_scans, shipment_expenses,
--    shipment_location_pings -- 3 tabel yang diketahui punya kolom
--    `shipment_id` di aplikasi ini) dari shipment-shipment LAIN
--    (duplikat) ke shipment "keeper" itu.
-- 4) Hapus shipment-shipment duplikat yang sekarang sudah kosong.
-- 5) Pastikan nama kendaraan placeholder-nya sudah "DISELESAIKAN ADMIN".
--
-- AMAN DIULANG (idempotent) -- kalau cuma ada 1 shipment placeholder
-- (atau tidak ada sama sekali), script ini tidak melakukan apa-apa.
-- TIDAK menyentuh shipment ASLI (hasil Loading sungguhan) sama sekali
-- -- hanya shipment milik kendaraan placeholder ini.
--
-- Kalau menjalankan script ini muncul error FK constraint yang
-- menyebut tabel LAIN (bukan 3 tabel di atas), berarti ada tabel lain
-- di proyek ini yang juga punya kolom `shipment_id` dan belum ketahuan
-- -- laporkan pesan errornya, jangan dipaksa jalan.

do $$
declare
  v_vehicle_id uuid;
  v_keeper_id uuid;
  v_duplicate_count int;
begin
  -- 1) Kendaraan placeholder-nya.
  select id into v_vehicle_id
  from vehicles
  where plate_number in ('DISELESAIKAN ADMIN', 'BYPASS-SIMULASI')
  order by (plate_number = 'DISELESAIKAN ADMIN') desc
  limit 1;

  if v_vehicle_id is null then
    raise notice 'Tidak ada kendaraan placeholder ditemukan -- tidak ada yang perlu dibersihkan.';
    return;
  end if;

  -- 2) Shipment "keeper" = yang paling lama dibuat.
  select id into v_keeper_id
  from shipments
  where vehicle_id = v_vehicle_id
  order by created_at asc
  limit 1;

  if v_keeper_id is null then
    raise notice 'Tidak ada shipment placeholder ditemukan -- tidak ada yang perlu dibersihkan.';
    return;
  end if;

  select count(*) into v_duplicate_count
  from shipments
  where vehicle_id = v_vehicle_id and id <> v_keeper_id;

  if v_duplicate_count = 0 then
    raise notice 'Cuma ada 1 shipment placeholder (id: %) -- tidak ada duplikat, tidak ada yang perlu digabung.', v_keeper_id;
  else
    -- 3) Pindahkan baris terkait dari shipment duplikat ke keeper.
    update shipment_scans
    set shipment_id = v_keeper_id
    where shipment_id in (
      select id from shipments where vehicle_id = v_vehicle_id and id <> v_keeper_id
    );

    update shipment_expenses
    set shipment_id = v_keeper_id
    where shipment_id in (
      select id from shipments where vehicle_id = v_vehicle_id and id <> v_keeper_id
    );

    update shipment_location_pings
    set shipment_id = v_keeper_id
    where shipment_id in (
      select id from shipments where vehicle_id = v_vehicle_id and id <> v_keeper_id
    );

    -- 4) Hapus shipment duplikat yang sudah kosong.
    delete from shipments
    where vehicle_id = v_vehicle_id and id <> v_keeper_id;

    raise notice '% shipment duplikat digabung ke shipment keeper id: %', v_duplicate_count, v_keeper_id;
  end if;

  -- 5) Pastikan nama kendaraan placeholder sudah yang terbaru.
  update vehicles
  set plate_number = 'DISELESAIKAN ADMIN'
  where id = v_vehicle_id and plate_number <> 'DISELESAIKAN ADMIN';
end $$;
