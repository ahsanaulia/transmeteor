-- Aktifkan Supabase Realtime (Postgres Changes) untuk semua tabel yang
-- dipakai RealtimeSyncService (lib/services/realtime_sync_service.dart).
--
-- WAJIB DIJALANKAN supaya fitur "realtime, tidak perlu refresh manual"
-- benar-benar jalan -- tanpa ini, kode Flutter-nya tetap subscribe ke
-- channel realtime tapi TIDAK PERNAH menerima event apa pun (tabel belum
-- terdaftar di publication `supabase_realtime`), jadi kelihatannya diam
-- saja tanpa error.
--
-- Aman dijalankan berkali-kali (idempotent) -- tiap ALTER PUBLICATION
-- dibungkus supaya tidak error kalau tabelnya sudah pernah didaftarkan
-- sebelumnya (mis. lewat toggle "Enable Realtime" di Supabase Dashboard).
--
-- CATATAN: kalau Row Level Security (RLS) aktif di salah satu tabel ini,
-- Supabase Realtime cuma mengirim event untuk baris yang boleh di-SELECT
-- oleh role yang sedang login (authenticated/anon) sesuai policy RLS
-- tabel itu. Kalau setelah ini ada tabel yang tetap tidak realtime,
-- cek dulu RLS policy SELECT-nya.

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.employees;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_roles;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.company;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicles;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.shipments;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.shipment_scans;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.shipment_expenses;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.shipment_location_pings;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.receiving;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.receiving_details;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.item_types;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.package_types;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.pricing_types;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.route_pricing;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.senders;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- representatives -- tabel baru (6 Oktober 2026 lanjutan, fitur
-- "Selesaikan di Perwakilan"). Sudah didaftarkan juga di
-- `add_representatives_table.sql` sendiri -- baris ini cuma supaya
-- script "jalankan semua tabel sekali lagi" ini tetap lengkap/konsisten
-- kalau dipakai ulang di kemudian hari.
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.representatives;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
