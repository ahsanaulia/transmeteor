-- ============================================================
-- CEK DEFINITIF: apakah masalahnya RLS untuk role 'authenticated'
-- (role yang dipakai APLIKASI lewat Supabase API), BUKAN cuma cek
-- data mentah lewat SQL Editor (SQL Editor jalan sebagai superuser,
-- SELALU bisa lihat semua data walau RLS aktif -- makanya QUERY
-- sebelumnya semua "berhasil" walau appnya kosong).
--
-- Jalankan SEMUA blok di bawah, urut dari atas ke bawah, di Supabase
-- SQL Editor. Kirim balik SEMUA hasilnya (boleh screenshot per blok).
-- ============================================================

-- ------------------------------------------------------------
-- BLOK 1 -- daftar LENGKAP semua policy yang aktif di 3 tabel ini
-- (bukan cuma yang kita buat kemarin -- kalau ada policy LAIN yang
-- lebih lama dan sifatnya RESTRICTIVE, itu bisa menutup akses lagi
-- walau policy permissive kita sudah ada).
-- ------------------------------------------------------------
select
  tablename,
  policyname,
  permissive,   -- <- PERMISSIVE atau RESTRICTIVE, ini kuncinya
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where tablename in ('receiving', 'receiving_details', 'shipment_scans')
order by tablename, permissive, policyname;

-- ------------------------------------------------------------
-- BLOK 2 -- pastikan RLS memang ENABLED di ke-3 tabel ini (kalau
-- 'rls_enabled' = false, berarti RLS tidak aktif sama sekali dan
-- policy di atas tidak relevan -- tapi kalau begitu seharusnya app
-- BISA lihat semua data, jadi kemungkinan kecil ini penyebabnya).
-- ------------------------------------------------------------
select relname as tablename, relrowsecurity as rls_enabled, relforcerowsecurity as rls_forced
from pg_class
where relname in ('receiving', 'receiving_details', 'shipment_scans');

-- ------------------------------------------------------------
-- BLOK 3 -- INI YANG PALING PENTING: coba jalankan query yang PERSIS
-- SAMA SHAPE-nya dengan yang dipakai APLIKASI (join shipment_scans ->
-- receiving_details -> receiving) TAPI sebagai role 'authenticated'
-- (role yang benar-benar dipakai app lewat API), BUKAN sebagai
-- superuser SQL Editor biasa. Kalau blok ini return 0 baris padahal
-- BLOK 4 (di bawah, tanpa set role) return banyak baris -- itu BUKTI
-- PASTI ini murni soal RLS/role, bukan soal data atau soal kode Dart.
set local role authenticated;

select
  ss.id as scan_id,
  ss.receiving_detail_id,
  rd.id as detail_id,
  rd.receiving_id,
  r.receipt_number,
  r.destination,
  r.destination_id
from shipment_scans ss
left join receiving_details rd on rd.id = ss.receiving_detail_id
left join receiving r on r.id = rd.receiving_id
where ss.shipment_id = (select id from shipments where shipment_number = 'SHP000016')
order by ss.scanned_at;

reset role;

-- ------------------------------------------------------------
-- BLOK 4 -- query yang SAMA PERSIS seperti BLOK 3, tapi TANPA
-- "set local role authenticated" (jalan sebagai superuser biasa) --
-- ini pembanding. Kalau BLOK 4 ini banyak baris tapi BLOK 3 di atas
-- 0 baris, itu mengkonfirmasi 100% dugaan RLS/role.
-- ------------------------------------------------------------
select
  ss.id as scan_id,
  ss.receiving_detail_id,
  rd.id as detail_id,
  rd.receiving_id,
  r.receipt_number,
  r.destination,
  r.destination_id
from shipment_scans ss
left join receiving_details rd on rd.id = ss.receiving_detail_id
left join receiving r on r.id = rd.receiving_id
where ss.shipment_id = (select id from shipments where shipment_number = 'SHP000016')
order by ss.scanned_at;
