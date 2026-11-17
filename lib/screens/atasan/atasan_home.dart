import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/lka.dart';
import '../../services/akun.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../../widgets/beranda_cards.dart';
import '../../widgets/kontribusi_bayar.dart';
import '../../widgets/kontribusi_kategori.dart';
import '../../widgets/kontribusi_tipe.dart';
import '../../widgets/sell_out_card.dart';
import '../../widgets/widgets.dart';
import '../toko/hari_pc_view.dart';
import '../toko/stok_screen.dart';
import 'akun_pc_screen.dart';
import 'audit_screen.dart';
import 'brand_screen.dart';
import 'export_screen.dart';
import 'kpi_screen.dart';
import 'offday_screen.dart';
import 'organisasi_screen.dart';
import 'produk_screen.dart';
import 'storage_screen.dart';
import 'target_screen.dart';
import 'toko_screen.dart';

/// Beranda MT, Trainer, dan Sales: pencapaian cakupan akun + menu kelola.
class AtasanHome extends StatefulWidget {
  const AtasanHome({super.key});

  @override
  State<AtasanHome> createState() => _AtasanHomeState();
}

class _AtasanHomeState extends State<AtasanHome> {
  int _tab = 0;
  DateTime _tanggal = wibToday();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _b = {};
  int _rev = 0;
  Timer? _refresh;

  /// MT bisa membuka beranda versi satu Trainer; MT / Trainer bisa membuka versi satu Sales.
  Map<String, dynamic>? _trainer;
  Map<String, dynamic>? _sales;

  Profile get me => Session.current!;
  Cakupan get _filter => Cakupan(
        trainerId: _trainer?['trainer_id'] as String?,
        salesId: _sales?['sales_id'] as String?,
      );

