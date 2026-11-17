import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../services/presence_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/pickers.dart';
import '../widgets/widgets.dart';
import 'session_gate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _loadError;
  bool _isAtasan = false;
  Map<String, dynamic>? _selected;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _profiles = asList(await Session.db.rpc('list_login_profiles'));
    } catch (e) {
      _loadError = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _daftar =>
      _profiles.where((p) => _isAtasan ? p['role'] != 'pc' : p['role'] == 'pc').toList();

  static String _sub(Map<String, dynamic> p) => switch (p['role']) {
        'pc' => '${p['toko']} · ${p['area']}',
        'sales' => 'Sales${'${p['area']}'.isEmpty ? '' : ' · ${p['area']}'}',
        _ => labelRole('${p['role']}'),
      };

  /// Akun MT dibuat di Supabase. Trainer, Sales, dan PC membuat password sendiri saat login pertama.
  bool get _needCreate => _selected != null && _selected!['role'] != 'mt' && _selected!['sudah_daftar'] != true;

  Future<void> _pilih() async {
    final p = await showSearchPicker(
      context,
      title: _isAtasan ? 'Pilih nama MT / Trainer / Sales' : 'Pilih nama Product Consultant',
      loader: () async => _daftar,
      titleOf: (m) => '${m['nama']}',
      subtitleOf: _sub,
    );
    if (p != null) {
      setState(() {
        _selected = p;
        _pw.clear();
        _pw2.clear();
      });
    }
  }

  Future<void> _submit() async {
    final p = _selected;
    if (p == null) {
      showMsg(context, 'Pilih nama terlebih dahulu');
      return;
    }
    final pw = _pw.text;
    if (pw.length < 6) {
      showMsg(context, 'Password minimal 6 karakter');
      return;
    }
    if (_needCreate && pw != _pw2.text) {
      showMsg(context, 'Konfirmasi password tidak sama');
      return;
    }
    setState(() => _busy = true);
    final auth = Session.db.auth;
    try {
      if (_needCreate) {
        final res = await auth.signUp(email: p['email'] as String, password: pw);
        if (res.session == null) {
          throw 'Akun dibuat, tetapi login otomatis gagal. Minta MT mematikan "Confirm email" di Supabase.';
        }
      } else {
        await auth.signInWithPassword(email: p['email'] as String, password: pw);
      }
      final prof = await Session.load();
      if (prof == null) {
        await auth.signOut();
        throw 'Akun belum terhubung ke data. Hubungi Sales, Trainer, atau MT.';
      }
      await PresenceService.login();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => homeFor(prof)), (_) => false);
    } on AuthException catch (e) {
      if (mounted) {
        final m = e.message.toLowerCase();
        showMsg(
          context,
          m.contains('invalid login')
              ? 'Password salah'
              : (m.contains('already') ? 'Akun sudah terdaftar. Muat ulang lalu masukkan password.' : e.message),
        );
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? ErrorRetry(error: 'Tidak bisa terhubung ke server.\n$_loadError', onRetry: _load)
                : ListView(padding: const EdgeInsets.all(24), children: [
                    const SizedBox(height: 24),
                    const Icon(Icons.assignment_turned_in, size: 64, color: brandGreen),
                    const SizedBox(height: 8),
                    Text(
                      'Daily Report LKA',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: brandGreen),
                    ),
                    const Text('Local Key Account · OPPO Big Sampit', textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Product Consultant'), icon: Icon(Icons.person)),
                        ButtonSegment(value: true, label: Text('MT · Trainer · Sales'), icon: Icon(Icons.admin_panel_settings)),
                      ],
                      selected: {_isAtasan},
                      onSelectionChanged: (s) => setState(() {
                        _isAtasan = s.first;
                        _selected = null;
                        _pw.clear();
                        _pw2.clear();
                      }),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _pilih,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: _isAtasan ? 'Nama MT / Trainer / Sales' : 'Nama Product Consultant',
                          suffixIcon: const Icon(Icons.search),
                        ),
                        child: Text(sel == null ? 'Ketuk untuk memilih nama' : '${sel['nama']}'),
                      ),
                    ),
                    if (sel != null) ...[
                      const SizedBox(height: 6),
                      Text(_sub(sel), style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (_needCreate) ...[
                      const SizedBox(height: 12),
                      const InfoBanner('Login pertama: buat password kamu (minimal 6 karakter).', icon: Icons.key),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: _needCreate ? 'Buat password' : 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_needCreate) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pw2,
                        obscureText: _obscure,
                        decoration: const InputDecoration(labelText: 'Ketik ulang password'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: busyIcon(_busy, Icons.login),
                      label: Text(_needCreate ? 'Buat password & masuk' : 'Masuk'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Lupa password? Minta Sales, Trainer, atau MT melakukan reset.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ]),
      ),
    );
  }
}
