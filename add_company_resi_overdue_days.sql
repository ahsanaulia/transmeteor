-- Kolom ambang hari "resi terlambat" di tabel `company` (16 Oktober 2026,
-- permintaan user eksplisit): "Pada daftar Resi baik di Admin maupun
-- Supervisor, harus berwarna Merah (kotaknya) atau garis kotaknya jika
-- Resi tersebut lewat dari xx hari dari hari ini. xx hari adalah nilai
-- yang diinput di tabel company."
--
-- LINGKUP (klarifikasi user): kotak merah HANYA untuk resi yang
-- statusnya masih "Penerimaan" (belum pernah dimuat/di-loading sama
-- sekali) -- dihitung dari HARI INI dikurangi `receiving.received_at`
-- (tanggal resi diterima). Resi yang sudah "Masih Perjalanan" atau
-- "Selesai" TIDAK PERNAH ditandai merah lewat fitur ini, berapa pun
-- lama usianya -- lihat perhitungan di Flutter (`ReceivingListPage`
-- Admin & `SupervisorResiTab` Supervisor).
--
-- Diisi/diubah lewat halaman Admin "Profil Perusahaan" (field baru
-- "Batas Hari Resi Terlambat"), BUKAN konstanta di kode -- supaya
-- ambang harinya bisa disesuaikan tanpa build ulang app, sama seperti
-- `gps_ping_interval_seconds`.

alter table public.company
  add column if not exists resi_overdue_days integer not null default 3;

comment on column public.company.resi_overdue_days is
  'Ambang hari (dari tanggal resi diterima, received_at) sebelum resi '
  'yang masih berstatus Penerimaan (belum pernah di-loading) ditandai '
  'TERLAMBAT (kotak/garis kotak merah) di Monitoring Resi Admin & '
  'Supervisor. Diisi admin lewat halaman Profil Perusahaan. Default 3 '
  'hari untuk baris lama yang belum sempat mengisi nilai ini.';

notify pgrst, 'reload schema';
