import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/lka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Brand kompetitor untuk stok (cukup total unit per brand, tanpa tipe).
const brandStokKompetitor = ['VIVO', 'SAMSUNG', 'REALME', 'INFINIX', 'XIAOMI', 'TECNO', 'ITEL', 'OTHERS'];

/// Stok kompetitor toko: total unit HP per brand. Tampil di Rekap stok & DOS (Sales, Trainer, MT, Manajer).
class StokKompetitorScreen extends StatefulWidget {
  final PcHari toko;
  const StokKompetitorScreen({super.key, required this.toko});

  @override
  State<StokKompetitorScreen> createState() => _StokKompetitorScreenState();
}

class _StokKompetitorScreenState extends State<StokKompetitorScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DateTime? _pada;
  final Map<String, TextEditingController> _c = {for (final b in brandStokKompetitor) b: TextEditingController()};

  bool get _boleh {
    final me = Session.current;
    return me != null && (me.isPc || me.bolehUbah);
  }

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
      final rows = asList(await Session.db
          .from('stok_kompetitor')
          .select('brand,unit,updated_at')
          .eq('store_id', widget.toko.storeId));
      for (final c in _c.values) {
        c.text = '';
      }
      _pada = null;
      for (final r in rows) {
        _c['${r['brand']}']?.text = '${toNum(r['unit']).toInt()}';
        final w = r['updated_at'] == null ? null : parseWib('${r['updated_at']}');
        if (w != null && (_pada == null || w.isAfter(_pada!))) _pada = w;
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _total => _c.values.fold(0, (a, c) => a + (int.tryParse(c.text) ?? 0));

  Future<void> _simpan() async {
    setState(() => _saving = true);
    try {
      await Session.db.rpc('simpan_stok_kompetitor', params: {
        'p_store': widget.toko.storeId,
        'p_data': {for (final e in _c.entries) e.key: int.tryParse(e.value.text) ?? 0},
      });
      if (!mounted) return;
      showMsg(context, 'Stok kompetitor tersimpan');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stok kompetitor'),
          Text(widget.toko.toko, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      bottomNavigationBar: _loading || _error != null || !_boleh
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _simpan,
                  icon: busyIcon(_saving, Icons.save),
                  label: Text('Simpan · total ${angka(_total)} unit'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
                  InfoBanner(
                    'Isi jumlah stok HP brand lain yang ada di toko saat ini (total per brand, tidak perlu per tipe). '
                    'Data ini masuk ke Rekap stok & DOS yang dilihat Sales dan Trainer.\n'
                    '${_pada == null ? 'Belum pernah diisi.' : 'Terakhir diperbarui ${tglPendek(_pada!)} ${jamMenit(_pada!)} WIB.'}',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Column(children: [
                        for (final b in brandStokKompetitor)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(child: Text(b, style: const TextStyle(fontWeight: FontWeight.bold))),
                              SizedBox(
                                width: 110,
                                child: TextField(
                                  controller: _c[b],
                                  enabled: _boleh,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textAlign: TextAlign.right,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(isDense: true, hintText: '0', suffixText: 'unit'),
                                ),
                              ),
                            ]),
                          ),
                        const Divider(),
                        Row(children: [
                          const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                          Text('${angka(_total)} unit', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
