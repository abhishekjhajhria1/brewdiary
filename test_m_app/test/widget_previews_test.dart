// The pictures Android shows in the widget picker (res/drawable-nodpi/*_preview.png),
// drawn by the same code that draws the live widgets — so the preview is what you get.
// Regenerate after changing a widget's look:
//   flutter test test/widget_previews_test.dart --dart-define=WRITE_PREVIEWS=true
import 'dart:io';

import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/ui/home_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _write = bool.fromEnvironment('WRITE_PREVIEWS');
const _dir = 'android/app/src/main/res/drawable-nodpi';

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  testWidgets('the widget picker previews are drawn by the widgets themselves', (t) async {
    await bootApp(t, signedIn: true);
    final mosaic = (await t.runAsync(() => renderMosaicCard(entryStore.entries, testNow)))!;
    final split = (await t.runAsync(() => renderSplitCard(owed: 900, owe: 0, currency: 'INR')))!;
    expect(mosaic.length, greaterThan(1000));
    expect(split.length, greaterThan(1000));
    if (_write) {
      File('$_dir/mosaic_widget_preview.png').writeAsBytesSync(mosaic);
      File('$_dir/split_widget_preview.png').writeAsBytesSync(split);
    }
    for (final f in ['mosaic_widget_preview.png', 'split_widget_preview.png']) {
      expect(File('$_dir/$f').existsSync(), isTrue, reason: '$f is what the widget picker shows — regenerate with WRITE_PREVIEWS');
    }
  });
}
