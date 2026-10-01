// The taste passport — a little book you swipe through: the leather cover, the
// identity page (what you're into, the counts, a machine-readable strip), then a
// page for each year and each month with its visa stamps: a place first visited,
// a drink first tasted, a kind first tried, every dry night. Variety, never
// volume: ten nights at one bar is one stamp, and a dry night earns its own.
//
// Opened from the calendar (the month or the year you're looking at), from You,
// and from a venue's menu. Any page can be shared as a picture.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/passport.dart';

/// [open] is 'YYYY-MM' for a month's page, 'YYYY' for a year's; null opens the
/// identity page.
Future<void> showTasteCard(BuildContext context, {String? open}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => TasteCardScreen(open: open)));

/// One page of the book.
class _Page {
  final String id; // 'cover', 'id', 'YYYY', 'YYYY-MM'
  final String title;
  const _Page(this.id, this.title);
}

class TasteCardScreen extends StatefulWidget {
  final String? open;
  const TasteCardScreen({super.key, this.open});
  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  static const _hiddenKey = 'brewdiary.tastecard.hidden';
  late final Set<String> _hidden = {...(Prefs.getJson<List<dynamic>>(_hiddenKey) ?? const []).map((e) => '$e')};
  bool _dryTonight = false;
  bool _showPlaces = true;
  bool _sharing = false;
  late final List<_Page> _pages = _book();
  late final PageController _pc = PageController(viewportFraction: .9, initialPage: _start());
  late int _at = _start();
  final _keys = <String, GlobalKey>{};

  List<_Page> _book() {
    final months = {for (final e in entryStore.entries) e.date.substring(0, 7)}.toList()..sort((a, b) => b.compareTo(a));
    final now = appNow();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (!months.contains(thisMonth)) months.insert(0, thisMonth);
    final pages = <_Page>[const _Page('cover', 'Cover'), const _Page('id', 'Identity')];
    String? year;
    for (final m in months) {
      final y = m.substring(0, 4);
      if (y != year) {
        year = y;
        pages.add(_Page(y, 'The year $y'));
      }
      final d = parseKey('$m-01');
      pages.add(_Page(m, '${monthNames[d.month - 1]} ${d.year}'));
    }
    return pages;
  }

  int _start() {
    final i = widget.open == null ? -1 : _pages.indexWhere((p) => p.id == widget.open);
    return i >= 0 ? i : 1;
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _keys[_pages[_at].id]?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brewdiary-passport-${_pages[_at].id}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: 'My taste passport on brewdiary'));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _toggle(String line) {
    setState(() => _hidden.contains(line) ? _hidden.remove(line) : _hidden.add(line));
    Prefs.setJson(_hiddenKey, _hidden.toList());
  }

  Widget _pageView(_Page page, List<(String, String, String)> lines) {
    final entries = entryStore.entries;
    final key = _keys.putIfAbsent(page.id, GlobalKey.new);
    final Widget child = switch (page.id) {
      'cover' => PassportCover(name: auth.profile?.name),
      'id' => PassportIdentity(
          name: auth.profile?.name,
          passport: passport(entries),
          lines: [for (final l in lines) if (!_hidden.contains(l.$1)) (l.$2, l.$3)],
          dryTonight: _dryTonight,
          showPlaces: _showPlaces,
        ),
      _ => () {
          final isYear = page.id.length == 4;
          final from = isYear ? '${page.id}-01-01' : '${page.id}-01';
          final d = parseKey(from);
          final to = isYear ? '${page.id}-12-31' : toKey(DateTime(d.year, d.month + 1, 0));
          final stamps = stampsBetween(entries, from, to).where((s) => _showPlaces || s.kind != StampKind.place).toList();
          return VisaPage(
            title: isYear ? page.id : page.title,
            stamps: stamps,
            pageNo: _pages.indexOf(page),
            max: isYear ? 12 : 9,
            empty: isYear ? 'A year of stamps starts with one night.' : 'No stamps this month yet — a new place, a first taste or a dry night earns one.',
          );
        }(),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SingleChildScrollView(physics: const ClampingScrollPhysics(), child: RepaintBoundary(key: key, child: page.id == 'cover' ? AspectRatio(aspectRatio: .7, child: child) : child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final lines = tasteLines(tasteProfile(entryStore.entries));
    final page = _pages[_at];
    final isMonth = page.id.length == 7;
    final isYear = page.id.length == 4;
    final from = isYear ? '${page.id}-01-01' : (isMonth ? '${page.id}-01' : null);
    final stamps = from == null
        ? const <VisaStamp>[]
        : stampsBetween(entryStore.entries, from, isYear ? '${page.id}-12-31' : toKey(DateTime(parseKey(from).year, parseKey(from).month + 1, 0)));
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SubPage(
          title: 'Taste passport',
          subtitle: 'Places, first tastes, new kinds, dry nights — swipe through the pages.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 560,
              child: PageView.builder(
                controller: _pc,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _at = i),
                itemBuilder: (_, i) => _pageView(_pages[i], lines),
              ),
            ),
            const SizedBox(height: S.s),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconBtn(Ph.caretLeft, tooltip: 'Previous page', onTap: _at == 0 ? null : () => _pc.previousPage(duration: Motion.med, curve: Curves.easeOutCubic)),
              SizedBox(width: 150, child: Text(page.title, textAlign: TextAlign.center, style: T.row(bd))),
              IconBtn(Ph.caretRight, tooltip: 'Next page', onTap: _at == _pages.length - 1 ? null : () => _pc.nextPage(duration: Motion.med, curve: Curves.easeOutCubic)),
            ]),
            if (from != null) ...[const SizedBox(height: S.m), StampTally(stamps)],
            const SizedBox(height: S.l),
            BdButton(_sharing ? 'Making it…' : 'Share this page', icon: Ph.shareNetwork, onTap: _share),
            const SizedBox(height: S.xl),
            Group(children: [
              SettingRow(
                title: 'Nothing with alcohol tonight',
                hint: 'Says so on your identity page.',
                trailing: BdToggle(on: _dryTonight, label: 'Nothing with alcohol tonight', onChanged: (v) => setState(() => _dryTonight = v)),
              ),
              SettingRow(
                title: 'Show place stamps',
                hint: 'Where you have been, on the pages and in what you share.',
                trailing: BdToggle(on: _showPlaces, label: 'Show place stamps', onChanged: (v) => setState(() => _showPlaces = v)),
              ),
              for (final l in lines)
                SettingRow(
                  title: 'Show "${l.$2}"',
                  trailing: BdToggle(on: !_hidden.contains(l.$1), label: 'Show ${l.$2}', onChanged: (_) => _toggle(l.$1)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
