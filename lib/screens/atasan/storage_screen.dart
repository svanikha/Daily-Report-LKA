import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

String ukuranTeks(num b) {
  if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '$b B';
}

/// Penyimpanan server (khusus MT). LKA tidak menyimpan foto: isi storage hanya APK update aplikasi.
/// APK lama dihapus otomatis oleh GitHub Actions setiap build (hanya 5 terbaru per saluran yang disimpan).
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _r;
  Map<String, dynamic>? _bersih;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Session.db.rpc('info_storage'));
      try {
        _bersih = asMap(await Session.db.rpc('info_bersih'));
      } catch (_) {}
      if (mounted) {
        setState(() {
          _r = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errMsg(e));
    }
  }

  Future<void> _bersihkan() async {
    final ok = await confirmDialog(
      context,
      'Bersihkan sekarang?',
      'Semua data harian yang lebih tua dari 1 tahun (sebelum ${_bersih?['batas'] ?? '-'}) dihapus permanen. '
          'Akun, toko, produk, dan stok terkini tidak dihapus.',
      yes: 'Bersihkan',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final r = asMap(await Session.db.rpc('bersihkan_sekarang'));
      final total = r.entries.where((e) => e.key != 'batas').fold<num>(0, (a, e) => a + toNum(e.value));
      if (mounted) showMsg(context, '${angka(total)} baris data lama dihapus');
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _kartuBersih() {
    final b = _bersih;
    if (b == null) return const SizedBox.shrink();
    final log = asList(b['log']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Hapus otomatis data > 1 tahun', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Setiap hari pukul 02.00 WIB, data harian sebelum ${b['batas']} dihapus: penjualan, NOSELL, cek limit, '
              'laporan, kehadiran, MS Allbrand, riwayat stok, target, riwayat login & perubahan. '
              'Akun, toko, area, produk, dan stok terkini tetap.',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (log.isEmpty) const Text('Belum pernah berjalan.', style: TextStyle(fontSize: 12)),
          for (final l in log)
            Text(
              '${tglJam(parseWib('${l['waktu']}'))} · ${l['pemicu']} · '
              '${asMap(l['rincian']).values.fold<num>(0, (a, v) => a + toNum(v))} baris dihapus',
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _bersihkan,
            icon: const Icon(Icons.cleaning_services),
            label: const Text('Bersihkan sekarang'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('Penyimpanan server')),
      body: _error != null
          ? ErrorRetry(error: _error!, onRetry: _load)
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    StatGrid(children: [
                      StatCard(
                          label: 'Database', value: ukuranTeks(toNum(r['db_bytes'])), sub: 'kuota Free 500 MB', icon: Icons.dns),
                      StatCard(
                          label: 'File storage', value: ukuranTeks(toNum(r['total'])), sub: 'kuota Free 1 GB', icon: Icons.folder),
                      StatCard(
                          label: 'APK tersimpan',
                          value: '${r['apk_jumlah']} file',
                          sub: ukuranTeks(toNum(r['apk_bytes'])),
                          icon: Icons.android),
                    ]),
                    const SizedBox(height: 8),
                    const InfoBanner('Daily Report LKA tidak menyimpan foto. APK lama dihapus otomatis setiap ada build baru '
                        '(5 APK terbaru per saluran tetap disimpan).'),
                    _kartuBersih(),
                    const SectionHeader('APK'),
                    for (final a in asList(r['apk']))
                      Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.android),
                          title: Text('${a['nama']}'),
                          subtitle: Text('${ukuranTeks(toNum(a['size']))} · ${tglJam(parseWib('${a['dibuat']}'))}'),
                        ),
                      ),
                  ]),
                ),
    );
  }
}
