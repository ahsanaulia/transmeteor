-- Menyelesaikan banyak resi sekaligus (LOAD + DELIVER untuk SEMUA
-- barang di tiap resi yang disebutkan) -- persis logika yang sama
-- dengan tombol "Selesaikan" (Bypass Admin, Tipe 2) di Monitoring Resi
-- [ShipmentService.forceCompleteReceivingByAdmin], cuma dibuat jalan
-- untuk banyak resi dalam satu skrip supaya tidak perlu klik satu-satu.
--
-- Scan yang dibuat ditautkan ke shipment placeholder "DISELESAIKAN
-- ADMIN" yang SAMA dengan yang dipakai tombol "Selesaikan" di app
-- (dicari dulu lewat plat kendaraan, dibuat kalau belum ada) -- supaya
-- hasilnya 100% konsisten dengan yang aplikasi sendiri hasilkan, dan
-- tetap tersembunyi dari daftar Shipment (sudah ditangani
-- `VehicleService.isBypassPlaceholder`).
--
-- Resi yang dimasukkan di bawah ini HANYA yang Anda konfirmasi SUDAH
-- selesai/jalan semua (termasuk barang yang sebelumnya ketahuan belum
-- pernah ter-scan sama sekali):
--   RESI000054, RESI000311, RESI000357, RESI000419, RESI000509,
--   RESI000566, RESI000662, RESI000748, RESI000781, RESI000918,
--   RESI001120
--
-- TIDAK termasuk di sini (sengaja dilewati):
--   - RESI000341 (Pakan 14 sak) -- Anda konfirmasi barangnya MEMANG
--     belum jalan.
--   - RESI001316 (gabus) -- sudah benar seperti sekarang (2 bal sudah
--     jalan lewat split sebelumnya, 3 bal sengaja masih menunggu).
--   - RESI000622 (gabus 8 ball, baru 2 selesai) -- ditangani TERPISAH
--     di bagian KEDUA skrip ini di bawah (perlu di-SPLIT dulu, tidak
--     bisa pakai "Selesaikan" biasa karena cuma SEBAGIAN yang jalan).
--
-- GANTI v_admin_employee_id di bawah sebelum menjalankan.

-- =====================================================================
-- BAGIAN 1 -- selesaikan resi yang 100% sudah jalan
-- =====================================================================
do $$
declare
  v_receipt_numbers text[] := array[
    'RESI000054', 'RESI000311', 'RESI000357', 'RESI000419',
    'RESI000509', 'RESI000566', 'RESI000662', 'RESI000748',
    'RESI000781', 'RESI000918', 'RESI001120'
  ];
  v_admin_employee_id uuid := 'GANTI_UUID_EMPLOYEE_ADMIN';
  v_note text := 'Input manual data lama lewat SQL (selesaikan_banyak_resi_dan_split_622.sql) -- dikonfirmasi user sudah jalan & tiba semua';

  v_bypass_vehicle_id uuid;
  v_bypass_shipment_id uuid;
  v_receiving record;
  v_detail record;
  v_unit_total int;
  v_i int;
  v_unit_code text;
  v_resi_count int := 0;
  v_scan_count int := 0;
