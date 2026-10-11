// Build-time configuration. Nothing secret lives here: the Supabase anon key is public
// by design (every row is guarded by RLS), and the AI key stays on the website's server.
//
//   flutter run --dart-define-from-file=env.json
// where env.json is { "SUPABASE_URL": "...", "SUPABASE_ANON_KEY": "...", "SITE_URL": "https://bwdy.site" }.
//
// Both values are required: a build without them opens a "not connected" page that
// says what's missing, and never a pretend venue.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The deployed website. Ninkasi (/api/venue-ai) and account deletion are served
  /// from here — the phone never holds an AI key.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://bwdy.site');

  static bool get cloud => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Uri api(String path) => Uri.parse('$siteUrl$path');
}
