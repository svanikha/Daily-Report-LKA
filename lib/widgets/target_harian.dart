import 'package:flutter/material.dart';

import '../data/lka.dart';
import '../utils.dart';
import 'sell_out_card.dart';

/// Target harian: (target - pencapaian) ÷ sisa hari kerja, untuk Unit HP, Value HP, dan Unit IoT.
/// Hari offday / izin / sakit tidak dihitung hari kerja, jadi target harian naik bila ada hari libur.
class TargetHarianCard extends StatelessWidget {
  final Map<String, dynamic> bulan;
  final Map<String, dynamic> target;
  final Map<String, dynamic> hari;
  final HariKerja hk;
  const TargetHarianCard({super.key, required this.bulan, required this.target, required this.hari, required this.hk});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    final items = [
      ('Unit HP', 'unit', (num v) => '${angka(v.ceil())} unit'),
      ('Value HP', 'value', rupiahSingkat),
      ('Unit IoT', 'iot', (num v) => '${angka(v.ceil())} unit'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.today, color: c, size: 20),
            const SizedBox(width: 6),
            const Expanded(child: Text('Target harian', style: TextStyle(fontWeight: FontWeight.bold))),
            Text('Timegone ${hk.timegoneText}', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ]),
          Text(
            'Sisa ${hk.sisaHariKerja} hari kerja (termasuk hari ini)'
            '${hk.offdaySisa > 0 ? ', tanpa ${hk.offdaySisa} hari offday/izin/sakit' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final it in items) Expanded(child: _kotak(context, it.$1, it.$2, it.$3)),
          ]),
        ]),
      ),
    );
  }

  Widget _kotak(BuildContext context, String label, String jenis, String Function(num) f) {
    final t = toNum(target[jenis]);
    final capai = toNum(bulan[jenis]);
    final hariIni = toNum(hari[jenis]);
    final String utama;
    final String bawah;
    final Color warna;
    if (t <= 0) {
      utama = '-';
      bawah = 'Target belum diatur';
      warna = Colors.blueGrey;
    } else if (capai >= t) {
      utama = 'Tercapai';
      bawah = '${f(capai)} dari ${f(t)}';
      warna = Colors.green.shade700;
    } else {
      // Kebutuhan dihitung dari pencapaian sebelum hari ini, supaya angka hari ini tidak berubah-ubah
      final perHari = hk.perHari(t, capai - hariIni);
      utama = f(perHari);
      bawah = hariIni >= perHari ? 'Hari ini ${f(hariIni)} ✓' : 'Hari ini ${f(hariIni)}';
      warna = hariIni >= perHari ? Colors.green.shade700 : Colors.red.shade700;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warna.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(utama, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: warna)),
        ),
        Text(t > 0 && capai < t ? 'per hari' : '', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        Text(bawah, style: TextStyle(fontSize: 10.5, color: warna)),
      ]),
    );
  }
}
