// Share an entry (or a score) as an image — ports of src/components/share/ShareCard.tsx
// and ScoreCard.tsx. Instead of a <canvas>, the card is a widget rendered off a
// RepaintBoundary into a PNG and handed to the native share sheet.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/entries.dart';
import '../theme.dart';
import 'common.dart';

const _paper = Color(0xFFFAF6EE);
const _ink = Color(0xFF1B1714);
const _accent = Color(0xFFB8742A);

Future<void> _shareBoundary(GlobalKey key, String filename, String text) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return;
  final image = await boundary.toImage(pixelRatio: 3);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
    ),
  );
}

ImageProvider? _imageFor(String? url) {
  if (url == null) return null;
  return url.startsWith('http') ? NetworkImage(url) : FileImage(File(url));
}

enum _Template { minimal, poster }

/// Opens the entry card as a sheet with template toggle + share.
Future<void> showShareCard(BuildContext context, Entry entry) {
  return showBdSheet(
    context,
    title: 'Share as an image',
    builder: (_) => _ShareCardSheet(entry: entry),
  );
}

class _ShareCardSheet extends StatefulWidget {
  final Entry entry;
  const _ShareCardSheet({required this.entry});
  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  final _key = GlobalKey();
  var _template = _Template.minimal;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final e = widget.entry;
    final streak = currentStreak(loggedDates(entryStore.entries));
    final photo = e.photos?.isNotEmpty == true ? e.photos!.first.url : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Segmented<_Template>(options: const [(_Template.minimal, 'Minimal'), (_Template.poster, 'Poster')], value: _template, onChanged: (t) => setState(() => _template = t)),
        const SizedBox(height: S.m),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(rCtl + 4),
              child: RepaintBoundary(
                key: _key,
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: _template == _Template.minimal ? _MinimalCard(entry: e, streak: streak, photo: photo) : _PosterCard(entry: e, streak: streak, photo: photo),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: S.s),
        Text('Only what you see here is shared — never your notes, who you were with, or where.', textAlign: TextAlign.center, style: T.caption(bd)),
        const SizedBox(height: S.xl),
        BdButton(
          'Share',
          icon: Ph.export,
          busy: _busy,
          onTap: () async {
            setState(() => _busy = true);
            await _shareBoundary(_key, 'brewdiary-${e.date}.png', '${e.drink}${e.mood != null ? ' — ${e.mood}' : ''}');
            if (mounted) setState(() => _busy = false);
          },
        ),
      ],
    );
  }
}

