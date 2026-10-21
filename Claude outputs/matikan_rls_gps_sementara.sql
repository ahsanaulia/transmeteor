-- Matikan RLS sementara di shipment_location_pings untuk uji coba GPS --
-- supaya RLS tidak ikut jadi variabel pengganggu selagi menguji perbaikan
-- LateInitializationError (akar masalah sebenarnya, lihat penjelasan chat).
-- Policy insert/select yang sudah dibuat sebelumnya TETAP ADA (tidak
-- dihapus), cuma tidak dipaksakan selama RLS mati.
alter table public.shipment_location_pings disable row level security;

-- ============================================================
-- NANTI kalau tracking sudah terbukti jalan normal (titik lokasi masuk
-- terus tanpa error), NYALAKAN LAGI row level security -- jangan
-- dibiarkan mati permanen di data produksi:
-- ============================================================
-- alter table public.shipment_location_pings enable row level security;
