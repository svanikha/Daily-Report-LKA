import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/cakupan_data.dart';
import '../../widgets/widgets.dart';

/// List produk HP & IoT PER AREA. MT (area mana pun), Trainer (area cakupan), Sales (areanya sendiri)
/// bisa menambah produk, mengubah nama/harga/tipe fokus, dan menonaktifkan. Perubahan hanya berlaku
/// di area yang dipilih. MT juga bisa menambahkan produk baru ke SEMUA area sekaligus.
class ProdukScreen extends StatefulWidget {
  const ProdukScreen({super.key});

  @override
  State<ProdukScreen> createState() => _ProdukScreenState();
}

class _ProdukScreenState extends State<ProdukScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _areas = [];
  int? _area;
  List<Map<String, dynamic>> _rows = [];
  String _tipe = 'HP';
  String _q = '';

  bool get _mt => Session.current?.isMt ?? false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _areas = await muatArea();
      if (_areas.isNotEmpty) _area = toNum(_areas.first['id']).toInt();
    } catch (e) {
      _error = errMsg(e);
    }
    await _load();
  }

  Future<void> _load() async {
    if (_area == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = asList(
          await Session.db.from('products').select().eq('area_id', _area!).order('tipe').order('urutan').order('nama'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _namaArea => '${_areas.where((a) => toNum(a['id']).toInt() == _area).firstOrNull?['nama'] ?? ''}';

  Future<void> _edit([Map<String, dynamic>? p, bool semuaArea = false]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProdukForm(
        produk: p,
        areaId: _area!,
        namaArea: _namaArea,
        semuaArea: semuaArea,
        tipeAwal: _tipe,
        grupList: _rows.map((r) => '${r['grup']}').toSet().toList(),
        fokusList: _rows.map((r) => r['fokus']).whereType<String>().toSet().toList(),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = _rows
        .where((r) => r['tipe'] == _tipe && (q.isEmpty || '${r['nama']} ${r['grup']}'.toLowerCase().contains(q)))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produk HP & IoT'),
        actions: [
          if (_mt)
            TextButton.icon(
              onPressed: _area == null ? null : () => _edit(null, true),
              icon: const Icon(Icons.public, color: Colors.white),
              label: const Text('Semua area', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      floatingActionButton: _area == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Produk baru'),
            ),
      body: _error != null
          ? ErrorRetry(error: _error!, onRetry: _init)
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
              if (_areas.isEmpty && !_loading) const InfoBanner('Belum ada area di cakupan akun ini.'),
              if (_areas.isNotEmpty)
                AreaDropdown(
                  areas: _areas,
                  value: _area,
                  onChanged: (v) {
                    setState(() => _area = v);
                    _load();
                  },
                ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'HP', label: Text('HP'), icon: Icon(Icons.smartphone)),
                  ButtonSegment(value: 'IOT', label: Text('IoT'), icon: Icon(Icons.watch)),
                ],
                selected: {_tipe},
                onSelectionChanged: (s) => setState(() => _tipe = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari produk...', isDense: true),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 4),
              InfoBanner('Perubahan hanya berlaku di area $_namaArea dan tercatat di riwayat. '
                  'Penjualan yang sudah tercatat tidak ikut berubah.'),
              if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (!_loading)
                for (final p in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      title: Text('${p['nama']}',
                          style: TextStyle(
                              decoration: p['aktif'] == true ? null : TextDecoration.lineThrough,
                              color: p['aktif'] == true ? null : Colors.grey)),
                      subtitle: Text([
                        '${p['grup']}',
                        if (p['fokus'] != null) 'Fokus ${p['fokus']}',
                        if (p['aktif'] != true) 'Nonaktif',
                      ].join(' · ')),
                      trailing: Text(rupiah(toNum(p['harga'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => _edit(p),
                    ),
                  ),
            ]),
    );
  }
}

class _ProdukForm extends StatefulWidget {
  final Map<String, dynamic>? produk;
  final int areaId;
  final String namaArea;
  final bool semuaArea;
  final String tipeAwal;
  final List<String> grupList;
  final List<String> fokusList;
  const _ProdukForm({
    required this.produk,
    required this.areaId,
    required this.namaArea,
    required this.semuaArea,
    required this.tipeAwal,
    required this.grupList,
    required this.fokusList,
  });

  @override
  State<_ProdukForm> createState() => _ProdukFormState();
}

class _ProdukFormState extends State<_ProdukForm> {
  late final _nama = TextEditingController(text: '${widget.produk?['nama'] ?? ''}');
  late final _grup = TextEditingController(text: '${widget.produk?['grup'] ?? ''}');
  late final _harga = TextEditingController(text: widget.produk == null ? '' : '${toNum(widget.produk!['harga']).toInt()}');
  late final _fokus = TextEditingController(text: '${widget.produk?['fokus'] ?? ''}');
  late String _tipe = '${widget.produk?['tipe'] ?? widget.tipeAwal}';
  late bool _aktif = widget.produk?['aktif'] != false;
  bool _busy = false;

  @override
  void dispose() {
    _nama.dispose();
    _grup.dispose();
    _harga.dispose();
    _fokus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nama = _nama.text.trim();
    final grup = _grup.text.trim();
    final harga = digitsOnly(_harga.text);
    final fokus = _fokus.text.trim();
    if (nama.isEmpty || grup.isEmpty || harga <= 0) {
      showMsg(context, 'Nama, seri/jenis, dan harga wajib diisi');
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.semuaArea) {
        final n = await Session.db.rpc('produk_semua_area', params: {
          'p_tipe': _tipe,
          'p_nama': nama,
          'p_grup': grup,
          'p_harga': harga,
          'p_fokus': fokus.isEmpty ? null : fokus,
        });
        if (mounted) showMsg(context, 'Ditambahkan ke ${toNum(n).toInt()} area');
      } else {
        final data = {
          'tipe': _tipe,
          'nama': nama,
          'grup': grup,
          'harga': harga,
          'fokus': fokus.isEmpty ? null : fokus,
          'aktif': _aktif,
        };
        if (widget.produk == null) {
          await Session.db.from('products').insert({...data, 'area_id': widget.areaId, 'urutan': 999});
        } else {
          await Session.db.from('products').update(data).eq('id', widget.produk!['id'] as int);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            widget.semuaArea
                ? 'Produk baru untuk SEMUA area'
                : '${widget.produk == null ? 'Produk baru' : 'Ubah produk'} · area ${widget.namaArea}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (widget.semuaArea)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: InfoBanner('Produk ditambahkan ke setiap area yang belum punya produk ini, dan ke list awal area baru.'),
            ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'HP', label: Text('HP')),
              ButtonSegment(value: 'IOT', label: Text('IoT')),
            ],
            selected: {_tipe},
            onSelectionChanged: widget.produk == null ? (s) => setState(() => _tipe = s.first) : null,
          ),
          const SizedBox(height: 12),
          TextField(controller: _nama, decoration: const InputDecoration(labelText: 'Nama produk *', hintText: 'A7 PRO 5G [8/256]')),
          const SizedBox(height: 12),
          TextField(
            controller: _grup,
            decoration: InputDecoration(
              labelText: _tipe == 'HP' ? 'Seri *' : 'Jenis *',
              hintText: _tipe == 'HP' ? 'A Series / Reno Series / Find Series' : 'Pad / Watch / Band / Audio',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _harga,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Harga (Rp) *', prefixText: 'Rp '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fokus,
            decoration: InputDecoration(
              labelText: 'Tipe fokus (kosongkan jika bukan)',
              hintText: widget.fokusList.isEmpty ? 'misal A7 Pro' : widget.fokusList.join(' / '),
            ),
          ),
          if (widget.fokusList.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final f in widget.fokusList)
                ActionChip(label: Text(f), onPressed: () => setState(() => _fokus.text = f)),
            ]),
          if (!widget.semuaArea)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _aktif,
              onChanged: (v) => setState(() => _aktif = v),
              title: const Text('Aktif dijual'),
              subtitle: const Text('Nonaktif = tidak muncul di stok dan penjualan area ini'),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: busyIcon(_busy, Icons.save),
            label: const Text('Simpan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ]),
      ),
    );
  }
}
