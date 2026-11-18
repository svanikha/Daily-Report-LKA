import 'package:flutter/material.dart';

import '../../data/lka.dart';
import '../../services/akun.dart';
import '../../services/cache_data.dart';
import '../../services/notif_service.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import '../toko/hari_pc_view.dart';

/// Beranda PC dengan 3 tab: Beranda (pencapaian) · Laporan (laporan harian) · Kelola (akun).
class PcHome extends StatefulWidget {
  final Profile pc;
  const PcHome({super.key, required this.pc});

  @override
  State<PcHome> createState() => _PcHomeState();
}

class _PcHomeState extends State<PcHome> {
  final _beranda = GlobalKey<HariPcViewState>();
  final _laporan = GlobalKey<HariPcViewState>();
  late final PcHari _pc = PcHari.dariProfil(widget.pc);
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    NotifService.requestPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  /// Jadwalkan ulang pengingat lokal stok & laporan setiap data dimuat.
  Future<void> _jadwalkan(Map<String, dynamic> r) async {
    try {
      final today = wibToday();
      final rows = asList(await Session.db
          .from('pc_day_status')
          .select('tanggal')
          .eq('pc_id', widget.pc.id)
          .gte('tanggal', ymd(today))
          .lte('tanggal', ymd(addDays(today, 7))));
      await NotifService.reschedule(
        offdays: {for (final x in rows) '${x['tanggal']}'},
        stokDone: r['stok_waktu'] != null,
        laporanDone: r['laporan'] != null,
      );
    } catch (_) {
      // Tanpa internet: pengingat dijadwalkan lagi saat aplikasi dibuka berikutnya.
    }
  }

  Future<void> _muatUlang() async {
    await CacheData.bersihkan();
    _beranda.currentState?.load();
    _laporan.currentState?.load();
  }

  @override
  Widget build(BuildContext context) {
    const judul = ['Beranda', 'Laporan', 'Kelola'];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${judul[_tab]} · ${widget.pc.toko}'),
          Text('${widget.pc.nama} · ${hariTgl(_pc.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          if (_tab < 2) IconButton(onPressed: _muatUlang, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 0) _beranda.currentState?.load();
          if (i == 1) _laporan.currentState?.load();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Laporan'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Kelola'),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        HariPcView(key: _beranda, pc: _pc, bagian: BagianPc.beranda, onChanged: () => _laporan.currentState?.load()),
        HariPcView(
          key: _laporan,
          pc: _pc,
          bagian: BagianPc.laporan,
          onLoaded: _jadwalkan,
          onChanged: () => _beranda.currentState?.load(),
        ),
        _kelola(),
      ]),
    );
  }

  Widget _kelola() {
    final p = widget.pc;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.person),
          title: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Product Consultant · ${p.toko}\nArea ${p.area}'
              '${p.sales != null ? ' · Sales ${p.sales}' : ''}${p.trainer != null ? ' · Trainer ${p.trainer}' : ''}'),
          isThreeLine: true,
        ),
      ),
      const SectionHeader('Akun'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Ganti password'),
          onTap: () => changePasswordDialog(context),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Keluar'),
          onTap: () => logout(context),
        ),
      ),
      const SizedBox(height: 12),
      const InfoBanner('Lupa password? Minta Sales, Trainer, atau MT mengatur password baru.', icon: Icons.help_outline),
      Center(child: Text('Daily Report LKA · versi ${UpdateService.versionName}', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}
