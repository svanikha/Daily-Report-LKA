import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/cakupan_data.dart';
import '../../widgets/widgets.dart';

/// Kelola toko: tambah, ganti nama, nonaktifkan. Pindah area hanya MT.
/// Toko tidak dihapus supaya riwayat penjualan tetap tersimpan.
class TokoScreen extends StatefulWidget {
  const TokoScreen({super.key});

  @override
  State<TokoScreen> createState() => _TokoScreenState();
}

class _TokoScreenState extends State<TokoScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _toko = [];
  List<Map<String, dynamic>> _areas = [];

  bool get _mt => Session.current?.isMt ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _toko.isEmpty;
      _error = null;
    });
    try {
      final res = await Future.wait([muatToko(semua: true), muatArea()]);
      _toko = res[0];
      _areas = res[1];
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _form([Map<String, dynamic>? t]) async {
    final nama = TextEditingController(text: '${t?['nama'] ?? ''}');
    int? area = t == null ? (_areas.length == 1 ? toNum(_areas.first['id']).toInt() : null) : toNum(t['area_id']).toInt();
    var aktif = t?['aktif'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(t == null ? 'Tambah toko' : 'Ubah toko'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nama,
              autofocus: t == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama toko *'),
            ),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: t != null && !_mt,
              child: AreaDropdown(areas: _areas, value: area, onChanged: (v) => setD(() => area = v), label: 'Area *'),
            ),
            if (t != null && !_mt)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Pindah area hanya oleh Manajer Trainer.', style: TextStyle(fontSize: 12)),
              ),
            if (t != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: aktif,
                onChanged: (v) => setD(() => aktif = v),
                title: const Text('Toko aktif'),
                subtitle: const Text('Nonaktif = hilang dari laporan; riwayat tetap tersimpan'),
              ),
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
    if (n.isEmpty || area == null) {
      if (mounted) showMsg(context, 'Nama dan area wajib diisi');
      return;
    }
    setState(() => _busy = true);
    try {
      await Session.db.rpc('simpan_toko', params: {'p_id': t?['id'], 'p_nama': n, 'p_area': area, 'p_aktif': aktif});
      await _load();
      if (mounted) showMsg(context, t == null ? 'Toko $n ditambahkan. Tambahkan PC di menu PC.' : 'Toko tersimpan');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    String? area;
    final out = <Widget>[];
    for (final t in _toko) {
      if (t['area'] != area) {
        area = '${t['area']}';
        out.add(SectionHeader('Area $area${t['sales'] != null ? ' · ${t['sales']}' : ''}'));
      }
      final pcs = asList(t['pc']);
      out.add(Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          leading: Icon(Icons.store, color: t['aktif'] == true ? null : Colors.grey),
          title: Text('${t['nama']}${t['aktif'] == true ? '' : ' (nonaktif)'}',
              style: TextStyle(color: t['aktif'] == true ? null : Colors.grey)),
          subtitle: Text(pcs.isEmpty ? 'Belum ada PC' : '${pcs.length} PC: ${pcs.map((p) => p['nama']).join(', ')}'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: _busy ? null : () => _form(t),
        ),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Toko')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _areas.isEmpty ? null : () => _form(),
        icon: const Icon(Icons.add_business),
        label: const Text('Tambah toko'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_areas.isEmpty) const InfoBanner('Belum ada area di cakupan akun ini. Area dibuat oleh MT.'),
                  if (_toko.isEmpty && _areas.isNotEmpty) const EmptyState(text: 'Belum ada toko', icon: Icons.store),
                  ...out,
                ]),
    );
  }
}
