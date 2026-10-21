import '../core/services/supabase_service.dart';
import '../models/vehicle_model.dart';

class VehicleService {
  static final _client = SupabaseService.client;

  /// Semua kendaraan yang SUDAH DISIAPKAN Admin (is_active=true) DAN
  /// BELUM diberangkatkan (is_loading=true).
  ///
  /// **DIKEMBALIKAN (13 Oktober 2026, permintaan user eksplisit:
  /// "Kembalikan perubahan, bahwa kendaraan harus disiapkan oleh admin
  /// baru muncul di loading")** -- fitur 10 Oktober 2026 yang membuat
  /// SEMUA kendaraan tampil apa adanya di "Pilih Kendaraan" Loading
  /// (terlepas sudah disiapkan atau belum) DIBATALKAN. is_active
  /// KEMBALI berarti "sudah disiapkan Admin lewat 'Siapkan Kendaraan'
  /// (`prepareVehicle`, sopir sudah ditentukan)" -- kendaraan baru
  /// (`createVehicle`, default is_active=false SEKARANG) dan kendaraan
  /// yang baru selesai 1 perjalanan (`ShipmentService.returnToOffice`/
  /// `forceCompleteByAdmin`, is_active otomatis di-set false lagi
  /// SEKARANG) TIDAK tampil di sini sampai Admin menyiapkannya (ulang).
  ///
  /// **DITAMBAH filter `is_loading=true` (21 Oktober 2026, permintaan
  /// user eksplisit: "kendaraan yang sama di menu Daftar Muatan (admin).
  /// Ini benar. Hanya kendaraan yang sedang dimuat yang muncul ... Hal
  /// yang sama harus dilakukan di daftar pilih kendaraan di Loading")**
  /// -- SEBELUMNYA kendaraan yang SUDAH diberangkatkan (status shipment
  /// DEPARTED) TETAP muncul di sini selama is_active masih true (supaya
  /// bisa "lanjutkan muat"). SEKARANG disamakan dengan "Daftar Muatan"
  /// (`shipmentsLoadingProvider`, filter `status == 'LOADING'`): begitu
  /// kendaraan diberangkatkan (`is_loading` jadi false, lihat doc comment
  /// `VehicleService.setLoading`), kendaraan itu HILANG dari "Pilih
  /// Kendaraan" juga -- TIDAK bisa lagi dibuka utk tambah muatan lewat
  /// halaman ini (beda dari perilaku lama).
  static Future<List<VehicleModel>> getVehicles() async {
    final response = await _client
        .from('vehicles')
        .select()
        .eq('is_active', true)
        .eq('is_loading', true)
        .order('plate_number', ascending: true);

    return (response as List)
        .map((data) => VehicleModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }

  /// SEMUA kendaraan (termasuk yang belum disiapkan/dinonaktifkan) --
  /// dipakai di halaman admin "Siapkan Kendaraan", dan di
  /// ShipmentListPage supaya shipment lama tetap bisa ditemukan data
  /// kendaraannya.
  static Future<List<VehicleModel>> getAllVehicles() async {
    final response = await _client
        .from('vehicles')
        .select()
        .order('plate_number', ascending: true);

    return (response as List)
        .map((data) => VehicleModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }

  /// Kendaraan yang disiapkan Admin untuk employee ini sebagai SOPIR
  /// (is_active=true). Dipakai DriverHomePage untuk kartu "Mobil Anda
  /// sudah disiapkan, tunggu Loading mulai muat" saat belum ada shipment.
  static Future<VehicleModel?> getPreparedVehicleForDriver(
    String employeeId,
  ) async {
    final response = await _client
        .from('vehicles')
        .select()
        .eq('driver_employee_id', employeeId)
        .eq('is_active', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return VehicleModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Kendaraan yang disiapkan Admin untuk employee ini sebagai salah
  /// satu HELPER (is_active=true). Dipakai HelperHomePage untuk kartu
  /// yang sama seperti getPreparedVehicleForDriver.
  static Future<VehicleModel?> getPreparedVehicleForHelper(
    String employeeId,
  ) async {
    final response = await _client
        .from('vehicles')
        .select()
        .or(
          'helper1_employee_id.eq.$employeeId,'
          'helper2_employee_id.eq.$employeeId,'
          'helper3_employee_id.eq.$employeeId',
        )
        .eq('is_active', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return VehicleModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Mengambil satu kendaraan berdasarkan ID -- dipakai di
  /// DriverHomePage/HelperHomePage buat nampilin plat nomor shipment aktif.
  static Future<VehicleModel?> getVehicleById(String id) async {
    final response = await _client
        .from('vehicles')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;

    return VehicleModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Menambahkan kendaraan baru. Bisa dilakukan lewat "Pendataan Armada"
  /// baik dari Admin maupun dari Aplikasi Loading.
  ///
  /// **DIKEMBALIKAN (13 Oktober 2026)**: kendaraan baru is_active =
  /// false lagi (BELUM disiapkan) -- perubahan 10 Oktober 2026 yang
  /// membuatnya langsung true DIBATALKAN (lihat doc comment
  /// `getVehicles`). Kendaraan baru TIDAK muncul di "Pilih Kendaraan"
  /// Loading sampai Admin menentukan sopirnya lewat "Siapkan Kendaraan"
  /// (`prepareVehicle`).
  ///
  /// vehicle_code dibuat otomatis oleh trigger Postgres, Flutter tidak
  /// mengirim vehicle_code.
  static Future<VehicleModel> createVehicle({
    required String plateNumber,
    String? vehicleType,
    double? capacityKg,
  }) async {
    final data = {
      'plate_number': plateNumber,
      'vehicle_type': vehicleType,
      'capacity_kg': capacityKg,
      'is_active': false,
    };

    final response =
        await _client.from('vehicles').insert(data).select().single();

    return VehicleModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Set is_active manual -- dipakai admin untuk menonaktifkan/
  /// mengaktifkan kembali kendaraan secara PERMANEN (mis. dijual/rusak),
  /// DAN (DIKEMBALIKAN 13 Oktober 2026) dipanggil OTOMATIS lagi oleh
  /// `ShipmentService.returnToOffice`/`forceCompleteByAdmin` setiap
  /// shipment selesai (ARRIVED) -- supaya kendaraan "hilang" lagi dari
  /// "Pilih Kendaraan" Loading sampai Admin menyiapkannya ulang (pilih
  /// sopir lagi lewat "Siapkan Kendaraan"). Lihat doc comment
  /// `getVehicles` untuk alasan revert-nya.
  static Future<void> setActive(String vehicleId, bool isActive) async {
    await _client.from('vehicles').update({
      'is_active': isActive,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', vehicleId);
  }

  /// Set `is_loading` manual (21 Oktober 2026, permintaan user eksplisit:
  /// "admin saat menyiapkan kendaraan sekaligus is_loading jadi true.
  /// Jika admin berangkatkan kendaraan is_loading jadi false."). Dipanggil
  /// dari [prepareVehicle] (true) dan dari "Berangkatkan Kendaraan"
  /// (`shipment_dispatch_page.dart`) + `ShipmentService.forceStartTripByAdmin`
  /// (false) -- lihat doc comment `VehicleModel.isLoading` untuk beda
  /// field ini dengan [isActive]. Trigger SQL `trg_vehicles_recalculate_
  /// receiving_status` otomatis menghitung ulang status Monitoring Resi
  /// ("Sedang Dimuat"/"Masih Perjalanan") begitu kolom ini berubah --
  /// Flutter tidak perlu memanggil apa pun lagi setelah ini.
  static Future<void> setLoading(String vehicleId, bool isLoading) async {
    await _client.from('vehicles').update({
      'is_loading': isLoading,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', vehicleId);
  }

  /// Menentukan/mengganti sopir & (maks 3) helper kendaraan ini lewat
  /// "Siapkan Kendaraan"/"Pendataan Armada".
  ///
  /// **DIKEMBALIKAN (13 Oktober 2026)**: `is_active: true` di sini
  /// KEMBALI jadi GATE UTAMA supaya kendaraan muncul di "Pilih
  /// Kendaraan" Loading (lihat doc comment `getVehicles`) -- bukan lagi
  /// sekadar "jaring pengaman". Method ini SEKARANG wajib dipanggil dulu
  /// (sopir ditentukan) sebelum kendaraan bisa dipakai memuat barang.
  ///
  /// `is_loading: true` ditambahkan (21 Oktober 2026, lihat doc comment
  /// [setLoading]) -- "Siapkan Kendaraan" = titik admin MULAI menyiapkan
  /// kendaraan utk loading, jadi is_loading langsung true dari sini juga.
  static Future<VehicleModel> prepareVehicle({
    required String vehicleId,
    required String driverEmployeeId,
    String? driverName,
    String? driverPhone,
    List<String> helperEmployeeIds = const [],
  }) async {
    final helpers = helperEmployeeIds.take(3).toList();

    final data = {
      'is_active': true,
      'is_loading': true,
      'driver_employee_id': driverEmployeeId,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'helper1_employee_id': helpers.isNotEmpty ? helpers[0] : null,
      'helper2_employee_id': helpers.length > 1 ? helpers[1] : null,
      'helper3_employee_id': helpers.length > 2 ? helpers[2] : null,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await _client
        .from('vehicles')
        .update(data)
        .eq('id', vehicleId)
        .select()
        .single();

    return VehicleModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Kendaraan placeholder "DISELESAIKAN ADMIN" -- dipakai SATU-SATUNYA
  /// oleh `ShipmentService.forceCompleteReceivingByAdmin` (tombol
  /// "Selesaikan" di Monitoring Resi, 10 Oktober 2026, permintaan user
  /// eksplisit) untuk menautkan scan LOAD/DELIVER sintetis yang dibuat
  /// admin TANPA kendaraan/sopir fisik yang benar-benar memuat resi itu
  /// -- supaya jejaknya tetap bisa dibedakan dari shipment asli (lewat
  /// plat nomornya) kalau nanti dicek di Monitoring Kinerja Perjalanan.
  ///
  /// `is_active = false` supaya TIDAK muncul di "Pilih Kendaraan"
  /// Loading -- kendaraan ini murni administratif, tidak pernah benar-
  /// benar dipakai memuat barang. Dicari dulu lewat `plate_number`
  /// sebelum insert -- dibuat SEKALI, dipakai ulang di setiap
  /// pemanggilan "Selesaikan" berikutnya.
  ///
  /// GANTI NAMA (16 Oktober 2026 -- permintaan user eksplisit: "JADI
  /// NAMA SHIPMENTNYA : diselesaikan admin"): plat sebelumnya
  /// "BYPASS-SIMULASI" diganti "DISELESAIKAN ADMIN" supaya kalau
  /// kelihatan di layar mana pun (mis. daftar Shipment umum yang belum
  /// tentu tahu konsep `isBypassAdmin`, lihat `ReceivingListPage`),
  /// langsung jelas artinya tanpa perlu istilah teknis. SELF-HEALING:
  /// kalau baris lama dgn plat "BYPASS-SIMULASI" masih ada di database
  /// (dibuat sebelum perubahan nama ini), method ini otomatis RENAME
  /// baris itu di tempat (`id` TIDAK berubah, jadi shipment placeholder
  /// yang SUDAH menempel ke kendaraan itu -- lihat `ShipmentService.
  /// _getOrCreateBypassShipment` -- TETAP ketemu, tidak bikin baris
  /// kendaraan/shipment duplikat baru) -- TIDAK PERLU migrasi SQL manual.
  static Future<VehicleModel> getOrCreateBypassVehicle() async {
    const plateNumber = 'DISELESAIKAN ADMIN';
    const legacyPlateNumber = 'BYPASS-SIMULASI';

    final existing = await _client
        .from('vehicles')
        .select()
        .eq('plate_number', plateNumber)
        .maybeSingle();

    if (existing != null) {
      return VehicleModel.fromMap(Map<String, dynamic>.from(existing));
    }

    final legacy = await _client
        .from('vehicles')
        .select()
        .eq('plate_number', legacyPlateNumber)
        .maybeSingle();

    if (legacy != null) {
      final renamed = await _client
          .from('vehicles')
          .update({'plate_number': plateNumber})
          .eq('id', legacy['id'] as String)
          .select()
          .single();

      return VehicleModel.fromMap(Map<String, dynamic>.from(renamed));
    }

    final response = await _client
        .from('vehicles')
        .insert({
          'plate_number': plateNumber,
          'vehicle_type': 'Placeholder Bypass Admin',
          'is_active': false,
        })
        .select()
        .single();

    return VehicleModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// True kalau [plateNumber] adalah plat kendaraan placeholder
  /// "DISELESAIKAN ADMIN" (dulu "BYPASS-SIMULASI") -- lihat
  /// [getOrCreateBypassVehicle] di atas. Terima String (bukan
  /// `VehicleModel`) supaya bisa dipakai langsung dari mana pun datanya
  /// berasal -- baik dari `VehicleModel.plateNumber` (lewat
  /// [isBypassPlaceholder] di bawah) MAUPUN dari Map mentah hasil query
  /// Supabase (mis. `monitoring_service.dart`, yang JOIN manual tabel
  /// `vehicles` tanpa lewat `VehicleModel`).
  ///
  /// **MENGAPA INI PENTING (16 Oktober 2026, permintaan user eksplisit)**:
  /// ada 2 mekanisme "diselesaikan paksa Admin" yang BERBEDA di aplikasi
  /// ini, dan user menegaskan keduanya HARUS dibedakan di UI:
  ///   - **Tipe 1** (`ShipmentService.forceCompleteByAdmin`, tombol
  ///     "Intervensi Admin" di shipment yang SEDANG loading/berangkat):
  ///     shipment yang BENAR-BENAR dimuat & berangkat pakai kendaraan &
  ///     sopir ASLI, admin cuma memaksa status jadi ARRIVED karena sopir
  ///     tidak bisa menyelesaikan sendiri lewat HP-nya. **Harus TETAP
  ///     tampil** di semua daftar shipment (Admin & Supervisor), nama
  ///     sopirnya tetap ada.
  ///   - **Tipe 2** (`ShipmentService.forceCompleteReceivingByAdmin`,
  ///     tombol "Selesaikan" per-resi di Monitoring Resi): resi yang
  ///     TIDAK PERNAH dimuat kendaraan apa pun -- murni administratif,
  ///     ditautkan ke kendaraan placeholder ini supaya scan LOAD/DELIVER
  ///     sintetisnya tetap punya `shipment_id` yang valid. **Harus
  ///     DISEMBUNYIKAN** dari semua daftar shipment (Admin & Supervisor)
  ///     -- resi ini seharusnya tidak dianggap punya "status shipment"
  ///     sama sekali dari sudut pandang user.
  ///
  /// KEDUA tipe SAMA-SAMA men-set `completed_by_admin = true` di kolom
  /// `shipments` -- jadi flag itu SENDIRIAN **TIDAK BISA** dipakai untuk
  /// membedakan keduanya (percobaan pertama pakai flag ini saja TERBUKTI
  /// SALAH, lihat project doc Tambahan #47 vs #48). Identitas KENDARAAN
  /// (placeholder vs kendaraan asli manapun) adalah satu-satunya pembeda
  /// yang benar, karena HANYA Tipe 2 yang memakai kendaraan placeholder
  /// ini -- Tipe 1 selalu memakai kendaraan asli yang memang dipakai
  /// loading. Pakai helper ini (bukan `completedByAdmin`) di mana pun UI
  /// perlu menyembunyikan khusus Tipe 2.
  static bool isBypassPlaceholderPlate(String? plateNumber) {
    return plateNumber == 'DISELESAIKAN ADMIN' ||
        plateNumber == 'BYPASS-SIMULASI';
  }

  /// Overload kenyamanan untuk kode yang sudah punya `VehicleModel` utuh
  /// (bukan Map mentah) -- lihat [isBypassPlaceholderPlate].
  static bool isBypassPlaceholder(VehicleModel? vehicle) {
    return isBypassPlaceholderPlate(vehicle?.plateNumber);
  }
}
