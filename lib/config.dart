/// Konfigurasi koneksi Supabase (project KHUSUS Daily Report LKA, terpisah dari NKA).
/// Diisi saat build lewat --dart-define=SUPABASE_URL=... dan SUPABASE_ANON_KEY=...
/// (GitHub -> Settings -> Secrets and variables -> Actions -> Variables).
/// Anon key memang dirancang untuk ada di aplikasi; keamanan data dijaga Row Level Security.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://GANTI.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'GANTI_ANON_KEY');

  static bool get isConfigured => !supabaseUrl.contains('GANTI') && !supabaseAnonKey.contains('GANTI');
}
