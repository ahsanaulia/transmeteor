-- Isi scan LOAD lama (data historis) untuk SEMUA barang di resi yang
-- disebutkan, ke SATU shipment yang SUDAH ADA (dicari lewat nomor
-- shipment-nya), lalu ubah status shipment itu jadi DEPARTED
-- (Berangkat). Dipakai untuk mengoreksi data lama -- resi ini
-- SEBENARNYA sudah dimuat/berangkat di dunia nyata, tapi tidak pernah
-- tercatat scan LOAD-nya di aplikasi.
--
-- SENGAJA HANYA 3 ISIAN (tidak ada plat kendaraan/sopir sama sekali di
-- sini) -- script ini TIDAK PERNAH membuat shipment baru, HANYA
-- menambahkan scan LOAD ke shipment yang Anda sebutkan nomornya, yang
-- harus SUDAH ADA di database (jadi plat/sopir shipment itu otomatis
-- ikut data shipment yang sudah ada, tidak perlu diisi ulang di sini).
--
-- CARA PAKAI:
-- 1) ISI 3 variabel di bagian "ISI DI SINI" di bawah: v_receipt_numbers,
--    v_shipment_number, v_scanned_by_employee_id.
-- 2) Jalankan SELURUH file ini (dari "do $$" sampai akhir) di Supabase
--    SQL Editor sekali jalan.
-- 3) Baca NOTICE yang muncul -- menunjukkan berapa baris scan LOAD yang
--    baru ditambahkan & status shipment sebelum/sesudah diubah.
--
-- LOGIKA unit_code/unit_index DIBUAT SAMA PERSIS dengan yang dipakai
-- aplikasi Flutter (`ShipmentService._physicalUnitCodes`/`recordScan`),
-- supaya data hasil SQL ini tidak dianggap "aneh"/beda format kalau
-- nanti dicek dari app:
--   - Barang TANPA LABEL (`is_unlabeled = true`): 1 unit sintetis,
--     unit_code = 'NOLABEL-' || id baris `receiving_details`.
--   - Barang BERLABEL, quantity <= 1: 1 unit, unit_code = item_code
--     polos.
--   - Barang BERLABEL, quantity > 1: unit_code = item_code || '-U1',
--     '-U2', dst sebanyak round(quantity) (dibulatkan, maksimal 999).
-- Baris yang unit_code-nya SUDAH PERNAH ter-scan LOAD (constraint
-- unique(unit_code, scan_type) di `shipment_scans`) OTOMATIS dilewati,
-- TIDAK menimbulkan error & TIDAK bikin duplikat -- aman dijalankan
-- berkali-kali (idempotent) kalau sebagian barang resi ini kebetulan
-- sudah pernah ter-scan LOAD sebelumnya.

do $$
declare
  -- =====================================================================
  -- ISI DI SINI sebelum menjalankan script ini -- CUMA 3 baris ini.
  -- =====================================================================

  -- Nomor resi (receipt_number) yang mau diisi scan LOAD-nya. Boleh 1
  -- atau banyak sekaligus (semuanya masuk ke shipment YANG SAMA, yang
  -- disebutkan di v_shipment_number di bawah).
  v_receipt_numbers text[] := array['GANTI_NOMOR_RESI_1', 'GANTI_NOMOR_RESI_2'];

  -- Nomor shipment yang SUDAH ADA (persis seperti yang tertulis di app,
  -- mis. di "Riwayat Shipment"/manifest/Monitoring Pemuatan).
  v_shipment_number text := 'GANTI_NOMOR_SHIPMENT';

  -- id pegawai (tabel `employees`) yang dianggap melakukan pencatatan
  -- loading manual ini -- WAJIB diisi uuid yang valid.
  v_scanned_by_employee_id uuid := 'GANTI_UUID_EMPLOYEE';

  -- Catatan audit, bebas diubah.
  v_note text := 'Input manual data lama lewat SQL (backfill_load_scans_and_set_departed.sql)';

  -- =====================================================================
  -- DI BAWAH INI logika otomatis -- TIDAK PERLU diubah.
  -- =====================================================================
  v_shipment_id uuid;
  v_status_sebelum text;
  v_receiving record;
  v_detail record;
  v_unit_total int;
  v_i int;
  v_unit_code text;
  v_resi_count int := 0;
  v_scan_count int := 0;
