// Menus — the read side of supabase/042_menus.sql. A guest opens a venue's menu by
// tapping the NFC tag / scanning the QR on the table (bwdy.site/m/<slug>); the
// phone routes that link here. The read is anonymous-capable and records nothing:
// opening a menu tells the venue nothing about you.
import 'package:brewdiary_core/menus.dart';
import 'base.dart';

class MenuApi {
  /// null = no verified venue with that slug. Throws when the cloud can't be reached.
  static Future<Menu?> load(String slug) async {
    final c = db;
    if (c == null) throw StateError('not connected');
    return groupMenu(rows(await c.rpc('venue_menu', params: {'in_slug': slug})));
  }
}
