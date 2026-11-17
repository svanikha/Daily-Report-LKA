import 'package:flutter/material.dart';

import '../../data/lka.dart';
import '../../services/akun.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../../widgets/beranda_cards.dart';
import '../../widgets/kalender_penjualan.dart';
import '../../widgets/kontribusi_bayar.dart';
import '../../widgets/kontribusi_kategori.dart';
import '../../widgets/kontribusi_tipe.dart';
import '../../widgets/pickers.dart';
import '../../widgets/sell_out_card.dart';
import '../../widgets/widgets.dart';
import '../toko/hari_pc_view.dart';
import '../toko/penjualan_screen.dart';
import '../toko/stok_screen.dart';
import 'akun_pc_screen.dart';
import 'audit_screen.dart';
import 'brand_screen.dart';
import 'export_screen.dart';
import 'kpi_screen.dart';
import 'ms_area_screen.dart';
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

/// Hemat kuota: data dimuat saat beranda dibuka, saat aplikasi dibuka lagi dari latar belakang,
/// dan saat tombol muat ulang / tarik-ke-bawah. Tidak ada muat ulang otomatis berkala.
class _AtasanHomeState extends State<AtasanHome> with WidgetsBindingObserver {
  int _tab = 0;
  DateTime _tanggal = wibToday();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _b = {};
  int _rev = 0;
  DateTime? _dimuat;

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
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Aplikasi dibuka lagi dari latar belakang: muat ulang (paling cepat sekali per 1 menit).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted || _tab == 2) return;
    final d = _dimuat;
    if (d == null || DateTime.now().difference(d) > const Duration(minutes: 1)) _load();
  }

  Future<void> _load() async {
    _dimuat = DateTime.now();
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
    const judulTab = ['Beranda', 'Laporan', 'Kelola'];
    return PopScope(
      canPop: !_bisaKembali || _tab == 2,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _kembali();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _bisaKembali && _tab < 2 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _kembali) : null,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_tab == 2
                ? 'Kelola'
                : '${judulTab[_tab]}${_sales != null ? ' · Sales ${_sales!['sales']}' : (_trainer != null ? ' · Trainer ${_trainer!['trainer']}' : '')}'),
            Text('${me.nama} · ${me.roleLabel} · ${me.cakupan}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ]),
          actions: [
            if (_tab < 2) ...[
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
            NavigationDestination(icon: Icon(Icons.assignment), label: 'Laporan'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Kelola'),
          ],
        ),
        body: _tab == 2 ? _kelola() : _isi(laporan: _tab == 1),
      ),
    );
  }

  String get _judul => _sales != null
      ? 'area ${_sales!['area']}'
      : (_trainer != null ? 'Trainer ${_trainer!['trainer']}' : me.cakupan);

  /// Tambah penjualan untuk satu PC (koreksi oleh atasan): pilih PC, lalu buka penjualan hari ini.
  Future<void> _tambahPenjualan() async {
    final pcs = asList(_b['per_pc']);
    final p = await showSearchPicker(
      context,
      title: 'Tambah penjualan untuk PC',
      loader: () async => pcs,
      titleOf: (m) => '${m['pc']}',
      subtitleOf: (m) => '${m['toko']}',
    );
    if (p == null || !mounted) return;
    final pc = await PcDetailScreen.muat(context, '${p['pc_id']}', _tanggal);
    if (pc == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PenjualanScreen(toko: pc)));
    _load();
  }

  // ------------------------------------------------------------------
  Widget _isi({required bool laporan}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final hk = HariKerja.dari(_tanggal);
    final hariIni = isSameDay(_tanggal, wibToday());
    final pcs = asList(_b['per_pc']);
    final perSales = asList(_b['per_sales']);
    final key = '${_filter.key}-${ymd(_tanggal)}-$_rev';
    final judul = _judul;

    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(hariTgl(_tanggal), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    ];

    if (!laporan) {
      // ---------------- BERANDA: ringkasan pencapaian ----------------
      out.addAll([
        TimegoneBar(hk: hk, tampilSisa: false),
        KalenderPenjualan(
          key: ValueKey('kal-$key'),
          selected: _tanggal,
          filter: _filter,
          onSelect: (d) {
            setState(() => _tanggal = d);
            _load();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: pcs.isEmpty ? null : _tambahPenjualan,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Tambah / koreksi penjualan PC'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ),
        SellOutCard(hari: asMap(_b['hari']), bulan: asMap(_b['bulan']), target: asMap(_b['target']), hk: hk, judul: judul),
        RingkasanGajiCard(key: ValueKey('gaji-$key'), filter: _filter, tanggal: _tanggal, onTapPc: _bukaPc),
        KontribusiTipe(key: ValueKey('kt-$key'), filter: _filter, tanggal: _tanggal),
        KontribusiHpIot(bulan: asMap(_b['bulan'])),
        KontribusiBayar(key: ValueKey('kb-$key'), filter: _filter, tanggal: _tanggal),
        KontribusiKategori(key: ValueKey('kk-$key'), filter: _filter, tanggal: _tanggal),
      ]);
    } else {
      // ---------------- LAPORAN: pencapaian per Trainer / Sales / PC & status hari itu ----------------
      final peringkatSales = PeringkatCard(
        judul: 'Peringkat Sales',
        rows: perSales,
        hk: hk,
        namaKey: 'sales',
        idKey: 'sales_id',
        keterangan: (r) => '${r['area'] ?? ''} · ${r['toko']} toko · ${r['pc']} PC'
            '${r['trainer'] != null && _level == 'mt' ? ' · Trainer ${r['trainer']}' : ''} · NOSELL ${r['nosell'] ?? 0} hari',
        onTap: _bukaSales,
      );
      final peringkatTrainer = PeringkatCard(
        judul: 'Peringkat Trainer',
        rows: asList(_b['per_trainer']),
        hk: hk,
        namaKey: 'trainer',
        idKey: 'trainer_id',
        keterangan: (r) => 'Sales: ${r['sales'] ?? '-'} · ${r['toko']} toko · ${r['pc']} PC · NOSELL ${r['nosell'] ?? 0} hari',
        onTap: _bukaTrainer,
      );
      out.addAll([
        if (_level == 'mt') ...[
          peringkatTrainer,
          peringkatSales,
          NosellRekapCard(
            trainer: asList(_b['per_trainer']),
            sales: perSales,
            total: toNum(_b['nosell_total']),
            onTapTrainer: _bukaTrainer,
            onTapSales: _bukaSales,
          ),
        ],
        if (_level == 'trainer') ...[
          peringkatSales,
          SebaranPcCard(pcs: pcs, onTapPc: _bukaPc),
        ],
        DaftarPcCard(rows: pcs, hk: hk, hariIni: hariIni, onTap: _bukaPc),
        StatusPcCard(pcs: pcs, onTapPc: _bukaPc),
        ProduktivitasPcCard(pcs: pcs),
        if (_level != 'mt') NosellPcCard(pcs: pcs, onTapPc: _bukaPc),
        UpdateStokCard(data: asMap(_b['stok']), onTapToko: _bukaStok),
        Card(
          child: ListTile(
            leading: const Icon(Icons.pie_chart),
            title: const Text('MS Allbrand area', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Satu tabel: OPPO vs semua brand per toko · hari ini & todate'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MsAreaScreen(filter: _filter, tanggal: _tanggal, judul: judul),
            )),
          ),
        ),
      ]);
    }
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
      item(Icons.event_busy, 'Kehadiran PC', 'Offday, izin, sakit PC ($cak)', const OffdayScreen()),
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
      body: HariPcView(pc: pc, bagian: BagianPc.semua),
    );
  }
}
