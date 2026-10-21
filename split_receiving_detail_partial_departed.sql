-- Membagi 1 baris `receiving_details` jadi 2, karena ternyata CUMA
-- SEBAGIAN yang benar-benar sudah jalan/dimuat, bukan semuanya.
--
-- KONTEKS: barang "gabus" 5 bal (is_unlabeled = true) di resi
-- RESI001316 sudah sempat ditandai LOAD semuanya lewat backfill
-- sebelumnya -- ternyata di lapangan CUMA 2 bal yang benar-benar jalan,
-- 3 bal sisanya masih di gudang. Karena barang tanpa label (curah)
-- dilacak SEMUA-ATAU-TIDAK-SAMA-SEKALI per baris (1 baris = 1 status),
-- satu-satunya cara merepresentasikan "sebagian jalan, sebagian
-- tinggal" yang BENAR adalah memisah baris itu jadi 2:
--   - Baris LAMA (id TETAP SAMA): quantity diturunkan jadi yang BENAR
--     sudah jalan (2 bal). TIDAK MENYENTUH baris `shipment_scans` LOAD
--     yang sudah ada -- baris itu tetap valid karena masih menunjuk ke
--     id yang sama, cuma sekarang mewakili 2 bal (bukan 5).
--   - Baris BARU: quantity = sisanya (3 bal), kode item baru, BELUM
--     ada scan LOAD sama sekali -- otomatis muncul lagi sebagai "belum
--     dimuat" di Daftar Barang/Monitoring Resi, siap dimuat lain waktu.
-- Harga (`total_price`) & diskon (`discount_amount`) ikut dibagi
-- proporsional sesuai porsi quantity masing-masing, supaya totalnya
-- tetap sama dengan sebelum dipisah. `receiving.total_quantity`/
-- `total_price` otomatis ikut benar lewat trigger
-- `trg_receiving_details_recalculate` yang sudah ada -- TIDAK perlu
-- disentuh manual di sini.
--
-- CARA PAKAI: cek 2 variabel di bawah ("ISI DI SINI") sudah benar,
-- lalu jalankan SELURUH file ini (dari "do $$" sampai akhir) sekali di
-- Supabase SQL Editor.

do $$
declare
  -- =====================================================================
  -- ISI DI SINI -- cek lagi sebelum menjalankan.
  -- =====================================================================
  v_detail_id uuid := 'f0649c60-ff5c-4e30-9ca2-2a199153471b'; -- baris "gabus" 5 bal
  v_departed_qty numeric := 2; -- yang BENAR sudah jalan (sisanya otomatis dihitung)

  -- =====================================================================
  -- DI BAWAH INI logika otomatis -- TIDAK PERLU diubah.
  -- =====================================================================
  v_receiving_id uuid;
  v_item_code text;
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
  v_is_unlabeled boolean;
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
begin
  select
    receiving_id, item_code, item_type_id, pricing_type_id, item_name,
    quantity, quantity_unit, weight_kg, length_cm, width_cm, height_cm,
    volume_m3, unit_price, bundle_quantity, is_unlabeled, photo_url,
    storage_id, discount_percent, discount_amount
  into
    v_receiving_id, v_item_code, v_item_type_id, v_pricing_type_id, v_item_name,
    v_orig_quantity, v_quantity_unit, v_weight_kg, v_length_cm, v_width_cm, v_height_cm,
    v_volume_m3, v_unit_price, v_bundle_quantity, v_is_unlabeled, v_photo_url,
    v_storage_id, v_discount_percent, v_discount_amount
  from receiving_details
  where id = v_detail_id;

  if v_receiving_id is null then
    raise exception 'receiving_details dengan id % tidak ditemukan.', v_detail_id;
  end if;

  if v_departed_qty <= 0 or v_departed_qty >= v_orig_quantity then
    raise exception 'v_departed_qty (%) harus lebih dari 0 dan kurang dari quantity asli baris ini (%).', v_departed_qty, v_orig_quantity;
  end if;

  v_remaining_qty := v_orig_quantity - v_departed_qty;

  select receipt_number into v_receipt_number from receiving where id = v_receiving_id;

  -- Nomor urut kode item baru -- SAMA formula dengan yang dipakai app
  -- (`receiving_items_page.dart`: '{receiptNumber}-{sequence 2 digit}').
  select count(*) + 1 into v_next_seq from receiving_details where receiving_id = v_receiving_id;
  v_new_item_code := v_receipt_number || '-' || lpad(v_next_seq::text, 2, '0');

  -- Bagi harga & diskon proporsional sesuai porsi quantity.
  v_old_discount_amount := round(coalesce(v_discount_amount, 0) * v_departed_qty / v_orig_quantity, 2);
  v_new_discount_amount := coalesce(v_discount_amount, 0) - v_old_discount_amount;
  v_old_total_price := round(coalesce(v_unit_price, 0) * v_departed_qty, 2) - v_old_discount_amount;
  v_new_total_price := round(coalesce(v_unit_price, 0) * v_remaining_qty, 2) - v_new_discount_amount;

  -- Baris LAMA (id TETAP SAMA -- shipment_scans LOAD yang sudah ada
  -- TIDAK disentuh, tetap valid) -- sekarang mewakili HANYA porsi yang
  -- benar-benar sudah jalan.
  update receiving_details
  set quantity = v_departed_qty,
      total_price = v_old_total_price,
      discount_amount = v_old_discount_amount,
      updated_at = now()
  where id = v_detail_id;

  -- Baris BARU -- porsi yang masih tinggal di gudang, belum ada scan
  -- LOAD sama sekali.
  insert into receiving_details (
    receiving_id, item_code, item_type_id, pricing_type_id, item_name,
    quantity, quantity_unit, weight_kg, length_cm, width_cm, height_cm,
    volume_m3, unit_price, total_price, bundle_quantity, is_unlabeled,
    photo_url, storage_id, discount_percent, discount_amount
  ) values (
    v_receiving_id, v_new_item_code, v_item_type_id, v_pricing_type_id, v_item_name,
    v_remaining_qty, v_quantity_unit, v_weight_kg, v_length_cm, v_width_cm, v_height_cm,
    v_volume_m3, v_unit_price, v_new_total_price, v_bundle_quantity, v_is_unlabeled,
    v_photo_url, v_storage_id, v_discount_percent, v_new_discount_amount
  );

  raise notice 'Selesai. Baris "%" sekarang quantity = % (sudah jalan, scan LOAD lama tidak diubah). Baris baru "%" dibuat quantity = % (masih tinggal, belum ada scan).',
    v_item_code, v_departed_qty, v_new_item_code, v_remaining_qty;
end $$;
