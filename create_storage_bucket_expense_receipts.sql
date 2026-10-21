-- FIX: error "StorageException: new row violates row-level security
-- policy" saat menerima barang (upload foto untuk item "Tanpa Label QR").
--
-- SEBAB: kode (ReceivingService.uploadItemPhoto, juga dipakai
-- CompanyService.uploadLogo & ExpenseService.uploadReceiptPhoto) numpang
-- ke bucket Storage bernama "expense-receipts" dengan asumsi bucket ini
-- SUDAH ADA & sudah public (lihat catatan di create_company_table.sql,
-- 22 September 2026). Ternyata di project Supabase yang dipakai sekarang
-- bucket ini belum pernah benar-benar dibuat -- jadi insert ke
-- storage.objects ditolak oleh RLS (tidak ada bucket = tidak ada policy
-- yang mengizinkan = default DENY), bukan error "Bucket not found".
--
-- JALANKAN script ini SEKALI di Supabase Dashboard > SQL Editor (project
-- yang sedang dipakai aplikasi), lalu coba lagi proses terima barang --
-- TIDAK perlu rebuild/hot-restart aplikasi Flutter, ini perubahan di sisi
-- Supabase saja.

-- 1) Bikin bucket-nya (public, supaya getPublicUrl() bisa diakses
--    langsung tanpa signed URL -- dipakai utk preview foto & cetak PDF).
insert into storage.buckets (id, name, public)
values ('expense-receipts', 'expense-receipts', true)
on conflict (id) do update set public = true;

-- 2) Policy akses untuk tabel storage.objects, DIBATASI hanya ke bucket
--    ini (bucket_id = 'expense-receipts') supaya tidak membuka akses ke
--    bucket lain yang mungkin ada.
--    - SELECT: semua orang boleh baca (perlu, karena bucket public dan
--      link foto ditampilkan di preview/cetak tanpa login).
--    - INSERT: boleh upload foto baru (anon ATAU authenticated, karena
--      aplikasi ini belum pasti pakai Supabase Auth per-user -- kalau
--      nanti ditambah Auth, policy ini tetap jalan).
--    - UPDATE/DELETE: jaga-jaga untuk fitur hapus/ganti foto di masa
--      depan.

drop policy if exists "expense-receipts read" on storage.objects;
create policy "expense-receipts read"
on storage.objects for select
using (bucket_id = 'expense-receipts');

drop policy if exists "expense-receipts insert" on storage.objects;
create policy "expense-receipts insert"
on storage.objects for insert
to anon, authenticated
with check (bucket_id = 'expense-receipts');

drop policy if exists "expense-receipts update" on storage.objects;
create policy "expense-receipts update"
on storage.objects for update
to anon, authenticated
using (bucket_id = 'expense-receipts')
with check (bucket_id = 'expense-receipts');

drop policy if exists "expense-receipts delete" on storage.objects;
create policy "expense-receipts delete"
on storage.objects for delete
to anon, authenticated
using (bucket_id = 'expense-receipts');
