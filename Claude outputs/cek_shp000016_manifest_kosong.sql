-- ============================================================
-- CEK TARGETED: shipment SHP000016 -- manifest PDF-nya kosong padahal
-- kertas fisik (dicetak sewaktu masih "Sedang Dimuat") ada 28 baris
-- barang. Jalankan SEMUA query di bawah di Supabase SQL Editor (bypass
-- RLS), kirim balik SEMUA hasilnya (screenshot boleh).
-- ============================================================

-- QUERY A -- pastikan shipment-nya sendiri ada & lihat id-nya persis.
select id, shipment_number, status, loaded_at, departed_at, arrived_at
from shipments
where shipment_number = 'SHP000016';

-- QUERY B -- INI YANG PALING PENTING: hitung baris shipment_scans
-- (scan_type LOAD) yang shipment_id-nya cocok dengan id di atas. Kalau
-- hasilnya 0 (nol), datanya MEMANG SUDAH TIDAK ADA di shipment_scans --
-- berarti BUKAN soal RLS/akses (RLS sudah dibuka kemarin), tapi
-- shipment_id di baris shipment_scans itu ternyata TIDAK/BUKAN
-- SHP000016 (kemungkinan besar: 28 barang itu di-scan ke SHIPMENT LAIN
-- yang beda id, walau nomor shipment yang tercetak di kertas sama-sama
-- "SHP000016" -- ini bisa terjadi kalau ada 2 baris shipment berbeda
-- dengan shipment_number yang sama, atau salah kirim shipment_id waktu
-- generate PDF).
select
  ss.id as scan_id,
  ss.shipment_id,
  ss.scan_type,
  ss.unit_code,
  ss.scanned_at
from shipment_scans ss
where ss.shipment_id = (select id from shipments where shipment_number = 'SHP000016')
order by ss.scanned_at;

-- QUERY C -- jaga-jaga kalau ternyata ADA lebih dari satu baris
-- `shipments` dengan shipment_number yang sama "SHP000016" (harusnya
-- unique, tapi perlu dipastikan) -- kalau QUERY A di atas mengembalikan
-- LEBIH DARI 1 baris, itu jawabannya: PDF & kertas fisik merujuk ke 2
-- shipment (id) yang BEDA walau nomornya kelihatan sama.
select shipment_number, count(*) as jumlah_baris, array_agg(id) as semua_id
from shipments
where shipment_number = 'SHP000016'
group by shipment_number;

-- QUERY D -- lihat SEMUA baris shipment_scans (LOAD) yang scanned_at-nya
-- di sekitar tanggal 21 September 2026 (tanggal manifes di kertas),
-- APAPUN shipment_id-nya -- buat lihat ke shipment_id mana sebenarnya
-- 28 barang itu tersimpan, siapa tahu beda dari id di QUERY A.
select
  ss.shipment_id,
  s.shipment_number,
  s.status,
  count(*) as jumlah_unit
from shipment_scans ss
left join shipments s on s.id = ss.shipment_id
where ss.scan_type = 'LOAD'
  and ss.scanned_at >= '2026-09-21T00:00:00'
  and ss.scanned_at <  '2026-09-22T00:00:00'
group by ss.shipment_id, s.shipment_number, s.status
order by jumlah_unit desc;
