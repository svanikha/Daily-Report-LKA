import 'package:flutter/material.dart';

import '../data/lka.dart';
import '../services/presence_service.dart';
import '../utils.dart';
import 'sell_out_card.dart';
import 'status_online.dart';
import 'widgets.dart';

/// Judul kartu dengan ikon.
Widget judulKartu(BuildContext context, IconData icon, String title, {String? sub, Widget? trailing}) {
  final c = Theme.of(context).colorScheme.primary;
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, size: 18, color: c),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      ),
      if (trailing != null) trailing,
    ]),
  );
}

Color _warnaPct(num capai, num target, HariKerja hk) {
  if (target <= 0) return Colors.blueGrey;
  return capai / target * 100 >= hk.timegone ? Colors.green.shade700 : Colors.red.shade700;
}

String _pct(num capai, num target) => target <= 0 ? '-' : '${(capai / target * 100).toStringAsFixed(0)}%';

/// Porsi unit & value HP vs IoT (bulan berjalan).
class KontribusiHpIot extends StatelessWidget {
  final Map<String, dynamic> bulan;
  const KontribusiHpIot({super.key, required this.bulan});

  @override
  Widget build(BuildContext context) {
    final uHp = toNum(bulan['unit']);
    final uIot = toNum(bulan['iot']);
    final vHp = toNum(bulan['value']);
    final vIot = toNum(bulan['iot_value']);
    Widget baris(String label, num hp, num iot, String Function(num) f) {
      final tot = hp + iot;
      final p = tot > 0 ? hp / tot : 0.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('HP ${(p * 100).toStringAsFixed(0)}% · IoT ${tot > 0 ? ((1 - p) * 100).toStringAsFixed(0) : 0}%',
                style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                value: p.toDouble(), minHeight: 8, color: Colors.green.shade700, backgroundColor: Colors.blueGrey.shade200),
          ),
          const SizedBox(height: 2),
          Text('HP ${f(hp)} · IoT ${f(iot)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          judulKartu(context, Icons.donut_large, 'Kontribusi HP & IoT', sub: 'Bulan berjalan'),
          baris('Unit', uHp, uIot, (v) => '${angka(v)} unit'),
          baris('Value', vHp, vIot, rupiahSingkat),
        ]),
      ),
    );
  }
}

/// PC yang menjual hari ini ÷ PC bertugas, dan rata-rata unit HP per PC bulan ini.
class ProduktivitasCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const ProduktivitasCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tugas = toNum(data['pc_bertugas']);
    final jual = toNum(data['pc_menjual']);
    final total = toNum(data['pc_total']);
    final rata = total > 0 ? toNum(data['unit_bulan']) / total : 0;
    final p = tugas > 0 ? jual / tugas * 100 : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          judulKartu(context, Icons.trending_up, 'Produktivitas', sub: 'PC yang menjual ÷ PC bertugas hari itu'),
          Row(children: [
            Expanded(
              child: Text('${angka(jual)}/${angka(tugas)} = ${p.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: pctColor(p))),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rata.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('unit HP / PC bulan ini', style: TextStyle(fontSize: 11)),
            ]),
          ]),
        ]),
      ),
    );
  }
}

