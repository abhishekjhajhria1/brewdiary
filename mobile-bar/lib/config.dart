// Build-time configuration. Nothing secret lives here: the Supabase anon key is public
// by design (every row is guarded by RLS), and the AI key stays on the website's server.
//
//   flutter run --dart-define-from-file=env.json
// where env.json is { "SUPABASE_URL": "...", "SUPABASE_ANON_KEY": "...", "SITE_URL": "https://bwdy.site" }.
//
// With no Supabase values the app opens the DEMO venue: seeded, clearly labelled, and
// entirely on the device — for screenshots, tests and showing a bar what it does.
// `--dart-define=DEMO=true` forces demo mode even with the real values present.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The deployed website. Ninkasi (/api/venue-ai) and account deletion are served
  /// from here — the phone never holds an AI key.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://bwdy.site');

  static const forceDemo = bool.fromEnvironment('DEMO');

  static bool get cloud => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && !forceDemo;

  static Uri api(String path) => Uri.parse('$siteUrl$path');
}
