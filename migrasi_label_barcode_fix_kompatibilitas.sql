-- ============================================================
-- FIX KOMPATIBILITAS (21 Oktober 2026) -- jalankan SETELAH
-- `migrasi_label_barcode.sql` (yang sudah pernah dijalankan sebelumnya).
-- ============================================================
--
-- MASALAH: `migrasi_label_barcode.sql` mengubah `is_unlabeled` jadi
-- GENERATED COLUMN (tidak bisa ditulis langsung lagi, nilainya
-- diturunkan otomatis dari `label_type`). Niatnya supaya kode LAMA yang
-- masih MEMBACA is_unlabeled tetap jalan tanpa diubah -- tapi ternyata
-- app yang SEDANG BERJALAN (build SEBELUM sesi ini) juga MENULIS
-- is_unlabeled (ikut terkirim di payload update setiap kali save,
-- walau yang diubah user cuma field lain seperti total harga) --
-- Postgres MENOLAK dengan error:
--   "column is_unlabeled can only be updated to DEFAULT"
--
-- PERMINTAAN USER (eksplisit): jangan sampai app lama yang masih
-- berjalan jadi error. `label_type` boleh/harus tetap ada sebagai
-- TAMBAHAN kolom, tapi kolom is_unlabeled yang SUDAH ADA sebelumnya
-- TIDAK BOLEH diubah perilakunya (harus tetap bisa ditulis langsung
-- seperti sebelum migrasi label_type ada).
--
-- FIX: kembalikan `is_unlabeled` jadi kolom BIASA (bisa ditulis lagi,
-- SAMA SEPERTI SEBELUM `migrasi_label_barcode.sql`). `label_type` TETAP
-- ADA (tidak dihapus/diubah). Trigger di bawah menjaga is_unlabeled &
-- label_type SELALU sinkron otomatis, dari arah mana pun yang menulis:
--   - App LAMA (cuma tahu is_unlabeled, TIDAK tahu "BARCODE"): menulis
--     is_unlabeled -> label_type ikut disesuaikan (QR <-> TANPA_LABEL).
--   - App BARU (menulis label_type, termasuk opsi "BARCODE"):
--     is_unlabeled ikut diturunkan ulang dari label_type.
--   - Baris yang label_type-nya "BARCODE" SENGAJA DILINDUNGI dari app
--     lama: app lama tidak akan pernah menurunkan baris BARCODE balik
--     ke QR/TANPA_LABEL cuma karena ikut menulis is_unlabeled=false di
--     payload save-nya (app lama tidak tahu bedanya BARCODE vs QR, dua2
--     nya terbaca is_unlabeled=false).
--
-- Aman dijalankan berkali-kali (idempotent).

-- ------------------------------------------------------------
-- 1. Kembalikan is_unlabeled jadi kolom biasa (kalau saat ini masih
--    GENERATED dari migrasi sebelumnya).
-- ------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'receiving_details'
      and column_name = 'is_unlabeled' and is_generated = 'ALWAYS'
  ) then
    alter table public.receiving_details drop column is_unlabeled;
    alter table public.receiving_details
      add column is_unlabeled boolean not null default false;

    update public.receiving_details
    set is_unlabeled = (label_type = 'TANPA_LABEL');
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. Trigger penyinkron 2 arah (is_unlabeled <-> label_type).
-- ------------------------------------------------------------
create or replace function public.sync_receiving_detail_label_type()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    -- Baris baru: kalau pemanggil (app lama) cuma kirim is_unlabeled
    -- TANPA label_type sama sekali, label_type sudah terisi default
    -- 'QR' lewat kolom default -- turunkan jadi TANPA_LABEL kalau
    -- is_unlabeled true.
    if new.label_type = 'QR' and new.is_unlabeled then
      new.label_type := 'TANPA_LABEL';
    end if;
  else
    if new.label_type is distinct from old.label_type then
      -- Pemanggil (app baru) menulis label_type secara eksplisit --
      -- ikuti apa adanya, apa pun nilai is_unlabeled yang (mungkin
      -- ikut) terkirim di payload yang sama.
      null;
    elsif old.label_type = 'BARCODE' then
      -- Lindungi baris BARCODE dari app lama (yang tidak tahu opsi ini
      -- & bisa saja ikut menulis is_unlabeled=false di payload save
      -- untuk field lain) -- JANGAN diturunkan balik ke QR/TANPA_LABEL.
      new.label_type := old.label_type;
    elsif new.is_unlabeled is distinct from old.is_unlabeled then
      -- Pemanggil (app lama) menulis is_unlabeled secara eksplisit --
      -- turunkan label_type dari situ, SAMA seperti perilaku sebelum
      -- label_type ada.
      new.label_type := case when new.is_unlabeled then 'TANPA_LABEL' else 'QR' end;
    end if;
  end if;

  -- is_unlabeled SELALU disamakan dengan label_type final -- supaya
  -- app lama yang cuma MEMBACA is_unlabeled tetap melihat nilai yang
  -- benar, persis seperti waktu masih generated column.
  new.is_unlabeled := (new.label_type = 'TANPA_LABEL');
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_sync_receiving_detail_label_type on public.receiving_details;
create trigger trg_sync_receiving_detail_label_type
before insert or update on public.receiving_details
for each row execute function public.sync_receiving_detail_label_type();

notify pgrst, 'reload schema';

-- ============================================================
-- CATATAN UNTUK USER
-- ============================================================
-- - Setelah fix ini, app yang SEDANG BERJALAN (build lama, sebelum
--   fitur Label Barcode) bisa langsung dipakai lagi TANPA error --
--   TIDAK perlu buru-buru rebuild.
-- - App BARU (source code sekarang, dengan fitur "Label Barcode")
--   tetap berjalan normal seperti sebelum fix ini -- fix ini HANYA
--   mengubah perilaku di level database, tidak ada kode Flutter yang
--   perlu diubah lagi untuk fix ini.
-- - Satu pengecualian (risiko kecil, bukan bug baru): kalau barang yang
--   sudah dipasang Label Barcode (label_type = 'BARCODE') diedit lewat
--   app LAMA (misal admin ubah harga lewat Monitoring Resi versi lama),
--   label_type-nya TETAP 'BARCODE' (dilindungi trigger di atas) -- tapi
--   sebaiknya edit barang seperti itu pakai app yang sudah di-rebuild
--   begitu sempat, supaya semua tampilan (termasuk badge "Label
--   Barcode") konsisten.
