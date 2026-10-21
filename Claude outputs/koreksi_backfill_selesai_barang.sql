-- ============================================================
-- KOREKSI backfill `selesai_barang` -- JALANKAN SETELAH
-- `migrasi_flow_state_sisa_barang.sql` (yang sudah Anda jalankan &
-- hasilnya sudah benar untuk `sisa_barang`, TAPI `selesai_barang` di
-- situ masih salah hitung -- lihat penjelasan di bawah).
-- ============================================================
-- Backfill di migrasi utama (bagian 9) menghitung `selesai_barang`
-- dari JUMLAH SCAN `DELIVER` yang sudah ada -- padahal desain FINAL
-- (RPC `mark_selesai_for_shipment`, dipanggil setiap shipment "selesai
-- jalan"/ARRIVED) menentukan "selesai" dari JUMLAH SCAN `LOAD` pada
-- shipment yang SUDAH ARRIVED, BUKAN dari scan DELIVER. Dua definisi
-- ini TERNYATA jauh beda di data historis: BANYAK resi sudah dimuat &
-- shipment-nya sudah kembali ke kantor, TAPI tidak pernah di-scan
-- DELIVER per-unit secara eksplisit (konfirmasi dari hasil Anda: 1136
-- baris "SUDAH_DIMUAT" dengan `selesai_barang = 0` -- jumlah itu
-- terlalu besar untuk wajar kalau memang belum "selesai jalan" sama
-- sekali).
--
-- Perbaikan: reset `selesai_barang` ke 0, lalu REPLAY ulang RPC
-- `mark_selesai_for_shipment` yang SAMA PERSIS dipakai aksi real-time,
-- untuk SEMUA shipment yang statusnya SUDAH ARRIVED sampai saat ini --
-- hasilnya otomatis konsisten dengan logika forward (termasuk kasus 1
-- barang yang fisiknya terpecah ke LEBIH DARI SATU shipment, akan
-- benar jadi SELESAI_SEBAGIAN kalau salah satu shipment pembawanya
-- belum ARRIVED).
--
-- AMAN dijalankan ulang (idempotent -- selalu reset dulu ke 0 sebelum
-- replay). Mungkin makan beberapa puluh detik kalau jumlah shipment
-- ARRIVED historis sudah banyak -- biarkan sampai selesai.

-- 1) Reset -- supaya replay di bawah tidak dobel-hitung di atas hasil
--    backfill lama yang salah (DELIVER-based).
update receiving_details set selesai_barang = 0;

-- 2) Replay -- RPC yang SAMA PERSIS dipakai `returnToOffice`/
--    `forceCompleteByAdmin` di aplikasi, untuk SEMUA shipment yang
--    SUDAH ARRIVED (termasuk shipment placeholder "DISELESAIKAN ADMIN"
--    bekas intervensi Admin lama -- statusnya sejak awal sudah ARRIVED
--    juga).
do $$
declare
  r record;
begin
  for r in select id from shipments where status = 'ARRIVED' loop
    perform mark_selesai_for_shipment(r.id);
  end loop;
end $$;

-- 3) Sinkronkan ulang `flow_state` baris yang TIDAK tersentuh loop di
--    atas (`selesai_barang` masih 0 sampai sini) -- turunkan balik ke
--    BELUM_DIMUAT/LOADING_SEBAGIAN/SUDAH_DIMUAT sesuai `sisa_barang`
--    saja (bukan lagi berpatokan ke status SELESAI/SELESAI_SEBAGIAN
--    lama yang berasal dari hitungan DELIVER yang sudah dihapus di
--    langkah 1).
update receiving_details
set flow_state = receiving_detail_flow_state(
  receiving_detail_total_unit(is_unlabeled, quantity),
  coalesce(sisa_barang, 0),
  coalesce(selesai_barang, 0)
),
updated_at = now()
where coalesce(selesai_barang, 0) = 0;

-- 4) Verifikasi -- bandingkan dengan hasil sebelumnya (seharusnya
--    sekarang SUDAH_DIMUAT jauh lebih kecil dari 1136, pindah ke
--    SELESAI/SELESAI_SEBAGIAN).
select flow_state, count(*) as jumlah_baris,
  sum(sisa_barang) as total_sisa_barang,
  sum(selesai_barang) as total_selesai_barang
from receiving_details
group by flow_state
order by flow_state;
