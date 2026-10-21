-- FIX: nomor HP tujuan tidak muncul di "Tanda Terima Tujuan" untuk RESI
-- LAMA, walau nomor HP-nya sudah diisi di tabel `destinations` (halaman
-- "Kelola Daftar Tujuan") -- dikonfirmasi user (5 Oktober 2026).
--
-- SEBAB: `receiving.destination_phone` adalah SNAPSHOT yang disalin dari
-- `destinations.phone` HANYA SEKALI, pas resi itu pertama kali dibuat
-- (lihat `receiving_create_page.dart` & catatan di
-- `ReceivingModel.destinationPhone`, mengikuti pola migrasi
-- `fix_penerima_tujuan_ambiguity.sql`). Resi yang dibuat SEBELUM nomor HP
-- diisi di tabel `destinations` otomatis punya `destination_phone` kosong
-- selamanya, kecuali di-backfill manual seperti ini.
--
-- JALANKAN SEKALI di Supabase Dashboard > SQL Editor. AMAN dijalankan
-- berkali-kali (idempotent) -- hanya mengisi baris `receiving` yang
-- `destination_phone`-nya MASIH KOSONG, dan HANYA kalau `destinations`
-- sekarang punya nomor HP untuk tujuan itu. TIDAK PERNAH menimpa nomor
-- HP yang sudah terisi (jadi kalau ada resi lama yang sudah sengaja
-- diisi manual beda dari master, nilainya tetap aman).
--
-- TIDAK perlu rebuild/hot-restart aplikasi Flutter -- ini perubahan data
-- di sisi Supabase saja. Setelah dijalankan, buka ulang preview "Tanda
-- Terima Tujuan" untuk resi lama tsb (tidak perlu cetak ulang resi-nya).

update public.receiving r
set
  destination_phone = d.phone,
  updated_at = now()
from public.destinations d
where
  r.destination_id = d.id
  and (r.destination_phone is null or r.destination_phone = '')
  and d.phone is not null
  and d.phone <> '';

notify pgrst, 'reload schema';
