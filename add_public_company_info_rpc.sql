-- ============================================================
-- INFO PERUSAHAAN PUBLIK untuk header halaman "Telusuri Kiriman" (8
-- Oktober 2026, lanjutan lagi dari fitur "Telusuri Kiriman" poin 11)
-- ============================================================
--
-- Permintaan user: tampilkan Nama Perusahaan, Alamat, dan No. Telepon di
-- bagian ATAS halaman "Telusuri Kiriman" (`TrackShipmentPage`) -- halaman
-- ini dibuka TANPA login (sesi anon, sama seperti `track_shipment`), dan
-- header ini harus tetap tampil baik SEBELUM maupun SETELAH customer
-- melakukan pencarian resi (bukan bagian dari hasil pencarian).
--
-- SENGAJA dibuat function PUBLIK terpisah (SECURITY DEFINER) daripada
-- query langsung `_client.from('company').select()` seperti yang dipakai
-- `CompanyService.getCompany()` di sisi staff/admin yang SUDAH login --
-- alasannya SAMA PERSIS dengan `track_shipment`: RLS tabel `company`
-- TIDAK DIJAMIN mengizinkan baca anon (kalau nanti RLS diaktifkan,
-- `CompanyService.getCompany()` yang dipanggil dari sesi anon bisa diam-
-- diam balik null/error), dan function ini SENGAJA cuma mem-whitelist 3
-- field yang memang diminta tampil (nama/alamat/telepon perusahaan
-- sendiri -- bukan data sensitif), TIDAK ikut field lain di tabel
-- `company` seperti `company_track`/`gps_ping_interval_seconds`/
-- `logo_url` yang tidak diminta ditampilkan di header ini.
create or replace function public.get_public_company_info()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_address text;
  v_phone text;
begin
  -- Ambil baris PERTAMA (`order by created_at asc limit 1`) -- SAMA
  -- PERSIS logic `CompanyService.getCompany()`, karena tabel `company`
  -- di app ini memang selalu cuma diisi 1 baris (profil perusahaan
  -- tunggal, dari SQL setup awal).
  select name, address, phone
    into v_name, v_address, v_phone
  from company
  order by created_at asc
  limit 1;

  if v_name is null then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'name', v_name,
    'address', v_address,
    'phone', v_phone
  );
end;
$$;

-- Izinkan dipanggil TANPA login (anon) DAN sudah login (authenticated) --
-- sama seperti `track_shipment`, fungsi sendiri yang menjaga field apa
-- saja yang keluar (lihat whitelist di jsonb_build_object di atas).
grant execute on function public.get_public_company_info() to anon;
grant execute on function public.get_public_company_info() to authenticated;
