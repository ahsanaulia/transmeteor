-- LANJUTAN diagnostik RESI000311 & RESI000373.
--
-- Dari hasil diagnostik sebelumnya, ditemukan:
--   - RESI000311: 3 barang (-01,-02,-03) SUDAH ada LOAD (jam scan beda2,
--     terpisah sampai 1,5 jam -- ciri scan QR SATU-SATU saat muat
--     beneran, BUKAN ciri bypass "Selesaikan" yg nulis banyak baris
--     sekaligus dalam hitungan detik). 1 barang (-04, Tangki 1200L 5pcs,
--     BUKAN curah) BELUM ADA SCAN SAMA SEKALI.
--   - RESI000373: SEMUA 4 barang SUDAH ada LOAD, jumlah baris scan PAS
--     SAMA dengan quantity-nya (ciri scan QR satu-satu juga, bukan
--     bypass).
--
-- Supaya tidak cuma menduga dari pola jam, query ini mengecek LANGSUNG
-- shipment yang menampung scan-scan itu: apakah itu kendaraan BENERAN
-- (Tipe 1 -- "Intervensi Admin" di shipment yg sopirnya lupa selesaikan
-- app) atau kendaraan placeholder bypass (Tipe 2 -- "Selesaikan Resi").
-- Juga dicek status shipment-nya SEKARANG -- supaya tahu apakah
-- shipment itu masih "nyangkut" di halaman Loading (status LOADING/
-- belum DEPARTED) walau barangnya sudah full LOAD.

select
  r.receipt_number,
  sh.shipment_number,
  sh.status as status_shipment,
  v.plate_number,
  sh.completed_by_admin,
  sh.trip_started_by_admin,
  sh.admin_completion_note,
  sh.loaded_at,
  sh.departed_at,
  sh.arrived_at,
  count(distinct ss.unit_code) as jumlah_unit_load_di_shipment_ini
from receiving r
join receiving_details rd on rd.receiving_id = r.id
join shipment_scans ss on ss.receiving_detail_id = rd.id and ss.scan_type = 'LOAD'
join shipments sh on sh.id = ss.shipment_id
left join vehicles v on v.id = sh.vehicle_id
where r.receipt_number in ('RESI000311', 'RESI000373')
group by r.receipt_number, sh.id, sh.shipment_number, sh.status, v.plate_number,
  sh.completed_by_admin, sh.trip_started_by_admin, sh.admin_completion_note,
  sh.loaded_at, sh.departed_at, sh.arrived_at
order by r.receipt_number;
