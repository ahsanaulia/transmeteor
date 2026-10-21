import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';

/// Field "pilih dari daftar" (bukan ketik bebas) untuk data master yang
/// jumlahnya terbatas -- misalnya rute, jenis pengiriman, item type,
/// pricing type. Beda dengan [SearchPickField] yang query ke server
/// tiap ketik, [PickerField] menerima daftarnya lewat [itemsAsync]
/// (biasanya dari provider Riverpod yang sudah di-cache) dan filter-nya
/// dilakukan di sisi client karena datanya kecil.
///
/// Tap field ini membuka bottom sheet berisi daftar + kotak cari.
///
/// BUG NYATA yang ditemukan & diperbaiki (21 September 2026) -- laporan:
/// "jenis tarif yang baru ditambahkan admin tidak realtime muncul di sisi
/// penerima barang (Receiving)". Root cause-nya BUKAN di realtime sync
/// (`RealtimeSyncService` + `pricingTypesProvider` sudah benar, sudah
/// diverifikasi ulang) -- tapi di sini: bottom sheet [_PickerSheet] yang
/// dibuka lewat `showModalBottomSheet` dulu HANYA menerima [itemsAsync]
/// sebagai parameter constructor BIASA (snapshot beku saat sheet dibuka).
/// Kalau staff Receiving buka "Pilih Jenis Tarif", tidak ketemu jenis yang
/// dicari, lalu MEMBIARKAN sheet itu tetap terbuka sambil menunggu admin
/// menambahkan jenis baru di device lain -- daftar di sheet itu TIDAK
/// PERNAH ikut ter-update, walaupun `pricingTypesProvider` di baliknya
/// sudah realtime ter-invalidate & fetch ulang, karena sheet-nya cuma
/// widget State biasa (bukan Consumer) yang tidak pernah ref.watch lagi.
///
/// Perbaikannya: [itemsProvider] (opsional) -- kalau diisi, [_PickerSheet]
/// jadi ConsumerStatefulWidget yang `ref.watch()` LANGSUNG ke provider itu,
/// jadi daftarnya tetap hidup/realtime walaupun sheet dibiarkan terbuka.
/// Semua pemanggil [PickerField] di app ini SUDAH diupdate untuk mengisi
/// [itemsProvider] (lihat receiving_detail_form_sheet.dart,
/// assign_driver_helper_sheet.dart, prepare_vehicle_sheet.dart,
/// receiving_create_page.dart). Kalau [itemsProvider] tidak diisi, sheet
/// tetap jalan seperti sebelumnya (pakai snapshot [itemsAsync]) supaya
/// tidak memaksa breaking change untuk pemanggil baru yang datanya memang
/// bukan dari provider Riverpod.
class PickerField<T> extends StatelessWidget {
  final String label;
  final String hint;
  final String sheetTitle;
  final IconData? icon;
  final AsyncValue<List<T>> itemsAsync;
  final ProviderListenable<AsyncValue<List<T>>>? itemsProvider;
  final T? selected;
  final String Function(T item) itemLabel;
  final String? Function(T item)? itemSubtitle;
  final String Function(T item)? selectedText;
  final ValueChanged<T> onSelected;
  final VoidCallback? onClear;
  final bool enabled;

  // FITUR (21 Oktober 2026, permintaan user eksplisit -- Jenis Tarif):
  // "ketika mereka mencari di jenis tarif belum ada, maka ada pilihan
  // tambah jenis tarif" -- opsional (default null = perilaku lama TIDAK
  // berubah sama sekali untuk pemanggil yang belum mengisi ini). Kalau
  // diisi, tombol "tambah baru" muncul di bawah daftar sheet pencarian
  // (lihat `_PickerSheet`). [onAddNew] mengembalikan item baru yang
  // sudah tersimpan (pemanggil yang menanganinya sendiri, mis. buka
  // dialog form) -- hasilnya langsung dianggap "dipilih", sheet ditutup
  // seperti memilih item dari daftar biasa. Return null = dibatalkan,
  // sheet TETAP terbuka.
  final String? addNewLabel;
  final Future<T?> Function(BuildContext context)? onAddNew;

