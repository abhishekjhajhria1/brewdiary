// Ninkasi for hosts — what the team needs to know before and during a shift. Pure:
// a brief in, plain lines out. The same brief goes to /api/host-ai (src/lib/hostAdvisor.ts
// has the twin of these rules) when the AI is on; with no network or no key, these
// lines ARE the briefing.
//
// The brief holds only what the person's own role can already see in the app, and
// only counts: never a guest's name, never what one person had or spent. Nothing here
// suggests selling more; it's about service, the menu, the law and the neighbourhood.
class HostBrief {
  final String venueName;
  final String kind; // venue kind (db word)
  final String role; // staff role (db word)
  final bool sellsAlcohol;
  final bool counter;
  final DateTime today;
  final bool roomOpen;
  final bool canOpenRoom;
  final int? guestsIn;
  final bool quietTonight;
  final List<String> soldOut;
  final List<String> alcoholFree;
  final int menuItems;
  final List<({String reward, String at})> perks;
  final List<({String kind, String title, DateTime? startsOn, DateTime? endsOn, String where})> signals;
  final List<String> area;

  const HostBrief({
    required this.venueName,
    required this.kind,
    required this.role,
    required this.sellsAlcohol,
    required this.counter,
    required this.today,
    this.roomOpen = false,
    this.canOpenRoom = false,
    this.guestsIn,
    this.quietTonight = false,
    this.soldOut = const [],
    this.alcoholFree = const [],
    this.menuItems = 0,
    this.perks = const [],
    this.signals = const [],
    this.area = const [],
  });

  static String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The wire shape /api/host-ai reads (and trusts nothing in).
  Map<String, dynamic> toJson() => {
        'venueName': venueName,
        'kind': kind,
        'role': role,
        'sellsAlcohol': sellsAlcohol,
        'counter': counter,
        'today': _d(today),
        'roomOpen': roomOpen,
        'canOpenRoom': canOpenRoom,
        'guestsIn': guestsIn,
        'quietTonight': quietTonight,
        'soldOut': soldOut.take(20).toList(),
        'alcoholFree': alcoholFree.take(10).toList(),
        'menuItems': menuItems,
        'perks': [for (final p in perks.take(3)) {'reward': p.reward, 'at': p.at}],
        'signals': [
          for (final s in signals.take(10))
            {'kind': s.kind, 'title': s.title, if (s.startsOn != null) 'startsOn': _d(s.startsOn!), if (s.endsOn != null) 'endsOn': _d(s.endsOn!), 'where': s.where},
        ],
        'area': area.take(8).toList(),
      };
}

int _days(DateTime from, DateTime to) => DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays;

bool _isDryDay(String kind, String title) => kind == 'holiday' && RegExp(r'\bdry\b', caseSensitive: false).hasMatch(title);

String _when(DateTime today, DateTime? d) {
  if (d == null) return '';
  final n = _days(today, d);
  if (n <= 0) return 'today';
  if (n == 1) return 'tomorrow';
  const wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return n < 7 ? 'on ${wd[d.weekday - 1]}' : 'in $n days';
}

String _list(List<String> xs) => xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';

