-- DIAGNOSTIK (bukan perbaikan) -- untuk resi yang statusnya "Masih
-- Perjalanan" di Monitoring Resi, tapi masih muncul di checklist
-- Loading tanpa QR. Laporan user: RESI000311, RESI000373, dan
-- beberapa resi lain yang kasusnya sama -- diduga pernah diselesaikan
-- manual lewat tombol "Selesaikan" (Bypass Admin) di Monitoring Resi,
-- TAPI ada barang BARU yang ditambahkan ke resi itu SETELAH tombol
-- itu ditekan -- barang baru itu tidak ikut tersentuh bypass (bypass
-- hanya memproses barang yang ADA saat tombol ditekan), jadi:
--   (a) barang baru itu tetap "belum pernah dimuat" -> muncul lagi di
--       checklist Loading tanpa QR, dan
--   (b) karena ada barang yang belum ter-DELIVER, status resi turun
--       lagi dari "Selesai" ke "Masih Perjalanan".
--
-- GANTI nomor resi di bawah (boleh lebih dari 1 sekaligus), lalu
-- jalankan. Baca kolom `load_status`/`deliver_status` per barang --
-- kalau ada baris dengan `load_status = 'BELUM ADA SCAN'` yang
-- `created_at`-nya JAUH lebih baru dari baris lain di resi yang sama
-- (apalagi lebih baru dari `scanned_at` baris lain), itu mengkonfirmasi
-- dugaan di atas.

select
  r.receipt_number,
  rd.item_code,
  rd.item_name,
  rd.quantity,
  rd.quantity_unit,
  rd.is_unlabeled,
  rd.created_at as barang_dibuat,
  (
    select string_agg(
      'shipment=' || coalesce(sh.shipment_number, '-') ||
      ' (' || ss.scan_type || ' @ ' || ss.scanned_at::text ||
      coalesce(', note: ' || sh.admin_completion_note, '') || ')',
      ' | '
    )
    from shipment_scans ss
    left join shipments sh on sh.id = ss.shipment_id
    where ss.receiving_detail_id = rd.id
  ) as riwayat_scan,
  case when exists (
    select 1 from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'LOAD'
  ) then 'SUDAH ADA LOAD' else 'BELUM ADA SCAN SAMA SEKALI' end as load_status,
  case when exists (
    select 1 from shipment_scans ss
    where ss.receiving_detail_id = rd.id and ss.scan_type = 'DELIVER'
  ) then 'SUDAH ADA DELIVER' else 'BELUM DELIVER' end as deliver_status
from receiving r
join receiving_details rd on rd.receiving_id = r.id
where r.receipt_number in ('RESI000311', 'RESI000373')
order by r.receipt_number, rd.created_at;