/// PC yang sudah kirim laporan ÷ PC wajib lapor (tanpa offday/izin), dengan daftar yang belum.
class LaporanPcCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool hariIni;
  final void Function(Map<String, dynamic> pc)? onTapPc;
  const LaporanPcCard({super.key, required this.data, required this.hariIni, this.onTapPc});

  @override
  Widget build(BuildContext context) {
    final wajib = toNum(data['wajib']);
    final sudah = toNum(data['sudah']);
    final belum = asList(data['belum']);
    final lewat = !hariIni || lewatBatasLaporan();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          judulKartu(context, Icons.verified, 'Laporan PC', sub: 'Tidak termasuk PC offday / izin',
              trailing: Text('${angka(sudah)}/${angka(wajib)}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: sudah >= wajib ? Colors.green.shade700 : (lewat ? Colors.red.shade700 : Colors.orange.shade800)))),
          if (belum.isEmpty && wajib > 0)
            Text('Semua PC sudah kirim laporan ✓', style: TextStyle(color: Colors.green.shade700))
          else if (belum.isNotEmpty) ...[
            Text(lewat ? 'Tidak lapor:' : 'Belum lapor:',
                style: TextStyle(fontWeight: FontWeight.w600, color: lewat ? Colors.red.shade700 : null)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in belum)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${b['pc']} · ${b['toko']}', style: const TextStyle(fontSize: 12)),
                  onPressed: onTapPc == null ? null : () => onTapPc!(b),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Toko yang sudah update stok hari ini ÷ total toko, jam update terakhir. Ketuk untuk pilih toko.
class UpdateStokCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic> toko) onTapToko;
  const UpdateStokCard({super.key, required this.data, required this.onTapToko});

  @override
  Widget build(BuildContext context) {
    final toko = asList(data['toko']);
    final terakhir = toko
        .where((t) => t['update'] != null)
        .map((t) => parseWib('${t['update']}'))
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pilih(context, toko),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: judulKartu(
            context,
            Icons.inventory_2,
            'Update stok',
            sub: '${terakhir == null ? 'Belum ada update hari ini' : 'Terakhir ${jamMenit(terakhir)} WIB'} · ketuk untuk lihat stok toko',
            trailing: Text('${angka(toNum(data['sudah']))}/${angka(toNum(data['total']))}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Future<void> _pilih(BuildContext context, List<Map<String, dynamic>> toko) async {
    final t = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.8,
        child: ListView(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Pilih toko', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          for (final x in toko)
            ListTile(
              leading: Icon(x['update'] == null ? Icons.schedule : Icons.check_circle,
                  color: x['update'] == null ? Colors.orange.shade800 : Colors.green.shade700),
              title: Text('${x['toko']}'),
              subtitle: Text('${x['area']} · PC: ${(x['pc'] as List?)?.join(', ') ?? '-'}'),
              trailing: Text(x['update'] == null ? 'Belum' : jamMenit(parseWib('${x['update']}'))),
              onTap: () => Navigator.pop(ctx, x),
            ),
        ]),
      ),
    );
    if (t != null) onTapToko(t);
  }
}

/// Peringkat per Sales: unit, value, % target. Ketuk untuk membuka beranda versi Sales itu.
class PeringkatSalesCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final HariKerja hk;
  final void Function(Map<String, dynamic> sales) onTap;
  const PeringkatSalesCard({super.key, required this.rows, required this.hk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          judulKartu(context, Icons.leaderboard, 'Peringkat Sales', sub: 'Urut value HP bulan ini · ketuk untuk detail'),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Belum ada data')),
          for (var i = 0; i < rows.length; i++) _row(context, i + 1, rows[i]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, int no, Map<String, dynamic> r) {
    final u = toNum(r['unit']), tu = toNum(r['target_unit']);
    final v = toNum(r['value']), tv = toNum(r['target_value']);
    return InkWell(
      onTap: r['sales_id'] == null ? null : () => onTap(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          CircleAvatar(radius: 13, child: Text('$no', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['sales'] ?? 'Tanpa Sales'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${r['area'] ?? ''} · ${r['toko']} toko · ${r['pc']} PC${r['trainer'] != null ? ' · Trainer ${r['trainer']}' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${angka(u)} unit · ${_pct(u, tu)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: _warnaPct(u, tu, hk), fontSize: 12.5)),
            Text('${rupiahSingkat(v)} · ${_pct(v, tv)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: _warnaPct(v, tv, hk), fontSize: 12.5)),
          ]),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}

/// Daftar PC: unit, value, % target, status laporan, lampu online. Urut value tertinggi.
class DaftarPcCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final HariKerja hk;
  final bool hariIni;
  final void Function(Map<String, dynamic> pc) onTap;
  const DaftarPcCard({super.key, required this.rows, required this.hk, required this.hariIni, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          judulKartu(context, Icons.groups, 'Pencapaian per PC', sub: 'Urut value HP bulan ini · ketuk untuk detail PC'),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Belum ada PC')),
          for (var i = 0; i < rows.length; i++) _row(context, i + 1, rows[i]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, int no, Map<String, dynamic> r) {
    final u = toNum(r['unit']), tu = toNum(r['target_unit']);
    final v = toNum(r['value']), tv = toNum(r['target_value']);
    final status = StatusOnline.dari(
        {'last_seen': r['last_seen'], 'logged_in': r['logged_in'], 'auth_uid': r['sudah_daftar'] == true ? 'ada' : null},
        parseWib);
    final lap = r['laporan_pada'] == null ? null : parseWib('${r['laporan_pada']}');
    final libur = r['libur'] as String?;
    final Pill pill;
    if (lap != null) {
      pill = Pill('Lapor ${jamMenit(lap)}', color: Colors.green.shade700);
    } else if (libur != null) {
      pill = Pill(libur == 'izin' ? 'Izin' : 'Offday', color: Colors.teal);
    } else if (!hariIni || lewatBatasLaporan()) {
      pill = Pill('Tidak lapor', color: Colors.red.shade700);
    } else {
      pill = Pill('Belum lapor', color: Colors.grey.shade700);
    }
    return InkWell(
      onTap: () => onTap(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 24, child: Text('$no', style: TextStyle(color: Colors.grey.shade600))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                LampuOnline(online: status.online, size: 9),
                const SizedBox(width: 5),
                Flexible(child: Text('${r['pc']}', style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              Text('${r['toko']}${toNum(r['unit_hari']) > 0 ? ' · +${r['unit_hari']} hari ini' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(height: 3),
              pill,
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${angka(u)} unit · ${_pct(u, tu)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: _warnaPct(u, tu, hk), fontSize: 12.5)),
            Text('${rupiahSingkat(v)} · ${_pct(v, tv)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: _warnaPct(v, tv, hk), fontSize: 12.5)),
            if (toNum(r['iot']) > 0) Text('IoT ${angka(toNum(r['iot']))}', style: const TextStyle(fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}
