import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/printer_provider.dart';

/// Bottom sheet untuk pilih & sambungkan printer thermal Bluetooth yang
/// sudah di-pairing di pengaturan HP/tablet (pairing Bluetooth-nya sendiri
/// dilakukan lewat Settings HP, bukan dari dalam app ini).
///
/// Return `true` lewat Navigator.pop kalau berhasil connect, supaya
/// pemanggil tahu boleh lanjut cetak.
class PrinterConnectSheet extends ConsumerWidget {
  const PrinterConnectSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PrinterConnectSheet(),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairedAsync = ref.watch(pairedPrintersProvider);
    final connectionState = ref.watch(printerConnectionProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pilih Printer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref.invalidate(pairedPrintersProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Pastikan printer sudah di-pairing lewat pengaturan '
                    'Bluetooth HP/tablet ini terlebih dahulu.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: pairedAsync.when(
                  data: (devices) {
                    if (devices.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Belum ada printer yang ter-pairing. '
                            'Pairing dulu lewat Pengaturan Bluetooth HP.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isConnected =
                            connectionState.connectedDevice?.macAdress ==
                                device.macAdress;

                        return ListTile(
                          leading: Icon(
                            Icons.print_rounded,
                            color: isConnected
                                ? AppColors.green
                                : AppColors.textSecondary,
                          ),
                          title: Text(
                            device.name.isEmpty
                                ? '(Tanpa nama)'
                                : device.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: Text(device.macAdress),
                          trailing: isConnected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.green,
                                )
                              : (connectionState.isConnecting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null),
                          onTap: connectionState.isConnecting
                              ? null
                              : () async {
                                  final success = await ref
                                      .read(
                                        printerConnectionProvider.notifier,
                                      )
                                      .connect(device);

                                  if (!context.mounted) return;

                                  if (success) {
                                    Navigator.of(context).pop(true);
                                  } else {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Gagal menyambung ke printer.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.blue),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Text(
                      'Gagal memuat daftar printer: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.red),
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