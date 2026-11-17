import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/cakupan_data.dart';
import '../../widgets/widgets.dart';

/// Kehadiran PC per minggu (offday, izin, sakit). MT: semua PC. Trainer & Sales: PC di cakupannya.
class OffdayScreen extends StatefulWidget {
  const OffdayScreen({super.key});

  @override
  State<OffdayScreen> createState() => _OffdayScreenState();
}

class _OffdayScreenState extends State<OffdayScreen> {
  late DateTime _week = _mondayOf(wibToday());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _semua = [];
  List<Map<String, dynamic>> _areas = [];
  int? _area;
  List<Map<String, dynamic>> get _pcs =>
      _semua.where((p) => _area == null || toNum(p['area_id']).toInt() == _area).toList();
  final Map<String, String> _status = {}; // "pcId|yyyy-MM-dd" -> offday | izin

  static DateTime _mondayOf(DateTime d) => addDays(dateOnly(d), -(d.weekday - 1));
  List<DateTime> get _days => [for (var i = 0; i < 7; i++) addDays(_week, i)];

  @override
  void initState() {
    super.initState();
    _load();
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
        db.from('pc_day_status').select('pc_id,tanggal,status').gte('tanggal', ymd(_week)).lte('tanggal', ymd(addDays(_week, 6))),
      ]);
      _semua = [
        for (final t in res[0] as List<Map<String, dynamic>>)
          for (final p in asList(t['pc'])) {'id': p['id'], 'nama': p['nama'], 'toko': t['nama'], 'area_id': t['area_id']},
      ];
      _areas = res[1] as List<Map<String, dynamic>>;
      _status.clear();
      for (final r in asList(res[2])) {
        _status['${r['pc_id']}|${r['tanggal']}'] = '${r['status']}';
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Ketuk kotak: pilih langsung Hadir / Offday / Izin / Sakit.
  Future<void> _cycle(String pcId, DateTime d) async {
    final key = '$pcId|${ymd(d)}';
    final now = _status[key];
    final pilih = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(hariTgl(d), style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final o in const [('hadir', 'Hadir (kerja)', Icons.work), ('offday', 'Offday', Icons.beach_access),
                                 ('izin', 'Izin', Icons.event_busy), ('sakit', 'Sakit', Icons.sick)])
            ListTile(
              leading: Icon(o.$3),
              title: Text(o.$2),
              trailing: (now ?? 'hadir') == o.$1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
        ]),
      ),
    );
    if (pilih == null || pilih == (now ?? 'hadir')) return;
    final next = pilih == 'hadir' ? null : pilih;
    setState(() {
      if (next == null) {
        _status.remove(key);
      } else {
        _status[key] = next;
      }
    });
    try {
      final db = Session.db;
      if (next == null) {
        await db.from('pc_day_status').delete().eq('pc_id', pcId).eq('tanggal', ymd(d));
      } else {
        await db.from('pc_day_status').upsert(
          {'pc_id': pcId, 'tanggal': ymd(d), 'status': next, 'dibuat_oleh': Session.current?.id},
          onConflict: 'pc_id,tanggal',
        );
      }
    } catch (e) {
      if (mounted) showErr(context, e);
      _load();
    }
  }

  Future<void> _copyPrevWeek() async {
    final ok = await confirmDialog(context, 'Salin dari minggu lalu?',
        'Jadwal offday/izin minggu lalu disalin ke minggu ini. Jadwal yang sudah ada di minggu ini tetap.');
    if (!ok) return;
    try {
      final db = Session.db;
      final prev = addDays(_week, -7);
      final ids = _pcs.map((p) => p['id'] as String).toSet();
      final rows = asList(await db
          .from('pc_day_status')
          .select('pc_id,tanggal,status')
          .gte('tanggal', ymd(prev))
          .lte('tanggal', ymd(addDays(prev, 6))));
      final data = [
        for (final r in rows)
          if (ids.contains(r['pc_id']))
            {
              'pc_id': r['pc_id'],
              'tanggal': ymd(addDays(parseDate('${r['tanggal']}'), 7)),
              'status': r['status'],
              'dibuat_oleh': Session.current?.id,
            }
      ].where((x) => !_status.containsKey('${x['pc_id']}|${x['tanggal']}')).toList();
      if (data.isNotEmpty) await db.from('pc_day_status').upsert(data, onConflict: 'pc_id,tanggal');
      if (mounted) showMsg(context, '${data.length} jadwal disalin');
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kehadiran PC'),
        actions: [IconButton(onPressed: _copyPrevWeek, icon: const Icon(Icons.copy_all), tooltip: 'Salin dari minggu lalu')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Row(children: [
                    IconButton(
                      onPressed: () {
                        _week = addDays(_week, -7);
                        _load();
                      },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text('${tgl(_week)} - ${tgl(addDays(_week, 6))}',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () {
                        _week = addDays(_week, 7);
                        _load();
                      },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ]),
                  if (_areas.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AreaDropdown(
                          areas: _areas, value: _area, bolehSemua: true, onChanged: (v) => setState(() => _area = v)),
                    ),
                  const InfoBanner('Ketuk kotak untuk memilih Hadir, Offday, Izin, atau Sakit. '
                      'Hari offday/izin/sakit tidak wajib lapor dan tidak dihitung hari kerja, jadi target harian PC '
                      'dibagi ke hari kerja yang tersisa.'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Row(children: [
                          const SizedBox(width: 104),
                          for (final d in _days)
                            Expanded(
                              child: Column(children: [
                                Text(const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d.weekday - 1],
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                Text('${d.day}', style: const TextStyle(fontSize: 11)),
                              ]),
                            ),
                        ]),
                        const Divider(),
                        for (final p in _pcs)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              SizedBox(
                                width: 104,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${p['nama']}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  Text('${p['toko'] ?? ''}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                                ]),
                              ),
                              for (final d in _days) Expanded(child: _cell('${p['id']}', d)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ]),
    );
  }

  Widget _cell(String pcId, DateTime d) {
    final s = _status['$pcId|${ymd(d)}'];
    final color = switch (s) {
      'offday' => Colors.teal,
      'izin' => Colors.orange.shade700,
      'sakit' => Colors.purple.shade400,
      _ => Colors.grey.shade200,
    };
    return InkWell(
      onTap: () => _cycle(pcId, d),
      child: Container(
        height: 34,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(switch (s) { 'offday' => 'Off', 'izin' => 'Izin', 'sakit' => 'Sakit', _ => '' },
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
