// "Your diary, as a book" — the export, set as a calm, minimal PDF: a cover with
// your year's mosaic, the numbers at a glance, every entry month by month, the
// places, Together, Split, your to-try list, what venues keep on you, and your
// conversations with Ninkasi. Built on the phone from an [ExportBundle].
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';

import '../../data/export.dart';

/// The book's three faces. Newsreader carries the ₹ glyph, so money is set in it.
class BookFonts {
  final pw.Font serif, serifItalic, sans;
  const BookFonts({required this.serif, required this.serifItalic, required this.sans});

  static Future<BookFonts> load() async {
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    return BookFonts(serif: await f('Newsreader.ttf'), serifItalic: await f('Newsreader-Italic.ttf'), sans: await f('HankenGrotesk.ttf'));
  }
}

// ── palette ──────────────────────────────────────────────────────────────────
const _paper = PdfColor.fromInt(0xFFFBF8F2);
const _ink = PdfColor.fromInt(0xFF1B1714);
const _muted = PdfColor.fromInt(0xFF6A6058);
const _faint = PdfColor.fromInt(0xFF9C9187);
const _line = PdfColor.fromInt(0xFFE7DED0);
const _empty = PdfColor.fromInt(0xFFEFE8DC);
const _amber = PdfColor.fromInt(0xFFC98A2E);

/// Mosaic squares: amber blended into paper by level, so nothing relies on alpha.
PdfColor _level(int level) {
  if (level <= 0) return _empty;
  const mix = [0.0, .32, .52, .74, 1.0];
  final t = mix[level.clamp(0, 4)];
  double ch(double a, double b) => a + (b - a) * t;
  return PdfColor(ch(_empty.red, _amber.red), ch(_empty.green, _amber.green), ch(_empty.blue, _amber.blue));
}

Future<Uint8List> buildDiaryBook(ExportBundle b, BookFonts fonts) async {
  final book = _Book(b, fonts);
  return book.build();
}

class _Book {
  final ExportBundle b;
  final BookFonts f;
  _Book(this.b, this.f);

  // ── type ───────────────────────────────────────────────────────────────────
  pw.TextStyle serif(double size, {PdfColor color = _ink, bool italic = false, double? height}) =>
      pw.TextStyle(font: italic ? f.serifItalic : f.serif, fontSize: size, color: color, lineSpacing: height ?? 0, fontFallback: [f.sans]);
  pw.TextStyle sans(double size, {PdfColor color = _ink, double spacing = 0}) => pw.TextStyle(font: f.sans, fontSize: size, color: color, letterSpacing: spacing, fontFallback: [f.serif]);
  pw.TextStyle caps(double size, {PdfColor color = _faint}) => sans(size, color: color, spacing: size * .16);

  String get today => _longDate(b.generated);
  String _longDate(DateTime d) => '${d.day} ${monthNames[d.month - 1]} ${d.year}';
  String _keyDate(String key) {
    final d = parseKey(key);
    return '${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';
  }

