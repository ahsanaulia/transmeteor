import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/sender_model.dart';
import '../../../providers/master_data_providers.dart';
import '../../../services/sender_service.dart';
import '../widgets/sender_form_sheet.dart';

/// Halaman admin "Daftar Pengirim Langganan" -- daftar semua pengirim
/// (senders), tombol tambah pengirim baru, edit pengirim yang sudah
/// ada, dan aktif/nonaktifkan. Mengikuti pola PERSIS
/// `DestinationManagePage` (permintaan user, 6 Oktober 2026 lanjutan:
/// "Tambahkan di aplikasi admin : CRUD : Daftar Pengirim Langganan").
///
/// Sebelumnya pengirim cuma bisa didaftarkan "numpang" lewat form input
/// resi di Receiving (tombol "Tambah Baru" saat mencari pengirim yang
/// belum ada). Halaman ini menambah jalur admin supaya pengirim-pengirim
/// langganan (yang sudah pasti akan dipakai berulang) bisa didaftarkan
/// lebih dulu dari sini -- staff Receiving di lapangan tinggal cari &
/// pilih, mempercepat proses input resi.
///
/// Menonaktifkan pengirim TIDAK menghapusnya -- cuma bikin pengirim itu
/// tidak lagi muncul di pencarian saat input resi baru. Riwayat resi
/// lama yang sudah memakai pengirim itu tetap utuh.
class SenderManagePage extends ConsumerStatefulWidget {
  const SenderManagePage({super.key});

  @override
  ConsumerState<SenderManagePage> createState() => _SenderManagePageState();
}

class _SenderManagePageState extends ConsumerState<SenderManagePage> {
  String? _busySenderId;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });

    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(allSendersProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Cocokkan keyword ke nama, nomor HP, ATAU alamat pengirim -- supaya
  /// admin bisa cari "0812..." atau sepotong alamat, tidak cuma nama.
  List<SenderModel> _filterSenders(List<SenderModel> senders) {
    if (_searchQuery.isEmpty) return senders;

    return senders.where((sender) {
      final name = sender.name.toLowerCase();
      final phone = sender.phone?.toLowerCase() ?? '';
      final address = sender.address?.toLowerCase() ?? '';
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          address.contains(_searchQuery);
    }).toList();
  }

  void _refreshAll() {
    ref.invalidate(allSendersProvider);
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SenderFormSheet(),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _openEditSheet(SenderModel sender) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SenderFormSheet(existing: sender),
    );

    if (saved == true) _refreshAll();
  }

  Future<void> _toggleActive(SenderModel sender) async {
    setState(() => _busySenderId = sender.id);

    try {
      await SenderService.setActive(sender.id, !sender.isActive);
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status pengirim: $e')),
      );
    } finally {
      if (mounted) setState(() => _busySenderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sendersAsync = ref.watch(allSendersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Daftar Pengirim Langganan'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Pengirim'),
        backgroundColor: AppColors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Pengirim',
                hint: 'Cari nama, nomor HP, atau alamat pengirim...',
                icon: Icons.search_rounded,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Hapus pencarian',
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
            Expanded(
              child: sendersAsync.when(
                data: (senders) {
                  if (senders.isEmpty) {
                    return ErrorStateView(
                      title: 'Belum ada pengirim langganan.',
                      message: 'Tambahkan pengirim baru lewat tombol di bawah.',
                      icon: Icons.person_outline_rounded,
                      onRetry: _openAddSheet,
                    );
                  }

                  final filtered = _filterSenders(senders);

                  if (filtered.isEmpty) {
                    // Tanpa `onRetry` SENGAJA -- tombol bawaan
                    // `ErrorStateView` selalu berlabel "Coba Lagi" (cocok
                    // untuk retry fetch, BUKAN untuk "hapus pencarian").
                    return ErrorStateView(
                      title: 'Pengirim tidak ditemukan.',
                      message: 'Tidak ada pengirim yang cocok dengan "${_searchController.text}".',
                      icon: Icons.search_off_rounded,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final sender = filtered[index];

                      return _SenderTile(
                        sender: sender,
                        isBusy: _busySenderId == sender.id,
                        onTap: () => _openEditSheet(sender),
                        onToggleActive: () => _toggleActive(sender),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
                error: (error, stackTrace) => ErrorStateView(
                  title: 'Gagal memuat daftar pengirim.',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allSendersProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ringkasan detail pengirim buat subtitle di tile -- gabungkan telepon/
/// alamat yang terisi saja, dipisah "•". Kalau semua kosong (pengirim
/// cuma didaftarkan namanya saja), tampilkan placeholder supaya baris
/// subtitle tidak kosong melompong.
String _buildSubtitle(SenderModel sender) {
  final parts = [
    if (sender.phone != null && sender.phone!.isNotEmpty) sender.phone!,
    if (sender.address != null && sender.address!.isNotEmpty) sender.address!,
  ];

  return parts.isEmpty ? 'Belum ada detail tambahan' : parts.join(' • ');
}

class _SenderTile extends StatelessWidget {
  final SenderModel sender;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _SenderTile({
    required this.sender,
    required this.isBusy,
    required this.onTap,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (sender.isActive ? AppColors.green : AppColors.textSecondary)
              .withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person_rounded, color: AppColors.green),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _buildSubtitle(sender),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (sender.isActive ? AppColors.green : AppColors.textSecondary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sender.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: sender.isActive ? AppColors.green : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBusy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: sender.isActive,
                    activeColor: AppColors.green,
                    onChanged: (_) => onToggleActive(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
