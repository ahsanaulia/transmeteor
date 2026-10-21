-- ============================================================
-- AUTO-RECALCULATE TOTAL RECEIVING
-- ============================================================
-- Menjaga `receiving.total_quantity` dan `receiving.total_price` tetap
-- akurat setiap kali baris di `receiving_details` ditambah, diubah,
-- atau dihapus -- termasuk kalau datanya diubah langsung dari Supabase
-- Studio / SQL, bukan cuma lewat aplikasi Flutter.
--
-- Jalankan file ini sekali di Supabase SQL Editor (Database > SQL Editor).
--
-- Setelah trigger ini aktif, method `_refreshReceivingTotals()` di
-- `receiving_service.dart` sudah tidak diperlukan lagi -- perhitungan
-- total dipindah sepenuhnya ke database.
-- ============================================================

create or replace function recalculate_receiving_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receiving_id uuid;
  v_total_quantity numeric;
  v_total_price numeric;
begin
  if tg_op = 'DELETE' then
    v_receiving_id := old.receiving_id;
  else
    v_receiving_id := new.receiving_id;
  end if;

  select
    coalesce(sum(quantity), 0),
    coalesce(sum(total_price), 0)
  into v_total_quantity, v_total_price
  from receiving_details
  where receiving_id = v_receiving_id;

  update receiving
  set
    total_quantity = v_total_quantity::int,
    total_price = v_total_price,
    updated_at = now()
  where id = v_receiving_id;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_receiving_details_recalculate on receiving_details;

create trigger trg_receiving_details_recalculate
after insert or update or delete on receiving_details
for each row
execute function recalculate_receiving_totals();

-- ============================================================
-- CATATAN
-- ============================================================
-- 1. `security definer` dipakai supaya trigger bisa meng-update tabel
--    `receiving` walaupun RLS policy user yang login tidak mengizinkan
--    UPDATE langsung ke tabel tersebut. Pastikan function ini dibuat
--    oleh role yang memang berhak (biasanya `postgres` / owner project),
--    yang otomatis terjadi kalau dijalankan lewat SQL Editor Supabase.
-- 2. Trigger jalan per-baris (FOR EACH ROW). Untuk pemakaian normal
--    (tambah barang satu-satu di form) ini tidak masalah. Kalau nanti
--    ada fitur bulk-insert banyak baris sekaligus, pertimbangkan ganti
--    ke statement-level trigger dengan `transition table` supaya cuma
--    hitung ulang sekali per statement, bukan per baris.