  String _isoDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    return d == null ? '' : '${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';
  }

  String money(num v) => formatMoney(v, b.currency);

  // ── pieces ─────────────────────────────────────────────────────────────────
  pw.Widget mark({double size = 9}) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: size,
        height: size,
        child: pw.GridView(
          crossAxisCount: 2,
          mainAxisSpacing: size * .12,
          crossAxisSpacing: size * .12,
          children: [
            for (final l in const [1, 2, 3, 4]) pw.Container(color: _level(l)),
          ],
        ),
      ),
      pw.SizedBox(width: size * .5),
      pw.Text('brewdiary', style: serif(size * 1.15, italic: true)),
    ],
  );

  pw.Widget hairline({double top = 0, double bottom = 0}) => pw.Container(
    margin: pw.EdgeInsets.only(top: top, bottom: bottom),
    height: .6,
    color: _line,
  );

  pw.Widget section(String kicker, String title, {String? note}) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6, bottom: 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(kicker.toUpperCase(), style: caps(7.5, color: _amber)),
        pw.SizedBox(height: 6),
        pw.Text(title, style: serif(26)),
        if (note != null) ...[pw.SizedBox(height: 4), pw.Text(note, style: sans(9, color: _muted))],
        hairline(top: 12),
      ],
    ),
  );

  /// A heading never ends a page alone: it travels with its first line.
  List<pw.Widget> keep(pw.Widget head, List<pw.Widget> body) => body.isEmpty
      ? [head]
      : [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [head, body.first]),
          ...body.skip(1),
        ];

  /// Two columns, one row at a time, so a long list breaks cleanly across pages.
  List<pw.Widget> pairs(List<pw.Widget> cells) => [
    for (var i = 0; i < cells.length; i += 2)
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: cells[i]),
          pw.SizedBox(width: 28),
          pw.Expanded(child: i + 1 < cells.length ? cells[i + 1] : pw.SizedBox()),
        ],
      ),
  ];

  pw.Widget stat(String value, String label, {double size = 28}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(value, style: serif(size)),
      pw.SizedBox(height: 2),
      pw.Text(label.toUpperCase(), style: caps(6.8)),
    ],
  );

  pw.Widget leader(String left, String right, {pw.TextStyle? l, pw.TextStyle? r}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(left, style: l ?? serif(11)),
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(left: 6, right: 6, bottom: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _line, width: .8, style: pw.BorderStyle.dotted),
              ),
            ),
          ),
        ),
        pw.Text(right, style: r ?? sans(9, color: _muted)),
      ],
    ),
  );

  /// A year of nights ending at [end]: 53 columns of weeks.
  pw.Widget yearMosaic(DateTime end, {double cell = 6.6, double gap = 1.7}) {
    final counts = countsByDate(b.entries);
    final dry = dryDates(b.entries);
    const weeks = 53;
    final lastSunday = addDays(end, 7 - end.weekday);
    final start = addDays(lastSunday, -(weeks * 7 - 1));
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (var w = 0; w < weeks; w++)
          pw.Padding(
            padding: pw.EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
            child: pw.Column(
              children: [
                for (var d = 0; d < 7; d++)
                  () {
                    final day = addDays(start, w * 7 + d);
                    final k = toKey(day);
                    final future = day.isAfter(end);
                    final level = future ? 0 : intensityLevel(counts[k] ?? 0);
                    final isDry = !future && dry.contains(k) && level == 0;
                    return pw.Container(
                      width: cell,
                      height: cell,
                      margin: pw.EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                      decoration: pw.BoxDecoration(
                        color: future ? _paper : _level(level),
                        border: isDry ? pw.Border.all(color: _amber, width: .6) : null,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1)),
                      ),
                    );
                  }(),
              ],
            ),
          ),
      ],
    );
  }

  // ── pages ──────────────────────────────────────────────────────────────────
  pw.PageTheme theme({bool cover = false}) => pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: cover ? const pw.EdgeInsets.fromLTRB(56, 56, 56, 48) : const pw.EdgeInsets.fromLTRB(60, 56, 60, 48),
    buildBackground: (_) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: _paper)),
  );

  Future<Uint8List> build() async {
    final doc = pw.Document(title: 'brewdiary — ${b.name}', author: b.name, creator: 'brewdiary', subject: 'Your diary, as a book');
    doc.addPage(pw.Page(pageTheme: theme(cover: true), build: (_) => cover()));
    doc.addPage(
      pw.MultiPage(
        pageTheme: theme(),
        maxPages: 2000,
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 18),
          child: pw.Row(
            children: [
              pw.Text(b.name, style: sans(7.5, color: _faint)),
              pw.Spacer(),
              pw.Text('YOUR DIARY, AS A BOOK', style: caps(6.5)),
            ],
          ),
        ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14),
          child: pw.Row(
            children: [
              mark(size: 7),
              pw.Spacer(),
              pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: sans(7.5, color: _faint)),
            ],
          ),
        ),
        build: (_) => [
          ...glance(),
          ...diary(),
          ...places(),
          ...together(),
          ...split(),
          ...toTry(),
          ...venues(),
          ...ninkasi(),
          pw.SizedBox(height: 30),
          pw.Center(child: mark(size: 10)),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('Made on your phone from your own diary, ${_longDate(b.generated)}.', style: serif(9.5, color: _muted, italic: true)),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget cover() {
    final s = stats(b.entries);
    final dates = b.entries.map((e) => e.date).toList()..sort();
    final since = b.memberSince != null ? DateTime.tryParse(b.memberSince!) : (dates.isEmpty ? null : parseKey(dates.first));
    final range = dates.isEmpty ? 'Nothing logged yet' : '${_keyDate(dates.first)}  —  ${_keyDate(dates.last)}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            mark(size: 11),
            pw.Spacer(),
            pw.Text('A DRINK DIARY', style: caps(7.5)),
          ],
        ),
        pw.Spacer(flex: 3),
        pw.Text('The diary of', style: serif(16, italic: true, color: _muted)),
        pw.SizedBox(height: 4),
        pw.Text(b.name, style: serif(50)),
        pw.SizedBox(height: 8),
        pw.Text([if (b.handle != null) '@${b.handle}', if (since != null) 'kept since ${monthNames[since.month - 1]} ${since.year}'].join('   ·   '), style: sans(9.5, color: _muted)),
        pw.SizedBox(height: 40),
        pw.Center(child: yearMosaic(b.generated)),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            pw.Text('A year of nights, darker the more you logged. Ringed squares are dry days.', style: sans(7.5, color: _faint)),
            pw.Spacer(),
            pw.Text('less ', style: sans(7, color: _faint)),
            for (var l = 0; l <= 4; l++) pw.Container(width: 6, height: 6, margin: const pw.EdgeInsets.only(left: 1.6), color: _level(l)),
            pw.Text('  more', style: sans(7, color: _faint)),
          ],
        ),
        pw.Spacer(flex: 2),
        pw.Row(
          children: [
            pw.Expanded(child: stat('${s.total}', 'nights logged')),
            pw.Expanded(child: stat('${s.dry}', 'dry nights')),
            pw.Expanded(child: stat('${s.longest}', 'longest run')),
            pw.Expanded(child: stat('${s.kinds}', 'kinds tried')),
          ],
        ),
        hairline(top: 22, bottom: 10),
        pw.Row(
          children: [
            pw.Text(range, style: sans(8, color: _muted)),
            pw.Spacer(),
            pw.Text('Made $today', style: sans(8, color: _faint)),
          ],
        ),
      ],
    );
  }

  List<pw.Widget> glance() {
    final s = stats(b.entries);
    final p = passport(b.entries, 1000);
    final drinks = drinkEntries(b.entries);
    final nightsBy = <String, Set<String>>{};
    final names = <String, String>{};
    for (final e in drinks) {
      final k = e.drink.trim().toLowerCase();
      if (k.isEmpty) continue;
      names.putIfAbsent(k, () => e.drink.trim());
      (nightsBy[k] ??= {}).add(e.date);
    }
    final top = nightsBy.entries.toList()..sort((a, c) => c.value.length.compareTo(a.value.length));
    final placesBy = <String, Set<String>>{};
    for (final e in b.entries) {
      final v = e.venue?.trim();
      if (v != null && v.isNotEmpty) (placesBy[v] ??= {}).add(e.date);
    }
    final topPlaces = placesBy.entries.toList()..sort((a, c) => c.value.length.compareTo(a.value.length));
    final words = lexicon(b.entries).take(14).toList();
    String nights(int n) => n == 1 ? '1 night' : '$n nights';
    return [
      section('At a glance', 'The numbers'),
      pw.Row(
        children: [
          pw.Expanded(child: stat('${s.total}', 'nights logged')),
          pw.Expanded(child: stat('${s.dry}', 'dry nights')),
          pw.Expanded(child: stat('${s.longest}', 'longest run')),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        children: [
          pw.Expanded(child: stat('${s.current}', 'run right now')),
          pw.Expanded(child: stat('${s.kinds}', 'kinds tried')),
          pw.Expanded(child: stat('${p.places}', 'places been')),
        ],
      ),
      pw.SizedBox(height: 28),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('MOST OFTEN', style: caps(7)),
                pw.SizedBox(height: 6),
                if (top.isEmpty) pw.Text('Nothing yet.', style: serif(10, italic: true, color: _muted)),
                for (final t in top.take(8)) leader(names[t.key]!, nights(t.value.length)),
              ],
            ),
          ),
          pw.SizedBox(width: 28),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('WHERE', style: caps(7)),
                pw.SizedBox(height: 6),
                if (topPlaces.isEmpty) pw.Text('No places noted yet.', style: serif(10, italic: true, color: _muted)),
                for (final t in topPlaces.take(8)) leader(t.key, nights(t.value.length)),
              ],
            ),
          ),
        ],
      ),
      if (words.isNotEmpty) ...[
        pw.SizedBox(height: 26),
        pw.Text('IN YOUR WORDS', style: caps(7)),
        pw.SizedBox(height: 6),
        pw.Text(words.map((w) => w.word).join('  ·  '), style: serif(13, italic: true, color: _muted, height: 4)),
      ],
      pw.NewPage(),
    ];
  }

  List<pw.Widget> diary() {
    if (b.entries.isEmpty) return [section('The diary', 'Every night'), pw.Text('Nothing logged yet — the first page is waiting.', style: serif(12, italic: true, color: _muted)), pw.NewPage()];
    final byMonth = <String, Map<String, List<Entry>>>{};
    final sorted = [...b.entries]..sort((a, c) => a.date == c.date ? a.createdAt.compareTo(c.createdAt) : a.date.compareTo(c.date));
    for (final e in sorted) {
      ((byMonth[e.date.substring(0, 7)] ??= {})[e.date] ??= []).add(e);
    }
    final out = <pw.Widget>[section('The diary', 'Every night', note: '${sorted.length} entries across ${loggedDates(b.entries).length} days, oldest first.')];
    for (final month in byMonth.entries) {
      final d = parseKey('${month.key}-01');
      final n = month.value.length;
      out.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('${monthNames[d.month - 1]} ${d.year}', style: serif(18)),
              pw.Spacer(),
              pw.Text(n == 1 ? '1 day' : '$n days', style: sans(8, color: _faint)),
            ],
          ),
        ),
      );
      out.add(hairline(bottom: 4));
      for (final day in month.value.entries) {
        final date = parseKey(day.key);
        out.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 7),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _line, width: .4)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 46,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('${date.day}', style: serif(18)),
                      pw.Text(const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][date.weekday - 1], style: caps(6.5)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [for (final e in day.value) entry(e)]),
                ),
              ],
            ),
          ),
        );
      }
    }
    out.add(pw.NewPage());
    return out;
  }

  pw.Widget entry(Entry e) {
    final dry = isDryDay(e);
    final details = [
      if (e.mood != null && e.mood!.trim().isNotEmpty) e.mood!.trim(),
      if (e.venue != null && e.venue!.trim().isNotEmpty) e.venue!.trim(),
      if (e.whoWith != null && e.whoWith!.isNotEmpty) 'with ${e.whoWith!.join(', ')}',
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4, top: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Text(
                  dry ? 'A dry day' : e.drink,
                  style: serif(12.5, italic: dry, color: dry ? _amber : _ink),
                ),
              ),
              pw.Text(timeOfDayLabel(e.createdAt), style: sans(7.5, color: _faint)),
            ],
          ),
          if (details.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1.5),
              child: pw.Text(details.join('   ·   '), style: sans(8.5, color: _muted)),
            ),
          if (e.note != null && e.note!.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(e.note!.trim(), style: serif(10, italic: true, color: _muted, height: 2)),
            ),
        ],
      ),
    );
  }

  List<pw.Widget> places() {
    final p = passport(b.entries, 1000);
    if (p.stamps.isEmpty) return const [];
    return [
      ...keep(
        section('Places', 'Where the nights were', note: 'One line per place, dated by the first night you logged there.'),
        pairs([for (final s in p.stamps) leader(s.place, _keyDate(s.date), r: sans(8, color: _faint))]),
      ),
      pw.SizedBox(height: 28),
    ];
  }

  List<pw.Widget> together() {
    if (b.friends.isEmpty && b.circles.isEmpty && b.parties.isEmpty && b.plans.isEmpty && b.comments.isEmpty) return const [];
    pw.Widget sub(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(t.toUpperCase(), style: caps(7)),
    );
    return keep(section('Together', 'The people'), [
      if (b.friends.isNotEmpty) ...[
        sub('Friends · ${b.friends.length}'),
        ...pairs([
          for (final n in b.friends)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(n, style: serif(11)),
            ),
        ]),
      ],
      if (b.circles.isNotEmpty) ...[sub('Circles'), for (final c in b.circles) leader(c.name, c.members == 1 ? '1 person' : '${c.members} people')],
      if (b.parties.isNotEmpty) ...[
        sub('Parties'),
        for (final p in b.parties) leader([p.name, if (p.venue != null) p.venue!].join(' — '), _keyDate(p.date)),
      ],
      if (b.plans.isNotEmpty) ...[
        sub('Plans you made'),
        for (final p in b.plans) leader([p.title, if (p.city != null) p.city!].join(' — '), _keyDate(p.date)),
      ],
      if (b.comments.isNotEmpty) ...[
        sub('What you said'),
        for (final c in b.comments)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 7),
            padding: const pw.EdgeInsets.only(left: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: _line, width: 1.4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(c.body, style: serif(10.5, height: 2)),
                pw.Text(_isoDate(c.at), style: sans(7, color: _faint)),
              ],
            ),
          ),
      ],
      pw.SizedBox(height: 28),
    ]);
  }

  List<pw.Widget> split() {
    if (b.expenses.isEmpty) return const [];
    return keep(section('Split', 'Rounds and tabs'), [
      for (final e in b.expenses)
        leader(
          '${_isoDate(e.at)}   ${e.what}',
          '${money(e.amount)}${e.paidByMe ? '  · you paid' : ''}',
          l: sans(9.5),
          r: serif(10, color: _muted),
        ),
      pw.SizedBox(height: 28),
    ]);
  }

  List<pw.Widget> toTry() {
    if (b.wishlist.isEmpty) return const [];
    return [
      ...keep(section('To try', 'Next time'), pairs([for (final w in b.wishlist) leader(w.drink, w.done ? 'tried' : 'to try', l: serif(11, color: w.done ? _muted : _ink))])),
      pw.SizedBox(height: 28),
    ];
  }

  List<pw.Widget> venues() {
    if (b.venueNotes.isEmpty && b.perks.isEmpty && b.visits == 0) return const [];
    return keep(section('At venues', 'What places keep on you', note: 'Only what a venue recorded itself. Your diary never reaches a venue.'), [
      if (b.visits > 0) leader('Visits recorded by venues', '${b.visits}'),
      for (final p in b.perks) leader('Perk claimed — ${p.reward}', _isoDate(p.at)),
      for (final n in b.venueNotes)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(n.venue, style: serif(12)),
              if (n.body.trim().isNotEmpty) pw.Text(n.body.trim(), style: serif(10, italic: true, color: _muted)),
              if (n.tags.isNotEmpty) pw.Text(n.tags.join('  ·  '), style: sans(8, color: _faint)),
            ],
          ),
        ),
      pw.SizedBox(height: 28),
    ]);
  }

  List<pw.Widget> ninkasi() {
    if (b.chats.isEmpty) return const [];
    final chats = [...b.chats]..sort((a, c) => a.at.compareTo(c.at));
    return [
      pw.NewPage(),
      ...keep(section('Ninkasi', 'Conversations', note: 'What you asked, and what she said.'), [
        for (final c in chats)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_longDate(c.at).toUpperCase(), style: caps(6.5)),
                pw.SizedBox(height: 4),
                pw.Text(c.user, style: sans(10, color: _ink)),
                pw.SizedBox(height: 5),
                pw.Container(
                  padding: const pw.EdgeInsets.only(left: 10),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(left: pw.BorderSide(color: _amber, width: 1.2)),
                  ),
                  child: pw.Text(c.assistant, style: serif(10.5, color: _muted, height: 2.5)),
                ),
              ],
            ),
          ),
      ]),
    ];
  }
}
