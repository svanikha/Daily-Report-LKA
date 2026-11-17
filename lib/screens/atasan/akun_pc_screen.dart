import 'package:flutter/material.dart';

import '../../services/akun.dart';
import '../../services/presence_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/cakupan_data.dart';
import '../../widgets/status_online.dart';
import '../../widgets/widgets.dart';

/// Kelola PC: tambah, tempatkan di toko (PC stay), ubah nama, pindah toko, nonaktifkan, reset password.
/// MT: semua toko. Trainer & Sales: toko di cakupannya (dijaga juga di server).
class AkunPcScreen extends StatefulWidget {
  const AkunPcScreen({super.key});

  @override
  State<AkunPcScreen> createState() => _AkunPcScreenState();
}

class _AkunPcScreenState extends State<AkunPcScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _pcs = [];
  List<Map<String, dynamic>> _sales = []; // Trainer: Sales yang dipegang

  Profile get me => Session.current!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _pcs.isEmpty && _stores.isEmpty;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        muatToko(),
        db.from('profiles').select('id,nama,store_id,aktif,auth_uid,last_seen,last_login,logged_in').eq('role', 'pc').order('nama'),
      ]);
      _stores = res[0] as List<Map<String, dynamic>>;
      final ids = _stores.map((s) => toNum(s['id']).toInt()).toSet();
      _pcs = asList(res[1]).where((p) => ids.contains(toNum(p['store_id']).toInt())).toList();
      if (me.isTrainer) {
        final ts = asList(await db.from('trainer_sales').select('sales_id').eq('trainer_id', me.id));
        final sid = ts.map((r) => '${r['sales_id']}').toList();
        _sales = sid.isEmpty
            ? []
            : asList(await db.from('profiles').select('id,nama,auth_uid').inFilter('id', sid).order('nama'));
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _form([Map<String, dynamic>? pc]) async {
    final nama = TextEditingController(text: '${pc?['nama'] ?? ''}');
    int? toko = pc == null ? null : toNum(pc['store_id']).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(pc == null ? 'Tambah PC' : 'Ubah PC'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nama,
              autofocus: pc == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama PC *'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: toko,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Toko *'),
              items: [
                for (final s in _stores)
                  DropdownMenuItem(
                    value: toNum(s['id']).toInt(),
                    child: Text('${s['nama']} · ${s['area'] ?? ''}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setD(() => toko = v),
            ),
            if (pc != null) ...[
              const SizedBox(height: 8),
              Text('Pindah toko: data penjualan lama tetap tercatat di toko lama.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = nama.text.trim();
    nama.dispose();
    if (ok != true) return;
    if (n.isEmpty || toko == null) {
      if (mounted) showMsg(context, 'Nama dan toko wajib diisi');
      return;
    }
    await _jalankan(() => Session.db.rpc('simpan_pc', params: {'p_id': pc?['id'], 'p_nama': n, 'p_store': toko}),
        pc == null ? 'PC $n ditambahkan. PC membuat password sendiri saat login pertama.' : 'Data PC tersimpan');
  }

  Future<void> _reset(Map<String, dynamic> pc) async {
    final ok = await confirmDialog(context, 'Reset password ${pc['nama']}?',
        'PC akan keluar dan membuat password baru saat login berikutnya.', yes: 'Reset');
    if (!ok) return;
    await _jalankan(() => Session.db.rpc('reset_password', params: {'p_profile': pc['id']}),
        'Password ${pc['nama']} direset');
  }

  /// Hapus PERMANEN (MT & Trainer): akun, login, dan semua data penjualan, cek limit, laporan, kehadiran, target.
  Future<void> _hapusPermanen(Map<String, dynamic> pc) async {
    final ok = await confirmDialog(
      context,
      'Hapus permanen ${pc['nama']}?',
      'Akun, login, dan SEMUA data PC ini (penjualan, cek limit, laporan, kehadiran, target) dihapus dan tidak bisa '
          'dikembalikan. Pencapaian toko/area ikut berkurang. Stok toko tidak berubah.\n\nJika hanya berhenti bekerja '
          'dan riwayatnya mau disimpan, pilih Nonaktifkan.',
      yes: 'Hapus permanen',
    );
    if (!ok) return;
    await _jalankan(() => Session.db.rpc('hapus_pc_permanen', params: {'p_pc': pc['id']}),
        'PC ${pc['nama']} dihapus permanen');
  }

  Future<void> _hapus(Map<String, dynamic> pc) async {
    final aktif = pc['aktif'] != false;
    final ok = await confirmDialog(
      context,
      '${aktif ? 'Nonaktifkan' : 'Aktifkan lagi'} PC ${pc['nama']}?',
      aktif
          ? 'Akun tidak bisa login dan tidak wajib lapor. Riwayat penjualan dan laporan tetap tersimpan.'
          : 'PC muncul lagi di layar login dan membuat password baru.',
      yes: aktif ? 'Nonaktifkan' : 'Aktifkan',
    );
    if (!ok) return;
    await _jalankan(
        () => Session.db.rpc('simpan_pc',
            params: {'p_id': pc['id'], 'p_nama': pc['nama'], 'p_store': pc['store_id'], 'p_aktif': !aktif}),
        'PC ${pc['nama']} ${aktif ? 'dinonaktifkan' : 'diaktifkan'}');
  }

  Future<void> _jalankan(Future<dynamic> Function() aksi, String pesan) async {
    setState(() => _busy = true);
    try {
      await aksi();
      await _load();
      if (mounted) showMsg(context, pesan);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PC · ${me.cakupan}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _stores.isEmpty ? null : () => _form(),
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah PC'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                  if (_busy) const LinearProgressIndicator(),
                  const InfoBanner('Ketuk PC untuk mengubah nama atau memindah toko. Tombol gembok = reset password '
                      '(PC lupa password): PC membuat password baru saat login berikutnya. PC baru cukup memilih '
                      'namanya di layar login lalu membuat password sendiri.'),
                  if (_sales.isNotEmpty) ...[
                    const SectionHeader('Sales yang kamu pegang'),
                    for (final s in _sales)
                      Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const Icon(Icons.badge),
                          title: Text('${s['nama']}'),
                          subtitle: Text(s['auth_uid'] == null ? 'Belum membuat password' : 'Sudah login'),
                          trailing: s['auth_uid'] == null
                              ? null
                              : PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (v) {
                                    if (v == 'atur') aturPasswordDialog(context, profileId: '${s['id']}', nama: '${s['nama']}');
                                    if (v == 'reset') _reset(s);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'atur', child: Text('Atur password baru')),
                                    PopupMenuItem(value: 'reset', child: Text('Reset (buat password sendiri)')),
                                  ],
                                ),
                        ),
                      ),
                  ],
                  for (final s in _stores) ..._tokoSection(s),
                ]),
    );
  }

  List<Widget> _tokoSection(Map<String, dynamic> s) {
    final id = toNum(s['id']).toInt();
    final pcs = _pcs.where((p) => toNum(p['store_id']).toInt() == id).toList();
    return [
      SectionHeader('${s['nama']} · ${s['area'] ?? ''}'),
      if (pcs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Belum ada PC',
              style: TextStyle(color: Colors.grey.shade700)),
        ),
      for (final p in pcs)
        Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            title: Text('${p['nama']}${p['aktif'] == false ? ' (nonaktif)' : ''}',
                style: TextStyle(fontWeight: FontWeight.w600, color: p['aktif'] == false ? Colors.grey : null)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatusOnlineRow(status: StatusOnline.dari(p, parseWib)),
              Text(
                p['auth_uid'] == null
                    ? 'Belum membuat password'
                    : 'Login terakhir: ${p['last_login'] == null ? '-' : waktuSingkat(parseWib('${p['last_login']}'))}',
                style: const TextStyle(fontSize: 11),
              ),
            ]),
            onTap: _busy ? null : () => _form(p),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (p['auth_uid'] != null)
                IconButton(
                  tooltip: 'Reset password',
                  onPressed: _busy ? null : () => _reset(p),
                  icon: const Icon(Icons.lock_reset),
                ),
              PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (v) {
                if (v == 'ubah') _form(p);
                if (v == 'reset') _reset(p);
                if (v == 'atur') aturPasswordDialog(context, profileId: '${p['id']}', nama: '${p['nama']}');
                if (v == 'hapus') _hapus(p);
                if (v == 'permanen') _hapusPermanen(p);
                if (v == 'riwayat') showRiwayatLogin(context, '${p['id']}', '${p['nama']}', StatusOnline.dari(p, parseWib));
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'riwayat', child: Text('Riwayat login')),
                const PopupMenuItem(value: 'ubah', child: Text('Ubah nama / pindah toko')),
                if (p['auth_uid'] != null) const PopupMenuItem(value: 'atur', child: Text('Atur password baru')),
                if (p['auth_uid'] != null) const PopupMenuItem(value: 'reset', child: Text('Reset (buat password sendiri)')),
                PopupMenuItem(value: 'hapus', child: Text(p['aktif'] == false ? 'Aktifkan lagi' : 'Nonaktifkan PC')),
                if (me.isMt || me.isTrainer)
                  PopupMenuItem(
                      value: 'permanen',
                      child: Text('Hapus permanen', style: TextStyle(color: Colors.red.shade700))),
              ],
            ),
            ]),
          ),
        ),
    ];
  }
}
