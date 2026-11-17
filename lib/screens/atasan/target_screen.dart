import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/lka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/cakupan_data.dart';
import '../../widgets/widgets.dart';

/// Target bulanan per toko dan per PC (unit HP, value HP, tipe fokus, unit IoT, value IoT), diisi manual.
/// Target toko yang kosong dihitung dari jumlah target PC di toko itu.
/// MT: semua toko. Trainer & Sales: toko di cakupannya.
class TargetScreen extends StatefulWidget {
  const TargetScreen({super.key});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  DateTime _bulan = monthStart();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _perPc = false;
  List<Map<String, dynamic>> _toko = [];
  List<Map<String, dynamic>> _areas = [];
  int? _area;
  final Map<String, TextEditingController> _c = {}; // "s|storeId|jenis" atau "p|pcId|jenis"

  List<Map<String, dynamic>> get _tokoTampil =>
      _toko.where((t) => _area == null || toNum(t['area_id']).toInt() == _area).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        muatToko(),
        muatArea(),
        db.from('store_targets').select('store_id,jenis,nilai').eq('bulan', ymd(_bulan)),
        db.from('pc_targets').select('pc_id,jenis,nilai').eq('bulan', ymd(_bulan)),
      ]);
      _toko = res[0] as List<Map<String, dynamic>>;
      _areas = res[1] as List<Map<String, dynamic>>;
      final nilai = {
        for (final r in asList(res[2])) 's|${r['store_id']}|${r['jenis']}': toNum(r['nilai']),
        for (final r in asList(res[3])) 'p|${r['pc_id']}|${r['jenis']}': toNum(r['nilai']),
      };
      for (final c in _c.values) {
        c.dispose();
      }
      _c.clear();
      for (final t in _toko) {
        for (final d in targetDefs) {
          final k = 's|${t['id']}|${d.jenis}';
          _c[k] = TextEditingController(text: _teks(nilai[k]));
          for (final p in asList(t['pc'])) {
            final kp = 'p|${p['id']}|${d.jenis}';
            _c[kp] = TextEditingController(text: _teks(nilai[kp]));
          }
        }
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _teks(num? v) => v == null || v == 0 ? '' : '${v.toInt()}';
  num _v(String k) => digitsOnly(_c[k]?.text ?? '');

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final b = ymd(_bulan);
      if (_perPc) {
        final rows = [
          for (final t in _tokoTampil)
            for (final p in asList(t['pc']))
              for (final d in targetDefs) {'pc_id': p['id'], 'bulan': b, 'jenis': d.jenis, 'nilai': _v('p|${p['id']}|${d.jenis}')}
        ];
        if (rows.isNotEmpty) await Session.db.from('pc_targets').upsert(rows, onConflict: 'pc_id,bulan,jenis');
      } else {
        final rows = [
          for (final t in _tokoTampil)
            for (final d in targetDefs) {'store_id': t['id'], 'bulan': b, 'jenis': d.jenis, 'nilai': _v('s|${t['id']}|${d.jenis}')}
        ];
        if (rows.isNotEmpty) await Session.db.from('store_targets').upsert(rows, onConflict: 'store_id,bulan,jenis');
      }
      if (mounted) showMsg(context, 'Target ${_perPc ? 'PC' : 'toko'} ${namaBulan(_bulan)} tersimpan');
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _gantiBulan(int n) {
    _bulan = DateTime(_bulan.year, _bulan.month + n, 1);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _tokoTampil;
    final total = <String, num>{};
    for (final t in list) {
      for (final d in targetDefs) {
        total[d.jenis] = (total[d.jenis] ?? 0) + _targetToko(t, d.jenis);
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Target bulanan')),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: busyIcon(_saving, Icons.save),
                  label: Text('Simpan target ${_perPc ? 'PC' : 'toko'} ${namaBulan(_bulan)}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Row(children: [
                    IconButton(onPressed: () => _gantiBulan(-1), icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: Text(namaBulan(_bulan),
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(onPressed: () => _gantiBulan(1), icon: const Icon(Icons.chevron_right)),
                  ]),
                  if (_areas.length > 1)
                    AreaDropdown(areas: _areas, value: _area, bolehSemua: true, onChanged: (v) => setState(() => _area = v)),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Per toko'), icon: Icon(Icons.store)),
                      ButtonSegment(value: true, label: Text('Per PC'), icon: Icon(Icons.person)),
                    ],
                    selected: {_perPc},
                    onSelectionChanged: (s) => setState(() => _perPc = s.first),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      title: Text('Total ${_area == null ? 'cakupan' : 'area'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text([
                        for (final d in targetDefs)
                          '${d.label}: ${d.rupiah ? rupiah(total[d.jenis] ?? 0) : angka(total[d.jenis] ?? 0)}',
                      ].join('\n')),
                    ),
                  ),
                  InfoBanner(_perPc
                      ? 'Target per PC diisi manual. Toko tanpa target toko memakai jumlah target PC-nya.'
                      : 'Target toko dipakai untuk pencapaian Sales, Trainer, dan MT. Kosongkan untuk memakai jumlah target PC.'),
                  for (final t in list) _perPc ? _pcCard(t) : _tokoCard(t),
                ]),
    );
  }

  /// Target toko: isian toko, atau jumlah target PC bila kosong.
  num _targetToko(Map<String, dynamic> t, String jenis) {
    final v = _v('s|${t['id']}|$jenis');
    if (v > 0) return v;
    return asList(t['pc']).fold<num>(0, (a, p) => a + _v('p|${p['id']}|$jenis'));
  }

  Widget _fields(String prefix) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in targetDefs)
          SizedBox(
            width: d.rupiah ? 190 : 130,
            child: TextField(
              controller: _c['$prefix|${d.jenis}'],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: d.label, isDense: true, prefixText: d.rupiah ? 'Rp ' : null),
              onChanged: (_) => setState(() {}),
            ),
          ),
      ]);

  Widget _tokoCard(Map<String, dynamic> t) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${t['area']} · ${asList(t['pc']).length} PC', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            _fields('s|${t['id']}'),
          ]),
        ),
      );

  Widget _pcCard(Map<String, dynamic> t) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${t['area']}', style: Theme.of(context).textTheme.bodySmall),
            if (asList(t['pc']).isEmpty) const Text('Belum ada PC'),
            for (final p in asList(t['pc'])) ...[
              const SizedBox(height: 10),
              Text('${p['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _fields('p|${p['id']}'),
            ],
          ]),
        ),
      );
}
