import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/lka.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Gambar "Daily Report LKA" satu PC untuk dibagikan ke grup Feishu / Lark: ringkasan dan tabel MS Allbrand.
class LaporanScreen extends StatefulWidget {
  final PcHari pc;
  const LaporanScreen({super.key, required this.pc});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  final _key = GlobalKey();
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  Map<String, dynamic> _r = {};

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
      _r = asMap(await Session.db.rpc('rekap_pc', params: {'p_pc': widget.pc.pcId, 'p_tanggal': widget.pc.tgl}));
      _r['ms_oppo_todate'] = toNum(asMap(_r['bulan'])['toko_unit']);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw 'Gagal membuat gambar';
      final nama = '${widget.pc.toko}_${widget.pc.pcNama}'.replaceAll(' ', '_');
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'DailyReportLKA_${nama}_${widget.pc.tgl}.png')
        ],
        text: 'Daily Report LKA ${widget.pc.pcNama} · ${widget.pc.toko} · ${hariTgl(widget.pc.tanggal)}',
      ));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gambar laporan')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: (_loading || _sharing || _error != null) ? null : _share,
            icon: busyIcon(_sharing, Icons.share),
            label: const Text('Bagikan ke Feishu / Lark'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: FittedBox(
                      child: RepaintBoundary(key: _key, child: LaporanCard(tanggal: widget.pc.tanggal, r: _r)),
                    ),
                  ),
                ),
    );
  }
}

/// Isi gambar laporan (lebar tetap 360 agar hasilnya sama di semua HP).
class LaporanCard extends StatelessWidget {
  final DateTime tanggal;
  final Map<String, dynamic> r;
  const LaporanCard({super.key, required this.tanggal, required this.r});

