import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils.dart';

class Profile {
  final String id;
  final String nama;

  /// mt, trainer, sales, pc
  final String role;
  final int? storeId;
  final String toko;
  final int? areaId;
  final String area;
  final String email;
  final String? sales;
  final String? trainer;

  const Profile({
    required this.id,
    required this.nama,
    required this.role,
    this.storeId,
    this.toko = '',
    this.areaId,
    this.area = '',
    required this.email,
    this.sales,
    this.trainer,
  });

  bool get isPc => role == 'pc';
  bool get isSales => role == 'sales';
  bool get isTrainer => role == 'trainer';
  bool get isMt => role == 'mt';

  /// MT, Trainer, dan Sales memakai beranda atasan.
  bool get usesAdminHome => !isPc;

  String get roleLabel => labelRole(role);

  /// Ringkasan cakupan untuk judul layar.
  String get cakupan => switch (role) {
        'mt' => 'Semua area',
        'trainer' => 'Wilayah Trainer',
        'sales' => area.isEmpty ? 'Belum punya area' : 'Area $area',
        _ => toko,
      };

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        nama: (m['nama'] ?? '') as String,
        role: (m['role'] ?? 'pc') as String,
        storeId: m['store_id'] == null ? null : toNum(m['store_id']).toInt(),
        toko: (m['toko'] ?? '') as String,
        areaId: m['area_id'] == null ? null : toNum(m['area_id']).toInt(),
        area: (m['area'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        sales: m['sales'] as String?,
        trainer: m['trainer'] as String?,
      );
}

String labelRole(String role) => switch (role) {
      'pc' => 'Product Consultant',
      'sales' => 'Sales',
      'trainer' => 'Trainer',
      'mt' => 'Manajer Trainer',
      _ => role,
    };

class Session {
  static Profile? current;

  /// Naik setiap data akun berubah, agar tampilan ikut diperbarui.
  static final perubahan = ValueNotifier<int>(0);

  static SupabaseClient get db => Supabase.instance.client;

  static Future<Profile?> load() async {
    if (db.auth.currentSession == null) {
      current = null;
      return null;
    }
    final res = await db.rpc('my_profile');
    if (res == null) {
      current = null;
      return null;
    }
    current = Profile.fromMap(asMap(res));
    return current;
  }
}
