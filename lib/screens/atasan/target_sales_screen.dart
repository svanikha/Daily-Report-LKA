import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Target bulanan per Sales (unit HP, value HP, tipe fokus, unit IoT). MT: semua Sales; Trainer: Sales yang dipegang.
/// Kosong / 0 = pakai jumlah target toko & PC di area Sales itu. Target Trainer = jumlah target Sales-nya.
class TargetSalesScreen extends StatefulWidget {
  const TargetSalesScreen({super.key});

  @override
  State<TargetSalesScreen> createState() => _TargetSalesScreenState();
}

class _TargetSalesScreenState extends State<TargetSalesScreen> {
  static const _jenis = [('unit', 'Unit HP'), ('value', 'Value HP (Rp)'), ('fokus', 'Tipe fokus'), ('iot', 'Unit IoT')];
  DateTime _bulan = monthStart();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _sales = []; // {id, nama, area, trainer}
  final Map<String, TextEditingController> _c = {}; // "salesId|jenis"

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
      final me = Session.current!;
      final res = await Future.wait<dynamic>([
        db.from('profiles').select('id,nama').eq('role', 'sales').eq('aktif', true).order('nama'),
        db.from('areas').select('nama,sales_id'),
        db.from('trainer_sales').select('sales_id,trainer_id,trainer:profiles!trainer_sales_trainer_id_fkey(nama)'),
        db.from('sales_targets').select('sales_id,jenis,nilai').eq('bulan', ymd(_bulan)),
      ]);
      final area = <String, List<String>>{};
      for (final a in asList(res[1])) {
        area.putIfAbsent('${a['sales_id']}', () => []).add('${a['nama']}');
      }
      final ts = {for (final t in asList(res[2])) '${t['sales_id']}': t};
      _sales = [
        for (final s in asList(res[0]))
          if (me.isMt || ts['${s['id']}']?['trainer_id'] == me.id)
            {
              ...s,
              'area': (area['${s['id']}'] ?? []).join(', '),
              'trainer': asMap(ts['${s['id']}']?['trainer'])['nama'],
              'trainer_id': ts['${s['id']}']?['trainer_id'],
            },
      ];
      final nilai = {for (final r in asList(res[3])) '${r['sales_id']}|${r['jenis']}': toNum(r['nilai'])};
      for (final c in _c.values) {
        c.dispose();
      }
      _c.clear();
      for (final s in _sales) {
        for (final j in _jenis) {
          final v = nilai['${s['id']}|${j.$1}'];
          _c['${s['id']}|${j.$1}'] = TextEditingController(text: v == null || v == 0 ? '' : '${v.round()}');
        }
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final rows = [
        for (final e in _c.entries)
          {
            'sales_id': e.key.split('|')[0],
            'bulan': ymd(_bulan),
            'jenis': e.key.split('|')[1],
            'nilai': e.value.text.trim().isEmpty ? 0 : digitsOnly(e.value.text),
          },
      ];
      if (rows.isNotEmpty) await Session.db.from('sales_targets').upsert(rows, onConflict: 'sales_id,bulan,jenis');
      if (mounted) showMsg(context, 'Target Sales ${namaBulan(_bulan)} tersimpan');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _geser(int n) {
    _bulan = DateTime(_bulan.year, _bulan.month + n, 1);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Total per Trainer (gabungan Sales yang dipegang)
    final perTrainer = <String, Map<String, num>>{};
    for (final s in _sales) {
      final t = '${s['trainer'] ?? 'Tanpa Trainer'}';
      for (final j in _jenis) {
        final v = digitsOnly(_c['${s['id']}|${j.$1}']?.text ?? '');
        perTrainer.putIfAbsent(t, () => {})[j.$1] = (perTrainer[t]![j.$1] ?? 0) + v;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Target Sales & Trainer')),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: busyIcon(_saving, Icons.save),
                  label: const Text('Simpan target Sales'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: Column(children: [
        Row(children: [
          IconButton(onPressed: () => _geser(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(namaBulan(_bulan), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => _geser(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorRetry(error: _error!, onRetry: _load)
                  : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                      const InfoBanner('Kosong = memakai jumlah target toko/PC di area Sales itu. '
                          'Target Trainer = jumlah target semua Sales yang dipegang (dihitung otomatis).'),
                      const SectionHeader('Target Trainer (gabungan Sales)'),
                      for (final e in perTrainer.entries)
                        Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Unit ${angka(e.value['unit'] ?? 0)} · Value ${rupiah(e.value['value'] ?? 0)} · '
                                'Fokus ${angka(e.value['fokus'] ?? 0)} · IoT ${angka(e.value['iot'] ?? 0)}'),
                          ),
                        ),
                      const SectionHeader('Target per Sales'),
                      for (final s in _sales)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${s['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${s['area']}${s['trainer'] != null ? ' · Trainer ${s['trainer']}' : ''}',
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final j in _jenis)
                                  SizedBox(
                                    width: j.$1 == 'value' ? 170 : 100,
                                    child: TextField(
                                      controller: _c['${s['id']}|${j.$1}'],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(labelText: j.$2, isDense: true),
                                    ),
                                  ),
                              ]),
                            ]),
                          ),
                        ),
                    ]),
        ),
      ]),
    );
  }
}
