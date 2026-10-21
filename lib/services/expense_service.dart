import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';
import '../models/shipment_expense_model.dart';

class ExpenseService {
  static final _client = SupabaseService.client;
  static const _receiptBucket = 'expense-receipts';

  /// Upload foto struk (opsional) ke Supabase Storage, balikin URL publiknya.
  ///
  /// Diasumsikan bucket `expense-receipts` PUBLIC (biar gampang buat demo).
  /// Kalau bucket-nya kamu buat PRIVATE, ganti baris `getPublicUrl` di bawah
  /// jadi `createSignedUrl(path, 60 * 60 * 24 * 365)` (signed URL 1 tahun).
  static Future<String> uploadReceiptPhoto({
    required String shipmentId,
    required Uint8List bytes,
  }) async {
    final path = '$shipmentId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage.from(_receiptBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    return _client.storage.from(_receiptBucket).getPublicUrl(path);
  }

  /// Menyimpan satu laporan pengeluaran (BBM / Penginapan / Makan).
  static Future<ShipmentExpenseModel> createExpense({
    required String shipmentId,
    required String employeeId,
    required String expenseType,
    required double amount,
    String? notes,
    String? photoUrl,
    required double latitude,
    required double longitude,
  }) async {
    final data = {
      'shipment_id': shipmentId,
      'employee_id': employeeId,
      'expense_type': expenseType,
      'amount': amount,
      'notes': notes,
      'photo_url': photoUrl,
      'latitude': latitude,
      'longitude': longitude,
    };

    final response = await _client
        .from('shipment_expenses')
        .insert(data)
        .select()
        .single();

    return ShipmentExpenseModel.fromMap(Map<String, dynamic>.from(response));
  }

  /// Daftar pengeluaran satu shipment, terbaru duluan (buat rekap admin).
  static Future<List<ShipmentExpenseModel>> getExpensesForShipment(
    String shipmentId,
  ) async {
    final response = await _client
        .from('shipment_expenses')
        .select()
        .eq('shipment_id', shipmentId)
        .order('recorded_at', ascending: false);

    return (response as List)
        .map((data) =>
            ShipmentExpenseModel.fromMap(Map<String, dynamic>.from(data)))
        .toList();
  }
}