begin
  if v_admin_employee_id is null then
    raise exception 'v_admin_employee_id wajib diisi.';
  end if;

  -- Get-or-create kendaraan placeholder "DISELESAIKAN ADMIN" (self-healing
  -- dari nama lama "BYPASS-SIMULASI" juga, sama seperti
  -- VehicleService.getOrCreateBypassVehicle).
  select id into v_bypass_vehicle_id from vehicles where plate_number = 'DISELESAIKAN ADMIN';
  if v_bypass_vehicle_id is null then
    update vehicles set plate_number = 'DISELESAIKAN ADMIN'
    where plate_number = 'BYPASS-SIMULASI'
    returning id into v_bypass_vehicle_id;
  end if;
  if v_bypass_vehicle_id is null then
    insert into vehicles (plate_number, is_active)
    values ('DISELESAIKAN ADMIN', false)
    returning id into v_bypass_vehicle_id;
  end if;

  -- Get-or-create shipment placeholder TUNGGAL yang menempel ke
  -- kendaraan itu (sama seperti ShipmentService._getOrCreateBypassShipment).
  select id into v_bypass_shipment_id from shipments where vehicle_id = v_bypass_vehicle_id limit 1;
  if v_bypass_shipment_id is null then
    insert into shipments (
      vehicle_id, status, loaded_by, loaded_at, arrived_at,
      completed_by_admin, admin_completion_note
    ) values (
      v_bypass_vehicle_id, 'ARRIVED', v_admin_employee_id, now(), now(),
      true,
      'Placeholder bypass admin (Monitoring Resi > Selesaikan) -- alasan tiap resi ada di catatan masing-masing scan, bukan di sini.'
    )
    returning id into v_bypass_shipment_id;
  end if;

  for v_receiving in
    select id, receipt_number from receiving where receipt_number = any(v_receipt_numbers)
  loop
    v_resi_count := v_resi_count + 1;

    for v_detail in
      select id, item_code, quantity, is_unlabeled
      from receiving_details
      where receiving_id = v_receiving.id
    loop
      if v_detail.is_unlabeled then
        v_unit_total := 1;
      else
        v_unit_total := greatest(1, least(999, round(v_detail.quantity)::int));
      end if;

      for v_i in 1..v_unit_total loop
        if v_detail.is_unlabeled then
          v_unit_code := 'NOLABEL-' || v_detail.id;
        elsif v_unit_total = 1 then
          v_unit_code := v_detail.item_code;
        else
          v_unit_code := v_detail.item_code || '-U' || v_i;
        end if;

        -- LOAD (kalau belum ada)
        if not exists (
          select 1 from shipment_scans
          where unit_code = v_unit_code and scan_type = 'LOAD'
        ) then
          insert into shipment_scans (
            shipment_id, receiving_detail_id, unit_code, unit_index,
            scan_type, scanned_by, scanned_at, notes
          ) values (
            v_bypass_shipment_id, v_detail.id, v_unit_code, v_i,
            'LOAD', v_admin_employee_id, now(),
            'Bypass Admin "Selesaikan" (' || v_receiving.receipt_number || '): ' || v_note
          );
          v_scan_count := v_scan_count + 1;
        end if;

        -- DELIVER (kalau belum ada)
        if not exists (
          select 1 from shipment_scans
          where unit_code = v_unit_code and scan_type = 'DELIVER'
        ) then
          insert into shipment_scans (
            shipment_id, receiving_detail_id, unit_code, unit_index,
            scan_type, scanned_by, scanned_at, notes
          ) values (
            v_bypass_shipment_id, v_detail.id, v_unit_code, v_i,
            'DELIVER', v_admin_employee_id, now(),
            'Bypass Admin "Selesaikan" (' || v_receiving.receipt_number || '): ' || v_note
          );
          v_scan_count := v_scan_count + 1;
        end if;
      end loop;
    end loop;
  end loop;

  if v_resi_count = 0 then
    raise exception 'Tidak ada resi ditemukan dari daftar: %.', v_receipt_numbers;
  end if;

  raise notice 'BAGIAN 1 selesai. % resi diproses, % baris shipment_scans baru ditambahkan (LOAD+DELIVER).', v_resi_count, v_scan_count;
end $$;

-- =====================================================================
-- BAGIAN 2 -- RESI000622 "gabus" 8 ball, baru 2 yang benar2 jalan.
-- Sama seperti RESI001316 sebelumnya: split dulu baris curah ini jadi
-- 2 (2 ball sudah jalan / 6 ball masih di gudang), baru porsi yang
-- sudah jalan itu ditandai LOAD+DELIVER ke shipment placeholder yang
-- SAMA dengan Bagian 1 di atas. Porsi 6 ball TIDAK disentuh sama sekali
-- (sengaja dibiarkan tanpa scan -- masih menunggu truk berikutnya).
-- =====================================================================
do $$
declare
  v_item_code_gabus text := 'RESI000622-01'; -- GANTI kalau kode item beda
  v_departed_qty numeric := 2; -- yang BENAR sudah jalan
  v_admin_employee_id uuid := 'GANTI_UUID_EMPLOYEE_ADMIN';

  v_detail_id uuid;
  v_receiving_id uuid;
  v_item_type_id uuid;
  v_pricing_type_id uuid;
  v_item_name text;
  v_orig_quantity numeric;
  v_quantity_unit text;
  v_weight_kg numeric;
  v_length_cm numeric;
  v_width_cm numeric;
  v_height_cm numeric;
  v_volume_m3 numeric;
  v_unit_price numeric;
  v_bundle_quantity int;
  v_photo_url text;
  v_storage_id uuid;
  v_discount_percent numeric;
  v_discount_amount numeric;

  v_remaining_qty numeric;
  v_receipt_number text;
  v_next_seq int;
  v_new_item_code text;
  v_old_discount_amount numeric;
  v_new_discount_amount numeric;
  v_old_total_price numeric;
  v_new_total_price numeric;

  v_bypass_vehicle_id uuid;
  v_bypass_shipment_id uuid;
  v_unit_code text;
