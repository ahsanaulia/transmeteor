import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// UI KIT bersama -- Dashboard Supervisor (16 Oktober 2026, permintaan
/// user "perbaikan UI supervisor": "Berwarna warni antar data", referensi
/// 2 gambar yang dikirim user -- (1) dashboard dengan kartu statistik
/// warna-warni pastel/vivid [user: "ini juga warna2 pastel bagus"], (2)
/// kartu dengan garis/strip aksen warna solid di bagian atas + badan
/// putih bersih [user: "ini bisa jadi contoh kotak"].
///
/// Dipakai di SEMUA kartu Tab 1 (Resi), Tab 2 (Shipment & isi muatan),
/// Tab 3 (Zona/Storage) supaya treatment visual konsisten:
///   - `SupervisorAccentCard`: strip warna solid di atas (meniru gambar
///     referensi "kotak") + badan kartu bertint pastel SANGAT tipis dari
///     warna yang SAMA -- warna tetap mengikuti arti status/kategori data
///     yang SUDAH ADA sebelumnya (status Penerimaan/Masih Perjalanan/
///     Selesai, dsb), bukan warna acak. Jadi "colorful ANTAR DATA" karena
///     tiap data dengan status beda otomatis tampil beda warna.
///   - `SupervisorField`: pasangan label+value yang dibesarkan + sekat
///     (border bawah tipis) antar field -- dan SENGAJA tanpa prefix
///     angka ("1.", "2.", dst, permintaan user: "semua nomor dihilangkan
///     depan label"). Awalnya diminta cuma utk Tab 3, tapi konvensi
///     penomoran yang sama dipakai di Tab 1 & Tab 2 juga -- dihapus di
///     ketiganya supaya konsisten (lihat laporan ke user).
class SupervisorAccentCard extends StatelessWidget {
  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double accentHeight;

  const SupervisorAccentCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.accentHeight = 7,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: accentHeight, color: color),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: card),
    );
  }
}

/// Field label+value dibesarkan dengan sekat jelas, tanpa prefix angka.
class SupervisorField extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final double width;

  const SupervisorField({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.width = 270,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.only(bottom: 10, right: 18),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip pastel: latar pastel SAJA, huruf hitam bold tebal (permintaan
/// user eksplisit utk chip koli & chip zona: "huruf Hitam dan Bold dan
/// latarnya saja warna Pastel").
class SupervisorPastelChip extends StatelessWidget {
  final String label;
  final Color pastelColor;
  final IconData? icon;
  final double fontSize;

  const SupervisorPastelChip({
    super.key,
    required this.label,
    required this.pastelColor,
    this.icon,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: pastelColor.withOpacity(0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: Colors.black87),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w900,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}
