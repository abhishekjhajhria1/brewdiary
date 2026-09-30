// The area heat map, read (048 area_heat_map). Pure: the rows in, a map and a plain-
// English guide out. Everything here is already a group of 5+ people who said yes —
// the database drops the rest — so the guide only ever talks about crowds.
import 'package:brewdiary_core/geo.dart';
import 'package:brewdiary_core/money.dart' show spendBand;

class HeatRow {
  final String cell;
  final String layer; // people | persona | taste | hours | spend
  final String label;
  final int people;
  const HeatRow(this.cell, this.layer, this.label, this.people);
}

/// One neighbourhood, everything the map may say about it.
class CellRead {
  final String cell;
  int people = 0;
  final Map<String, int> personas = {};
  final Map<String, int> tastes = {};
  final Map<String, int> hours = {};

  /// The typical night's tab as a band floor (0 = under the first band); null = not shown.
  num? spendFloor;
  CellRead(this.cell);

  String? get topPersona => _top(personas);
  String? get topTaste => _top(tastes);
  String? get topHours => _top(hours);
}

String? _top(Map<String, int> m) {
  if (m.isEmpty) return null;
  final e = m.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
  return e.first.key;
}

Map<String, CellRead> readMap(List<HeatRow> rows) {
  final out = <String, CellRead>{};
  for (final r in rows) {
    final c = out.putIfAbsent(r.cell, () => CellRead(r.cell));
    switch (r.layer) {
      case 'people':
        c.people = r.people;
      case 'persona':
        c.personas[r.label] = r.people;
      case 'taste':
        c.tastes[r.label] = r.people;
      case 'hours':
        c.hours[r.label] = r.people;
      case 'spend':
        c.spendFloor = num.tryParse(r.label);
    }
  }
  return out;
}

// ── words ─────────────────────────────────────────────────────────────────────
const personaOrder = ['coffee_tea', 'beer', 'wine', 'cocktails', 'zero_proof', 'explorer', 'other'];
const personaLabel = {
  'coffee_tea': 'Coffee & tea people',
  'beer': 'Beer people',
  'wine': 'Wine people',
  'cocktails': 'Cocktails & spirits',
  'zero_proof': 'Zero-proof',
  'explorer': 'Explorers',
  'other': 'Something else',
};
const personaBlurb = {
  'coffee_tea': 'Mostly log coffee and tea.',
  'beer': 'Mostly log beer.',
  'wine': 'Mostly log wine.',
  'cocktails': 'Mostly log cocktails and spirits.',
  'zero_proof': 'Mostly soft drinks and dry days.',
  'explorer': 'Log four or more kinds of drink — they like trying things.',
  'other': 'Log things that fit no one box.',
};
const tasteOrder = ['coffee', 'tea', 'beer', 'wine', 'cocktail', 'spirit', 'soft'];
const tasteLabel = {
  'coffee': 'Coffee',
  'tea': 'Tea',
  'beer': 'Beer',
  'wine': 'Wine',
  'cocktail': 'Cocktails',
  'spirit': 'Spirits',
  'soft': 'Soft drinks',
};
const hoursOrder = ['morning', 'afternoon', 'evening', 'late'];
const hoursLabel = {'morning': 'Mornings', 'afternoon': 'Afternoons', 'evening': 'Evenings', 'late': 'Late'};
const hoursSpan = {'morning': '5 am–noon', 'afternoon': 'noon–5 pm', 'evening': '5–9 pm', 'late': 'after 9 pm'};

/// "10+ people" — the map's figures are already rounded down to 5s.
String crowd(int n) => '$n+ ${n == 1 ? 'person' : 'people'}';

/// A band floor in words: "₹1,000+", or "under ₹500" — money.dart's own bands.
String spendWords(num floor, String currency) => spendBand(floor, currency);