  static const _ink = Color(0xFF1B2421);
  static const _muted = Color(0xFF66736E);
  static const _red = Color(0xFFC62828);
  static const _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final hari = asMap(r['hari']);
    final bulan = asMap(r['bulan']);
    final target = asMap(r['target']);
    final laporan = r['laporan'] == null ? null : asMap(r['laporan']);
    final libur = r['libur'] as String?;
    final penjualan = asList(r['penjualan']);
    final cek = asList(r['cek_limit']);
    final cekBulan = asMap(r['cek_limit_bulan']);
    final stokKosong = (r['stok_kosong_fokus'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final stokUpdate = r['stok_update'] == null ? null : parseWib('${r['stok_update']}');
    final hk = HariKerja.dari(tanggal, offdaySisa: toNum(r['offday_sisa']).toInt());
    final msDetail = asList(r['ms_detail']);
    final msOppo = asMap(r['ms_oppo']);
    final unitHari = toNum(hari['unit']);
    final cash = toNum(r['cash_unit']);
    final kredit = toNum(r['kredit_unit']);
    final bayar = cash + kredit;

    return Container(
      width: 360,
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: brandGreen,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DAILY REPORT LKA',
                style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${r['toko'] ?? ''}'.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(hariTgl(tanggal), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            Text('PC: ${r['pc'] ?? '-'} · ${r['area'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            Text('Sales: ${r['sales'] ?? '-'} · Trainer: ${r['trainer'] ?? '-'}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
        if (libur != null) _banner('PC ${labelLibur(libur)} HARI INI',const Color(0xFF00897B)),
        _section('SELL-OUT OPPO', [
          Row(children: [
            Expanded(child: _stat('Unit HP hari ini', '${angka(unitHari)} unit', rupiah(toNum(hari['value'])))),
            const SizedBox(width: 8),
            Expanded(child: _stat('IoT hari ini', '${angka(toNum(hari['iot']))} unit', rupiah(toNum(hari['iot_value'])))),
          ]),
          const SizedBox(height: 6),
          if (penjualan.isEmpty)
            Text(r['nihil_penjualan'] == true ? 'NOSELL (dilaporkan tidak ada penjualan)' : 'Belum ada penjualan',
                style: const TextStyle(color: _red, fontWeight: FontWeight.w600, fontSize: 12))
          else
            for (final s in penjualan)
              _line('${s['nama']}', 'x${s['qty']}${s['cara_bayar'] != null ? ' · ${s['cara_bayar']}' : ''}', small: true),
        ]),
        _section('PENCAPAIAN ${namaBulan(tanggal).toUpperCase()}', [
          _line('Timegone', hk.timegoneText, color: brandGreen),
          _line('Sisa hari kerja', '${hk.sisaHariKerja} hari${hk.offdaySisa > 0 ? ' (tanpa ${hk.offdaySisa} offday)' : ''}'),
          const SizedBox(height: 4),
          for (final d in targetDefs)
            _progress(d.label, toNum(bulan[d.jenis]), toNum(target[d.jenis]), d.rupiah ? rupiah : (v) => '${angka(v)} unit', hk),
        ]),
        _section('MS ALLBRAND TOKO', [
          if (r['kompetitor_terisi'] != true)
            const Text('MS Allbrand belum diisi', style: TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.w600))
          else
            _msTabel(msOppo, msDetail, toNum(hari['toko_unit'])),
        ]),
        if (bayar > 0)
          _section('PEMBAYARAN HP', [
            _line('Cash : Kredit', '${(cash / bayar * 100).toStringAsFixed(0)}% : ${(kredit / bayar * 100).toStringAsFixed(0)}%'),
            if (r['kredit_top'] != null) _line('Kredit terbanyak', '${r['kredit_top']}'),
          ]),
        _section('CEK LIMIT', [
          if (cek.isEmpty)
            Text(r['nihil_cek_limit'] == true ? 'Tidak ada pengajuan hari ini' : 'Belum diisi',
                style: TextStyle(color: r['nihil_cek_limit'] == true ? _muted : _red, fontSize: 12))
          else
            for (final l in cek)
              _line('${l['leasing']}', l['hasil'] == 'Approve' ? 'Approve ${rupiah(toNum(l['limit']))}' : 'Reject',
                  small: true, color: l['hasil'] == 'Approve' ? _green : _red),
          if (toNum(cekBulan['total']) > 0)
            _line('Bulan ini', '${cekBulan['total']}x (${cekBulan['approve']} approve · ${cekBulan['reject']} reject)',
                small: true),
        ]),
        _section('STOK TOKO', [
          _line('Update stok', stokUpdate == null ? 'Belum diisi' : '${jamMenit(stokUpdate)} WIB',
              color: stokUpdate == null ? _red : _green),
          if (stokUpdate != null)
            _line('Stok kosong tipe fokus', stokKosong.isEmpty ? 'Tidak ada' : stokKosong.join(', '),
                color: stokKosong.isEmpty ? _green : _red),
        ]),
        Container(
          color: const Color(0xFFF1F4F3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            laporan == null
                ? 'Laporan belum dikirim · dibuat ${tglJam(wibNow())} WIB'
                : 'Laporan dikirim ${tglJam(parseWib('${laporan['dikirim_pada']}'))} WIB',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
      ]),
    );
  }

  Widget _banner(String t, Color c) => Container(
        color: c.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE4E9E7)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: brandGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _stat(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFF1F8F4), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          Text(value, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(sub, style: const TextStyle(color: _ink, fontSize: 11)),
        ]),
      );

  Widget _line(String a, String b, {bool small = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(a, style: TextStyle(color: _ink, fontSize: small ? 11.5 : 12.5))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(b,
                textAlign: TextAlign.right,
                style: TextStyle(color: color ?? _ink, fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );


  Widget _msTabel(Map<String, dynamic> msOppo, List<Map<String, dynamic>> detail, num oppoToday) {
    final brands = asList(r['ms_brands']);
    final oppoTodate = toNum(r['ms_oppo_todate']);
    num seg(String brand, String s) => detail
        .where((d) => '${d['brand']}'.toLowerCase() == brand.toLowerCase() && d['segmen'] == s)
        .fold<num>(0, (a, d) => a + toNum(d['unit']));
    num lainSeg(String s) => brands.fold<num>(0, (a, b) => a + seg('${b['nama']}', s));
    final lainToday = segmenList.fold<num>(0, (a, s) => a + lainSeg(s));
    final lainTodate = brands.fold<num>(0, (a, b) => a + toNum(b['todate']));
    String n(num v) => v == 0 ? '-' : angka(v);
    String pct(num o, num l) => o + l > 0 ? '${(o / (o + l) * 100).toStringAsFixed(0)}%' : '-';

    const head = TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold);
    const cell = TextStyle(color: _ink, fontSize: 10.5);
    const bold = TextStyle(color: _ink, fontSize: 10.5, fontWeight: FontWeight.bold);
    const oppoSt = TextStyle(color: brandGreen, fontSize: 10.5, fontWeight: FontWeight.bold);

    Widget c(String t, TextStyle st, {bool kiri = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Text(t, textAlign: kiri ? TextAlign.left : TextAlign.center, style: st),
        );
    TableRow row(List<String> v, TextStyle st, {Color? bg}) => TableRow(
          decoration: BoxDecoration(color: bg),
          children: [for (var i = 0; i < v.length; i++) c(v[i], st, kiri: i == 0)],
        );

    return Table(
      border: TableBorder.all(color: const Color(0xFFDDE3E1), width: 0.6),
      columnWidths: const {
        0: FlexColumnWidth(1.6),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(1.05),
        5: FlexColumnWidth(1.1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row(['Brand', '<3jt', '3-6jt', '6jt+', 'Today', 'Todate'], head, bg: brandGreen),
        row([
          'OPPO',
          for (final s in segmenList) n(toNum(msOppo[s])),
          n(oppoToday),
          n(oppoTodate),
        ], oppoSt, bg: const Color(0xFFF1F8F4)),
        for (var i = 0; i < brands.length; i++)
          row([
            '${brands[i]['nama']}',
            for (final s in segmenList) n(seg('${brands[i]['nama']}', s)),
            n(segmenList.fold<num>(0, (a, s) => a + seg('${brands[i]['nama']}', s))),
            n(toNum(brands[i]['todate'])),
          ], cell, bg: i.isOdd ? const Color(0xFFFAFBFB) : null),
        row([
          'Total',
          for (final s in segmenList) n(toNum(msOppo[s]) + lainSeg(s)),
          n(oppoToday + lainToday),
          n(oppoTodate + lainTodate),
        ], bold),
        row([
          'MS OPPO',
          for (final s in segmenList) pct(toNum(msOppo[s]), lainSeg(s)),
          pct(oppoToday, lainToday),
          pct(oppoTodate, lainTodate),
        ], oppoSt, bg: const Color(0xFFF1F8F4)),
      ],
    );
  }

  /// Satu segmen harga: OPPO vs brand lain + MS OPPO.

  Widget _progress(String label, num actual, num target, String Function(num) fmt, HariKerja hk) {
    final p = target > 0 ? actual / target * 100 : 0.0;
    final c = target > 0 ? (p >= hk.timegone ? _green : _red) : Colors.grey;
    final sisa = target - actual;
    final perHari = hk.perHari(target, actual);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600))),
          Text(target > 0 ? '${p.toStringAsFixed(0)}%' : '-', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: target > 0 ? (p / 100).clamp(0.0, 1.0).toDouble() : 0,
            minHeight: 6,
            color: c,
            backgroundColor: const Color(0xFFE4E9E7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          target <= 0
              ? '${fmt(actual)} (target belum diatur)'
              : '${fmt(actual)} dari ${fmt(target)}'
                  '${sisa > 0 ? ' · sisa ${fmt(sisa)}${perHari > 0 ? ' · ${fmt(perHari.ceil())}/hari' : ''}' : ' · TERCAPAI'}',
          style: const TextStyle(color: _muted, fontSize: 10.5),
        ),
      ]),
    );
  }
}
