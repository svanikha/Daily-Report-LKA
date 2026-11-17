import 'package:flutter/material.dart';

import '../../data/lka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Cek limit leasing satu PC pada satu tanggal (tanpa foto). Wajib diisi sebelum kirim laporan:
/// minimal satu pengajuan, atau tandai "tidak ada pengajuan hari ini".
class CekLimitScreen extends StatefulWidget {
  final PcHari pc;
  const CekLimitScreen({super.key, required this.pc});

  @override
  State<CekLimitScreen> createState() => _CekLimitScreenState();
}

class _CekLimitScreenState extends State<CekLimitScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _nihil = false;
  bool _changed = false;

  PcHari get t => widget.pc;

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
        db.from('leasing_checks').select().eq('pc_id', t.pcId).eq('tanggal', t.tgl).order('created_at'),
        db.from('checkins').select('modul').eq('pc_id', t.pcId).eq('tanggal', t.tgl).eq('modul', 'cek_limit'),
      ]);
      _rows = asList(res[0]);
      _nihil = asList(res[1]).isNotEmpty;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setNihil(bool v) async {
    try {
      if (v) {
        await Session.db.from('checkins').upsert(
          {'pc_id': t.pcId, 'store_id': t.storeId, 'tanggal': t.tgl, 'modul': 'cek_limit', 'oleh': Session.current?.id},
          onConflict: 'pc_id,tanggal,modul',
        );
      } else {
        await Session.db.from('checkins').delete().eq('pc_id', t.pcId).eq('tanggal', t.tgl).eq('modul', 'cek_limit');
      }
      _changed = true;
      setState(() => _nihil = v);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _tambah() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _LeasingForm(pc: t)));
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _hapus(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context, 'Hapus cek limit?', '${r['leasing']} · ${r['hasil']}', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('leasing_checks').delete().eq('id', '${r['id']}');
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final approve = _rows.where((r) => r['hasil'] == 'Approve').length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cek limit leasing'),
            Text('${t.pcNama} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ]),
        ),
        bottomNavigationBar: !boleh
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _tambah,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah cek limit'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorRetry(error: _error!, onRetry: _load)
                : ListView(padding: const EdgeInsets.all(12), children: [
                    if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                    InfoBanner('Hari ini ${_rows.length} pengajuan · $approve approve · ${_rows.length - approve} reject'),
                    if (_rows.isEmpty)
                      Card(
                        child: SwitchListTile(
                          value: _nihil,
                          onChanged: boleh ? _setNihil : null,
                          title: const Text('Tidak ada pengajuan hari ini'),
                          subtitle: const Text('Tandai jika memang tidak ada konsumen yang cek limit.'),
                        ),
                      ),
                    if (_rows.isEmpty && !_nihil) const EmptyState(text: 'Belum ada cek limit', icon: Icons.fact_check),
                    for (final r in _rows)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: Icon(r['hasil'] == 'Approve' ? Icons.check_circle : Icons.cancel,
                              color: r['hasil'] == 'Approve' ? Colors.green.shade700 : Colors.red.shade700),
                          title: Text('${r['leasing']}'),
                          subtitle: Text([
                            '${r['hasil']}',
                            if (r['hasil'] == 'Approve') 'limit ${rupiah(toNum(r['limit_disetujui']))}',
                            jamMenit(parseWib('${r['created_at']}')),
                          ].join(' · ')),
                          trailing: boleh
                              ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _hapus(r))
                              : null,
                        ),
                      ),
                  ]),
      ),
    );
  }
}

class _LeasingForm extends StatefulWidget {
  final PcHari pc;
  const _LeasingForm({required this.pc});

  @override
  State<_LeasingForm> createState() => _LeasingFormState();
}

class _LeasingFormState extends State<_LeasingForm> {
  String? _leasing;
  String _hasil = 'Approve';
  final _limit = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_leasing == null) {
      showMsg(context, 'Pilih leasing');
      return;
    }
    final limit = digitsOnly(_limit.text);
    if (_hasil == 'Approve' && limit <= 0) {
      showMsg(context, 'Isi limit yang disetujui');
      return;
    }
    setState(() => _busy = true);
    try {
      await Session.db.from('leasing_checks').insert({
        'store_id': widget.pc.storeId,
        'pc_id': widget.pc.pcId,
        'tanggal': widget.pc.tgl,
        'leasing': _leasing,
        'hasil': _hasil,
        'limit_disetujui': _hasil == 'Approve' ? limit : null,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah cek limit')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Leasing *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in leasingList)
            ChoiceChip(label: Text(l), selected: _leasing == l, onSelected: (_) => setState(() => _leasing = l)),
        ]),
        const SizedBox(height: 16),
        const Text('Hasil *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Approve', label: Text('Approve'), icon: Icon(Icons.check)),
            ButtonSegment(value: 'Reject', label: Text('Reject'), icon: Icon(Icons.close)),
          ],
          selected: {_hasil},
          onSelectionChanged: (s) => setState(() => _hasil = s.first),
        ),
        if (_hasil == 'Approve') ...[
          const SizedBox(height: 16),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Limit disetujui (Rp) *', prefixText: 'Rp '),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: busyIcon(_busy, Icons.save),
          label: const Text('Simpan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}
