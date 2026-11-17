import 'package:flutter/material.dart';

import '../../data/lka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/estimasi_gaji.dart';
import '../../widgets/insentif_harian.dart';
import '../../widgets/kalender_penjualan.dart';
import '../../widgets/kontribusi_kategori.dart';
import '../../widgets/kontribusi_tipe.dart';
import '../../widgets/sell_out_card.dart';
import '../../widgets/widgets.dart';
import 'cek_limit_screen.dart';
import 'laporan_screen.dart';
import 'ms_allbrand_screen.dart';
import 'penjualan_bulan_screen.dart';
import 'penjualan_screen.dart';
import 'stok_screen.dart';

/// Laporan satu PC pada satu tanggal: status, timegone, capaian, insentif, estimasi gaji,
/// kalender, kontribusi tipe, empat bagian laporan, dan tombol kirim laporan.
/// Dipakai beranda PC dan detail PC untuk atasan.
class HariPcView extends StatefulWidget {
  final PcHari pc;

  /// Dipanggil setiap data selesai dimuat (beranda PC memakainya untuk menjadwalkan pengingat).
  final void Function(Map<String, dynamic> rekap)? onLoaded;
  const HariPcView({super.key, required this.pc, this.onLoaded});

  @override
  State<HariPcView> createState() => HariPcViewState();
}

class HariPcViewState extends State<HariPcView> {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Map<String, dynamic> _r = {};
  int _rev = 0;

