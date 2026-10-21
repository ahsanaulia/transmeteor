-- Kolom baru buat fitur "Intervensi Admin: Selesaikan Perjalanan" --
-- admin (otoritas tertinggi) bisa menandai shipment ARRIVED secara
-- manual kalau sopir mengalami kendala aplikasi di lapangan (HP rusak,
-- hilang sinyal, dll) dan tidak bisa menekan "Sudah Kembali ke Kantor"
-- sendiri lewat aplikasinya.
alter table public.shipments
  add column if not exists completed_by_admin boolean not null default false;

alter table public.shipments
  add column if not exists admin_completion_note text;

notify pgrst, 'reload schema';
