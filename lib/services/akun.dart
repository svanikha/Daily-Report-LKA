import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../screens/login_screen.dart';
import '../widgets/widgets.dart';
import 'notif_service.dart';
import 'presence_service.dart';
import 'session.dart';

Future<void> changePasswordDialog(BuildContext context) async {
  final a = TextEditingController();
  final b = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ganti password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'Password baru')),
        const SizedBox(height: 12),
        TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Ketik ulang')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (a.text.length < 6) {
    showMsg(context, 'Password minimal 6 karakter');
    return;
  }
  if (a.text != b.text) {
    showMsg(context, 'Konfirmasi password tidak sama');
    return;
  }
  try {
    await Session.db.auth.updateUser(UserAttributes(password: a.text));
    if (context.mounted) showMsg(context, 'Password berhasil diganti');
  } catch (e) {
    if (context.mounted) showErr(context, e);
  }
}

/// Atur password baru untuk akun lain (MT: semua; Trainer: Sales & PC-nya; Sales: PC-nya).
/// Password lama tidak bisa dilihat siapa pun; password baru ditampilkan sekali untuk diberitahukan.
Future<void> aturPasswordDialog(BuildContext context, {required String profileId, required String nama}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Atur password $nama'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password baru (min. 6 karakter)'),
        ),
        const SizedBox(height: 8),
        const Text('Beritahukan password ini ke pemilik akun. Ia bisa menggantinya sendiri di menu Akun.',
            style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
      ],
    ),
  );
  final pw = c.text.trim();
  c.dispose();
  if (ok != true || !context.mounted) return;
  if (pw.length < 6) {
    showMsg(context, 'Password minimal 6 karakter');
    return;
  }
  try {
    await Session.db.rpc('atur_password', params: {'p_profile': profileId, 'p_password': pw});
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 36),
        title: const Text('Password tersimpan'),
        content: SelectableText('$nama\nPassword: $pw', style: const TextStyle(fontSize: 16)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  } catch (e) {
    if (context.mounted) showErr(context, e);
  }
}

Future<void> logout(BuildContext context) async {
  final ok = await confirmDialog(context, 'Keluar?', 'Kamu perlu memasukkan password lagi saat masuk.', yes: 'Keluar');
  if (!ok) return;
  await NotifService.cancelAll();
  await PresenceService.logout();
  await Session.db.auth.signOut();
  Session.current = null;
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
}

/// Tombol menu akun (ganti password, keluar) untuk AppBar.
class AkunMenuButton extends StatelessWidget {
  const AkunMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Session.current;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle),
      tooltip: 'Akun',
      onSelected: (v) {
        if (v == 'pw') changePasswordDialog(context);
        if (v == 'out') logout(context);
      },
      itemBuilder: (_) => [
        if (p != null)
          PopupMenuItem<String>(
            enabled: false,
            child: Text('${p.nama}\n${p.roleLabel} · ${p.cakupan}', style: const TextStyle(color: Colors.black87)),
          ),
        const PopupMenuItem(value: 'pw', child: ListTile(leading: Icon(Icons.key), title: Text('Ganti password'))),
        const PopupMenuItem(value: 'out', child: ListTile(leading: Icon(Icons.logout), title: Text('Keluar'))),
      ],
    );
  }
}
