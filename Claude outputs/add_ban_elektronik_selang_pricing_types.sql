-- Tambahan jenis harga (pricing_types) dari daftar kertas/scan kedua yang
-- dikirim 7 September 2026 -- ban luar mobil, elektronik (kompor/kulkas/
-- mesin cuci/dryer/freezer), dan selang.
--
-- CATATAN SEBELUM DIJALANKAN:
--
--   1. Judul di kertas asli tertulis "Ban luar mobil" (bukan "Ban Motor").
--      7 baris ukuran & harga di bawahnya semua saya beri prefix
--      "Ban Luar Mobil" -- kalau maksudnya beda, tinggal ganti nama lewat
--      halaman "Kelola Jenis Harga" setelah di-run.
--   2. PERIKSA -- 7 baris "Ban Luar Mobil" TIDAK ada satuan tertulis di
--      kertas (cuma ukuran + harga, mis. "195/60 Rp.30.000"). Saya
--      asumsikan satuannya "/ pcs" (per ban). Kalau satuan sebenarnya beda
--      (mis. per set 4 ban), koreksi lewat halaman "Kelola Jenis Harga".
--   3. PERIKSA -- baris Kulkas, Washing Machine, Dryer Machine, dan
--      Freezer juga TIDAK ada satuan tertulis. Saya asumsikan "/ unit".
--      Kompor Rinnai (4 baris di atasnya) satuannya jelas tertulis "/dos"
--      jadi tidak perlu asumsi.
--   4. Salah ketik kecil di kertas asli sudah saya rapikan tanpa mengubah
--      arti: "185./65" -> "185/65", "tubless" -> "Tubeless",
--      "Frezzer" -> "Freezer", "rol"/"Roll" -> "roll" (satuan selang).
--
-- Kode (price037 - price058) melanjutkan penomoran dari batch sebelumnya
-- (price005 - price036, daftar kemasan/packaging), tidak bentrok.

INSERT INTO "public"."pricing_types"
  ("id", "code", "name", "description", "is_active", "created_at", "updated_at", "price")
VALUES
  -- Ban luar mobil -- PERIKSA satuan "/ pcs" (lihat catatan #2 di atas)
  (gen_random_uuid(), 'price037', 'Ban Luar Mobil 195/60 / pcs', 'Ban Luar Mobil 195/60 / pcs', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price038', 'Ban Luar Mobil 175/65 / pcs', 'Ban Luar Mobil 175/65 / pcs', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price039', 'Ban Luar Mobil 205/65 / pcs', 'Ban Luar Mobil 205/65 / pcs', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price040', 'Ban Luar Mobil 235/60 Tubeless / pcs', 'Ban Luar Mobil 235/60 Tubeless / pcs', true, NOW(), NOW(), 40000.00),
  (gen_random_uuid(), 'price041', 'Ban Luar Mobil 265/65 / pcs', 'Ban Luar Mobil 265/65 / pcs', true, NOW(), NOW(), 50000.00),
  (gen_random_uuid(), 'price042', 'Ban Luar Mobil 185/65 / pcs', 'Ban Luar Mobil 185/65 / pcs', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price043', 'Ban Luar Mobil 7.50R16 / pcs', 'Ban Luar Mobil 7.50R16 / pcs', true, NOW(), NOW(), 50000.00),

  -- Kompor Rinnai -- satuan jelas tertulis "/dos", tidak perlu asumsi
  (gen_random_uuid(), 'price044', 'Kompor Rinnai RI-712A / dos', 'Kompor Rinnai RI-712A / dos', true, NOW(), NOW(), 20000.00),
  (gen_random_uuid(), 'price045', 'Kompor Rinnai 202S / dos', 'Kompor Rinnai 202S / dos', true, NOW(), NOW(), 18000.00),
  (gen_random_uuid(), 'price046', 'Kompor Rinnai 522S / dos', 'Kompor Rinnai 522S / dos', true, NOW(), NOW(), 18000.00),
  (gen_random_uuid(), 'price047', 'Kompor Rinnai 301S / dos', 'Kompor Rinnai 301S / dos', true, NOW(), NOW(), 15000.00),

  -- Elektronik besar -- PERIKSA satuan "/ unit" (lihat catatan #3 di atas)
  (gen_random_uuid(), 'price048', 'Kulkas 287L / unit', 'Kulkas 287L / unit', true, NOW(), NOW(), 200000.00),
  (gen_random_uuid(), 'price049', 'Kulkas 480L / unit', 'Kulkas 480L / unit', true, NOW(), NOW(), 500000.00),
  (gen_random_uuid(), 'price050', 'Kulkas 189L / unit', 'Kulkas 189L / unit', true, NOW(), NOW(), 150000.00),
  (gen_random_uuid(), 'price051', 'Kulkas 186L / unit', 'Kulkas 186L / unit', true, NOW(), NOW(), 150000.00),
  (gen_random_uuid(), 'price052', 'Washing Machine 8Kg / unit', 'Washing Machine 8Kg / unit', true, NOW(), NOW(), 200000.00),
  (gen_random_uuid(), 'price053', 'Dryer Machine 32Kg / unit', 'Dryer Machine 32Kg / unit', true, NOW(), NOW(), 250000.00),
  (gen_random_uuid(), 'price054', 'Freezer AQF-S6 / unit', 'Freezer AQF-S6 / unit', true, NOW(), NOW(), 150000.00),

  -- Selang -- satuan jelas tertulis "/roll", tidak perlu asumsi
  (gen_random_uuid(), 'price055', 'Selang Stabilo 1/4 100mtr / roll', 'Selang Stabilo 1/4 100mtr / roll', true, NOW(), NOW(), 10000.00),
  (gen_random_uuid(), 'price056', 'Selang Stabilo 1/2 50mtr / roll', 'Selang Stabilo 1/2 50mtr / roll', true, NOW(), NOW(), 10000.00),
  (gen_random_uuid(), 'price057', 'Selang Stabilo 5/8 50mtr / roll', 'Selang Stabilo 5/8 50mtr / roll', true, NOW(), NOW(), 18000.00),
  (gen_random_uuid(), 'price058', 'Selang Benang 5/8 / roll', 'Selang Benang 5/8 / roll', true, NOW(), NOW(), 18000.00);
