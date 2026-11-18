import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/kontribusi_tipe.dart';
import '../../widgets/widgets.dart';
import '../toko/stok_kompetitor_screen.dart';

/// Rekap stok terkini + DOS (days of stock) untuk MT & Manajer LKA:
/// 1) total semua area per series, 2) per area Sales (ketuk untuk rincian series).
/// Jual/hari = unit terjual tgl 1 s.d. tanggal dipilih ÷ jumlah hari. DOS = stok ÷ jual/hari.
class RekapStokScreen extends StatefulWidget {
  final DateTime tanggal;
  const RekapStokScreen({super.key, required this.tanggal});

  @override
  State<RekapStokScreen> createState() => _RekapStokScreenState();
}

/// Stok & jual satu baris.
class _Baris {
  num stok = 0;
  num jual = 0;
  void tambah(Map<String, dynamic> r) {
    stok += toNum(r['stok']);
    jual += toNum(r['jual']);
  }
}

class _RekapStokScreenState extends State<RekapStokScreen> {
  late DateTime _tgl = widget.tanggal;
  bool _loading = true;
  String? _error;
  int _hari = 1;
  List<Map<String, dynamic>> _area = [];

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
      final r = asMap(await Session.db.rpc('rekap_stok', params: {'p_tanggal': ymd(_tgl)}));
      _hari = toNum(r['hari']).toInt().clamp(1, 31);
      _area = asList(r['area']);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pilihTanggal() async {
    final d = await showDatePicker(context: context, initialDate: _tgl, firstDate: DateTime(2026, 1, 1), lastDate: wibToday());
    if (d != null) {
      _tgl = dateOnly(d);
      _load();
    }
  }

  num _perHari(num jual) => jual / _hari;

  /// DOS dalam hari; null jika tidak ada penjualan.
  num? _dos(_Baris b) => b.jual <= 0 ? null : b.stok / _perHari(b.jual);

  String _dosTeks(_Baris b) {
    final d = _dos(b);
    if (d == null) return b.stok > 0 ? 'tdk laku' : '-';
    return '${d.round()} hr';
  }

  Color _dosWarna(_Baris b) {
    final d = _dos(b);
    if (d == null) return b.stok > 0 ? Colors.orange.shade800 : Colors.grey;
    if (d < 7) return Colors.red.shade700;
    if (d > 45) return Colors.orange.shade800;
    return Colors.green.shade700;
  }

  /// Baris per series dari rows (gabungan beberapa area).
  Map<String, _Baris> _perSeries(Iterable<Map<String, dynamic>> rows) {
    final m = <String, _Baris>{};
    for (final r in rows) {
      m.putIfAbsent('${r['grup']}', _Baris.new).tambah(r);
    }
    return m;
  }

