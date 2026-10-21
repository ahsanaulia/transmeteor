import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Kartu aksi (ikon + judul + subjudul + chevron/panah) yang dipakai
/// untuk menu utama di home page maupun daftar aksi di profile page.
///
/// [dense] = true untuk gaya list-row (dipakai di Profile),
/// [dense] = false (default) untuk gaya card besar (dipakai di menu Home).
class MenuActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback? onTap;
  final bool dense;

  const MenuActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final double iconBoxSize = dense ? 52 : 58;
    final double radius = dense ? 20 : 21;

    return Container(
      decoration: BoxDecoration(
        gradient: dense
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, accentColor.withOpacity(0.035)],
              ),
        color: dense ? AppColors.surface : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accentColor.withOpacity(dense ? 0.10 : 0.14),
        ),
        boxShadow: dense
            ? null
            : [
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    gradient: dense
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accentColor.withOpacity(0.18),
                              accentColor.withOpacity(0.07),
                            ],
                          ),
                    color: dense ? accentColor.withOpacity(0.10) : null,
                    borderRadius: BorderRadius.circular(dense ? 15 : 17),
                    border: dense
                        ? null
                        : Border.all(color: accentColor.withOpacity(0.10)),
                  ),
                  child: Icon(icon, size: dense ? 25 : 29, color: accentColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: dense ? 15 : 16,
                          fontWeight: dense ? FontWeight.w800 : FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: dense ? 3 : 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                dense
                    ? Icon(Icons.chevron_right_rounded, color: accentColor)
                    : Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withOpacity(0.16),
                              accentColor.withOpacity(0.07),
                            ],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                          color: accentColor,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
