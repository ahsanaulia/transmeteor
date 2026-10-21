-- DIAGNOSTIK GLOBAL (read-only, tidak mengubah apa pun).
--
-- Tujuan: mencari SEMUA resi dengan kasus yang sama seperti RESI000311
-- -- yaitu resi yang SEBAGIAN barangnya sudah ter-LOAD (ada riwayat muat)
-- tapi ADA SATU ATAU LEBIH barang lain di resi yang sama yang BELUM
-- PERNAH ter-scan LOAD SAMA SEKALI. Resi seperti ini akan:
--   (a) terus muncul di checklist "Loading tanpa QR" (barangnya memang
--       belum pernah dimuat), dan
--   (b) tidak akan pernah mencapai status "Selesai" di Monitoring Resi
--       selama barang itu belum di-scan atau datanya dibenahi manual.
--
-- Ini BUKAN laporan bug kode -- biasanya ini kejadian operasional nyata:
-- barang ditambahkan ke resi tapi lupa/belum sempat dinaikkan ke truk
-- manapun. Query ini cuma membantu MENEMUKAN semua kasusnya sekaligus,
-- supaya tidak perlu dicek satu-satu.

select
  r.receipt_number,
  rd.item_code,
  rd.item_name,
  rd.quantity,
  rd.quantity_unit,
  rd.is_unlabeled,
  rd.created_at as barang_dibuat
from receiving r
join receiving_details rd on rd.receiving_id = r.id
where
  -- resi ini punya SETIDAKNYA satu barang lain yang SUDAH pernah di-LOAD
  exists (
    select 1
    from receiving_details rd2
    join shipment_scans ss2 on ss2.receiving_detail_id = rd2.id and ss2.scan_type = 'LOAD'
    where rd2.receiving_id = r.id
  )
  -- TAPI baris ini sendiri belum pernah ter-LOAD sama sekali
  and not exists (
    select 1 from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'LOAD'
  )
order by r.receipt_number, rd.created_at;
