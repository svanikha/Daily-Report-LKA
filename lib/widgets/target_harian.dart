import 'package:flutter/material.dart';

import '../data/lka.dart';
import '../services/session.dart';
import '../utils.dart';
import 'sell_out_card.dart';
import 'widgets.dart';

/// Jenis target harian: label, kunci, format.
final _jenisHarian = <(String, String, String Function(num))>[
  ('Unit HP', 'unit', (num v) => '${angka(v.ceil())} unit'),
  ('Value HP', 'value', rupiahSingkat),
  ('Tipe fokus', 'fokus', (num v) => '${angka(v.ceil())} unit'),
  ('Unit IoT', 'iot', (num v) => '${angka(v.ceil())} unit'),
];

/// Target harian: (target - pencapaian) ÷ sisa hari kerja untuk Unit HP, Value HP, Tipe fokus, Unit IoT.
/// Hari offday / izin / sakit tidak dihitung hari kerja, jadi target harian naik bila ada hari libur.
/// Atasan (MT, Trainer, Sales) bisa mengatur angka sendiri untuk satu tanggal ([manual]); angka itu
/// menggantikan hitungan otomatis.
class TargetHarianCard extends StatelessWidget {
  final Map<String, dynamic> bulan;
  final Map<String, dynamic> target;
  final Map<String, dynamic> hari;
  final HariKerja hk;

  /// Target harian yang diatur atasan untuk tanggal ini: {unit, value, fokus, iot, oleh}.
  final Map<String, dynamic>? manual;

  /// Atasan: ketuk ikon edit untuk mengatur target harian.
  final VoidCallback? onEdit;
  const TargetHarianCard({
    super.key,
    required this.bulan,
    required this.target,
    required this.hari,
    required this.hk,
    this.manual,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    final m = manual;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.today, color: c, size: 20),
            const SizedBox(width: 6),
            const Expanded(child: Text('Target harian', style: TextStyle(fontWeight: FontWeight.bold))),
            Text('Timegone ${hk.timegoneText}', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
            if (onEdit != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Atur target harian',
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 20),
              ),
          ]),
          Text(
            'Sisa ${hk.sisaHariKerja} hari kerja (termasuk hari ini)'
            '${hk.offdaySisa > 0 ? ', tanpa ${hk.offdaySisa} hari offday/izin/sakit' : ''}'
            '${m != null && m.keys.any((k) => k != 'oleh') ? '\nSebagian target diatur oleh ${m['oleh'] ?? 'atasan'}' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _jenisHarian.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final it in _jenisHarian.skip(i).take(2)) Expanded(child: _kotak(context, it.$1, it.$2, it.$3)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _kotak(BuildContext context, String label, String jenis, String Function(num) f) {
    final t = toNum(target[jenis]);
    final capai = toNum(bulan[jenis]);
    final hariIni = toNum(hari[jenis]);
    final atur = manual?[jenis];
    final String utama;
    final String bawah;
    final Color warna;
    if (atur != null) {
      final perHari = toNum(atur);
      utama = f(perHari);
      bawah = hariIni >= perHari ? 'Hari ini ${f(hariIni)} ✓' : 'Hari ini ${f(hariIni)}';
      warna = hariIni >= perHari ? Colors.green.shade700 : Colors.red.shade700;
    } else if (t <= 0) {
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
        Text(atur != null ? 'per hari · diatur atasan' : (t > 0 && capai < t ? 'per hari' : ''),
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        Text(bawah, style: TextStyle(fontSize: 10.5, color: warna)),
      ]),
    );
  }
}

/// Dialog atasan: atur target harian satu PC untuk satu tanggal. Kolom kosong = hitungan otomatis.
/// Mengembalikan true jika tersimpan.
Future<bool> aturTargetHarianDialog(
  BuildContext context, {
  required String pcId,
  required String pcNama,
  required DateTime tanggal,
  Map<String, dynamic> awal = const {},
}) async {
  final c = {
    for (final j in _jenisHarian)
      j.$2: TextEditingController(text: awal[j.$2] == null ? '' : '${toNum(awal[j.$2]).round()}'),
  };
  final hasil = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Target harian $pcNama'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${hariTgl(tanggal)}. Kosongkan untuk memakai hitungan otomatis (sisa target ÷ sisa hari kerja).',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final j in _jenisHarian)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: c[j.$2],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: j.$2 == 'value' ? '${j.$1} (Rp)' : '${j.$1} (unit)',
                  isDense: true,
                ),
              ),
            ),
        ]),
      ),
      actions: [
        if (awal.keys.any((k) => k != 'oleh'))
          TextButton(onPressed: () => Navigator.pop(ctx, 'hapus'), child: const Text('Pakai otomatis')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'simpan'), child: const Text('Simpan')),
      ],
    ),
  );
  final nilai = {
    for (final e in c.entries) e.key: e.value.text.trim().isEmpty ? null : digitsOnly(e.value.text),
  };
  for (final x in c.values) {
    x.dispose();
  }
  if (hasil == null || !context.mounted) return false;
  try {
    final db = Session.db.from('pc_target_harian');
    if (hasil == 'hapus' || nilai.values.every((v) => v == null)) {
      await db.delete().eq('pc_id', pcId).eq('tanggal', ymd(tanggal));
    } else {
      await db.upsert({'pc_id': pcId, 'tanggal': ymd(tanggal), ...nilai}, onConflict: 'pc_id,tanggal');
    }
    if (context.mounted) showMsg(context, 'Target harian $pcNama tersimpan');
    return true;
  } catch (e) {
    if (context.mounted) showErr(context, e);
    return false;
  }
}
