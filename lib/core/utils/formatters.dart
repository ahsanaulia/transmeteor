/// Format angka jadi string Rupiah dengan pemisah ribuan, tanpa
/// bergantung ke package `intl` (yang tidak ada di dependency langsung
/// project ini) -- contoh: `formatRupiah(25000)` -> `'Rp 25.000'`.
String formatRupiah(num value) {
  final isNegative = value < 0;
  final digits = value.abs().round().toString();

  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;

    if (i > 0 && remaining % 3 == 0) {
      buffer.write('.');
    }

    buffer.write(digits[i]);
  }

  return '${isNegative ? '-' : ''}Rp $buffer';
}

/// Format tanggal ke gaya Indonesia tanpa package `intl` -- contoh:
/// `formatDateId(DateTime(2026, 8, 17))` -> `'17 Agustus 2026'`.
String formatDateId(DateTime date) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Format jam dari [DateTime] jadi "HH:mm" 2 digit (zona waktu lokal
/// perangkat, SAMA seperti `date.hour`/`date.minute` apa adanya -- tidak
/// melakukan konversi zona waktu apa pun). Contoh:
/// `formatTimeId(DateTime(2026, 8, 17, 9, 5))` -> `'09:05'`. Dipakai
/// bareng `formatDateId` di tempat yang perlu menampilkan jam, misalnya
/// jam terima barang di teks WhatsApp (`ReceiptPreviewPage`).
String formatTimeId(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}