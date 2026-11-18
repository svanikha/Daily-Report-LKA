import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

/// Hemat egress: hasil RPC beranda disimpan sementara di HP (memori + penyimpanan HP) selama [umur].
/// Buka-tutup aplikasi dalam 5 menit memakai data yang sama tanpa mengambil ulang dari server.
/// Tarik-ke-bawah / tombol muat ulang / kembali dari layar ubah data -> [bersihkan] lalu ambil data baru.
class CacheData {
  static const umur = Duration(minutes: 5);
  static const _prefix = 'cache_rpc|';
  static final Map<String, (DateTime, dynamic)> _mem = {};
  static SharedPreferences? _sp;

  static Future<SharedPreferences?> _prefs() async {
    try {
      return _sp ??= await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static String _kunci(String fn, Map<String, dynamic> params) =>
      '$_prefix${Session.current?.id ?? '-'}|$fn|${jsonEncode(params)}';

  /// Panggil RPC [fn] dengan cache. [paksa] = abaikan cache dan ambil dari server.
  static Future<dynamic> rpc(String fn, Map<String, dynamic> params, {bool paksa = false}) async {
    final k = _kunci(fn, params);
    final now = DateTime.now();
    if (!paksa) {
      final m = _mem[k];
      if (m != null && now.difference(m.$1) < umur) return m.$2;
      final sp = await _prefs();
      final s = sp?.getString(k);
      if (s != null) {
        try {
          final j = jsonDecode(s) as Map<String, dynamic>;
          final t = DateTime.fromMillisecondsSinceEpoch(j['t'] as int);
          if (now.difference(t) < umur) {
            _mem[k] = (t, j['v']);
            return j['v'];
          }
        } catch (_) {}
      }
    }
    final v = await Session.db.rpc(fn, params: params);
    _mem[k] = (now, v);
    final sp = await _prefs();
    try {
      await sp?.setString(k, jsonEncode({'t': now.millisecondsSinceEpoch, 'v': v}));
    } catch (_) {}
    return v;
  }

  /// Hapus semua cache (setelah data diubah atau muat ulang manual).
  static Future<void> bersihkan() async {
    _mem.clear();
    final sp = await _prefs();
    if (sp == null) return;
    for (final k in sp.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await sp.remove(k);
    }
  }
}
