import '../services/session.dart';
import '../utils.dart';

/// Cara bayar penjualan (disimpan di sales.metode + sales.cara_bayar).
const cashViaList = ['Transfer', 'Tunai'];
const kreditViaList = ['Avanto', 'Kredivo', 'HCI', 'Indodana', 'Kreditplus', 'Akulaku', 'Yesscredit'];

/// Kategori user (pembeli), disimpan di sales.kategori_user.
const kategoriUserList = ['Walk-in', 'Databased', 'Online'];

/// Leasing untuk cek limit (sama dengan pilihan Kredit di penjualan).
const leasingList = kreditViaList;

/// Batas laporan malam PC: 22.30 WIB.
const batasLaporanText = '22.30';

DateTime batasLaporanPada(DateTime tanggal) => DateTime(tanggal.year, tanggal.month, tanggal.day, 22, 30);

bool lewatBatasLaporan([DateTime? wib]) {
  final w = wib ?? wibNow();
  return w.hour * 60 + w.minute >= 22 * 60 + 30;
}

/// Segmen harga MS Allbrand.
const segmenList = ['lt3', '3to6', 'gt6'];
const segmenLabel = {'lt3': '< 3 jt', '3to6': '3 jt - 6 jt', 'gt6': '6 jt up'};

/// Segmen yang berlaku untuk satu brand (Apple hanya 6 jt up).
List<String> segmenBrand(String nama) => nama.toLowerCase() == 'apple' ? const ['gt6'] : segmenList;

/// Hari kerja & timegone dalam satu bulan.
/// timegone = tanggal / jumlah hari di bulan itu (10/30 = 33%).
/// sisa hari kerja = hari berjalan s.d. akhir bulan (termasuk hari ini) dikurangi offday PC.
class HariKerja {
  final int hariKe;
  final int totalHari;
  final int sisaHariKerja;
  final int offdaySisa;
  const HariKerja({required this.hariKe, required this.totalHari, required this.sisaHariKerja, required this.offdaySisa});

  factory HariKerja.dari(DateTime tanggal, {int offdaySisa = 0}) {
    final total = monthEnd(tanggal).day;
    final sisa = total - tanggal.day + 1 - offdaySisa;
    return HariKerja(hariKe: tanggal.day, totalHari: total, sisaHariKerja: sisa < 0 ? 0 : sisa, offdaySisa: offdaySisa);
  }

  double get timegone => hariKe / totalHari * 100;
  String get timegoneText => '$hariKe/$totalHari = ${timegone.toStringAsFixed(0)}%';

  num perHari(num target, num capai) {
    final kurang = target - capai;
    if (kurang <= 0 || sisaHariKerja <= 0) return 0;
    return kurang / sisaHariKerja;
  }
}

/// Jenis target bulanan (per toko dan per PC).
class TargetDef {
  final String jenis;
  final String label;
  final bool rupiah;
  const TargetDef(this.jenis, this.label, {this.rupiah = false});
}

const targetDefs = [
  TargetDef('unit', 'Unit HP'),
  TargetDef('value', 'Value HP', rupiah: true),
  TargetDef('fokus', 'Tipe fokus (unit)'),
  TargetDef('iot', 'Unit IoT'),
  TargetDef('iot_value', 'Value IoT', rupiah: true),
];

/// Filter data beranda & kartu bersama. Semua null = seluruh cakupan akun.
class Cakupan {
  final String? salesId;
  final int? storeId;
  final String? pcId;
  const Cakupan({this.salesId, this.storeId, this.pcId});

  Map<String, dynamic> get params => {'p_sales': salesId, 'p_store': storeId, 'p_pc': pcId};
  String get key => '${salesId ?? ''}|${storeId ?? ''}|${pcId ?? ''}';
  bool get semua => salesId == null && storeId == null && pcId == null;

  @override
  bool operator ==(Object other) => other is Cakupan && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Satu PC pada satu tanggal: konteks semua layar input harian.
/// Stok & MS Allbrand memakai [storeId] (per toko); penjualan, cek limit, laporan memakai [pcId].
class PcHari {
  final String pcId;
  final String pcNama;
  final int storeId;
  final String toko;
  final int areaId;
  final String area;
  final DateTime tanggal;

  /// offday | izin | null
  final String? libur;

  const PcHari({
    required this.pcId,
    required this.pcNama,
    required this.storeId,
    required this.toko,
    required this.areaId,
    this.area = '',
    required this.tanggal,
    this.libur,
  });

  factory PcHari.dariProfil(Profile p) => PcHari(
        pcId: p.id,
        pcNama: p.nama,
        storeId: p.storeId!,
        toko: p.toko,
        areaId: p.areaId ?? 0,
        area: p.area,
        tanggal: wibToday(),
      );

  PcHari salin({DateTime? tanggal, String? libur, bool hapusLibur = false, int? areaId, String? area}) => PcHari(
        pcId: pcId,
        pcNama: pcNama,
        storeId: storeId,
        toko: toko,
        areaId: areaId ?? this.areaId,
        area: area ?? this.area,
        tanggal: tanggal == null ? this.tanggal : dateOnly(tanggal),
        libur: hapusLibur ? null : (libur ?? (tanggal == null ? this.libur : null)),
      );

  String get tgl => ymd(tanggal);
  bool get hariIni => isSameDay(tanggal, wibToday());
  bool get milikSaya => Session.current?.id == pcId;

  /// Sama dengan server can_write_daily / can_write_pc (stok, cek limit, tanda nihil).
  bool get bolehIsiHarian {
    final me = Session.current;
    if (me == null || tanggal.isAfter(wibToday())) return false;
    if (me.isPc) return milikSaya && hariIni && !lewatBatasLaporan();
    return true; // atasan: koreksi data PC di cakupannya (dijaga server)
  }

  /// Sama dengan server can_write_sales.
  bool get bolehIsiPenjualan {
    final me = Session.current;
    final today = wibToday();
    if (me == null || tanggal.isAfter(today)) return false;
    if (me.isPc) return milikSaya && tanggal.year == today.year && tanggal.month == today.month;
    return true;
  }

  String get alasanTerkunci => 'Input PC hanya untuk hari ini sampai pukul $batasLaporanText WIB.';
}

String jamMenit(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
