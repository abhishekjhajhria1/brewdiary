// Contact sheets of the share studio's pictures (skipped unless TOUR is defined): every
// style, every sticker, every frame and every look, on a real photo, as they export.
//   flutter test test/studio_contact_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/studio_*.png (git-ignored).
import 'dart:io';

import 'package:brewdiary/ui/screens/photo_frames.dart';
import 'package:brewdiary/ui/screens/photo_studio.dart';
import 'package:brewdiary/ui/screens/stickers.dart';
import 'package:brewdiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tour = bool.fromEnvironment('TOUR');

const _story = NightStory(
  dateKey: '2026-09-26',
  title: "Mira's birthday",
  venue: 'Soka, Bandra',
  mood: 'electric',
  withPeople: 3,
  who: ['Mira', 'Arjun', 'Kabir'],
  time: '21:40',
  newToYou: 2,
  lines: [StoryLine('Mezcal Negroni', qty: 2, price: 650), StoryLine('Paloma', price: 520), StoryLine('Truffle fries', price: 380), StoryLine('Lime soda', qty: 2, price: 150)],
  total: 2500,
);

void main() {
  setUpAll(loadFonts);

  Future<void> sheet(WidgetTester t, String name, List<(String, StudioLook)> items, {double ratio = 9 / 16, int cols = 4}) async {
    const w = 270.0;
    final h = w / ratio;
    final rows = (items.length / cols).ceil();
    t.view.physicalSize = Size(cols * (w + 24) + 24, rows * (h + 44) + 24) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final photo = FileImage(File('test/fixtures/night.jpg').absolute);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await t.runAsync(() => precacheImage(photo, t.element(find.byType(Scaffold))));
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1D22),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 24, runSpacing: 4, children: [
            for (final (label, look) in items)
              SizedBox(
                width: w,
                child: Column(children: [
                  Composition(story: _story, photo: photo, look: look, width: w, ratio: ratio),
                  SizedBox(height: 40, child: Center(child: Text(label, style: T.rawSans(14, Colors.white70)))),
                ]),
              ),
          ]),
        ),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('tour/studio_$name.png'));
  }

  testWidgets('every style', (t) => sheet(t, 'styles', [for (final s in studioStyles) s]), skip: !_tour);

  testWidgets('every sticker', (t) => sheet(t, 'stickers', [for (final k in StickerKind.values) (stickerNames[k]!, StudioLook(kind: k, look: PhotoLook.warm))], cols: 5), skip: !_tour);

  testWidgets('stickers on a frosted pane and a card, in sans and mono', (t) => sheet(t, 'plates', [
        for (final k in [StickerKind.stats, StickerKind.line, StickerKind.caption, StickerKind.time, StickerKind.menu])
          for (final (n, l) in [
            ('frost', StudioLook(kind: k, plate: StickerPlate.frost, look: PhotoLook.warm)),
            ('card · sans', StudioLook(kind: k, plate: StickerPlate.card, face: StickerFace.sans, ink: StickerInk.dark, look: PhotoLook.warm)),
            ('mono · amber', StudioLook(kind: k, face: StickerFace.mono, ink: StickerInk.amber, look: PhotoLook.warm)),
          ])
            ('${stickerNames[k]} · $n', l),
      ], cols: 6), skip: !_tour);

  testWidgets('every frame, paper and black', (t) => sheet(t, 'frames', [
        for (final f in PhotoFrame.values) (frameNames[f]!, StudioLook(kind: null, frame: f, look: PhotoLook.warm)),
        for (final f in PhotoFrame.values.where(frameHasTone)) ('${frameNames[f]} · black', StudioLook(kind: null, frame: f, frameDark: true, look: PhotoLook.warm)),
      ], ratio: 4 / 5, cols: 5), skip: !_tour);

  testWidgets('every look', (t) => sheet(t, 'looks', [
        for (final l in PhotoLook.values) (lookNames[l]!, StudioLook(kind: null, look: l)),
        ('Film + grain', const StudioLook(kind: null, look: PhotoLook.film, grain: true)),
        ('Noir + vignette', const StudioLook(kind: null, look: PhotoLook.noir, vignette: true)),
      ], ratio: 1, cols: 5), skip: !_tour);
}
