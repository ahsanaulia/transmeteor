import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Dialog konfirmasi sukses (ikon centang + judul + pesan + kotak nilai
/// yang di-highlight, misalnya nomor resi). Dipakai setiap kali ada aksi
/// create/simpan yang menghasilkan sebuah nomor/kode yang perlu
/// ditunjukkan ke user.
///
/// Navigasi setelah dialog (pop sekali, dua kali, atau pindah halaman)
/// diserahkan ke pemanggil lewat [onDone] / [onSecondary], supaya widget
/// ini tidak perlu tahu konteks navigasi tempat dia dipanggil.
///
/// [secondaryLabel] & [onSecondary] opsional -- isi kalau butuh 2 pilihan
/// aksi (misal "Tambah Barang" vs "Nanti Saja").
class SuccessResultDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? valueLabel;
  final String? value;
  final String buttonLabel;
  final VoidCallback onDone;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const SuccessResultDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onDone,
    this.valueLabel,
    this.value,
    this.buttonLabel = 'Selesai',
    this.secondaryLabel,
    this.onSecondary,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onDone,
    String? valueLabel,
    String? value,
    String buttonLabel = 'Selesai',
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SuccessResultDialog(
        title: title,
        message: message,
        valueLabel: valueLabel,
        value: value,
        buttonLabel: buttonLabel,
        onDone: onDone,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.blue, AppColors.cyan],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 42,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (value != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEAF2FF), Color(0xFFE9FBFF)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  if (valueLabel != null)
                    Text(
                      valueLabel!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    value!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              child: Text(buttonLabel),
            ),
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}