/// The briefing, most urgent first.
List<String> hostBriefing(HostBrief b) {
  final lines = <String>[];

  // The law first: a dry day changes the whole shift.
  for (final s in b.signals) {
    if (!_isDryDay(s.kind, s.title) || s.startsOn == null) continue;
    final n = _days(b.today, s.startsOn!);
    final ongoing = n <= 0 && (s.endsOn == null || _days(b.today, s.endsOn!) >= 0);
    if (ongoing && b.sellsAlcohol) {
      lines.add('Today is a dry day (${s.title}): no alcohol may be sold. Lead with the alcohol-free list.');
    } else if (n == 1 && b.sellsAlcohol) {
      lines.add('Tomorrow is a dry day (${s.title}) — let regulars know tonight.');
    }
  }

  // Tonight.
  if (b.counter) {
    lines.add('The till is ready — punch cards once a day per guest.');
  } else if (b.roomOpen) {
    lines.add('Tonight\'s room is open${b.guestsIn == null ? '' : (b.guestsIn == 0 ? ' — no one has joined yet' : ', ${b.guestsIn} ${b.guestsIn == 1 ? 'guest' : 'guests'} in')}.');
  } else {
    lines.add(b.canOpenRoom ? 'No room open yet — open tonight\'s room so guests can join from the table.' : 'No room open yet — ask a manager to open tonight\'s room.');
  }
  if (b.quietTonight && b.perks.isNotEmpty) {
    lines.add('It\'s a quiet night: a visit counts double toward the card. Worth a word to regulars — it\'s a visit, not a drink, that counts.');
  }

  // The menu.
  if (b.soldOut.isNotEmpty) {
    lines.add('86\'d: ${_list(b.soldOut.take(5).toList())}${b.soldOut.length > 5 ? ' and ${b.soldOut.length - 5} more' : ''}. Say so before they order.');
  }
  if (b.sellsAlcohol) {
    if (b.alcoholFree.isNotEmpty) {
      lines.add('Alcohol-free tonight: ${_list(b.alcoholFree.take(3).toList())}. Offer one with every recommendation.');
    } else if (b.menuItems > 0) {
      lines.add('Nothing alcohol-free on the menu — add at least one (Menu).');
    }
  }

  // Around us.
  final soon = [
    for (final s in b.signals)
      if (!_isDryDay(s.kind, s.title) && (s.startsOn == null ? s.kind != 'price' && s.kind != 'venue' : _days(b.today, s.startsOn!) <= 3)) s,
  ];
  for (final s in soon.take(2)) {
    final when = _when(b.today, s.startsOn);
    lines.add('Around you: ${s.title}${when.isEmpty ? '' : ' ($when${s.where.isEmpty ? '' : ', ${s.where}'})'}.');
  }
  lines.addAll(b.area.take(2));

  if (b.sellsAlcohol && !b.counter) lines.add('Water is free and on every table. If someone\'s had enough, stop serving alcohol, offer water and food, and get the manager.');
  return lines;
}

/// Starter questions for the chat, for this person's job.
List<String> hostStarters(HostBrief b) => [
      if (b.sellsAlcohol) 'What\'s alcohol-free tonight?',
      'What\'s on around us?',
      'How do I explain the loyalty card?',
      if (b.sellsAlcohol) 'Someone\'s had enough — what do I do?',
      if (!b.sellsAlcohol) 'What sells best near us?',
    ];

/// Scripted answers for when Ninkasi is out of reach (no network, demo, no AI key).
String hostFallbackAnswer(HostBrief b, String question) {
  final q = question.toLowerCase();
  if (q.contains('enough') || q.contains('drunk') || q.contains('cut off')) {
    return 'Stop serving them alcohol — calmly, and without an audience. Offer water and something to eat, bring in the manager, and help them get home safely (a cab, a friend). Never argue, and never make it about them as a person. Nothing goes on their card.';
  }
  if (q.contains('alcohol-free') || q.contains('zero') || q.contains('mocktail')) {
    return b.alcoholFree.isEmpty
        ? 'There\'s nothing marked alcohol-free on the menu yet. Water is always free; ask a manager to add a proper zero-proof option.'
        : 'Tonight: ${_list(b.alcoholFree)}. Mention one with every recommendation — lots of people want one and don\'t ask.';
  }
  if (q.contains('around') || q.contains('event') || q.contains('nearby')) {
    final s = b.signals.where((s) => !_isDryDay(s.kind, s.title)).take(3).toList();
    return s.isEmpty
        ? 'Nothing listed around you right now. Events, openings and dry days show here as they come in.'
        : s.map((s) => '${s.title}${s.startsOn == null ? '' : ' (${_when(b.today, s.startsOn)})'}').join('. ');
  }
  if (q.contains('card') || q.contains('loyalty') || q.contains('perk') || q.contains('reward')) {
    if (b.perks.isEmpty) return 'This venue doesn\'t run a loyalty card yet — a manager can set one up in More › Loyalty card.';
    final p = b.perks.first;
    return 'Each visit counts toward the card: ${p.reward} after ${p.at}. Guests see their progress in their own app; staff hand the reward over from the guest\'s card. It\'s visits that count — never how much anyone drinks.';
  }
  return 'I can\'t reach the full Ninkasi right now. Here\'s the briefing: ${hostBriefing(b).take(3).join(' ')}';
}
