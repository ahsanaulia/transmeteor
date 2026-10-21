import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../models/destination_model.dart';
import '../../../services/destination_service.dart';
import 'receiving_by_destination_page.dart';

/// Daftar semua tujuan (destinations) yang pernah dipakai -- dari sini
/// staff Receiving bisa tap satu tujuan untuk lihat & cetak semua resi
/// yang menuju ke tujuan yang sama (ReceivingByDestinationPage).
///
/// Ini yang menjawab kasus: 4 pengirim berbeda kirim ke tujuan yang sama
/// -- supaya sopir tidak perlu bolak-balik ke tujuan yang sama beberapa
/// kali kalau resinya dicek satu per satu.
class ReceivingDestinationsPage extends StatefulWidget {
  const ReceivingDestinationsPage({super.key});

  @override
  State<ReceivingDestinationsPage> createState() =>
      _ReceivingDestinationsPageState();
}

class _ReceivingDestinationsPageState
    extends State<ReceivingDestinationsPage> {
  final _searchController = TextEditingController();

  List<DestinationModel> _destinations = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({String? keyword}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final destinations = keyword != null && keyword.trim().isNotEmpty
          ? await DestinationService.searchDestinations(keyword.trim())
          : await DestinationService.getDestinations();

      if (!mounted) return;

      setState(() {
        _destinations = destinations;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(keyword: value));
  }

  void _openDestination(DestinationModel destination) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceivingByDestinationPage(destination: destination),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daftar Resi per Tujuan',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Pilih tujuan untuk lihat & cetak semua resinya',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: AppTextField(
                controller: _searchController,
                label: 'Cari Tujuan',
                hint: 'Ketik nama tujuan...',
                icon: Icons.search_rounded,
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    if (_errorMessage != null) {
      return ErrorStateView(
        title: 'Gagal memuat daftar tujuan',
        message: _errorMessage,
        onRetry: () => _load(keyword: _searchController.text),
      );
    }

    if (_destinations.isEmpty) {
      return const ErrorStateView(
        icon: Icons.place_outlined,
        title: 'Belum ada tujuan',
        message: 'Tujuan akan muncul di sini setelah dipakai saat '
            'menerima barang.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: _destinations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final destination = _destinations[index];

        return AppCard(
          padding: const EdgeInsets.all(14),
          child: InkWell(
            onTap: () => _openDestination(destination),
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.place_rounded,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (destination.address != null &&
                          destination.address!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          destination.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
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
        );
      },
    );
  }
}