begin
  select
    id, receiving_id, item_type_id, pricing_type_id, item_name,
    quantity, quantity_unit, weight_kg, length_cm, width_cm, height_cm,
    volume_m3, unit_price, bundle_quantity, photo_url,
    storage_id, discount_percent, discount_amount
  into
    v_detail_id, v_receiving_id, v_item_type_id, v_pricing_type_id, v_item_name,
    v_orig_quantity, v_quantity_unit, v_weight_kg, v_length_cm, v_width_cm, v_height_cm,
    v_volume_m3, v_unit_price, v_bundle_quantity, v_photo_url,
    v_storage_id, v_discount_percent, v_discount_amount
  from receiving_details
  where item_code = v_item_code_gabus;

  if v_detail_id is null then
    raise exception 'receiving_details dengan item_code % tidak ditemukan.', v_item_code_gabus;
  end if;

  if v_departed_qty <= 0 or v_departed_qty >= v_orig_quantity then
    raise exception 'v_departed_qty (%) harus lebih dari 0 dan kurang dari quantity asli baris ini (%).', v_departed_qty, v_orig_quantity;
  end if;

  v_remaining_qty := v_orig_quantity - v_departed_qty;

  select receipt_number into v_receipt_number from receiving where id = v_receiving_id;
  select count(*) + 1 into v_next_seq from receiving_details where receiving_id = v_receiving_id;
  v_new_item_code := v_receipt_number || '-' || lpad(v_next_seq::text, 2, '0');

  v_old_discount_amount := round(coalesce(v_discount_amount, 0) * v_departed_qty / v_orig_quantity, 2);
  v_new_discount_amount := coalesce(v_discount_amount, 0) - v_old_discount_amount;
  v_old_total_price := round(coalesce(v_unit_price, 0) * v_departed_qty, 2) - v_old_discount_amount;
  v_new_total_price := round(coalesce(v_unit_price, 0) * v_remaining_qty, 2) - v_new_discount_amount;

  -- Baris LAMA (id TETAP SAMA) -- sekarang mewakili porsi yang BENAR
  -- sudah jalan (2 ball).
  update receiving_details
  set quantity = v_departed_qty,
      total_price = v_old_total_price,
      discount_amount = v_old_discount_amount,
      updated_at = now()
  where id = v_detail_id;

  -- Baris BARU -- porsi yang masih tinggal di gudang (6 ball), TIDAK
  -- disentuh scan sama sekali.
  insert into receiving_details (
    receiving_id, item_code, item_type_id, pricing_type_id, item_name,
    quantity, quantity_unit, weight_kg, length_cm, width_cm, height_cm,
    volume_m3, unit_price, total_price, bundle_quantity, is_unlabeled,
    photo_url, storage_id, discount_percent, discount_amount
  ) values (
    v_receiving_id, v_new_item_code, v_item_type_id, v_pricing_type_id, v_item_name,
    v_remaining_qty, v_quantity_unit, v_weight_kg, v_length_cm, v_width_cm, v_height_cm,
    v_volume_m3, v_unit_price, v_new_total_price, v_bundle_quantity, true,
    v_photo_url, v_storage_id, v_discount_percent, v_new_discount_amount
  );

  -- Tandai porsi yang sudah jalan (baris LAMA, sekarang quantity = 2)
  -- LOAD + DELIVER, ke shipment placeholder yang SAMA dengan Bagian 1.
  select id into v_bypass_vehicle_id from vehicles where plate_number = 'DISELESAIKAN ADMIN';
  if v_bypass_vehicle_id is null then
    update vehicles set plate_number = 'DISELESAIKAN ADMIN'
    where plate_number = 'BYPASS-SIMULASI'
    returning id into v_bypass_vehicle_id;
  end if;
  if v_bypass_vehicle_id is null then
    insert into vehicles (plate_number, is_active) values ('DISELESAIKAN ADMIN', false)
    returning id into v_bypass_vehicle_id;
  end if;

  select id into v_bypass_shipment_id from shipments where vehicle_id = v_bypass_vehicle_id limit 1;
  if v_bypass_shipment_id is null then
    insert into shipments (
      vehicle_id, status, loaded_by, loaded_at, arrived_at,
      completed_by_admin, admin_completion_note
    ) values (
      v_bypass_vehicle_id, 'ARRIVED', v_admin_employee_id, now(), now(),
      true,
      'Placeholder bypass admin (Monitoring Resi > Selesaikan) -- alasan tiap resi ada di catatan masing-masing scan, bukan di sini.'
    )
    returning id into v_bypass_shipment_id;
  end if;

  v_unit_code := 'NOLABEL-' || v_detail_id;

  if not exists (select 1 from shipment_scans where unit_code = v_unit_code and scan_type = 'LOAD') then
    insert into shipment_scans (shipment_id, receiving_detail_id, unit_code, unit_index, scan_type, scanned_by, scanned_at, notes)
    values (v_bypass_shipment_id, v_detail_id, v_unit_code, 1, 'LOAD', v_admin_employee_id, now(),
      'Bypass Admin "Selesaikan" (' || v_receipt_number || ', porsi 2 ball yang sudah jalan): input manual lewat SQL');
  end if;

  if not exists (select 1 from shipment_scans where unit_code = v_unit_code and scan_type = 'DELIVER') then
    insert into shipment_scans (shipment_id, receiving_detail_id, unit_code, unit_index, scan_type, scanned_by, scanned_at, notes)
    values (v_bypass_shipment_id, v_detail_id, v_unit_code, 1, 'DELIVER', v_admin_employee_id, now(),
      'Bypass Admin "Selesaikan" (' || v_receipt_number || ', porsi 2 ball yang sudah jalan): input manual lewat SQL');
  end if;

  raise notice 'BAGIAN 2 selesai. Baris "%" sekarang quantity = % (sudah jalan, LOAD+DELIVER ditambahkan). Baris baru "%" dibuat quantity = % (masih tinggal, belum ada scan).',
    v_item_code_gabus, v_departed_qty, v_new_item_code, v_remaining_qty;
end $$;
