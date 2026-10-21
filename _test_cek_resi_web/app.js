// ============================================================
// app.js -- logic halaman "Cek Resi" (website publik terpisah)
// ============================================================
//
// Port dari `TrackShipmentPage` (Flutter, lib/features/auth/pages/
// track_shipment_page.dart) -- perilaku/logic dibuat SAMA PERSIS supaya
// hasil yang dilihat customer konsisten, cuma medium-nya beda (website
// statis murni, bukan halaman di dalam app utama).
//
// Website ini CUMA panggil 2 RPC publik Supabase yang SUDAH ada &
// SUDAH digrant ke role `anon` (lihat add_track_shipment_rpc.sql &
// add_public_company_info_rpc.sql di project Flutter):
//   - get_public_company_info()      -- header nama/alamat/telp
//   - track_shipment(p_search)       -- hasil pencarian resi
// TIDAK ADA query langsung ke tabel apa pun -- semua lewat RPC yang
// field keluarannya sudah di-whitelist di sisi database.

(function () {
  'use strict';

  const CONFIG = window.CEK_RESI_CONFIG || {};
  const supabase = window.supabase.createClient(
    CONFIG.SUPABASE_URL,
    CONFIG.SUPABASE_ANON_KEY
  );

  // ------------------------------------------------------------
  // Util format tanggal/jam -- SAMA PERSIS gaya `formatDateId`/
  // `formatTimeId` di app Flutter (bulan Indonesia, TANPA konversi ke
  // timezone lokal browser -- dibaca APA ADANYA dari field UTC yang
  // dikirim Postgres, persis seperti Dart `DateTime.parse(...).hour`
  // tanpa `.toLocal()`). Ini supaya kalau customer & admin lihat jam
  // yang sama, angkanya identik, tidak digeser timezone device masing-
  // masing.
  // ------------------------------------------------------------
  const MONTHS_ID = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  function formatDateId(isoString) {
    if (!isoString) return '';
    const d = new Date(isoString);
    return `${d.getUTCDate()} ${MONTHS_ID[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
  }

  function formatTimeId(isoString) {
    if (!isoString) return '';
    const d = new Date(isoString);
    const hh = String(d.getUTCHours()).padStart(2, '0');
    const mm = String(d.getUTCMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  }

  function fmtQty(value) {
    const n = Number(value) || 0;
    return n % 1 === 0 ? String(n) : String(n);
  }

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str == null ? '' : String(str);
    return div.innerHTML;
  }

  // ------------------------------------------------------------
  // Elements
  // ------------------------------------------------------------
  const el = {
    companyHeader: document.getElementById('companyHeader'),
    companyName: document.getElementById('companyName'),
    companyAddress: document.getElementById('companyAddress'),
    companyPhone: document.getElementById('companyPhone'),

    searchView: document.getElementById('searchView'),
    searchInput: document.getElementById('searchInput'),
    searchButton: document.getElementById('searchButton'),
    searchButtonLabel: document.getElementById('searchButtonLabel'),
    searchError: document.getElementById('searchError'),

    resultView: document.getElementById('resultView'),
    searchAgainButton: document.getElementById('searchAgainButton'),
    resultTitle: document.getElementById('resultTitle'),
    resultDestination: document.getElementById('resultDestination'),
    resultAddress: document.getElementById('resultAddress'),
    resultReceivedAt: document.getElementById('resultReceivedAt'),

    statusIconBox: document.getElementById('statusIconBox'),
    statusIcon: document.getElementById('statusIcon'),
    statusLabel: document.getElementById('statusLabel'),
    statusDescription: document.getElementById('statusDescription'),

    partialBanner: document.getElementById('partialBanner'),

    receivedItemsSection: document.getElementById('receivedItemsSection'),
    receivedItemsCard: document.getElementById('receivedItemsCard'),

    vehiclesSection: document.getElementById('vehiclesSection'),
    vehiclesList: document.getElementById('vehiclesList'),

    mapContainer: document.getElementById('mapContainer'),
    mapEmptyNote: document.getElementById('mapEmptyNote'),
  };

  let leafletMap = null;

  // ------------------------------------------------------------
  // Header perusahaan
  // ------------------------------------------------------------
  async function loadCompanyHeader() {
    try {
      const { data, error } = await supabase.rpc('get_public_company_info');
      if (error || !data || data.found !== true) return;

      if (!data.name) return;

      el.companyName.textContent = data.name;
      if (data.address) el.companyAddress.textContent = data.address;
      if (data.phone) el.companyPhone.textContent = data.phone;
      el.companyHeader.classList.remove('hidden');
    } catch (e) {
      // Diamkan -- header memang opsional, kegagalan di sini tidak
      // boleh menghalangi fitur utama (cek resi).
      console.warn('Gagal memuat info perusahaan:', e);
    }
  }

  // ------------------------------------------------------------
  // Status mapping -- SAMA PERSIS `_statusInfo` di Flutter
  // ------------------------------------------------------------
  function statusInfo(status) {
    switch (status) {
      case 'loading':
        return { label: 'Sedang Dimuat', color: 'var(--orange)', bg: 'rgba(255,166,61,0.12)', icon: '📦', description: 'Barang sedang dimuat ke kendaraan.' };
      case 'berangkat':
        return { label: 'Dalam Perjalanan', color: 'var(--blue)', bg: 'rgba(40,120,240,0.12)', icon: '🚚', description: 'Kendaraan sudah berangkat menuju tujuan.' };
      case 'tiba':
        return { label: 'Sudah Tiba', color: 'var(--green)', bg: 'rgba(25,185,130,0.12)', icon: '✅', description: 'Barang sudah tiba di tujuan.' };
      default:
        return { label: 'Diterima di Kantor', color: 'var(--navy)', bg: 'rgba(16,27,61,0.10)', icon: '📥', description: 'Barang sudah diterima, belum dimuat ke kendaraan.' };
    }
  }

  function itemProgress(item) {
    const quantity = Number(item.quantity) || 0;
    const loaded = Number(item.loadedCount) || 0;
    const delivered = Number(item.deliveredCount) || 0;

    if (quantity <= 0) return { text: '-', color: 'var(--text-secondary)' };
    if (delivered >= quantity) return { text: 'Sudah tiba semua di tujuan.', color: 'var(--green)' };
    if (loaded >= quantity) return { text: 'Sudah dimuat semua, sedang dalam perjalanan.', color: 'var(--blue)' };
    if (loaded > 0) {
      return {
        text: `${fmtQty(loaded)} dari ${fmtQty(quantity)} sudah dimuat -- sisanya (${fmtQty(quantity - loaded)}) masih di kantor/perwakilan (dikirim bertahap).`,
        color: 'var(--orange)',
      };
    }
    return { text: 'Belum dimuat, masih di kantor/perwakilan.', color: 'var(--text-secondary)' };
  }

  // ------------------------------------------------------------
  // Render hasil
  // ------------------------------------------------------------
  function renderResult(data) {
    const receiptNumber = data.receiptNumber || '-';
    const nomorBuku = data.nomorBuku;
    const destination = data.destination || '-';
    const destinationAddress = data.destinationAddress;
    const receivedAt = data.receivedAt;
    const totalQuantity = Number(data.totalQuantity) || 0;
    const loadedQuantity = Number(data.loadedQuantity) || 0;
    const status = data.status || 'diterima';
    const vehicles = Array.isArray(data.vehicles) ? data.vehicles : [];
    const receivedItems = Array.isArray(data.receivedItems) ? data.receivedItems : [];

    el.resultTitle.textContent = nomorBuku ? `${receiptNumber} / ${nomorBuku}` : receiptNumber;
    el.resultDestination.textContent = `Tujuan: ${destination}`;

    if (destinationAddress) {
      el.resultAddress.textContent = `Alamat: ${destinationAddress}`;
      el.resultAddress.classList.remove('hidden');
    } else {
      el.resultAddress.classList.add('hidden');
    }

    if (receivedAt) {
      el.resultReceivedAt.textContent = `Diterima: ${formatDateId(receivedAt)}, pukul ${formatTimeId(receivedAt)}`;
      el.resultReceivedAt.classList.remove('hidden');
    } else {
      el.resultReceivedAt.classList.add('hidden');
    }

    const info = statusInfo(status);
    el.statusIconBox.style.background = info.bg;
    el.statusIcon.textContent = info.icon;
    el.statusLabel.textContent = info.label;
    el.statusLabel.style.color = info.color;
    el.statusDescription.textContent = info.description;

    const isPartial = loadedQuantity < totalQuantity && totalQuantity > 0;
    if (isPartial) {
      const pending = totalQuantity - loadedQuantity;
      el.partialBanner.textContent = `${fmtQty(loadedQuantity)} dari ${fmtQty(totalQuantity)} barang sudah dimuat -- sisanya (${fmtQty(pending)}) masih berada di kantor/perwakilan, belum berangkat.`;
      el.partialBanner.classList.remove('hidden');
    } else {
      el.partialBanner.classList.add('hidden');
    }

    // Detail Barang (Sesuai Penerimaan)
    if (receivedItems.length > 0) {
      el.receivedItemsCard.innerHTML = receivedItems
        .map((item, idx) => {
          const progress = itemProgress(item);
          const divider = idx > 0 ? '<div style="height:1px;background:var(--border);margin:10px 0;"></div>' : '';
          return `
            ${divider}
            <div>
              <div class="item-name">${escapeHtml(item.itemName)} -- ${fmtQty(item.quantity)} ${escapeHtml(item.quantityUnit || '')}</div>
              <div class="item-progress" style="color:${progress.color}">${escapeHtml(progress.text)}</div>
            </div>`;
        })
        .join('');
      el.receivedItemsSection.classList.remove('hidden');
    } else {
      el.receivedItemsSection.classList.add('hidden');
    }

    // Detail Pemuatan (per kendaraan)
    if (vehicles.length > 0) {
      el.vehiclesList.innerHTML = vehicles.map((v) => renderVehicleCard(v)).join('');
      el.vehiclesSection.classList.remove('hidden');
    } else {
      el.vehiclesList.innerHTML = '';
      el.vehiclesSection.classList.add('hidden');
    }

    // Posisi Kendaraan (map)
    renderMap(status, vehicles);

    el.searchView.classList.add('hidden');
    el.resultView.classList.remove('hidden');
  }

  function renderVehicleCard(v) {
    const plate = v.vehicle_plate || '-';
    const driverName = v.driver_name;
    const driverPhone = v.driver_phone;
    const loadedAt = v.loaded_at;
    const items = Array.isArray(v.items) ? v.items : [];

    let html = `<div class="vehicle-card">
      <div class="vehicle-plate-row">🚚 ${escapeHtml(plate)}</div>`;

    if (loadedAt) {
      html += `<div class="vehicle-sub">Mulai dimuat: ${formatDateId(loadedAt)}, pukul ${formatTimeId(loadedAt)}</div>`;
    }

    if (driverName) {
      const driverLine = driverPhone ? `Sopir: ${driverName} (${driverPhone})` : `Sopir: ${driverName}`;
      html += `<div class="vehicle-driver">${escapeHtml(driverLine)}</div>`;
    }

    if (items.length > 0) {
      html += `<div class="vehicle-items-title">Barang yang dimuat:</div>
        <div class="vehicle-items-list">`;
      html += items
        .map((it) => `&bull; ${escapeHtml(it.itemName)} -- ${fmtQty(it.loadedCount)} ${escapeHtml(it.quantityUnit || '')}`)
        .join('<br>');
      html += `</div>`;
    }

    html += `</div>`;
    return html;
  }

  function renderMap(status, vehicles) {
    if (leafletMap) {
      leafletMap.remove();
      leafletMap = null;
    }
    el.mapContainer.innerHTML = '';

    if (status === 'diterima') {
      showMapEmptyNote('Barang masih diterima di kantor, belum dimuat ke kendaraan -- peta posisi akan muncul setelah barang mulai dimuat.');
      return;
    }
    if (status === 'tiba') {
      showMapEmptyNote('Barang sudah tiba di tujuan -- perjalanan selesai.');
      return;
    }

    const markers = vehicles
      .filter((v) => v.latitude != null && v.longitude != null)
      .map((v) => ({
        lat: Number(v.latitude),
        lng: Number(v.longitude),
        label: v.vehicle_plate || '-',
      }));

    if (markers.length === 0) {
      showMapEmptyNote('Kendaraan belum mengirim titik lokasi terbaru. Coba cek lagi beberapa saat lagi.');
      return;
    }

    el.mapEmptyNote.classList.add('hidden');
    el.mapContainer.classList.remove('hidden');

    const center = [markers[0].lat, markers[0].lng];
    const zoom = markers.length > 1 ? 10 : 13;

    leafletMap = L.map(el.mapContainer).setView(center, zoom);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19,
    }).addTo(leafletMap);

    markers.forEach((m) => {
      L.marker([m.lat, m.lng])
        .addTo(leafletMap)
        .bindPopup(`<b>${escapeHtml(m.label)}</b><br>${m.lat.toFixed(6)}, ${m.lng.toFixed(6)}`);
    });
  }

  function showMapEmptyNote(message) {
    el.mapContainer.classList.add('hidden');
    el.mapEmptyNote.textContent = message;
    el.mapEmptyNote.classList.remove('hidden');
  }

  // ------------------------------------------------------------
  // Search
  // ------------------------------------------------------------
  async function doSearch() {
    const value = el.searchInput.value.trim();

    el.searchError.classList.add('hidden');

    if (!value) {
      el.searchError.textContent = 'Masukkan nomor resi atau nomor buku dulu.';
      el.searchError.classList.remove('hidden');
      return;
    }

    el.searchButton.disabled = true;
    el.searchButtonLabel.textContent = 'Mencari...';

    try {
      const { data, error } = await supabase.rpc('track_shipment', { p_search: value });

      if (error) throw error;

      if (!data || data.found !== true) {
        el.searchError.textContent = `Nomor Resi/Nomor Buku "${escapeHtml(value)}" tidak ditemukan. Periksa kembali penulisannya.`;
        el.searchError.classList.remove('hidden');
        return;
      }

      renderResult(data);
    } catch (e) {
      console.error('Gagal cek resi:', e);
      el.searchError.textContent = 'Gagal memeriksa status kiriman. Coba lagi nanti.';
      el.searchError.classList.remove('hidden');
    } finally {
      el.searchButton.disabled = false;
      el.searchButtonLabel.textContent = 'Cari Status Kiriman';
    }
  }

  function searchAgain() {
    el.resultView.classList.add('hidden');
    el.searchView.classList.remove('hidden');
    el.searchInput.value = '';
    el.searchError.classList.add('hidden');
    el.searchInput.focus();
  }

  // ------------------------------------------------------------
  // Wiring
  // ------------------------------------------------------------
  el.searchButton.addEventListener('click', doSearch);
  el.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') doSearch();
  });
  el.searchAgainButton.addEventListener('click', searchAgain);

  loadCompanyHeader();
})();
