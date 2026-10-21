-- Jalankan ULANG "lengkapi yang masih kurang" untuk SEMUA resi yang Anda
-- konfirmasi sudah selesai (sekali lagi, daftar yang sama dengan
-- selesaikan_banyak_resi_dan_split_622.sql Bagian 1) -- AMAN dijalankan
-- walau sebagian sudah lengkap: tiap unit dijaga NOT EXISTS per
-- unit_code+scan_type, jadi yang sudah benar TIDAK akan dobel/berubah,
-- cuma yang masih bolong yang ditambal.
--
-- Ini dibuat setelah ketahuan RESI000311-04 (Tangki 1200L, 5 pcs,
-- BERLABEL) kemarin masih ada unit yang belum ke-scan walau skrip
-- pertama sudah dijalankan -- supaya pasti SEMUA 11 resi ini benar2
-- tuntas (bukan cuma RESI000311), bukan cuma dicek sepintas (EXISTS
-- gampang keliru untuk barang berlabel quantity > 1, lihat catatan
-- panjang di `cek_detail_unit_resi311.sql`).
--
-- TIDAK termasuk: RESI000341 (belum jalan), RESI001316 & RESI000622
-- (sudah ditangani terpisah lewat split -- JANGAN dimasukkan ke sini,
-- nanti barang yang sengaja belum dimuat ikut ditandai selesai).
--
-- GANTI v_admin_employee_id dulu sebelum menjalankan.

do $$
declare
  v_receipt_numbers text[] := array[
    'RESI000054', 'RESI000311', 'RESI000357', 'RESI000419',
    'RESI000509', 'RESI000566', 'RESI000662', 'RESI000748',
    'RESI000781', 'RESI000918', 'RESI001120'
  ];
  v_admin_employee_id uuid := '55492445-fd27-49d0-be05-cbfe0b579106';
  v_note text := 'Input manual data lama lewat SQL (selesaikan_ulang_semua_resi.sql) -- melengkapi unit yang kemarin masih kurang';

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
          raise notice '% -- LOAD ditambahkan: %', v_receiving.receipt_number, v_unit_code;
        end if;

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
          raise notice '% -- DELIVER ditambahkan: %', v_receiving.receipt_number, v_unit_code;
        end if;
      end loop;
    end loop;
  end loop;

  raise notice 'Selesai. % resi dicek ulang, % baris shipment_scans baru ditambahkan (kalau 0, berarti semuanya memang sudah lengkap dari sebelumnya).', v_resi_count, v_scan_count;
end $$;
