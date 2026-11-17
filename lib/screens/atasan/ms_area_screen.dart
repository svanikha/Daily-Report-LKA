import 'package:flutter/material.dart';

import '../../data/lka.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// MS Allbrand semua toko di cakupan dalam satu tabel: baris = toko, kolom = OPPO + tiap brand,
/// Total dan MS OPPO %. Bisa beralih Hari ini / Todate. Dikelompokkan per area.
class MsAreaScreen extends StatefulWidget {
  final Cakupan filter;
  final DateTime tanggal;
  final String judul;
  const MsAreaScreen({super.key, required this.filter, required this.tanggal, required this.judul});

  @override
  State<MsAreaScreen> createState() => _MsAreaScreenState();
}

class _MsAreaScreenState extends State<MsAreaScreen> {
  late DateTime _tgl = widget.tanggal;
  bool _todate = false;
  bool _loading = true;
  String? _error;
  List<String> _brands = [];
  List<Map<String, dynamic>> _toko = [];

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
      final r = asMap(await Session.db.rpc('ms_area', params: {'p_tanggal': ymd(_tgl), ...widget.filter.params}));
      _brands = [for (final b in (r['brands'] as List? ?? const [])) '$b'];
      _toko = asList(r['toko']);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pilihTanggal() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tgl,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
    );
    if (d != null) {
      _tgl = dateOnly(d);
      _load();
    }
  }

  num _oppo(Map<String, dynamic> t) => toNum(t[_todate ? 'oppo_bulan' : 'oppo_hari']);
  num _brand(Map<String, dynamic> t, String b) => toNum(asMap(t[_todate ? 'brand_bulan' : 'brand_hari'])[b]);
  num _lain(Map<String, dynamic> t) => _brands.fold<num>(0, (a, b) => a + _brand(t, b));

  static String _n(num v) => v == 0 ? '-' : angka(v);
  static String _pct(num o, num l) => o + l > 0 ? '${(o / (o + l) * 100).toStringAsFixed(0)}%' : '-';

  @override
  Widget build(BuildContext context) {
    final area = <String, List<Map<String, dynamic>>>{};
    for (final t in _toko) {
      area.putIfAbsent('${t['area']}${t['sales'] != null ? ' · ${t['sales']}' : ''}', () => []).add(t);
    }
    final belum = _toko.where((t) => t['terisi'] != true).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MS Allbrand'),
          Text(widget.judul, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [IconButton(onPressed: _pilihTanggal, icon: const Icon(Icons.calendar_month))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Text(hariTgl(_tgl), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Hari ini')),
                      ButtonSegment(value: true, label: Text('Todate')),
                    ],
                    selected: {_todate},
                    onSelectionChanged: (s) => setState(() => _todate = s.first),
                  ),
                  const SizedBox(height: 8),
                  if (!_todate && belum > 0)
                    InfoBanner('$belum toko belum mengisi MS Allbrand tanggal ini (ditandai merah).',
                        icon: Icons.warning_amber, color: Colors.orange.shade800),
                  if (_toko.isEmpty) const EmptyState(text: 'Tidak ada toko', icon: Icons.store),
                  for (final e in area.entries) ...[
                    SectionHeader('Area ${e.key}'),
                    _tabel(e.value),
                  ],
                  if (area.length > 1) ...[
                    const SectionHeader('Total semua area'),
                    _tabel(_toko, hanyaTotal: true),
                  ],
                ]),
    );
  }

  Widget _tabel(List<Map<String, dynamic>> rows, {bool hanyaTotal = false}) {
    const head = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold);
    const cell = TextStyle(fontSize: 11.5);
    const bold = TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold);
    final oppoSt = TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: brandGreen);
    Widget c(String t, TextStyle st, {bool kiri = false, Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          alignment: kiri ? Alignment.centerLeft : Alignment.center,
          child: Text(t, style: st),
        );
    final kolom = ['Toko', 'OPPO', ..._brands, 'Total', 'MS OPPO'];
    final totOppo = rows.fold<num>(0, (a, t) => a + _oppo(t));
    final totBrand = {for (final b in _brands) b: rows.fold<num>(0, (a, t) => a + _brand(t, b))};
    final totLain = totBrand.values.fold<num>(0, (a, b) => a + b);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: const Color(0xFFDDE3E1), width: 0.6),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: brandGreen),
              children: [for (var i = 0; i < kolom.length; i++) c(kolom[i], head, kiri: i == 0)],
            ),
            if (!hanyaTotal)
              for (var i = 0; i < rows.length; i++)
                TableRow(
                  decoration: BoxDecoration(color: i.isOdd ? const Color(0xFFF7F9F8) : null),
                  children: [
                    c('${rows[i]['toko']}', TextStyle(fontSize: 11.5, color: !_todate && rows[i]['terisi'] != true ? Colors.red.shade700 : null),
                        kiri: true),
                    c(_n(_oppo(rows[i])), oppoSt),
                    for (final b in _brands) c(_n(_brand(rows[i], b)), cell),
                    c(_n(_oppo(rows[i]) + _lain(rows[i])), bold),
                    c(_pct(_oppo(rows[i]), _lain(rows[i])), oppoSt),
                  ],
                ),
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFE8F3EE)),
              children: [
                c('TOTAL (${rows.length} toko)', bold, kiri: true),
                c(_n(totOppo), oppoSt),
                for (final b in _brands) c(_n(totBrand[b]!), bold),
                c(_n(totOppo + totLain), bold),
                c(_pct(totOppo, totLain), oppoSt),
              ],
            ),
            TableRow(
              children: [
                c('Share', cell, kiri: true),
                c(_pct(totOppo, totLain), oppoSt),
                for (final b in _brands)
                  c(totOppo + totLain > 0 ? '${(totBrand[b]! / (totOppo + totLain) * 100).toStringAsFixed(0)}%' : '-', cell),
                c('100%', cell),
                c('', cell),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
