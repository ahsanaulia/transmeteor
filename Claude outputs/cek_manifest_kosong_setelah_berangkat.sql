-- ============================================================
-- FIX: Manifest/Tanda Terima Tujuan kosong SETELAH shipment
-- diberangkatkan (status DEPARTED) -- DAN kekhawatiran user yang sama:
-- barang yang sudah TIBA di tujuan (ARRIVED) jangan sampai tidak bisa
-- di-EDIT atau malah HILANG dari tampilan.
-- ============================================================
--
-- INSTRUKSI EKSPLISIT USER (jangan dilanggar): "untuk admin jangan
-- pakai flow, misal tiba2 manifest sudah tidak bisa dibuka lagi", lalu
-- "atau barang yang sudah tiba ditujuan tidak bisa diedit atau hilang"
-- -- sejalan dengan aturan standing project ini yang berulang kali
-- ditegaskan di sesi-sesi sebelumnya ("admin harus punya fungsi
-- tertinggi", "jangan mencegat flow aplikasi"). Jadi solusinya: BUKA
-- akses baca DAN edit untuk admin di SEMUA status, BUKAN menambah gate.
--
-- KENAPA dicurigai RLS (Row Level Security), BUKAN data hilang/bug logic
-- Flutter: tidak ada satupun kode Flutter yang menghapus/mengubah baris
-- shipment_scans/receiving_details saat status berubah (shipment
-- diberangkatkan ATAU barang ditandai sampai) -- sudah dicek ulang di
-- kode servicenya masing-masing, tidak ada yang menyentuh data itu sama
-- sekali selain field status/timestamp-nya sendiri. Pola gejala ("kerja
-- normal sebelum status berubah, bermasalah setelah status berubah",
-- tanpa satu baris kode pun yang menyentuh datanya) PERSIS SAMA seperti
-- kasus RLS GPS tracking yang pernah ditemukan & diperbaiki sebelumnya
-- di project ini.
--
-- LANGKAH: jalankan SEMUA query di bawah. Postgres RLS meng-OR-kan semua
-- PERMISSIVE policy untuk perintah yang sama -- jadi menambah policy
-- "boleh semua" di bawah ini otomatis MEMBUKA akses tanpa perlu tahu/
-- menghapus nama policy lama yang mungkin sudah ada dan lebih ketat.

-- ------------------------------------------------------------
-- LANGKAH 1 (opsional, buat konfirmasi sebelum fix) -- cek datanya
-- memang masih ada di database, apa pun statusnya.
-- ------------------------------------------------------------
select
  s.shipment_number,
  s.status,
  s.departed_at,
  s.arrived_at,
  count(ss.id) filter (where ss.scan_type = 'LOAD') as jumlah_scan_load,
  count(ss.id) filter (where ss.scan_type = 'DELIVER') as jumlah_scan_deliver
from shipments s
left join shipment_scans ss on ss.shipment_id = s.id
where s.status in ('DEPARTED', 'ARRIVED')
group by s.id, s.shipment_number, s.status, s.departed_at, s.arrived_at
order by coalesce(s.arrived_at, s.departed_at) desc nulls last
limit 20;

-- ------------------------------------------------------------
-- LANGKAH 2 -- FIX: pastikan RLS aktif (aman dijalankan walau sudah
-- aktif) lalu tambahkan policy BACA + EDIT (select/insert/update/
-- delete) TANPA batasan status/pemilik untuk SEMUA user yang sudah
-- login (authenticated) -- mencakup role ADMIN dashboard maupun staff
-- Loading/Driver/Receiving. Ini menutup KEDUA kekhawatiran user: (1)
-- manifest shipment yang sudah berangkat tetap bisa dibuka, (2) barang
-- yang sudah sampai tujuan tetap bisa diedit (fitur "Ubah Harga Admin")
-- dan tidak hilang dari tampilan.
-- ------------------------------------------------------------
alter table shipment_scans enable row level security;
alter table receiving_details enable row level security;
alter table receiving enable row level security;

drop policy if exists "authenticated full access shipment_scans" on shipment_scans;
create policy "authenticated full access shipment_scans"
  on shipment_scans for all
  to authenticated
  using (true)
  with check (true);

drop policy if exists "authenticated full access receiving_details" on receiving_details;
create policy "authenticated full access receiving_details"
  on receiving_details for all
  to authenticated
  using (true)
  with check (true);

drop policy if exists "authenticated full access receiving" on receiving;
create policy "authenticated full access receiving"
  on receiving for all
  to authenticated
  using (true)
  with check (true);

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- LANGKAH 3 (opsional, buat verifikasi lebih lanjut kalau LANGKAH 2
-- ternyata BELUM menyelesaikan masalah) -- lihat SEMUA policy yang ada
-- sekarang di 3 tabel ini, siapa tahu ada policy RESTRICTIVE (beda dari
-- PERMISSIVE, tidak ikut di-OR, malah WAJIB semuanya lolos) yang ikut
-- menghalangi -- kalau ketemu ada yang `permissive = false` di hasil
-- query ini, itu perlu di-DROP manual (nama policy-nya ada di kolom
-- policyname), beri tahu Claude hasilnya di sesi berikutnya.
-- ------------------------------------------------------------
select schemaname, tablename, policyname, cmd, permissive, roles, qual
from pg_policies
where tablename in ('shipment_scans', 'receiving_details', 'receiving')
order by tablename, policyname;