begin
  if v_scanned_by_employee_id is null then
    raise exception 'v_scanned_by_employee_id wajib diisi.';
  end if;

  -- Cari shipment yang SUDAH ADA -- TIDAK PERNAH membuat baris baru.
  select id, status into v_shipment_id, v_status_sebelum
  from shipments
  where shipment_number = v_shipment_number;

  if v_shipment_id is null then
    raise exception 'Shipment dengan nomor "%" tidak ditemukan di tabel shipments. Cek lagi penulisannya (harus PERSIS sama dengan yang tertulis di app).', v_shipment_number;
  end if;

  raise notice 'Memakai shipment yang sudah ada: nomor "%" (id = %, status sebelum = %).', v_shipment_number, v_shipment_id, v_status_sebelum;

  -- Loop setiap resi yang disebutkan.
  for v_receiving in
    select id, receipt_number
    from receiving
    where receipt_number = any(v_receipt_numbers)
  loop
    v_resi_count := v_resi_count + 1;

    -- Loop setiap barang (receiving_details) di resi ini.
    for v_detail in
      select id, item_code, quantity, is_unlabeled
      from receiving_details
      where receiving_id = v_receiving.id
    loop
      if v_detail.is_unlabeled then
        -- Barang tanpa label -- 1 unit sintetis.
        v_unit_code := 'NOLABEL-' || v_detail.id;

        if not exists (
          select 1 from shipment_scans
          where unit_code = v_unit_code and scan_type = 'LOAD'
        ) then
          insert into shipment_scans (
            shipment_id, receiving_detail_id, unit_code, unit_index,
            scan_type, scanned_by, scanned_at, notes
          ) values (
            v_shipment_id, v_detail.id, v_unit_code, 1,
            'LOAD', v_scanned_by_employee_id, now(), v_note
          );
          v_scan_count := v_scan_count + 1;
        end if;
      else
        -- Barang berlabel -- jumlah unit fisik = quantity (dibulatkan,
        -- clamp 1..999), SAMA formula dengan `_physicalUnitCodes` di
        -- Flutter.
        v_unit_total := greatest(1, least(999, round(v_detail.quantity)::int));

        for v_i in 1..v_unit_total loop
          if v_unit_total <= 1 then
            v_unit_code := v_detail.item_code;
          else
            v_unit_code := v_detail.item_code || '-U' || v_i;
          end if;

          if not exists (
            select 1 from shipment_scans
            where unit_code = v_unit_code and scan_type = 'LOAD'
          ) then
            insert into shipment_scans (
              shipment_id, receiving_detail_id, unit_code, unit_index,
              scan_type, scanned_by, scanned_at, notes
            ) values (
              v_shipment_id, v_detail.id, v_unit_code, v_i,
              'LOAD', v_scanned_by_employee_id, now(), v_note
            );
            v_scan_count := v_scan_count + 1;
          end if;
        end loop;
      end if;
    end loop;
  end loop;

  if v_resi_count = 0 then
    raise exception 'Tidak ada resi ditemukan untuk nomor: %. Cek lagi isian v_receipt_numbers.', v_receipt_numbers;
  end if;

  -- Ubah status shipment jadi DEPARTED (Berangkat).
  update shipments
  set status = 'DEPARTED',
      departed_at = coalesce(departed_at, now()),
      updated_at = now()
  where id = v_shipment_id;

  raise notice 'Selesai. % resi diproses, % baris shipment_scans (LOAD) baru ditambahkan, shipment "%" -> status DEPARTED (sebelumnya %).',
    v_resi_count, v_scan_count, v_shipment_number, v_status_sebelum;
end $$;
