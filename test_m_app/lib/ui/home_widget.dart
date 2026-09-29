// The home-screen widget (Android): this month's mosaic on your home screen.
//
// Flutter draws the card here (the same squares, amber by count, today ringed) and
// saves it as a PNG in the app's own storage; a tiny native AppWidget
// (android/app/src/main/kotlin/.../MosaicWidget.kt) shows that picture and opens
// the app when tapped. Redrawn a moment after the diary changes. Nothing leaves
// the phone. (iOS needs a WidgetKit extension added in Xcode — see the README.)
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../data/base.dart';
import '../data/entries.dart';
import 'theme.dart';

class HomeWidget {
  static const _channel = MethodChannel('brewdiary/widget');
  static const fileName = 'mosaic_widget.png';
  static Timer? _debounce;

  /// Follow the diary (Android only). Call once at startup.
  static void wire() {
    if (kIsWeb || !Platform.isAndroid) return;
    entryStore.addListener(_soon);
    _soon();
  }

  static void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), refresh);
  }

  static Future<void> refresh() async {
    try {
      final png = await renderMosaicCard(entryStore.entries, appNow());
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/$fileName').writeAsBytes(png, flush: true);
      await _channel.invokeMethod('refresh');
      // The quick-log widget shows today's water and cigarettes.
      final today = todayKey();
      int count(String drink) => entryStore.entries.where((e) => e.date == today && e.drink.trim().toLowerCase() == drink).length;
      await _channel.invokeMethod('quick', {'water': count('water'), 'cigarettes': count('cigarette')});
    } catch (e) {
      logDebug(e);
    }
  }

  static String? _lastSplit;

  /// The Split widget: called when the Split page has your balances. Redraws
  /// only when they changed.
  static void noteSplit({required double owed, required double owe, required String currency}) {
    if (kIsWeb || !Platform.isAndroid) return;
    final key = '$owed|$owe|$currency';
    if (key == _lastSplit) return;
    _lastSplit = key;
    () async {
      try {
        final png = await renderSplitCard(owed: owed, owe: owe, currency: currency);
        final dir = await getApplicationSupportDirectory();
        await File('${dir.path}/split_widget.png').writeAsBytes(png, flush: true);
        await _channel.invokeMethod('split');
      } catch (e) {
        logDebug(e);
      }
    }();
  }
}

/// The widget's picture: a dark glass card with the month name, your streak, and
/// this month's grid. 4:3-ish so it sits well in a 3×2 home-screen slot.
Future<Uint8List> renderMosaicCard(List<Entry> entries, DateTime now, {double scale = 3}) async {
  const bd = BD.darkTokens;
  const w = 240.0, h = 180.0, pad = 14.0, gap = 4.0, header = 30.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..scale(scale);

  final card = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(22));
  c.drawRRect(card, Paint()..color = const Color(0xF2121319));
  c.drawRRect(card.deflate(.4), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .8
    ..color = bd.glassBorder);

  void text(String s, Offset at, {required double size, required Color color, String family = T.sansFamily, FontWeight weight = FontWeight.w400, TextAlign align = TextAlign.left, double width = w}) {
    final p = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: align, maxLines: 1, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(color: color, fontSize: size, fontFamily: family, fontWeight: weight))
      ..addText(s);
    final para = p.build()..layout(ui.ParagraphConstraints(width: width));
    c.drawParagraph(para, at);
  }

  final s = stats(entries);
  text(monthNames[now.month - 1], const Offset(pad, pad - 3), size: 19, color: bd.ink, family: T.serifFamily);
  text(s.current == 0 ? 'Tap a day' : '${s.current} night streak', Offset(w / 2, pad + 2), size: 10.5, color: bd.accent, weight: FontWeight.w600, align: TextAlign.right, width: w / 2 - pad);

  final grid = monthGrid(now.year, now.month - 1);
  final rows = (grid.length / 7).ceil();
  final counts = countsByDate(entries);
  final cellW = (w - 2 * pad - 6 * gap) / 7;
  final cellH = (h - header - pad - pad / 2 - (rows - 1) * gap) / rows;
  final cell = cellW < cellH ? cellW : cellH;
  final gridW = 7 * cell + 6 * gap;
  final left = (w - gridW) / 2;
  final top = header + pad / 2;
  for (var i = 0; i < grid.length; i++) {
    final d = grid[i];
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(left + (i % 7) * (cell + gap), top + (i ~/ 7) * (cell + gap), cell, cell), const Radius.circular(4));
    final level = intensityLevel(counts[d.key] ?? 0);
    if (!d.inMonth) {
      c.drawRRect(r, Paint()..color = bd.ink.withValues(alpha: .03));
      continue;
    }
    c.drawRRect(r, Paint()..color = level == 0 ? bd.ink.withValues(alpha: d.isFuture ? .03 : .07) : bd.ycell(level));
    if (d.isToday) {
      c.drawRRect(r.deflate(.6), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = bd.accent);
    }
  }

  final img = await rec.endRecording().toImage((w * scale).round(), (h * scale).round());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// The Split widget's picture: what you're owed and what you owe. Your own
/// balance, on your own home screen.
Future<Uint8List> renderSplitCard({required double owed, required double owe, required String currency, double scale = 3}) async {
  const bd = BD.darkTokens;
  const w = 240.0, h = 100.0, pad = 16.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..scale(scale);
  final card = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(22));
  c.drawRRect(card, Paint()..color = const Color(0xF2121319));
  c.drawRRect(card.deflate(.4), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .8
    ..color = bd.glassBorder);
  void text(String s, Offset at, double size, Color color, {String family = T.sansFamily, FontWeight weight = FontWeight.w400, double width = w / 2 - pad}) {
    final p = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(color: color, fontSize: size, fontFamily: family, fontWeight: weight))
      ..addText(s);
    c.drawParagraph(p.build()..layout(ui.ParagraphConstraints(width: width)), at);
  }

  text('SPLIT', const Offset(pad, pad - 2), 9.5, bd.muted, weight: FontWeight.w600, width: w);
  text("You're owed", const Offset(pad, 34), 11, bd.muted);
  text(formatMoney(owed, currency, true), const Offset(pad, 50), 22, owed > 0 ? bd.accent : bd.ink, family: T.serifFamily);
  text('You owe', const Offset(w / 2 + 4, 34), 11, bd.muted);
  text(formatMoney(owe, currency, true), const Offset(w / 2 + 4, 50), 22, bd.ink, family: T.serifFamily);
  final img = await rec.endRecording().toImage((w * scale).round(), (h * scale).round());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