class _MinimalCard extends StatelessWidget {
  final Entry entry;
  final int streak;
  final String? photo;
  const _MinimalCard({required this.entry, required this.streak, this.photo});
  @override
  Widget build(BuildContext context) {
    final img = _imageFor(photo);
    final fg = img != null ? _paper : _ink;
    final sub = img != null ? _paper.withValues(alpha: .82) : const Color(0xFF6E665C);
    final meta = [entry.mood, shortDay(entry.date)].whereType<String>().join('  ·  ');
    return LayoutBuilder(
      builder: (c, box) {
        final s = box.maxWidth / 1080; // scale from the 1080×1350 canvas
        return Container(
          decoration: BoxDecoration(
            color: _paper,
            image: img == null ? null : DecorationImage(image: img, fit: BoxFit.cover),
          ),
          child: Container(
            decoration: img == null
                ? null
                : const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xD9000000)], stops: [.45, 1]),
                  ),
            padding: EdgeInsets.fromLTRB(72 * s, 60 * s, 72 * s, 60 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('brewdiary', style: T.rawSerif(36 * s, sub, italic: true)),
                const Spacer(),
                if (streak > 1)
                  Text(
                    'NIGHT $streak',
                    style: T.rawSans(26 * s, _accent, weight: FontWeight.w600, spacing: 3 * s),
                  ),
                SizedBox(height: 12 * s),
                Text(
                  entry.drink,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.rawSerif(92 * s, fg, weight: FontWeight.w600, height: 1.05),
                ),
                SizedBox(height: 24 * s),
                Text(meta, style: T.rawSerif(40 * s, sub, italic: true)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PosterCard extends StatelessWidget {
  final Entry entry;
  final int streak;
  final String? photo;
  const _PosterCard({required this.entry, required this.streak, this.photo});
  @override
  Widget build(BuildContext context) {
    final img = _imageFor(photo);
    final meta = [entry.mood, shortDay(entry.date), if (streak > 1) 'night $streak'].whereType<String>().join('  ·  ');
    return LayoutBuilder(
      builder: (c, box) {
        final s = box.maxWidth / 1080;
        return Container(
          color: _ink,
          child: Stack(
            children: [
              if (img != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: box.maxHeight * .42,
                  child: Image(image: img, fit: BoxFit.cover),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: box.maxHeight * .42,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_accent, Color(0xFF7A4712)]),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(72 * s, 80 * s, 72 * s, 72 * s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BREWDIARY',
                      style: T.rawSans(30 * s, _accent, weight: FontWeight.w600, spacing: 4 * s),
                    ),
                    SizedBox(height: 40 * s),
                    Text(
                      entry.drink,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: T.rawSerif(116 * s, _paper, weight: FontWeight.w700, height: .95),
                    ),
                    const Spacer(),
                    Text(meta, style: T.rawSans(34 * s, _paper, weight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── score card (sparks) ──────────────────────────────────────────────────────
class Score {
  final String name;
  final int sparks;
  final int vibe;
  final String context;
  final int? rank;
  final int? of;
  const Score({required this.name, required this.sparks, required this.vibe, required this.context, this.rank, this.of});
}

Future<void> showScoreCard(BuildContext context, Score score) => showBdSheet(
  context,
  title: 'Share your score',
  builder: (_) => _ScoreSheet(score: score),
);

class _ScoreSheet extends StatefulWidget {
  final Score score;
  const _ScoreSheet({required this.score});
  @override
  State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  final _key = GlobalKey();
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final sc = widget.score;
    final rankLine = sc.rank != null && sc.of != null && sc.of! > 1 ? '#${sc.rank} of ${sc.of}' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(rCtl + 4),
              child: RepaintBoundary(
                key: _key,
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: LayoutBuilder(
                    builder: (c, box) {
                      final s = box.maxWidth / 1080;
                      return Container(
                        color: _ink,
                        padding: EdgeInsets.fromLTRB(72 * s, 80 * s, 72 * s, 72 * s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('brewdiary', style: T.rawSerif(36 * s, _paper.withValues(alpha: .8), italic: true)),
                            const Spacer(),
                            if (rankLine != null)
                              Text(
                                rankLine.toUpperCase(),
                                style: T.rawSans(30 * s, _accent, weight: FontWeight.w600, spacing: 4 * s),
                              ),
                            Text('${sc.sparks}', style: T.rawSerif(260 * s, _paper, weight: FontWeight.w600, height: 1)),
                            Text(
                              sc.sparks == 1 ? 'SPARK' : 'SPARKS',
                              style: T.rawSans(34 * s, _accent, weight: FontWeight.w600, spacing: 5 * s),
                            ),
                            if (sc.vibe > 0) ...[SizedBox(height: 40 * s), Text('and ${sc.vibe} vibe from the room', style: T.rawSerif(44 * s, _paper.withValues(alpha: .85), italic: true))],
                            SizedBox(height: 40 * s),
                            Text(sc.context, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rawSans(30 * s, _paper.withValues(alpha: .7))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: S.s),
        Text('Sparks count variety — a new place, a new drink, a dry day. Never how much.', textAlign: TextAlign.center, style: T.caption(bd)),
        const SizedBox(height: S.xl),
        BdButton(
          'Share',
          icon: Ph.export,
          busy: _busy,
          onTap: () async {
            setState(() => _busy = true);
            await _shareBoundary(_key, 'brewdiary-score.png', '${sc.sparks} sparks on brewdiary');
            if (mounted) setState(() => _busy = false);
          },
        ),
      ],
    );
  }
}
