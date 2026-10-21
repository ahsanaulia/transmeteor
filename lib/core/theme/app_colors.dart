import 'package:flutter/material.dart';

/// Palet warna brand TRANS, dipakai di seluruh halaman.
///
/// Jangan definisikan warna brand baru di level halaman (page) --
/// tambahkan di sini supaya semua modul (shipments, tracking, vehicles,
/// dst) tetap konsisten satu sama lain dan gampang di-tune sekali jalan.
class AppColors {
  AppColors._();

  static const Color navy = Color(0xFF101B3D);
  static const Color blue = Color(0xFF2878F0);
  static const Color lightBlue = Color(0xFF5BA7FF);
  static const Color cyan = Color(0xFF13B9D6);
  static const Color violet = Color(0xFF8064F7);
  static const Color pink = Color(0xFFEF6BA8);
  static const Color green = Color(0xFF19B982);
  static const Color orange = Color(0xFFFFA63D);
  static const Color red = Color(0xFFDC2626);

  static const Color background = Color(0xFFF1F6FF);
  static const Color surface = Colors.white;
  static const Color fieldFill = Color(0xFFF7F9FD);
  static const Color border = Color(0xFFE5EAF2);

  static const Color textPrimary = Color(0xFF14203B);
  static const Color textSecondary = Color(0xFF687793);
}
