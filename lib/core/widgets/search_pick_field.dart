import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_text_field.dart';
import 'info_banner.dart';

/// Field pencarian generik dengan hasil pencarian debounce +
/// pilihan "tambah baru".
///
/// Ini pola yang dipakai berkali-kali di app ini: cari pengirim,
/// (nanti) cari item type, pricing type, destination, dsb. Daripada
/// menulis ulang state debounce-search di tiap halaman, pakai widget
/// ini dan cukup sediakan fungsi [onSearch] + cara menampilkan tiap item.
class SearchPickField<T> extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final Future<List<T>> Function(String keyword) onSearch;
  final String Function(T item) itemLabel;
  final String? Function(T item)? itemSubtitle;
  final ValueChanged<T> onSelected;
  final T? selected;
  final VoidCallback? onClear;
  final Widget Function(BuildContext context, T item)? selectedBuilder;
  final String? addNewLabel;
  final VoidCallback? onAddNew;
  final bool enabled;
  final Duration debounce;
  final String notFoundMessage;

  /// (21 September 2026) Tombol "Muat Ulang" opsional -- ditampilkan di
  /// bawah field kalau `true`. Pencarian di widget ini SEBENARNYA sudah
  /// selalu realtime (tiap ketikan query langsung ke server lewat
  /// [onSearch], tidak ada cache di tengah), jadi tombol ini bukan
  /// perbaikan bug staleness (beda dengan kasus `PickerField`) -- cuma
  /// jaring pengaman & kepastian visual buat staff, konsisten dengan
  /// tombol "Ambil Tarif Baru" di form input barang: begitu ditekan,
  /// query pencarian yang sedang diketik langsung diulang ke server dan
  /// staff dapat konfirmasi lewat SnackBar.
  final bool showRefreshButton;
  final String refreshLabel;

  const SearchPickField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.onSearch,
    required this.itemLabel,
    required this.onSelected,
    this.itemSubtitle,
    this.selected,
    this.onClear,
    this.selectedBuilder,
    this.addNewLabel,
    this.onAddNew,
    this.enabled = true,
    this.debounce = const Duration(milliseconds: 400),
    this.notFoundMessage =
        'Data belum ditemukan. Gunakan tombol di bawah untuk menambahkan.',
    this.showRefreshButton = false,
    this.refreshLabel = 'Muat Ulang',
  });

  @override
  State<SearchPickField<T>> createState() => _SearchPickFieldState<T>();
}

class _SearchPickFieldState<T> extends State<SearchPickField<T>> {
  List<T> _results = [];
  bool _isSearching = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();

    if (widget.selected != null) {
      widget.onClear?.call();
    }

    final keyword = value.trim();

    if (keyword.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    _timer = Timer(widget.debounce, () => _search(keyword));
  }

  Future<void> _search(String keyword) async {
    if (!mounted) return;

    setState(() => _isSearching = true);

    try {
      final results = await widget.onSearch(keyword);

      if (!mounted) return;

      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  void _select(T item) {
    setState(() => _results = []);
    widget.onSelected(item);
  }

  // Lihat doc comment [SearchPickField.showRefreshButton] -- pencarian
  // di sini sudah selalu live, jadi tombol ini cuma mengulang query yang
  // sedang diketik supaya staff dapat kepastian visual (SnackBar) kalau
  // datanya sudah pasti yang terbaru dari server.
  Future<void> _manualRefresh() async {
    final keyword = widget.controller.text.trim();

    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Ketik dulu kata kuncinya, lalu tekan ${widget.refreshLabel.toLowerCase()}.'),
        ),
      );
      return;
    }

    await _search(keyword);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 1),
        content: Text('Data sudah diambil ulang dari server.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResults = widget.selected == null &&
        !_isSearching &&
        widget.controller.text.trim().isNotEmpty;

    return Column(
      children: [
        AppTextField(
          controller: widget.controller,
          label: widget.label,
          hint: widget.hint,
          icon: Icons.search_rounded,
          enabled: widget.enabled,
          onChanged: _onChanged,
          suffixIcon: widget.selected != null
              ? IconButton(
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
        ),
        if (widget.showRefreshButton) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: (widget.enabled && !_isSearching) ? _manualRefresh : null,
              icon: _isSearching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(widget.refreshLabel),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.blue,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
        if (_isSearching) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (widget.selected != null && widget.selectedBuilder != null) ...[
          const SizedBox(height: 14),
          widget.selectedBuilder!(context, widget.selected as T),
        ],
        if (showResults) ...[
          const SizedBox(height: 12),
          if (_results.isNotEmpty)
            ..._results.map(
              (item) => _SearchPickResultTile<T>(
                label: widget.itemLabel(item),
                subtitle: widget.itemSubtitle?.call(item),
                onTap: () => _select(item),
              ),
            )
          else
            InfoBanner(
              variant: InfoBannerVariant.warning,
              message: widget.notFoundMessage,
            ),
        ],
        if (widget.addNewLabel != null && widget.onAddNew != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.enabled ? widget.onAddNew : null,
              icon: const Icon(Icons.add_rounded),
              label: Text(widget.addNewLabel!),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue,
                side: BorderSide(color: AppColors.blue.withOpacity(0.25)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchPickResultTile<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _SearchPickResultTile({
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
