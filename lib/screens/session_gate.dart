import 'package:flutter/material.dart';

import '../config.dart';
import '../services/presence_service.dart';
import '../services/session.dart';
import '../widgets/widgets.dart';
import 'atasan/atasan_home.dart';
import 'login_screen.dart';
import 'pc/pc_home.dart';

Widget homeFor(Profile p) => p.usesAdminHome ? const AtasanHome() : PcHome(pc: p);

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late Future<Profile?> _future = _muat();

  static Future<Profile?> _muat() async {
    final p = await Session.load();
    if (p != null) PresenceService.buka();
    return p;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aplikasi belum dihubungkan ke server Supabase.\nIsi Variables SUPABASE_URL dan SUPABASE_ANON_KEY di GitHub lalu build ulang.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return FutureBuilder<Profile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: ErrorRetry(
              error: 'Gagal memuat akun: ${errMsg(snap.error!)}',
              onRetry: () => setState(() => _future = _muat()),
            ),
          );
        }
        final p = snap.data;
        if (p == null) return const LoginScreen();
        return homeFor(p);
      },
    );
  }
}
