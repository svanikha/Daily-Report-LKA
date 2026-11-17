import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Riwayat perubahan produk, harga, KPI, dan target: siapa, kapan, dari berapa ke berapa.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _tabel = 'semua';

  static const _label = {
    'products': 'Produk & harga',
    'store_targets': 'Target toko',
    'pc_targets': 'Target PC',
    'kpi_gaji': 'KPI: UMR',
    'kpi_tier': 'KPI: tier',
    'kpi_potongan': 'KPI: potongan',
    'kpi_aturan': 'KPI: bonus/denda',
    'insentif_produk': 'Insentif produk',
    'insentif_lain': 'Insentif lain',
  };

  // Kolom yang tidak perlu ditampilkan di rincian perubahan
  static const _abaikan = {'id', 'diubah_oleh', 'diubah_pada', 'updated_by', 'updated_at'};

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
      var q = Session.db.from('audit_log').select('id,tabel,ref,aksi,nilai_lama,nilai_baru,waktu,oleh:profiles(nama)');
      if (_tabel == 'kpi') {
        q = q.inFilter('tabel', ['kpi_gaji', 'kpi_tier', 'kpi_potongan', 'kpi_aturan', 'insentif_produk', 'insentif_lain']);
      } else if (_tabel == 'target') {
        q = q.inFilter('tabel', ['store_targets', 'pc_targets']);
      } else if (_tabel == 'produk') {
        q = q.eq('tabel', 'products');
      }
      _rows = asList(await q.order('waktu', ascending: false).limit(200));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _ringkas(Map<String, dynamic> r) {
    final lama = asMap(r['nilai_lama']);
    final baru = asMap(r['nilai_baru']);
    if (r['aksi'] == 'INSERT') {
      final nama = baru['nama'] ?? baru['jenis'] ?? baru['kode'] ?? '';
      return 'Baru: $nama${baru['harga'] != null ? ' · ${rupiah(toNum(baru['harga']))}' : ''}'
          '${baru['nilai'] != null ? ' · ${angka(toNum(baru['nilai']))}' : ''}';
    }
    if (r['aksi'] == 'DELETE') return 'Dihapus: ${lama['nama'] ?? lama['jenis'] ?? lama['kode'] ?? ''}';
    final beda = <String>[];
    for (final k in baru.keys) {
      if (_abaikan.contains(k)) continue;
      if ('${lama[k]}' != '${baru[k]}') beda.add('$k: ${lama[k] ?? '-'} → ${baru[k] ?? '-'}');
    }
    final nama = baru['nama'] ?? baru['jenis'] ?? '';
    return '${nama.toString().isEmpty ? '' : '$nama · '}${beda.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat perubahan')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'semua', label: Text('Semua')),
              ButtonSegment(value: 'produk', label: Text('Produk')),
              ButtonSegment(value: 'kpi', label: Text('KPI')),
              ButtonSegment(value: 'target', label: Text('Target')),
            ],
            selected: {_tabel},
            onSelectionChanged: (s) {
              setState(() => _tabel = s.first);
              _load();
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorRetry(error: _error!, onRetry: _load)
                  : _rows.isEmpty
                      ? const EmptyState(text: 'Belum ada perubahan', icon: Icons.history)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            return ListTile(
                              dense: true,
                              title: Text('${_label[r['tabel']] ?? r['tabel']} · ${r['aksi']}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${_ringkas(r)}\n${asMap(r['oleh'])['nama'] ?? 'Sistem'} · '
                                  '${tglJam(parseWib('${r['waktu']}'))}'),
                              isThreeLine: true,
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
