-- Tabel profil perusahaan -- HANYA 1 baris (bukan tabel master multi-row),
-- dipakai sebagai kop di semua cetakan (resi, manifest, daftar resi per
-- tujuan). Diisi/diubah lewat halaman Admin "Profil Perusahaan".

create table if not exists public.company (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'TRANS',
  address text,
  phone text,
  logo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Baris default -- kalau tabel masih kosong, insert 1 baris awal supaya
-- aplikasi selalu punya data buat dibaca/diupdate (bukan insert baru
-- tiap kali disimpan, tapi update baris ini).
insert into public.company (name)
select 'TRANS'
where not exists (select 1 from public.company);

notify pgrst, 'reload schema';

-- CATATAN (diperbarui 22 September 2026): upload logo perusahaan TIDAK
-- LAGI butuh bucket Storage baru. Awalnya kode minta bucket baru bernama
-- "company-assets" yang harus dibuat manual dulu di Supabase Dashboard --
-- langkah manual itu ternyata belum sempat dilakukan, jadi tiap upload
-- logo lewat tombol "Pilih Logo"/"Ganti Logo" di halaman Admin "Profil
-- Perusahaan" gagal diam-diam (error "Bucket not found"). Sekarang
-- CompanyService.uploadLogo numpang ke bucket "expense-receipts" yang
-- SUDAH ADA & sudah public (dipakai fitur bukti pengeluaran), disimpan
-- di folder "company-logos/" di dalamnya supaya tetap rapi terpisah --
-- TIDAK ADA lagi setup manual yang perlu dilakukan di Supabase Dashboard.
