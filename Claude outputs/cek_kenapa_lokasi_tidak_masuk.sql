-- ============================================================
-- DIAGNOSTIK: kenapa shipment_location_pings tidak pernah terisi
-- ============================================================
-- Jalankan SATU PER SATU di Supabase SQL Editor, lihat hasilnya sebelum
-- lanjut ke query berikutnya.

-- 1) Apakah Row Level Security aktif di tabel ini?
select relname, relrowsecurity as rls_aktif
from pg_class
where relname = 'shipment_location_pings';

-- 2) Kalau rls_aktif = true, apakah ADA policy yang mengizinkan INSERT?
--    Kalau query ini kosong (tidak ada baris) padahal rls_aktif = true,
--    itu artinya SEMUA insert dari aplikasi (termasuk dari HP sopir)
--    DITOLAK diam-diam oleh Postgres -- ini penyebab paling mungkin,
--    karena kode Flutter sebelumnya menelan pesan error itu tanpa
--    menampilkannya ke mana pun (sudah diperbaiki, lihat catatan di bawah).
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'shipment_location_pings';

-- 3) Cek juga tabel shipments -- pastikan shipment SHP000009 (dari
--    screenshot) statusnya memang DEPARTED dan trip_started_at SUDAH
--    terisi (artinya sopir benar sudah menekan "Mulai Perjalanan").
--    Kalau trip_started_at MASIH NULL, berarti sopir belum pernah
--    menekan tombol itu / tombolnya gagal di tengah jalan -- beda kasus,
--    bukan soal RLS.
select shipment_number, status, trip_started_at, driver_employee_id
from shipments
where shipment_number = 'SHP000009';

-- 4) Setelah build baru (yang sudah menampilkan pesan error di kartu
--    tracking Driver) dipasang & dicoba di HP: cek langsung apakah
--    barisnya benar-benar masuk.
select *
from shipment_location_pings
order by recorded_at desc
limit 20;

-- ============================================================
-- KALAU langkah 2 di atas terbukti (RLS aktif, TIDAK ada policy INSERT)
-- ============================================================
-- Baru jalankan bagian ini. Aplikasi ini internal 1 perusahaan (semua
-- user sudah login sebagai pegawai), jadi policy paling sederhana &
-- aman: SEMUA user yang sudah login (authenticated) boleh insert titik
-- lokasi & baca semua titik lokasi (dipakai admin di Monitoring).

alter table public.shipment_location_pings enable row level security;

drop policy if exists "authenticated can insert location pings" on public.shipment_location_pings;
create policy "authenticated can insert location pings"
on public.shipment_location_pings
for insert
to authenticated
with check (true);

drop policy if exists "authenticated can read location pings" on public.shipment_location_pings;
create policy "authenticated can read location pings"
on public.shipment_location_pings
for select
to authenticated
using (true);
