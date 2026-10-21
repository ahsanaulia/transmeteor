import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Tombol utama (full width, rounded) dengan state loading bawaan.
///
/// Menggantikan pola berulang:
/// `FilledButton.icon(... child: _isLoading ? Spinner : Text ...)`
/// yang sebelumnya ditulis ulang di tiap form.
class PrimaryButton extends StatelessWidget {
  final String label;
  final String? loadingLabel;
  final bool isLoading;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final Color? backgroundColor;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loadingLabel,
    this.isLoading = false,
    this.icon,
    this.height = 54,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: backgroundColor ?? AppColors.blue,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
      ),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    );

    final labelWidget = Text(isLoading ? (loadingLabel ?? label) : label);

    Widget iconWidget;

    if (isLoading) {
      iconWidget = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    } else if (icon != null) {
      iconWidget = Icon(icon);
    } else {
      iconWidget = const SizedBox.shrink();
    }

    final showIcon = isLoading || icon != null;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: showIcon
          ? FilledButton.icon(
              onPressed: isLoading ? null : onPressed,
              style: style,
              icon: iconWidget,
              label: labelWidget,
            )
          : FilledButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: labelWidget,
            ),
    );
  }
}
