import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Text field bergaya seragam (filled, rounded, tanpa border garis)
/// yang dipakai di seluruh form aplikasi.
///
/// Kalau [validator] diisi, widget ini otomatis pakai `TextFormField`
/// (untuk dipakai di dalam `Form`). Kalau tidak, pakai `TextField` biasa.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool enabled;
  final bool obscureText;
  final double borderRadius;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.suffixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
    this.obscureText = false,
    this.borderRadius = 16,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  InputDecoration _decoration() {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveMaxLines = obscureText ? 1 : maxLines;

    if (validator != null) {
      return TextFormField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLines: effectiveMaxLines,
        onChanged: onChanged,
        validator: validator,
        decoration: _decoration(),
      );
    }

    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: effectiveMaxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: _decoration(),
    );
  }
}
