import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils.dart';

/// Notifikasi lokal PC (tanpa server/Firebase): pengingat stok pagi (10.00) dan laporan
/// malam (21.30 & 22.15). Tidak dikirim di hari offday/izin.
class NotifService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static tz.Location? _jkt;

  static const _stokDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'stok',
      'Pengingat stok pagi',
      channelDescription: 'Pengingat update stok harian',
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.public,
    ),
  );

  static const _reportDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'report',
      'Pengingat laporan malam',
      channelDescription: 'Pengingat kirim laporan sebelum 22.30 WIB',
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.public,
    ),
  );

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      _jkt = tz.getLocation('Asia/Jakarta');
      const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
      await _plugin.initialize(settings: settings);
    } catch (e) {
      debugPrint('Notifikasi gagal disiapkan: $e');
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> _at(int id, String title, String body, DateTime wib, NotificationDetails details) async {
    final loc = _jkt;
    if (loc == null) return;
    final when = tz.TZDateTime(loc, wib.year, wib.month, wib.day, wib.hour, wib.minute);
    if (!when.isAfter(tz.TZDateTime.now(loc))) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Menjadwalkan ulang pengingat PC untuk 7 hari ke depan. [offdays] = tanggal (yyyy-MM-dd) offday/izin.
  static Future<void> reschedule({
    required Set<String> offdays,
    required bool stokDone,
    required bool laporanDone,
  }) async {
    if (_jkt == null) return;
    try {
      await _plugin.cancelAll();
      final today = wibToday();
      for (var i = 0; i < 7; i++) {
        final d = addDays(today, i);
        if (offdays.contains(ymd(d))) continue;
        if (i > 0 || !stokDone) {
          await _at(2000 + i * 10, 'Update stok hari ini', 'Jangan lupa update stok toko hari ini.',
              DateTime(d.year, d.month, d.day, 10), _stokDetails);
        }
        if (i > 0 || !laporanDone) {
          await _at(2002 + i * 10, 'Waktunya kirim laporan',
              'Lengkapi stok, penjualan, MS Allbrand, dan cek limit, lalu kirim laporan sebelum 22.30 WIB.',
              DateTime(d.year, d.month, d.day, 21, 30), _reportDetails);
          await _at(2003 + i * 10, 'Laporan belum dikirim', '15 menit lagi batas laporan (22.30 WIB).',
              DateTime(d.year, d.month, d.day, 22, 15), _reportDetails);
        }
      }
    } catch (e) {
      debugPrint('Gagal menjadwalkan notifikasi: $e');
    }
  }
}
