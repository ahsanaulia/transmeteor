-- Cek LEBIH DALAM dari sekadar EXISTS -- untuk barang BERLABEL dengan
-- >1 unit fisik (quantity > 1), 1 baris `receiving_details` punya BANYAK
-- unit_code sendiri2 (item_code-U1, -U2, dst, lihat `_physicalUnitCodes`
-- di `shipment_service.dart`). Checklist app mensyaratkan SEMUA unit
-- unit_code itu sudah ter-LOAD -- kalau cuma SEBAGIAN, baris itu TETAP
-- muncul di checklist (dengan sisa unit yang kurang), padahal query
-- EXISTS sederhana (yang saya pakai sebelumnya) sudah bilang "SUDAH
-- LOAD" begitu ADA SATU unit saja yang ter-scan.
--
-- Ini langsung LIST semua baris shipment_scans (LOAD & DELIVER) yang
-- benar-benar ada untuk RESI000311-04 (Tangki 1200L, quantity 5,
-- berlabel) -- harusnya ada TEPAT 5 baris LOAD (unit_code
-- RESI000311-04-U1 s/d -U5) & 5 baris DELIVER kalau backfill-nya benar2
-- lengkap.

select
  rd.item_code,
  rd.quantity,
  ss.unit_code,
  ss.scan_type,
  ss.scanned_at,
  sh.shipment_number
from receiving_details rd
left join shipment_scans ss on ss.receiving_detail_id = rd.id
left join shipments sh on sh.id = ss.shipment_id
where rd.item_code = 'RESI000311-04'
order by ss.scan_type, ss.unit_code;
