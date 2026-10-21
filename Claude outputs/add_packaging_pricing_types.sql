-- Tambahan jenis harga (pricing_types) dari daftar kertas/scan yang dikirim
-- 7 September 2026 -- kemasan/packaging (Lux, Thinwall, Klir, Coolbox, dsb).
--
-- CATATAN SEBELUM DIJALANKAN -- ada 2 baris di kertas aslinya yang tulisannya
-- kurang jelas / kelihatan aneh, jadi saya isi dengan asumsi terbaik. TOLONG
-- DICEK dulu sebelum run, cari baris yang ditandai "-- PERIKSA:" di bawah:
--
--   1. "Coolbox 50liter Rp.25/0000 pcs" -- tulisan angkanya tidak jelas.
--      Saya asumsikan Rp 25.000/pcs (mengikuti pola coolbox 100L=50rb,
--      200L=100rb -- 50L jadi separuh dari 100L). Kalau salah, tinggal
--      UPDATE harganya nanti lewat halaman "Kelola Jenis Harga" di app.
--   2. "Thinwall Klirr 20000ML Rp.25.000" -- angka "20000ML" janggal
--      (kemungkinan maksudnya 2000ML, sama seperti kode "Lux 2.000ml" di
--      atasnya). Saya masukkan APA ADANYA sesuai tulisan di kertas
--      (20000ML) supaya tidak mengubah data tanpa konfirmasi Anda --
--      silakan koreksi nama/ukurannya lewat halaman "Kelola Jenis Harga"
--      kalau memang salah tulis.
--
-- Kode (price005 - price036) melanjutkan penomoran dari data yang sudah ada
-- (price001 - price004), tidak bentrok dengan kode lama (termasuk yang
-- format-nya beda: price00145, Price0062).

INSERT INTO "public"."pricing_types"
  ("id", "code", "name", "description", "is_active", "created_at", "updated_at", "price")
VALUES
  (gen_random_uuid(), 'price005', 'Kapas Karisma / dos', 'Kapas Karisma / dos', true, NOW(), NOW(), 40000.00),
  (gen_random_uuid(), 'price006', 'Lux 35ml / dos', 'Lux 35ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price007', 'Lux 75ml / dos', 'Lux 75ml / dos', true, NOW(), NOW(), 20000.00),
  (gen_random_uuid(), 'price008', 'Lux 2000ml / dos', 'Lux 2000ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price009', 'Lux 1500ml / dos', 'Lux 1500ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price010', 'Lux 1000ml / dos', 'Lux 1000ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price011', 'Lux 3000ml / dos', 'Lux 3000ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price012', 'Thinwall 200ml / dos', 'Thinwall 200ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price013', 'Thinwall Kokikku 200ml / dos', 'Thinwall Kokikku 200ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price014', 'Tutup Gelas 2000pcs / dos', 'Tutup Gelas 2000pcs / dos', true, NOW(), NOW(), 10000.00),
  (gen_random_uuid(), 'price015', 'Sendok Victory 10000pcs / dos', 'Sendok Victory 10000pcs / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price016', 'Klir 750ml / dos', 'Klir 750ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price017', 'Klir 650ml / dos', 'Klir 650ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price018', 'BX-4C / dos', 'BX-4C / dos', true, NOW(), NOW(), 20000.00),
  (gen_random_uuid(), 'price019', 'BX-3C / dos', 'BX-3C / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price020', 'Lid Bowl 360/500ml / dos', 'Lid Bowl 360/500ml / dos', true, NOW(), NOW(), 15000.00),
  (gen_random_uuid(), 'price021', 'Bowl 360ml / dos', 'Bowl 360ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price022', 'Coolbox 50 Liter / pcs', 'Coolbox 50 Liter / pcs', true, NOW(), NOW(), 25000.00), -- PERIKSA: lihat catatan #1 di atas
  (gen_random_uuid(), 'price023', 'Coolbox 100 Liter / pcs', 'Coolbox 100 Liter / pcs', true, NOW(), NOW(), 50000.00),
  (gen_random_uuid(), 'price024', 'Coolbox 200 Liter / pcs', 'Coolbox 200 Liter / pcs', true, NOW(), NOW(), 100000.00),
  (gen_random_uuid(), 'price025', 'Thinwall Klirr 1000ml / dos', 'Thinwall Klirr 1000ml / dos', true, NOW(), NOW(), 35000.00),
  (gen_random_uuid(), 'price026', 'Thinwall Klirr 1500ml / dos', 'Thinwall Klirr 1500ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price027', 'Thinwall Klirr 20000ml / dos', 'Thinwall Klirr 20000ml / dos', true, NOW(), NOW(), 25000.00), -- PERIKSA: lihat catatan #2 di atas
  (gen_random_uuid(), 'price028', 'Thinwall Klirr 250ml / dos', 'Thinwall Klirr 250ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price029', 'Thinwall Klirr 300ml / dos', 'Thinwall Klirr 300ml / dos', true, NOW(), NOW(), 25000.00),
  (gen_random_uuid(), 'price030', 'Thinwall Klirr 750ml / dos', 'Thinwall Klirr 750ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price031', 'Sauce Container Lux 35ml / dos', 'Sauce Container Lux 35ml / dos', true, NOW(), NOW(), 20000.00),
  (gen_random_uuid(), 'price032', 'Sauce Container Lux 100ml / dos', 'Sauce Container Lux 100ml / dos', true, NOW(), NOW(), 15000.00),
  (gen_random_uuid(), 'price033', 'Sauce Container Lux 75ml / dos', 'Sauce Container Lux 75ml / dos', true, NOW(), NOW(), 15000.00),
  (gen_random_uuid(), 'price034', 'Paper Bowl + Lid 800ml / dos', 'Paper Bowl + Lid 800ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price035', 'Paper Bowl + Lid 720ml / dos', 'Paper Bowl + Lid 720ml / dos', true, NOW(), NOW(), 30000.00),
  (gen_random_uuid(), 'price036', 'Paper Bowl + Lid 650ml / dos', 'Paper Bowl + Lid 650ml / dos', true, NOW(), NOW(), 30000.00);
