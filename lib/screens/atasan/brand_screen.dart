import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Khusus MT: daftar & urutan brand MS Allbrand. Brand yang tidak dipakai dinonaktifkan (data lama tetap).
class BrandScreen extends StatefulWidget {
  const BrandScreen({super.key});

  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      _rows = asList(await Session.db.from('competitor_brands').select().order('urutan'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _simpanUrutan() async {
    try {
      for (var i = 0; i < _rows.length; i++) {
        await Session.db.from('competitor_brands').update({'urutan': i + 1}).eq('id', _rows[i]['id'] as int);
      }
      if (mounted) showMsg(context, 'Urutan tersimpan');
    } catch (e) {
      if (mounted) showErr(context, e);
      _load();
    }
  }

  Future<void> _aktif(Map<String, dynamic> b, bool v) async {
    try {
      await Session.db.from('competitor_brands').update({'aktif': v}).eq('id', b['id'] as int);
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _tambah() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Brand baru'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nama brand')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    final n = c.text.trim();
    c.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await Session.db.from('competitor_brands').insert({'nama': n, 'urutan': _rows.length + 1});
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Brand MS Allbrand')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _tambah, icon: const Icon(Icons.add), label: const Text('Brand baru')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : Column(children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: InfoBanner('Tahan & geser untuk mengubah urutan. Apple hanya segmen 6 jt up.'),
                  ),
                  Expanded(
                    child: ReorderableListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      onReorder: (a, b) {
                        setState(() {
                          if (b > a) b--;
                          _rows.insert(b, _rows.removeAt(a));
                        });
                        _simpanUrutan();
                      },
                      children: [
                        for (final b in _rows)
                          Card(
                            key: ValueKey(b['id']),
                            margin: const EdgeInsets.only(bottom: 4),
                            child: SwitchListTile(
                              value: b['aktif'] == true,
                              onChanged: (v) => _aktif(b, v),
                              title: Text('${b['nama']}'),
                              subtitle: Text(b['aktif'] == true ? 'Tampil di input MS' : 'Nonaktif'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ]),
    );
  }
}
