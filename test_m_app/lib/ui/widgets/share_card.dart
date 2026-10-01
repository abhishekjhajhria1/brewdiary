// Share a score as an image — a port of src/components/share/ScoreCard.tsx (an
// entry is shared through the photo studio's overlays). Instead of a <canvas>, the card is a widget rendered off a
// RepaintBoundary into a PNG and handed to the native share sheet.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/overlays.dart' show NightBackdrop;
import '../theme.dart';
import 'common.dart';
import 'game.dart' show foil, foilHi, foilGradient;

const _paper = Color(0xFFFAF6EE);

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
                      return Stack(fit: StackFit.expand, children: [
                        NightBackdrop(seed: sc.context),
                        Container(color: Colors.black.withValues(alpha: .45)),
                        Padding(
                          padding: EdgeInsets.fromLTRB(80 * s, 76 * s, 80 * s, 72 * s),
                          child: Column(children: [
                            Row(children: [
                              Text('brewdiary', style: T.rawSerif(40 * s, _paper.withValues(alpha: .85), italic: true)),
                              const Spacer(),
                              if (rankLine != null)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 26 * s, vertical: 10 * s),
                                  decoration: BoxDecoration(color: foil.withValues(alpha: .18), borderRadius: BorderRadius.circular(40 * s), border: Border.all(color: foil.withValues(alpha: .6), width: 2 * s)),
                                  child: Text(rankLine.toUpperCase(), style: T.rawSans(30 * s, foilHi, weight: FontWeight.w700, spacing: 3 * s)),
                                ),
                            ]),
                            const Spacer(),
                            Container(
                              width: 560 * s,
                              height: 560 * s,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [foil.withValues(alpha: .22), Colors.transparent]),
                                border: Border.all(color: foil.withValues(alpha: .7), width: 4 * s),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                ShaderMask(
                                  shaderCallback: (r) => foilGradient.createShader(r),
                                  child: Text('${sc.sparks}', style: T.rawSerif(250 * s, Colors.white, weight: FontWeight.w500, height: 1)),
                                ),
                                SizedBox(height: 10 * s),
                                Text(sc.sparks == 1 ? 'SPARK' : 'SPARKS', style: T.rawSans(36 * s, foilHi, weight: FontWeight.w700, spacing: 8 * s)),
                              ]),
                            ),
                            const Spacer(),
                            if (sc.vibe > 0) Text('and ${sc.vibe} vibe from the room', textAlign: TextAlign.center, style: T.rawSerif(50 * s, _paper, italic: true)),
                            SizedBox(height: 18 * s),
                            Text(sc.context.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: T.rawSans(28 * s, _paper.withValues(alpha: .7), weight: FontWeight.w600, spacing: 4 * s)),
                            SizedBox(height: 10 * s),
                            Text('for variety — never for how much', textAlign: TextAlign.center, style: T.rawSans(26 * s, _paper.withValues(alpha: .55))),
                          ]),
                        ),
                      ]);
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
