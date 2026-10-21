-- WAJIB DIJALANKAN sebelum build Flutter terbaru dites (fix 5 Oktober
-- 2026: nomor HP tujuan sekarang live-join dari tabel `destinations`,
-- bukan snapshot lagi).
--
-- Query Flutter yang baru makai bentuk embed PostgREST:
--   .select('*, destinations:destination_id(phone)')
-- Ini HANYA bisa jalan kalau ada FOREIGN KEY dari
-- `receiving.destination_id` ke `destinations.id` di skema database --
-- kalau belum ada, SEMUA query resi (buka daftar resi, detail resi, buat
-- resi baru, dll -- hampir seluruh fitur Receiving) akan error
-- "Could not find a relationship between 'receiving' and 'destinations'
-- in the schema cache".
--
-- Script ini AMAN dijalankan meskipun FK-nya SUDAH ADA (dicek dulu lewat
-- IF NOT EXISTS, tidak akan error "constraint already exists") -- jadi
-- jalankan saja ini SEKALI sebelum testing, untuk jaga-jaga.

do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
      and tc.table_schema = kcu.table_schema
    where tc.table_schema = 'public'
      and tc.table_name = 'receiving'
      and tc.constraint_type = 'FOREIGN KEY'
      and kcu.column_name = 'destination_id'
  ) then
    alter table public.receiving
      add constraint receiving_destination_id_fkey
      foreign key (destination_id)
      references public.destinations (id)
      on delete set null;
  end if;
end $$;

-- WAJIB -- supaya PostgREST langsung kenal relasi baru/yang sudah ada
-- ini tanpa perlu restart project Supabase.
notify pgrst, 'reload schema';
