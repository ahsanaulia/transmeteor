import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../services/printer_service.dart';

/// State koneksi printer thermal yang dipakai selama sesi aplikasi
/// berjalan (belum disimpan permanen -- kalau app di-restart, printer
/// harus disambungkan ulang. Persist ke storage bisa menyusul kalau
/// dibutuhkan nanti).
class PrinterConnectionState {
  final BluetoothInfo? connectedDevice;
  final bool isConnecting;

  const PrinterConnectionState({
    this.connectedDevice,
    this.isConnecting = false,
  });

  bool get isConnected => connectedDevice != null;

  PrinterConnectionState copyWith({
    BluetoothInfo? connectedDevice,
    bool? isConnecting,
  }) {
    return PrinterConnectionState(
      connectedDevice: connectedDevice ?? this.connectedDevice,
      isConnecting: isConnecting ?? this.isConnecting,
    );
  }
}

class PrinterConnectionNotifier extends StateNotifier<PrinterConnectionState> {
  PrinterConnectionNotifier() : super(const PrinterConnectionState());

  Future<bool> connect(BluetoothInfo device) async {
    state = state.copyWith(isConnecting: true);

    try {
      final success = await PrinterService.connect(device.macAdress);

      state = success
          ? PrinterConnectionState(connectedDevice: device)
          : state.copyWith(isConnecting: false);

      return success;
    } catch (_) {
      state = state.copyWith(isConnecting: false);
      return false;
    }
  }

  Future<void> disconnect() async {
    await PrinterService.disconnect();
    state = const PrinterConnectionState();
  }

  /// Cek ulang status koneksi ke printer (misal habis idle lama / printer
  /// dimatikan). Kalau ternyata sudah putus, state di-reset supaya
  /// pemanggil tahu harus connect ulang.
  Future<bool> ensureStillConnected() async {
    if (state.connectedDevice == null) return false;

    final connected = await PrinterService.isConnected();

    if (!connected) {
      state = const PrinterConnectionState();
    }

    return connected;
  }
}

final printerConnectionProvider =
    StateNotifierProvider<PrinterConnectionNotifier, PrinterConnectionState>(
  (ref) => PrinterConnectionNotifier(),
);

final pairedPrintersProvider = FutureProvider<List<BluetoothInfo>>((ref) {
  return PrinterService.getPairedDevices();
});