  const PickerField({
    super.key,
    required this.label,
    required this.hint,
    required this.sheetTitle,
    required this.itemsAsync,
    required this.itemLabel,
    required this.onSelected,
    this.itemsProvider,
    this.icon,
    this.itemSubtitle,
    this.selectedText,
    this.selected,
    this.onClear,
    this.enabled = true,
    this.addNewLabel,
    this.onAddNew,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet<T>(
        title: sheetTitle,
        itemsAsync: itemsAsync,
        itemsProvider: itemsProvider,
        itemLabel: itemLabel,
        itemSubtitle: itemSubtitle,
        addNewLabel: addNewLabel,
        onAddNew: onAddNew,
      ),
    );

    if (picked != null) {
      onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = selected;
    final displayText =
        current != null ? (selectedText ?? itemLabel)(current) : null;

    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          suffixIcon: current != null && onClear != null
              ? IconButton(
                  onPressed: enabled ? onClear : null,
                  icon: const Icon(Icons.close_rounded),
                )
              : const Icon(Icons.expand_more_rounded),
          filled: true,
          fillColor: AppColors.fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(
          displayText ?? hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: displayText != null
                ? AppColors.textPrimary
                : AppColors.textSecondary,
            fontWeight:
                displayText != null ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _PickerSheet<T> extends ConsumerStatefulWidget {
  final String title;
  final AsyncValue<List<T>> itemsAsync;
  final ProviderListenable<AsyncValue<List<T>>>? itemsProvider;
  final String Function(T item) itemLabel;
  final String? Function(T item)? itemSubtitle;
  final String? addNewLabel;
  final Future<T?> Function(BuildContext context)? onAddNew;

  const _PickerSheet({
    required this.title,
    required this.itemsAsync,
    this.itemsProvider,
    required this.itemLabel,
    this.itemSubtitle,
    this.addNewLabel,
    this.onAddNew,
  });

  @override
  ConsumerState<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends ConsumerState<_PickerSheet<T>> {
  String _keyword = '';
  bool _isAddingNew = false;

  // Lihat doc comment [PickerField.onAddNew]. Dialognya sendiri DIBUKA &
  // DITANGANI oleh pemanggil (lewat context sheet ini, MASIH di atas
  // modal bottom sheet yang sama) -- widget ini cuma menutup sheet
  // dengan hasilnya kalau tidak dibatalkan (null).
  Future<void> _handleAddNew() async {
    if (widget.onAddNew == null || _isAddingNew) return;

    setState(() => _isAddingNew = true);

    try {
      final created = await widget.onAddNew!(context);

      if (!mounted) return;

      if (created != null) {
        Navigator.of(context).pop(created);
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingNew = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kalau [itemsProvider] diisi, watch LANGSUNG di sini supaya daftar
    // tetap live-update selama sheet ini terbuka (lihat doc comment di
    // PickerField soal bug staleness-nya). Kalau tidak diisi, fallback ke
    // snapshot [itemsAsync] seperti perilaku lama.
    final itemsAsync = widget.itemsProvider != null
        ? ref.watch(widget.itemsProvider!)
        : widget.itemsAsync;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E4EC),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  autofocus: false,
                  onChanged: (value) {
                    setState(() {
                      _keyword = value.trim().toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Cari...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: itemsAsync.when(
                  data: (items) {
                    final filtered = _keyword.isEmpty
                        ? items
                        : items
                            .where(
                              (item) => widget
                                  .itemLabel(item)
                                  .toLowerCase()
                                  .contains(_keyword),
                            )
                            .toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          'Data tidak ditemukan.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final subtitle = widget.itemSubtitle?.call(item);

                        return ListTile(
                          title: Text(
                            widget.itemLabel(item),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: subtitle != null
                              ? Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Text(
                      'Gagal memuat data: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ),
              ),
              // Lihat doc comment [PickerField.onAddNew] -- opsional,
              // perilaku lama (tanpa tombol ini sama sekali) TIDAK
              // berubah kalau pemanggil tidak mengisinya.
              if (widget.addNewLabel != null && widget.onAddNew != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isAddingNew ? null : _handleAddNew,
                      icon: _isAddingNew
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
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
                ),
            ],
          ),
        );
      },
    );
  }
}
