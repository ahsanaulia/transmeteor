-- Kolom baru buat fitur "Intervensi Admin: Mulai Paksa Perjalanan" --
-- admin (otoritas tertinggi) bisa menandai trip_started_at secara manual
-- kalau sopir lupa menekan "Mulai Perjalanan" di aplikasinya padahal
-- kendaraan sudah fisik meninggalkan gudang. Mirror pola kolom
-- completed_by_admin/admin_completion_note di
-- add_admin_force_complete_shipment.sql, tapi untuk ujung AWAL
-- perjalanan (bukan ujung akhir).
alter table public.shipments
  add column if not exists trip_started_by_admin boolean not null default false;

alter table public.shipments
  add column if not exists admin_start_trip_note text;

notify pgrst, 'reload schema';
