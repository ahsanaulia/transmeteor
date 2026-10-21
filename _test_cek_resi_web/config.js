// ============================================================
// KONFIGURASI -- WAJIB DIISI SEBELUM DEPLOY
// ============================================================
//
// Isi 2 nilai di bawah dengan punya project Supabase Anda:
//   - SUPABASE_URL  : Project Settings -> API -> "Project URL"
//   - SUPABASE_ANON_KEY : Project Settings -> API -> "anon public" key
//
// AMAN untuk dipasang di website publik (anon key MEMANG dibuat untuk
// dipasang di sisi client/browser) -- selama hanya 2 RPC yang dipakai
// website ini (`track_shipment`, `get_public_company_info`) yang
// digrant ke role `anon`, dan TIDAK ADA tabel lain yang bisa dibaca
// langsung oleh anon (lihat README.md bagian "Keamanan" untuk cara
// mengecek ini di project Supabase Anda).
//
// JANGAN PERNAH isi "service_role key" di sini -- itu key RAHASIA yang
// punya akses PENUH ke semua data, beda dengan "anon public" key.
window.CEK_RESI_CONFIG = {
  SUPABASE_URL: 'https://qcvrmntgotsvigkgoyge.supabase.co',
  SUPABASE_ANON_KEY:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFjdnJtbnRnb3Rzdmlna2dveWdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY2NTY2MDMsImV4cCI6MjEwMjIzMjYwM30.lxcp6DbLUa9KmN8256pxEVEfIcAXGZQAyGutXHOURfs',
};
