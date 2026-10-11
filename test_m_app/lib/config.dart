// Build-time configuration. Nothing secret lives here: the Supabase anon key is
// public by design (data is protected by RLS), and the AI key stays on the server.
//
// Pass values at build/run time:
//   flutter run --dart-define-from-file=env.json
// where env.json is (see env.example.json):
//   { "SUPABASE_URL": "...", "SUPABASE_ANON_KEY": "...", "SITE_URL": "https://bwdy.site" }
//
// Both values are required: a build without them opens a "not connected" page that
// says what's missing, and never runs on pretend accounts. (Signed out, the first
// nights you log stay on the phone and move to your diary when you make one.)
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The deployed website. Ninkasi (/api/bartender), account deletion and password
  /// reset are served from here — the phone never holds an AI key.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://bwdy.site');

  static bool get cloud => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Uri api(String path) => Uri.parse('$siteUrl$path');
}