  /// Tampilan yang dipakai: 'mt', 'trainer', atau 'sales'
  String get _level => _sales != null ? 'sales' : (_trainer != null ? 'trainer' : me.role);
  bool get _bisaKembali => _sales != null || _trainer != null;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted && _tab == 0) _load();
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _b.isEmpty;
      _error = null;
    });
    try {
      _b = asMap(await Session.db.rpc('beranda', params: {'p_tanggal': ymd(_tanggal), ..._filter.params}));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _rev++;
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
      helpText: 'Tanggal',
    );
    if (d != null) {
      setState(() => _tanggal = dateOnly(d));
      _load();
    }
  }

  void _bukaSales(Map<String, dynamic>? s) {
    setState(() {
      _sales = s;
      _b = {};
    });
    _load();
  }

  void _bukaTrainer(Map<String, dynamic>? t) {
    setState(() {
      _trainer = t;
      _sales = null;
      _b = {};
    });
    _load();
  }

  /// Kembali satu tingkat: Sales -> Trainer (jika dibuka dari Trainer) -> beranda awal.
  void _kembali() {
    if (_sales != null) {
      _bukaSales(null);
    } else {
      _bukaTrainer(null);
    }
  }

  Future<void> _bukaPc(Map<String, dynamic> r) async {
    final pc = await PcDetailScreen.muat(context, '${r['pc_id']}', _tanggal);
    if (pc == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PcDetailScreen(pc: pc)));
    _load();
  }

  Future<void> _bukaStok(Map<String, dynamic> t) async {
    final pc = PcHari(
      pcId: '',
      pcNama: '',
      storeId: toNum(t['store_id']).toInt(),
      toko: '${t['toko']}',
      areaId: toNum(t['area_id']).toInt(),
      area: '${t['area'] ?? ''}',
      tanggal: _tanggal,
    );
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StokScreen(toko: pc)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_bisaKembali || _tab != 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _kembali();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _bisaKembali && _tab == 0 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _kembali) : null,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_tab != 0
                ? 'Kelola'
                : (_sales != null
                    ? 'Sales ${_sales!['sales']}'
                    : (_trainer != null ? 'Trainer ${_trainer!['trainer']}' : 'Beranda'))),
            Text('${me.nama} · ${me.roleLabel} · ${me.cakupan}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ]),
          actions: [
            if (_tab == 0) ...[
              IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), tooltip: 'Pilih tanggal'),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
            ],
            const AkunMenuButton(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Beranda'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Kelola'),
          ],
        ),
        body: _tab == 0 ? _beranda() : _kelola(),
      ),
    );
  }

  // ------------------------------------------------------------------
  Widget _beranda() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final hk = HariKerja.dari(_tanggal);
    final hariIni = isSameDay(_tanggal, wibToday());
    final hari = asMap(_b['hari']);
    final bulan = asMap(_b['bulan']);
    final target = asMap(_b['target']);
    final perSales = asList(_b['per_sales']);
    final key = '${_filter.key}-${ymd(_tanggal)}-$_rev';
    final judul = _sales != null
        ? 'area ${_sales!['area']}'
        : (_trainer != null ? 'Trainer ${_trainer!['trainer']}' : me.cakupan);

    final sellOut = SellOutCard(hari: hari, bulan: bulan, target: target, hk: hk, judul: judul);
    final produktivitas = ProduktivitasCard(data: asMap(_b['produktivitas']));
    final laporan = LaporanPcCard(data: asMap(_b['laporan']), hariIni: hariIni, onTapPc: _bukaPc);
    final stok = UpdateStokCard(data: asMap(_b['stok']), onTapToko: _bukaStok);
    final hpIot = KontribusiHpIot(bulan: bulan);
    final kategori = KontribusiKategori(key: ValueKey('kk-$key'), filter: _filter, tanggal: _tanggal);
    final bayar = KontribusiBayar(key: ValueKey('kb-$key'), filter: _filter, tanggal: _tanggal);
    final tipe = KontribusiTipe(key: ValueKey('kt-$key'), filter: _filter, tanggal: _tanggal);
    final peringkat = PeringkatCard(
      judul: 'Peringkat Sales',
      rows: perSales,
      hk: hk,
      namaKey: 'sales',
      idKey: 'sales_id',
      keterangan: (r) => '${r['area'] ?? ''} · ${r['toko']} toko · ${r['pc']} PC'
          '${r['trainer'] != null && _level == 'mt' ? ' · Trainer ${r['trainer']}' : ''}',
      onTap: _bukaSales,
    );
    final peringkatTrainer = PeringkatCard(
      judul: 'Peringkat Trainer',
      rows: asList(_b['per_trainer']),
      hk: hk,
      namaKey: 'trainer',
      idKey: 'trainer_id',
      keterangan: (r) => 'Sales: ${r['sales'] ?? '-'} · ${r['toko']} toko · ${r['pc']} PC',
      onTap: _bukaTrainer,
    );
    final sebaran = SebaranPcCard(pcs: asList(_b['per_pc']), onTapPc: _bukaPc);
    final daftarPc = DaftarPcCard(rows: asList(_b['per_pc']), hk: hk, hariIni: hariIni, onTap: _bukaPc);

    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(hariTgl(_tanggal), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      TimegoneBar(hk: hk, tampilSisa: false),
      ...switch (_level) {
        // MT: semua area + peringkat per Sales
        'mt' => [sellOut, peringkatTrainer, peringkat, hpIot, kategori, bayar, tipe],
        // Trainer: area Sales yang dipegang (gabungan & per Sales)
        'trainer' => [sellOut, peringkat, sebaran, produktivitas, laporan, hpIot, kategori, bayar, tipe],
        // Sales (atau MT/Trainer membuka satu Sales)
        _ => [sellOut, daftarPc, stok, produktivitas, laporan, hpIot, kategori, bayar, tipe],
      },
      if (_level != 'sales') ...[
        const SizedBox(height: 4),
        ExpansionTile(
          title: const Text('Semua PC di cakupan'),
          subtitle: Text('${asList(_b['per_pc']).length} PC · update stok ${asMap(_b['stok'])['sudah'] ?? 0}/'
              '${asMap(_b['stok'])['total'] ?? 0} toko'),
          children: [daftarPc, stok],
        ),
      ],
    ];
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: out));
  }

  // ------------------------------------------------------------------
  Widget _kelola() {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget item(IconData icon, String title, String sub, Widget page) => Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(page),
          ),
        );
    final cak = me.isMt ? 'semua area' : (me.isTrainer ? 'area Sales yang kamu pegang' : 'area kamu');
    return ListView(padding: const EdgeInsets.all(12), children: [
      const SectionHeader('Data PC'),
      item(Icons.table_chart, 'Export data Excel', 'Ringkasan harian per toko & per PC, penjualan, stok, MS, cek limit ($cak)',
          const ExportScreen()),
      const SectionHeader('Pengaturan'),
      item(Icons.sell, 'Produk HP & IoT', me.isMt ? 'List produk per area, tambah ke semua area' : 'List produk $cak',
          const ProdukScreen()),
      item(Icons.payments, 'KPI & insentif',
          me.isTrainer ? 'Atur UMR, tier, potongan, bonus/denda, insentif wilayahmu' : 'Lihat aturan KPI per Trainer',
          const KpiScreen()),
      item(Icons.flag, 'Target bulanan', 'Target per toko dan per PC ($cak)', const TargetScreen()),
      item(Icons.event_busy, 'Offday & izin PC', 'Jadwal offday/izin PC ($cak)', const OffdayScreen()),
      item(Icons.store, 'Toko', 'Tambah, ubah, nonaktifkan toko ($cak)', const TokoScreen()),
      item(Icons.manage_accounts, 'PC', 'Tambah PC, tempatkan di toko, pindah, nonaktifkan, reset password',
          const AkunPcScreen()),
      if (me.isMt) ...[
        item(Icons.account_tree, 'Sales, Trainer & area', 'Akun Sales & Trainer, area Sales, penugasan Trainer → Sales',
            const OrganisasiScreen()),
        item(Icons.pie_chart, 'Brand MS Allbrand', 'Daftar & urutan brand', const BrandScreen()),
        item(Icons.storage, 'Penyimpanan server', 'Pemakaian storage & APK', const StorageScreen()),
      ],
      item(Icons.history, 'Riwayat perubahan', 'Produk, harga, KPI, dan target: siapa, kapan, dari berapa ke berapa',
          const AuditScreen()),
      const SectionHeader('Akun'),
      Card(child: ListTile(leading: const Icon(Icons.key), title: const Text('Ganti password'), onTap: () => changePasswordDialog(context))),
      Card(child: ListTile(leading: const Icon(Icons.logout), title: const Text('Keluar'), onTap: () => logout(context))),
      const SizedBox(height: 12),
      Center(child: Text('Daily Report LKA · versi ${UpdateService.versionName}', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

/// Detail satu PC untuk atasan (isi sama dengan beranda PC).
class PcDetailScreen extends StatelessWidget {
  final PcHari pc;
  const PcDetailScreen({super.key, required this.pc});

  /// Muat data PC (toko & area) lalu buat konteks PcHari.
  static Future<PcHari?> muat(BuildContext context, String pcId, DateTime tanggal) async {
    try {
      final p = asMap(await Session.db
          .from('profiles')
          .select('id,nama,store_id,stores(nama,area_id,areas(nama))')
          .eq('id', pcId)
          .single());
      final s = asMap(p['stores']);
      return PcHari(
        pcId: pcId,
        pcNama: '${p['nama']}',
        storeId: toNum(p['store_id']).toInt(),
        toko: '${s['nama'] ?? ''}',
        areaId: toNum(s['area_id']).toInt(),
        area: '${asMap(s['areas'])['nama'] ?? ''}',
        tanggal: tanggal,
      );
    } catch (e) {
      if (context.mounted) showErr(context, e);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pc.pcNama),
          Text('${pc.toko} · ${hariTgl(pc.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: HariPcView(pc: pc),
    );
  }
}
