import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum InfoBannerVariant { info, warning, error }

/// Banner kecil untuk pesan info/peringatan/error inline di dalam form
/// (bukan `SnackBar`), misalnya "data belum ditemukan" atau pesan
/// validasi sebelum submit.
class InfoBanner extends StatelessWidget {
  final String message;
  final InfoBannerVariant variant;
  final VoidCallback? onDismiss;

  const InfoBanner({
    super.key,
    required this.message,
    this.variant = InfoBannerVariant.info,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    const icon = Icons.info_outline_rounded;
    const errorIcon = Icons.error_outline_rounded;

    switch (variant) {
      case InfoBannerVariant.warning:
        bg = const Color(0xFFFFF8E8);
        fg = const Color(0xFF92400E);
        break;
      case InfoBannerVariant.error:
        bg = const Color(0xFFFFF0F0);
        fg = AppColors.red;
        break;
      case InfoBannerVariant.info:
        bg = const Color(0xFFEAF2FF);
        fg = AppColors.blue;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            variant == InfoBannerVariant.error ? errorIcon : icon,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: fg,
            ),
        ],
      ),
    );
  }
}
