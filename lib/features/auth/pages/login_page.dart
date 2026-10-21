import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/session_provider.dart';
import '../../../services/auth_service.dart';
import 'splash_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Email dan password wajib diisi.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signIn(
        email: email,
        password: password,
      );

      // Pastikan provider session tidak memakai cache dari akun
      // sebelumnya kalau ini login sebagai user yang berbeda.
      invalidateSession(ref);

      if (!mounted) return;

      // Setelah login berhasil, kembali ke SplashPage.
      // SplashPage bertugas menentukan halaman berdasarkan role.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const SplashPage(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Login gagal. Periksa email dan password.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 400,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      size: 64,
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'TRANS',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Manifest Pengiriman',
                    ),

                    // **DIHAPUS (13 Oktober 2026, permintaan user eksplisit:
                    // "Saya memilih untuk menggunakan website lain. Link
                    // berbeda... Sehingga tidak ada kemungkinan diluar
                    // perusahaan bisa memiliki akses pada aplikasi")** --
                    // tombol "Telusuri Kiriman" yang SEBELUMNYA ada di sini
                    // (membuka `TrackShipmentPage` embedded di app Flutter
                    // ini) DIHAPUS SELURUHNYA. Fitur cek resi publik
                    // sekarang HANYA ada di website statis TERPISAH (bukan
                    // bagian dari app ini sama sekali, domain berbeda) --
                    // supaya publik tidak pernah punya jalur apa pun menuju
                    // app Flutter ini (termasuk halaman login-nya pun tidak
                    // perlu dibuka publik lagi kalau tidak untuk login).
                    // Link ke website itu disimpan admin di
                    // `CompanyModel.companyPublicUrl` ("Profil Perusahaan"),
                    // ditampilkan di footer WA & cetakan Resi -- BUKAN lagi
                    // lewat tombol di halaman ini. `TrackShipmentPage` &
                    // `TrackShipmentService` DIBIARKAN ada di kode (tidak
                    // dihapus filenya) tapi sekarang jadi dead code, tidak
                    // dipanggil dari mana pun.
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: Divider(color: AppColors.border),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'Masuk sebagai Pegawai',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: AppColors.border),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    TextField(
                      controller: _emailController,
                      keyboardType:
                          TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border:
                            const OutlineInputBorder(),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword =
                                  !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _login(),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed:
                            _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('LOGIN'),
                      ),
                    ),

                    // "Register Employee" DIHAPUS dari sini (8 Oktober
                    // 2026, permintaan user poin 8: "Pada login,
                    // hilangkan register pengguna baru") -- pembuatan
                    // user pegawai baru sekarang HANYA lewat menu admin
                    // "Buat User Pegawai" (lihat
                    // `employee_create_page.dart`), bukan publik lagi.
                    //
                    // Tombol "Telusuri Kiriman" (poin 11, link PUBLIK,
                    // TIDAK perlu login) DIPINDAH ke ATAS form email/
                    // password (9 Oktober 2026, lihat Container berframe
                    // di atas) -- tidak ada lagi duplikatnya di sini.
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
