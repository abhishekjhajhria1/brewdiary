// The home-screen widget's picture: this month's mosaic, drawn from the diary.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/ui/home_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  testWidgets('draws a 3:2-ish card from the diary', (t) async {
    await bootApp(t, signedIn: true);
    final png = (await t.runAsync(() => renderMosaicCard(entryStore.entries, testNow)))!;
    final codec = (await t.runAsync(() => ui.instantiateImageCodec(png)))!;
    final frame = (await t.runAsync(codec.getNextFrame))!;
    expect(frame.image.width, 720);
    expect(frame.image.height, 540);
    if (const bool.fromEnvironment('TOUR')) {
      Directory('test/tour').createSync(recursive: true);
      File('test/tour/n1_home_widget.png').writeAsBytesSync(png);
    }
  });
}