  PcHari get t => widget.pc.salin(
        libur: _r['libur'] as String?,
        hapusLibur: _r.isNotEmpty && _r['libur'] == null,
        areaId: _r['area_id'] == null ? null : toNum(_r['area_id']).toInt(),
        area: _r['area'] as String?,
      );

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant HariPcView old) {
    super.didUpdateWidget(old);
    if (old.pc.pcId != widget.pc.pcId || old.pc.tgl != widget.pc.tgl) load();
  }

  Future<void> load() async {
    setState(() {
      _loading = _r.isEmpty;
      _error = null;
    });
    try {
      _r = asMap(await Session.db.rpc('rekap_pc', params: {'p_pc': widget.pc.pcId, 'p_tanggal': widget.pc.tgl}));
      widget.onLoaded?.call(_r);
      _rev++;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    load();
  }

  Future<void> _kirim() async {
    final ok = await confirmDialog(context, 'Kirim laporan?',
        'Laporan ${t.pcNama} ${tglPendek(t.tanggal)} akan ditandai terkirim. Data masih bisa dikoreksi sampai 22.30 WIB.',
        yes: 'Kirim');
    if (!ok) return;
    setState(() => _sending = true);
    try {
      await Session.db.rpc('kirim_laporan', params: {'p_tanggal': t.tgl});
      await load();
      if (mounted) _open(LaporanScreen(pc: t));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: load);
    final me = Session.current!;
    final hari = asMap(_r['hari']);
    final bulan = asMap(_r['bulan']);
    final target = asMap(_r['target']);
    final laporan = _r['laporan'] == null ? null : asMap(_r['laporan']);
    final kurang = (_r['kurang'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final stokUpdate = _r['stok_update'] == null ? null : parseWib('${_r['stok_update']}');
    final penjualan = asList(_r['penjualan']);
    final cek = asList(_r['cek_limit']);
    final libur = _r['libur'] as String?;
    final hk = HariKerja.dari(t.tanggal, offdaySisa: toNum(_r['offday_sisa']).toInt());
    final tokoUnit = toNum(hari['toko_unit']);
    final komp = toNum(hari['kompetitor']);
    final pcLain = (_r['pc_lain'] as List?)?.map((e) => '$e').toList() ?? const <String>[];

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        if (!me.isPc)
          InfoBanner(
            '${t.pcNama} · ${t.toko} · ${_r['area'] ?? ''}'
            '${_r['sales'] != null ? '\nSales: ${_r['sales']}' : ''}${_r['trainer'] != null ? ' · Trainer: ${_r['trainer']}' : ''}',
            icon: Icons.person,
          ),
        if (libur != null)
          InfoBanner('${libur == 'izin' ? 'IZIN' : 'OFFDAY'}: PC tidak wajib lapor hari ini.',
              icon: Icons.beach_access, color: Colors.teal),
        _statusLaporan(laporan, kurang),
        TimegoneBar(hk: hk),
        SellOutCard(
          hari: hari,
          bulan: bulan,
          target: target,
          hk: hk,
          onTapHp: () => _open(PenjualanBulanScreen(toko: t, tipe: 'HP')),
          onTapIot: () => _open(PenjualanBulanScreen(toko: t, tipe: 'IOT')),
        ),
        InsentifHariCard(key: ValueKey('ins-${t.pcId}-${t.tgl}-$_rev'), pcId: t.pcId, tanggal: t.tanggal),
        EstimasiGajiCard(key: ValueKey('gaji-${t.pcId}-${t.tgl}-$_rev'), pcId: t.pcId, tanggal: t.tanggal, pcNama: t.pcNama),
        KalenderPenjualan(
          key: ValueKey('kal-${t.pcId}-$_rev'),
          selected: t.tanggal,
          filter: Cakupan(pcId: t.pcId),
          onSelect: (d) => _open(PenjualanScreen(toko: t.salin(tanggal: d))),
        ),
        if (!me.isPc)
          KontribusiKategori(key: ValueKey('kk-${t.pcId}-${t.tgl}-$_rev'), filter: Cakupan(pcId: t.pcId), tanggal: t.tanggal),
        KontribusiTipe(key: ValueKey('kt-${t.pcId}-${t.tgl}-$_rev'), filter: Cakupan(pcId: t.pcId), tanggal: t.tanggal),
        const SectionHeader('Laporan harian'),
        _tile(
          icon: Icons.inventory_2,
          title: 'Update stok (per toko)',
          status: _r['stok_awal_pada'] == null
              ? 'Stok awal belum diisi: hitung stok fisik toko${pcLain.isNotEmpty ? ' (cukup 1 PC di toko)' : ''}'
              : stokUpdate == null
                  ? 'Hari ini belum dicek${pcLain.isNotEmpty ? ' · bisa dicek PC lain di toko' : ''}'
                  : 'Dicek ${jamMenit(stokUpdate)}${pcLain.isNotEmpty ? ' · dipakai bersama ${pcLain.join(', ')}' : ''}',
          ok: stokUpdate != null,
          onTap: () => _open(StokScreen(toko: t)),
        ),
        _tile(
          icon: Icons.point_of_sale,
          title: 'Penjualan',
          status: penjualan.isNotEmpty
              ? 'HP ${angka(toNum(hari['unit']))} unit · ${rupiah(toNum(hari['value']))} · IoT ${angka(toNum(hari['iot']))}'
              : (_r['nihil_penjualan'] == true ? 'Tidak ada penjualan (NOSELL)' : 'Belum ada penjualan'),
          ok: penjualan.isNotEmpty || _r['nihil_penjualan'] == true,
          onTap: () => _open(PenjualanScreen(toko: t)),
        ),
        _tile(
          icon: Icons.pie_chart,
          title: 'MS Allbrand (per toko)',
          status: _r['kompetitor_terisi'] == true
              ? 'Brand lain ${angka(komp)} unit · MS OPPO toko '
                  '${tokoUnit + komp > 0 ? '${(tokoUnit / (tokoUnit + komp) * 100).toStringAsFixed(0)}%' : '-'}'
              : 'Belum diisi',
          ok: _r['kompetitor_terisi'] == true,
          onTap: () => _open(MsAllbrandScreen(toko: t)),
        ),
        _tile(
          icon: Icons.fact_check,
          title: 'Cek limit (wajib)',
          status: cek.isNotEmpty
              ? '${cek.length} pengajuan · ${cek.where((c) => c['hasil'] == 'Approve').length} approve'
              : (_r['nihil_cek_limit'] == true ? 'Tidak ada pengajuan hari ini' : 'Belum diisi'),
          ok: cek.isNotEmpty || _r['nihil_cek_limit'] == true,
          onTap: () => _open(CekLimitScreen(pc: t)),
        ),
        const SizedBox(height: 16),
        if (laporan == null && me.isPc && t.milikSaya && t.bolehIsiHarian)
          FilledButton.icon(
            onPressed: _sending ? null : _kirim,
            icon: busyIcon(_sending, Icons.send),
            label: const Text('Kirim laporan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _open(LaporanScreen(pc: t)),
          icon: const Icon(Icons.image),
          label: const Text('Lihat & bagikan gambar laporan'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }

  Widget _statusLaporan(Map<String, dynamic>? laporan, List<String> kurang) {
    if (laporan != null) {
      final pada = parseWib('${laporan['dikirim_pada']}');
      return InfoBanner('Laporan terkirim ${jamMenit(pada)} WIB', icon: Icons.verified, color: Colors.green.shade700);
    }
    if (t.libur != null) return const SizedBox.shrink();
    if (!t.hariIni || lewatBatasLaporan()) {
      return InfoBanner('TIDAK LAPOR: laporan belum dikirim sampai $batasLaporanText WIB.',
          icon: Icons.error, color: Colors.red.shade700);
    }
    final sisa = batasLaporanPada(t.tanggal).difference(wibNow());
    return InfoBanner(
      'Laporan belum dikirim · sisa ${sisa.inHours} jam ${sisa.inMinutes % 60} menit (batas $batasLaporanText WIB)'
      '${kurang.isEmpty ? '\nSemua bagian sudah terisi, tekan Kirim laporan.' : '\nBelum: ${kurang.join(', ')}'}',
      icon: Icons.schedule,
      color: Colors.blueGrey,
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String status,
    required bool ok,
    required VoidCallback onTap,
  }) {
    final c = ok ? Colors.green.shade700 : Colors.grey.shade600;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(status, style: TextStyle(color: c)),
        trailing: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: c),
        onTap: onTap,
      ),
    );
  }
}
