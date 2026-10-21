-- Verifikasi SETELAH menjalankan selesaikan_banyak_resi_dan_split_622.sql.
-- Read-only. Mengecek apakah scan LOAD+DELIVER BENAR-BENAR sudah masuk
-- untuk resi-resi yang seharusnya selesai -- supaya ketahuan apakah
-- skripnya betul2 jalan, atau gagal di tengah (mis. karena
-- v_admin_employee_id belum diganti, lupa jalankan, dll).

select
  r.receipt_number,
  rd.item_code,
  rd.item_name,
  rd.quantity,
  rd.is_unlabeled,
  case when exists (
    select 1 from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'LOAD'
  ) then 'SUDAH LOAD' else 'BELUM LOAD' end as load_status,
  case when exists (
    select 1 from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'DELIVER'
  ) then 'SUDAH DELIVER' else 'BELUM DELIVER' end as deliver_status
from receiving r
join receiving_details rd on rd.receiving_id = r.id
where r.receipt_number in (
  'RESI000054', 'RESI000311', 'RESI000357', 'RESI000419',
  'RESI000509', 'RESI000566', 'RESI000622', 'RESI000662',
  'RESI000748', 'RESI000781', 'RESI000918', 'RESI001120'
)
order by r.receipt_number, rd.created_at;

-- Kalau ada baris 'BELUM LOAD' di luar yang Anda tahu memang belum jalan
-- (mis. sisa 6 ball RESI000622), berarti skripnya tidak/belum berhasil
-- jalan untuk baris itu -- kirim hasil query ini ke saya.

-- Cek juga apakah shipment placeholder "DISELESAIKAN ADMIN" benar-benar
-- kebentuk (kalau ini kosong, berarti skrip Bagian 1 belum pernah jalan
-- sukses sama sekali):
select v.plate_number, s.id as shipment_id, s.status, s.admin_completion_note,
  (select count(*) from shipment_scans where shipment_id = s.id) as jumlah_scan
from shipments s
join vehicles v on v.id = s.vehicle_id
where v.plate_number in ('DISELESAIKAN ADMIN', 'BYPASS-SIMULASI');
