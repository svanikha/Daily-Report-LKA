import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Khusus MT: akun Trainer & Sales, area milik Sales, dan penugasan Trainer -> Sales.
/// Area baru otomatis mendapat list produk HP & IoT induk (salinan list NKA).
class OrganisasiScreen extends StatefulWidget {
  const OrganisasiScreen({super.key});

  @override
  State<OrganisasiScreen> createState() => _OrganisasiScreenState();
}

class _OrganisasiScreenState extends State<OrganisasiScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _orang = [];
  List<Map<String, dynamic>> _areas = [];
  Map<String, String> _trainerDari = {}; // sales_id -> trainer_id

  List<Map<String, dynamic>> _role(String r) => _orang.where((p) => p['role'] == r).toList();
  String _nama(String? id) => '${_orang.where((p) => p['id'] == id).firstOrNull?['nama'] ?? '-'}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _orang.isEmpty;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('profiles').select('id,nama,role,aktif,auth_uid').inFilter('role', ['trainer', 'sales']).order('nama'),
        db.from('areas').select('id,nama,sales_id,aktif').order('nama'),
        db.from('trainer_sales').select('sales_id,trainer_id'),
      ]);
      _orang = asList(res[0]);
      _areas = asList(res[1]);
      _trainerDari = {for (final r in asList(res[2])) '${r['sales_id']}': '${r['trainer_id']}'};
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
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

  Future<void> _formOrang(String role, [Map<String, dynamic>? p]) async {
    final nama = TextEditingController(text: '${p?['nama'] ?? ''}');
    var aktif = p?['aktif'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${p == null ? 'Tambah' : 'Ubah'} ${role == 'sales' ? 'Sales' : 'Trainer'}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nama,
              autofocus: p == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama *'),
            ),
            if (p != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: aktif,
                onChanged: (v) => setD(() => aktif = v),
                title: const Text('Akun aktif'),
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
    if (ok != true || n.isEmpty) return;
    await _jalankan(
      () => Session.db.rpc('simpan_atasan', params: {'p_id': p?['id'], 'p_nama': n, 'p_role': role, 'p_aktif': aktif}),
      p == null ? '$n ditambahkan. Ia membuat password sendiri saat login pertama.' : 'Tersimpan',
    );
  }

  Future<void> _pilihTrainer(Map<String, dynamic> sales) async {
    final trainers = _role('trainer').where((t) => t['aktif'] == true).toList();
    final pilih = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Trainer untuk ${sales['nama']}'),
        children: [
          for (final t in trainers)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, '${t['id']}'), child: Text('${t['nama']}')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ''), child: const Text('— Tanpa Trainer —')),
        ],
      ),
    );
    if (pilih == null) return;
    await _jalankan(
      () => Session.db.rpc('set_trainer_sales', params: {'p_sales': sales['id'], 'p_trainer': pilih.isEmpty ? null : pilih}),
      'Penugasan Trainer tersimpan',
    );
  }

  Future<void> _formArea([Map<String, dynamic>? a]) async {
    final nama = TextEditingController(text: '${a?['nama'] ?? ''}');
    String? sales = a?['sales_id'] as String?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(a == null ? 'Tambah area' : 'Ubah area'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nama, autofocus: a == null, decoration: const InputDecoration(labelText: 'Nama area *')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: sales,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sales pemilik area'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— Belum ada —')),
                for (final s in _role('sales').where((s) => s['aktif'] == true))
                  DropdownMenuItem<String?>(value: '${s['id']}', child: Text('${s['nama']}')),
              ],
              onChanged: (v) => setD(() => sales = v),
            ),
            if (a == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Area baru otomatis mendapat list produk HP & IoT awal.', style: TextStyle(fontSize: 12)),
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
    if (ok != true || n.isEmpty) return;
    await _jalankan(() => Session.db.rpc('simpan_area', params: {'p_id': a?['id'], 'p_nama': n, 'p_sales': sales}),
        a == null ? 'Area $n ditambahkan' : 'Area tersimpan');
  }

  Future<void> _reset(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context, 'Reset password ${p['nama']}?',
        'Ia akan keluar dan membuat password baru saat login berikutnya.', yes: 'Reset');
    if (!ok) return;
    await _jalankan(() => Session.db.rpc('reset_password', params: {'p_profile': p['id']}), 'Password ${p['nama']} direset');
  }

  Widget _orangTile(Map<String, dynamic> p) {
    final sales = p['role'] == 'sales';
    final area = _areas.where((a) => a['sales_id'] == p['id']).map((a) => a['nama']).join(', ');
    final dipegang = _trainerDari.entries.where((e) => e.value == p['id']).map((e) => _nama(e.key)).join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        title: Text('${p['nama']}${p['aktif'] == true ? '' : ' (nonaktif)'}',
            style: TextStyle(fontWeight: FontWeight.w600, color: p['aktif'] == true ? null : Colors.grey)),
        subtitle: Text(sales
            ? 'Area: ${area.isEmpty ? '-' : area} · Trainer: ${_trainerDari[p['id']] == null ? '-' : _nama(_trainerDari[p['id']])}'
                '${p['auth_uid'] == null ? '\nBelum membuat password' : ''}'
            : 'Memegang Sales: ${dipegang.isEmpty ? '-' : dipegang}${p['auth_uid'] == null ? '\nBelum membuat password' : ''}'),
        isThreeLine: p['auth_uid'] == null,
        trailing: PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (v) {
            if (v == 'ubah') _formOrang('${p['role']}', p);
            if (v == 'trainer') _pilihTrainer(p);
            if (v == 'reset') _reset(p);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'ubah', child: Text('Ubah nama / aktif')),
            if (sales) const PopupMenuItem(value: 'trainer', child: Text('Atur Trainer')),
            if (p['auth_uid'] != null) const PopupMenuItem(value: 'reset', child: Text('Reset password')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales, Trainer & area')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                  if (_busy) const LinearProgressIndicator(),
                  const InfoBanner('Urutan pengisian: 1) Trainer, 2) Sales lalu atur Trainer-nya, 3) Area dan Sales pemiliknya, '
                      '4) Toko di menu Toko, 5) PC di menu PC.'),
                  SectionHeader('Trainer',
                      trailing: TextButton.icon(
                          onPressed: _busy ? null : () => _formOrang('trainer'),
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah'))),
                  for (final p in _role('trainer')) _orangTile(p),
                  SectionHeader('Sales',
                      trailing: TextButton.icon(
                          onPressed: _busy ? null : () => _formOrang('sales'),
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah'))),
                  for (final p in _role('sales')) _orangTile(p),
                  SectionHeader('Area',
                      trailing: TextButton.icon(
                          onPressed: _busy ? null : () => _formArea(), icon: const Icon(Icons.add), label: const Text('Tambah'))),
                  for (final a in _areas)
                    Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        leading: const Icon(Icons.map),
                        title: Text('${a['nama']}'),
                        subtitle: Text('Sales: ${a['sales_id'] == null ? '-' : _nama(a['sales_id'] as String?)}'
                            ' · Trainer: ${a['sales_id'] == null || _trainerDari[a['sales_id']] == null ? '-' : _nama(_trainerDari[a['sales_id']])}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: _busy ? null : () => _formArea(a),
                      ),
                    ),
                ]),
    );
  }
}