// ── the venue's clock ─────────────────────────────────────────────────────────
/// The time zone the "hours" layer is read in — the venue's, not the phone's. A
/// country with one zone maps straight; a wide one by state where we know it; UTC
/// otherwise (the database accepts only a real zone name).
String venueTimeZone(String country, String? region) {
  final c = country.toUpperCase();
  if (c == 'US') {
    const east = {'NY', 'MA', 'NJ', 'PA', 'FL', 'GA', 'DC', 'MD', 'VA', 'NC', 'SC', 'OH', 'MI', 'CT', 'RI', 'VT', 'NH', 'ME', 'DE'};
    const central = {'IL', 'TX', 'MN', 'WI', 'MO', 'LA', 'TN', 'AL', 'MS', 'IA', 'OK', 'KS', 'AR', 'NE'};
    const mountain = {'CO', 'UT', 'NM', 'MT', 'WY', 'ID'};
    final r = (region ?? '').toUpperCase();
    if (east.contains(r)) return 'America/New_York';
    if (central.contains(r)) return 'America/Chicago';
    if (mountain.contains(r)) return 'America/Denver';
    if (r == 'AZ') return 'America/Phoenix';
    if (r == 'HI') return 'Pacific/Honolulu';
    if (r == 'AK') return 'America/Anchorage';
    return 'America/Los_Angeles';
  }
  return const {
        'IN': 'Asia/Kolkata', 'GB': 'Europe/London', 'IE': 'Europe/Dublin', 'FR': 'Europe/Paris',
        'DE': 'Europe/Berlin', 'ES': 'Europe/Madrid', 'IT': 'Europe/Rome', 'NL': 'Europe/Amsterdam',
        'PT': 'Europe/Lisbon', 'BE': 'Europe/Brussels', 'AT': 'Europe/Vienna', 'PL': 'Europe/Warsaw',
        'SE': 'Europe/Stockholm', 'NO': 'Europe/Oslo', 'DK': 'Europe/Copenhagen', 'FI': 'Europe/Helsinki',
        'CH': 'Europe/Zurich', 'TR': 'Europe/Istanbul', 'AE': 'Asia/Dubai', 'SG': 'Asia/Singapore',
        'TH': 'Asia/Bangkok', 'JP': 'Asia/Tokyo', 'KR': 'Asia/Seoul', 'ZA': 'Africa/Johannesburg',
        'NZ': 'Pacific/Auckland', 'LK': 'Asia/Colombo', 'NP': 'Asia/Kathmandu', 'SA': 'Asia/Riyadh',
      }[c] ??
      'UTC';
}

// ── the guide ─────────────────────────────────────────────────────────────────
/// The map in plain words, for a manager and for Ninkasi. Only crowds, only what the
/// map already shows; its suggestions are about fit (menu, hours), never about
/// getting anyone to drink more.
List<String> areaGuide({
  required String venueCell,
  required Map<String, CellRead> cells,
  required String currency,
  required bool sellsAlcohol,
  required bool sharing,
}) {
  if (cells.isEmpty) {
    return const [
      'Nothing to show yet. A neighbourhood lights up once 5 people who said yes — across 3 venues — went out there. It fills in as more guests and venues join.',
    ];
  }
  final lines = <String>[];
  final list = cells.values.toList()..sort((a, b) => b.people - a.people);
  final busiest = list.first;
  final mine = venueCell.length >= 5 ? cells[venueCell.substring(0, 5)] : null;

  lines.add('Busiest: ${directionFrom(venueCell, busiest.cell)} — ${crowd(busiest.people)} went out there.');
  if (mine != null && busiest.cell != mine.cell) {
    lines.add('Your own neighbourhood: ${crowd(mine.people)}.');
  } else if (mine == null) {
    lines.add('Your own neighbourhood isn\'t on the map yet — fewer than 5 people who said yes, or fewer than 3 venues.');
  }

  // Who's around: the persona that leads in the most neighbourhoods.
  final leads = <String, int>{};
  for (final c in list) {
    final p = c.topPersona;
    if (p != null) leads[p] = (leads[p] ?? 0) + 1;
  }
  final lead = _top(leads);
  if (lead != null) {
    lines.add('${personaLabel[lead]} lead in ${leads[lead]} of ${list.length} neighbourhood${list.length == 1 ? '' : 's'}.');
  }
  if (mine?.topPersona != null) {
    lines.add('Near you it\'s mostly ${personaLabel[mine!.topPersona]!.toLowerCase()}${mine.topHours == null ? '' : ', out ${hoursLabel[mine.topHours]!.toLowerCase()}'}.');
  }

  // When: across the whole map.
  final hrs = <String, int>{};
  for (final c in list) {
    c.hours.forEach((k, v) => hrs[k] = (hrs[k] ?? 0) + v);
  }
  final peak = _top(hrs);
  if (peak != null) lines.add('Most people go out in the ${peak == 'late' ? 'late hours' : hoursLabel[peak]!.toLowerCase().replaceAll(RegExp(r's$'), '')} (${hoursSpan[peak]}).');

  // Spend: bands only, and only for venues that share.
  if (!sharing) {
    lines.add('Typical spend is shown to venues that share their own totals (Setup). Counts and bands only.');
  } else {
    final floors = [for (final c in list) if (c.spendFloor != null) c.spendFloor!]..sort();
    if (floors.isNotEmpty) lines.add('A typical night out around here: ${spendWords(floors[floors.length ~/ 2], currency)}.');
  }

  // Fit, not volume.
  final total = list.fold<int>(0, (s, c) => s + c.people);
  int share(String persona) => list.fold<int>(0, (s, c) => s + (c.personas[persona] ?? 0));
  if (total > 0 && share('zero_proof') * 5 >= total) {
    lines.add('Zero-proof drinkers are a real crowd here — a good alcohol-free list is worth it.');
  }
  if (sellsAlcohol && total > 0 && share('coffee_tea') * 3 >= total) {
    lines.add('Coffee and tea people are a big share — daytime hours or a coffee menu would meet them.');
  }
  if (total > 0 && share('explorer') * 5 >= total) {
    lines.add('Lots of explorers — a changing special or a new thing on the menu gives them a reason to try you.');
  }
  return lines;
}
