import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../services/admin_auth_service.dart';

/// Halaman Admin "Buat User Pegawai" (8 Oktober 2026, permintaan user
/// poin 8) -- MENGGANTIKAN self-register publik yang sebelumnya bisa
/// diakses siapa saja lewat tombol "Register Employee" di halaman login
/// (sudah DIHAPUS, lihat `login_page.dart`). Sekarang HANYA admin yang
/// bisa membuat akun pegawai baru, dari dalam Dashboard.
///
/// Formnya SAMA PERSIS `RegisterPage` lama (nomor employee, nama, HP,
/// role, email, password) supaya tidak ada perubahan pengalaman input --
/// bedanya cuma siapa yang mengaksesnya & cara pembuatan akun Auth-nya
/// (lihat doc comment panjang di `AdminAuthService` soal kenapa TIDAK
/// pakai `signUp()` biasa). Password DIKETIK ADMIN SENDIRI (bukan
/// digenerate random) -- sesuai permintaan "dibagikan kepada pegawai
/// dengan passwordnya", supaya admin tahu pasti apa yang harus dibagikan.
class EmployeeCreatePage extends StatefulWidget {
  const EmployeeCreatePage({super.key});

  @override
  State<EmployeeCreatePage> createState() => _EmployeeCreatePageState();
}

class _EmployeeCreatePageState extends State<EmployeeCreatePage> {
  final _formKey = GlobalKey<FormState>();

  final _employeeNumberController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  List<Map<String, dynamic>> _roles = [];
  String? _selectedRoleId;

  bool _isLoading = false;
  bool _isLoadingRoles = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  @override
  void dispose() {
    _employeeNumberController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    try {
      final response = await SupabaseService.client
          .from('employee_roles')
          .select('id, code, name')
          .eq('is_active', true)
          .order('name');

      if (!mounted) return;

      setState(() {
        // HELPER dikeluarkan dari pilihan -- sama seperti RegisterPage
        // lama, Helper cuma data (dipilih admin saat "Siapkan
        // Kendaraan"), bukan pengguna aplikasi yang login sendiri.
        _roles = List<Map<String, dynamic>>.from(response)
            .where((role) => (role['code'] as String?)?.toUpperCase() != 'HELPER')
            .toList();

        if (_roles.isNotEmpty) {
          _selectedRoleId = _roles.first['id'] as String;
        }

        _isLoadingRoles = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingRoles = false;
        _errorMessage = 'Gagal mengambil data role: ${e.toString()}';
      });
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRoleId == null) {
      setState(() => _errorMessage = 'Silakan pilih role employee.');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Password dan konfirmasi password tidak sama.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final employeeNumber = _employeeNumberController.text.trim();
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      await AdminAuthService.createEmployeeAccount(
        employeeNumber: employeeNumber,
        fullName: fullName,
        phone: _phoneController.text.trim(),
        email: email,
        password: password,
        roleId: _selectedRoleId!,
      );

      if (!mounted) return;

      // Tampilkan ulang email + password yang baru dibuat -- supaya
      // admin bisa langsung screenshot/catat untuk dibagikan ke pegawai
      // ybs (permintaan user: "dibagikan kepada pegawai dengan
      // passwordnya").
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('User Pegawai Dibuat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nama: $fullName'),
              Text('Nomor Employee: $employeeNumber'),
              const SizedBox(height: 8),
              Text('Email login: $email'),
              Text('Password: $password'),
              const SizedBox(height: 12),
              const Text(
                'Catat/screenshot sekarang untuk dibagikan ke pegawai '
                'bersangkutan -- password TIDAK ditampilkan lagi setelah '
                'ini ditutup.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(Object error) {
    final message = error.toString();

    if (message.contains('already registered') || message.contains('already exists')) {
      return 'Email tersebut sudah terdaftar.';
    }

    if (message.contains('employee_number')) {
      return 'Nomor employee tersebut sudah digunakan.';
    }

    if (message.contains('role_id')) {
      return 'Role employee tidak valid.';
    }

    return 'Gagal membuat user: $message';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat User Pegawai'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.person_add_alt_1, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Buat User Pegawai',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Akun login + password dibuat admin di sini, lalu '
                        'dibagikan manual ke pegawai bersangkutan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _employeeNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Nomor Employee',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Nomor employee wajib diisi.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Lengkap',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Nama lengkap wajib diisi.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Nomor HP',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildRoleDropdown(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email wajib diisi.';
                          }
                          if (!value.contains('@')) {
                            return 'Format email tidak valid.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Password wajib diisi.';
                          if (value.length < 6) return 'Password minimal 6 karakter.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Konfirmasi Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _obscureConfirmPassword = !_obscureConfirmPassword,
                            ),
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Konfirmasi password wajib diisi.'
                            : null,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: (_isLoading || _isLoadingRoles || _roles.isEmpty)
                              ? null
                              : _create,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('BUAT USER'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    if (_isLoadingRoles) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Role',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.work_outline),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Memuat role...'),
          ],
        ),
      );
    }

    if (_roles.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Role',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.work_outline),
        ),
        child: Text('Tidak ada role aktif.'),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedRoleId,
      decoration: const InputDecoration(
        labelText: 'Role',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.work_outline),
      ),
      items: _roles.map((role) {
        return DropdownMenuItem<String>(
          value: role['id'] as String,
          child: Text(role['name'] as String),
        );
      }).toList(),
      onChanged: _isLoading ? null : (value) => setState(() => _selectedRoleId = value),
      validator: (value) => (value == null || value.isEmpty) ? 'Role wajib dipilih.' : null,
    );
  }
}