  Widget _tabelSeries(Iterable<Map<String, dynamic>> rows) {
    final m = _perSeries(rows);
    final hp = m.entries.where((e) => e.key != 'IoT').toList()..sort((a, b) => urutanGrup(a.key).compareTo(urutanGrup(b.key)));
    final totalHp = _Baris();
    for (final e in hp) {
      totalHp
        ..stok += e.value.stok
        ..jual += e.value.jual;
    }
    final iot = m['IoT'] ?? _Baris();
    final semua = _Baris()
      ..stok = totalHp.stok + iot.stok
      ..jual = totalHp.jual + iot.jual;
    DataRow row(String nama, _Baris b, {bool tebal = false, Color? warna}) {
      final st = TextStyle(fontWeight: tebal ? FontWeight.bold : FontWeight.normal, fontSize: 13);
      return DataRow(cells: [
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          if (warna != null) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: warna, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(nama, style: st),
        ])),
        DataCell(Text(angka(b.stok), style: st)),
        DataCell(Text(_perHari(b.jual).toStringAsFixed(1), style: st)),
        DataCell(Text(_dosTeks(b), style: st.copyWith(color: _dosWarna(b), fontWeight: FontWeight.bold))),
      ]);
    }

    return _tabel(const ['Series', 'Stok', 'Jual/hari', 'DOS'], [
      for (final e in hp) row(e.key, e.value, warna: warnaGrup(e.key)),
      row('Total HP', totalHp, tebal: true),
      row('IoT', iot, warna: warnaGrup('IoT')),
      row('Total', semua, tebal: true),
    ]);
  }

  Widget _tabel(List<String> kolom, List<DataRow> rows) => Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 38,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 52,
            columnSpacing: 18,
            horizontalMargin: 12,
            headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            columns: [for (final k in kolom) DataColumn(label: Text(k), numeric: k != kolom.first)],
            rows: rows,
          ),
        ),
      );

  /// Stok kompetitor (total per brand) dari daftar toko.
  Widget _tabelKompetitor(Iterable<Map<String, dynamic>> toko) {
    final m = {for (final b in brandStokKompetitor) b: 0};
    var terisi = 0, jml = 0;
    for (final t in toko) {
      jml++;
      final k = asMap(t['kompetitor']);
      if (k.isNotEmpty) terisi++;
      for (final b in brandStokKompetitor) {
        m[b] = m[b]! + toNum(k[b]).toInt();
      }
    }
    final total = m.values.fold(0, (a, b) => a + b);
    const st = TextStyle(fontSize: 13);
    const tb = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tabel(const ['Brand', 'Stok'], [
        for (final e in m.entries) DataRow(cells: [DataCell(Text(e.key, style: st)), DataCell(Text(angka(e.value), style: st))]),
        DataRow(cells: [const DataCell(Text('Total', style: tb)), DataCell(Text(angka(total), style: tb))]),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text('Diisi $terisi dari $jml toko', style: Theme.of(context).textTheme.bodySmall),
      ),
    ]);
  }

  /// Tabel per toko: stok & DOS HP/IoT + stok kompetitor. Ketuk untuk rincian series.
  Widget _tabelToko(List<Map<String, dynamic>> toko) => _tabel(const ['Toko', 'Stok HP', 'DOS HP', 'Stok IoT', 'DOS IoT', 'Komp.'], [
        for (final t in toko)
          () {
            final hp = _Baris(), iot = _Baris();
            for (final r in asList(t['rows'])) {
              (r['tipe'] == 'IOT' ? iot : hp).tambah(r);
            }
            final k = asMap(t['kompetitor']);
            final komp = k.values.fold<num>(0, (a, v) => a + toNum(v));
            TextStyle w(_Baris b) => TextStyle(color: _dosWarna(b), fontWeight: FontWeight.bold, fontSize: 13);
            return DataRow(onSelectChanged: (_) => _rincianToko(t), cells: [
              DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['toko']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (t['stok_awal'] != true)
                  Text('stok awal belum diisi', style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
              ])),
              DataCell(Text(angka(hp.stok))),
              DataCell(Text(_dosTeks(hp), style: w(hp))),
              DataCell(Text(angka(iot.stok))),
              DataCell(Text(_dosTeks(iot), style: w(iot))),
              DataCell(Text(k.isEmpty ? '-' : angka(komp))),
            ]);
          }(),
      ]);

  void _rincianToko(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['toko']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            _tabelSeries(asList(t['rows'])),
            SectionHeader(t['kompetitor_pada'] == null
                ? 'Stok kompetitor (belum diisi)'
                : 'Stok kompetitor · ${tglPendek(parseWib('${t['kompetitor_pada']}'))}'),
            _tabelKompetitor([t]),
          ]),
        ),
      ),
    );
  }

  void _rincianArea(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['area']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Sales ${a['sales'] ?? '-'} · stok awal ${a['toko_stok_awal']}/${a['toko']} toko',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            _tabelSeries(asList(a['rows'])),
            const SectionHeader('Per toko (ketuk untuk rincian)'),
            _tabelToko(asList(a['toko_list'])),
            const SectionHeader('Stok kompetitor area ini'),
            _tabelKompetitor(asList(a['toko_list'])),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semuaRows = [for (final a in _area) ...asList(a['rows'])];
    final tokoAwal = _area.fold<num>(0, (s, a) => s + toNum(a['toko_stok_awal']));
    final toko = _area.fold<num>(0, (s, a) => s + toNum(a['toko']));
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rekap stok & DOS'),
          Text('Penjualan 1-${_tgl.day} ${namaBulan(_tgl)} · stok terkini',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          IconButton(onPressed: _pilihTanggal, icon: const Icon(Icons.calendar_month), tooltip: 'Pilih tanggal'),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                    InfoBanner(
                      'Jual/hari = unit terjual tgl 1-${_tgl.day} ÷ $_hari hari. DOS = stok ÷ jual/hari '
                      '(stok cukup untuk berapa hari). Merah < 7 hari, hijau 7-45 hari, oranye > 45 hari / tidak laku.\n'
                      'Stok awal sudah diisi $tokoAwal dari $toko toko; toko yang belum mengisi stok awal dihitung 0.',
                    ),
                    const SectionHeader('Total semua area'),
                    _tabelSeries(semuaRows),
                    if (_area.length == 1) ...[
                      const SectionHeader('Per toko (ketuk untuk rincian series)'),
                      _tabelToko(asList(_area.first['toko_list'])),
                    ],
                    const SectionHeader('Stok kompetitor'),
                    _tabelKompetitor([for (final a in _area) ...asList(a['toko_list'])]),
                    const SectionHeader('Per area Sales (ketuk untuk rincian per toko)'),
                    _tabel(const ['Area · Sales', 'Stok HP', 'DOS HP', 'Stok IoT', 'DOS IoT'], [
                      for (final a in _area)
                        () {
                          final hp = _Baris(), iot = _Baris();
                          for (final r in asList(a['rows'])) {
                            (r['tipe'] == 'IOT' ? iot : hp).tambah(r);
                          }
                          TextStyle w(_Baris b) => TextStyle(color: _dosWarna(b), fontWeight: FontWeight.bold, fontSize: 13);
                          return DataRow(
                            onSelectChanged: (_) => _rincianArea(a),
                            cells: [
                              DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${a['area']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('${a['sales'] ?? '-'} · ${a['toko_stok_awal']}/${a['toko']} toko',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                              ])),
                              DataCell(Text(angka(hp.stok))),
                              DataCell(Text(_dosTeks(hp), style: w(hp))),
                              DataCell(Text(angka(iot.stok))),
                              DataCell(Text(_dosTeks(iot), style: w(iot))),
                            ],
                          );
                        }(),
                    ]),
                  ]),
                ),
    );
  }
}
