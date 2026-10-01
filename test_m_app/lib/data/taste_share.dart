// Your taste at the table (056). When you open a venue's table link or menu link,
// the bartender gets your taste — what you're into, what you usually have, the
// mood words, "often alcohol-free", "nothing with alcohol tonight" — so the drink
// they make is one you'll like. Never your diary, never where else you've been.
//
// You say yes once (the first time you open a venue's menu); after that it shares
// on its own, for tonight only (8 hours), and you can stop it any time. And your
// guest card: a 6-letter code staff type at the till to find you.
import 'package:flutter/foundation.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'auth.dart';
import 'base.dart';
import 'entries.dart';

/// The words a kind is shared as (the same as the passport's).
const _kindWords = {
  'cocktail': 'Cocktails',
  'beer': 'Beer',
  'wine': 'Wine',
  'spirit': 'Spirits',
  'coffee': 'Coffee',
  'tea': 'Tea',
  'soft': 'Soft drinks',
  'other': 'Something else',
};

class TasteShare {
  final String venueId;
  final String venueName;
  final String? tableLabel;
  final DateTime expiresAt;
  const TasteShare({required this.venueId, required this.venueName, this.tableLabel, required this.expiresAt});
}

class TasteShareStore extends ChangeNotifier {
  static final instance = TasteShareStore();
  static const _consentKey = 'brewdiary.tasteshare.consent'; // 'on' | 'off'; absent = never asked
  static const _dryKey = 'brewdiary.tastecard.drytonight'; // the day it was switched on
  static const hiddenKey = 'brewdiary.tastecard.hidden'; // lines hidden on the passport

  /// null = we haven't asked yet.
  bool? get consent => switch (Prefs.getString(_consentKey)) { 'on' => true, 'off' => false, _ => null };
  Future<void> setConsent(bool on) async {
    await Prefs.setString(_consentKey, on ? 'on' : 'off');
    notifyListeners();
  }

  /// "Nothing with alcohol tonight" — it lasts the day it was switched on.
  bool get dryTonight => Prefs.getString(_dryKey) == todayKey();
  Future<void> setDryTonight(bool on) async {
    on ? await Prefs.setString(_dryKey, todayKey()) : await Prefs.remove(_dryKey);
    notifyListeners();
  }

  /// What a bar is sent: the taste card, minus any line you've hidden.
  Map<String, Object> payload() {
    final p = tasteProfile(entryStore.entries);
    final hidden = {...(Prefs.getJson<List<dynamic>>(hiddenKey) ?? const []).map((e) => '$e')};
    return {
      if (!hidden.contains('into') && p.favourites.isNotEmpty) 'into': p.favourites,
      if (!hidden.contains('usually') && p.kinds.isNotEmpty) 'usually': [for (final k in p.kinds) _kindWords[k.name] ?? k.name],
      if (!hidden.contains('mood') && p.moods.isNotEmpty) 'moods': p.moods,
      if (!hidden.contains('free')) 'alcohol_free_often': p.noAlcoholShare >= .4,
      'dry_tonight': dryTonight,
    };
  }

  /// Share with the venue behind a table [code] or a menu [slug]. Returns the share,
  /// or null when signed out / not connected.
  Future<TasteShare?> share({String? code, String? slug}) async {
    final c = db;
    if (c == null || !auth.isAuthed || (code == null && slug == null)) return null;
    final r = rows(await (code != null
        ? c.rpc('share_taste', params: {'in_code': code, 'in_taste': payload()})
        : c.rpc('share_taste_at', params: {'in_slug': slug, 'in_taste': payload()})));
    if (r.isEmpty) return null;
    notifyListeners();
    return TasteShare(venueId: '${r.first['venue_id']}', venueName: '${r.first['venue_name']}', expiresAt: DateTime.parse('${r.first['expires_at']}').toLocal());
  }

  Future<void> stop(String venueId) async {
    await db?.rpc('stop_taste_share', params: {'vid': venueId});
    notifyListeners();
  }

  Future<List<TasteShare>> mine() async {
    final c = db;
    if (c == null || !auth.isAuthed) return const [];
    return [
      for (final r in rows(await c.rpc('my_taste_shares')))
        TasteShare(venueId: '${r['venue_id']}', venueName: '${r['venue_name']}', tableLabel: r['table_label'] as String?, expiresAt: DateTime.parse('${r['expires_at']}').toLocal()),
    ];
  }

  /// My guest card: a fresh 6-letter code, good for 10 minutes.
  Future<({String code, DateTime expiresAt})?> guestCode() async {
    final c = db;
    if (c == null || !auth.isAuthed) return null;
    final r = rows(await c.rpc('my_guest_code'));
    if (r.isEmpty) return null;
    return (code: '${r.first['code']}', expiresAt: DateTime.parse('${r.first['expires_at']}').toLocal());
  }
}
