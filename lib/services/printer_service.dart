import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Wrapper tipis di atas package `print_bluetooth_thermal`.
///
/// Semua halaman yang butuh cetak (label & resi) cukup panggil lewat
/// service ini -- supaya kalau nanti ganti printer/package, cukup ubah
/// di satu tempat ini saja.
class PrinterService {
  static Future<List<BluetoothInfo>> getPairedDevices() {
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<bool> connect(String macAddress) {
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  static Future<bool> disconnect() {
    return PrintBluetoothThermal.disconnect;
  }

  static Future<bool> isConnected() {
    return PrintBluetoothThermal.connectionStatus;
  }

  static Future<bool> printBytes(List<int> bytes) {
    return PrintBluetoothThermal.writeBytes(bytes);
  }
}