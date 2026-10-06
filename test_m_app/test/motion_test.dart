// The motion and haptics vocabulary (lib/ui/widgets/motion.dart): it is the same file
// in both apps, every animation lands exactly at rest, numbers roll the right way,
// tabs keep their state, haptics say the right thing (and nothing when switched
// off), and reduced motion holds everything still.
import 'dart:io';

import 'package:brewdiary/ui/theme.dart';
import 'package:brewdiary/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduce = false}) => MaterialApp(
      theme: buildTheme(BD.darkTokens),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  test('the venue app carries the same motion file', () {
    final guest = File('lib/ui/widgets/motion.dart').readAsStringSync();
    final venue = File('../mobile-bar/lib/ui/widgets/motion.dart').readAsStringSync();
    expect(venue, guest, reason: 'change test_m_app/lib/ui/widgets/motion.dart and mobile-bar/lib/ui/widgets/motion.dart together');
  });

  group('haptics', () {
    final played = <String?>[];
    setUp(() {
      played.clear();
      Haptics.enabled = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') played.add(call.arguments as String?);
        return null;
      });
    });
    tearDown(() {
      Haptics.enabled = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('each kind plays its own pattern', () async {
      Haptics.tick();
      Haptics.tap();
      Haptics.knock();
      Haptics.success();
      Haptics.warning();
      Haptics.error();
      await Future<void>.delayed(Duration.zero);
      expect(played, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.successNotification',
        'HapticFeedbackType.warningNotification',
        'HapticFeedbackType.errorNotification',
      ]);
    });

    test('switched off, nothing plays', () async {
      Haptics.enabled = false;
      Haptics.tick();
      Haptics.success();
      Haptics.error();
      await Future<void>.delayed(Duration.zero);
      expect(played, isEmpty);
    });

    testWidgets('a button ticks; a card that opens a page does not', (t) async {
      var taps = 0;
      await t.pumpWidget(_host(Column(mainAxisSize: MainAxisSize.min, children: [
        BdButton('Log', expand: false, onTap: () => taps++),
        Glass(onTap: () => taps++, child: const SizedBox(width: 120, height: 60, child: Text('card'))),
      ])));
      await t.tap(find.text('Log'));
      await t.pumpAndSettle();
      expect(played, ['HapticFeedbackType.selectionClick']);
      await t.tap(find.text('card'));
      await t.pumpAndSettle();
      expect(played, ['HapticFeedbackType.selectionClick'], reason: 'the page that opens is the answer');
      expect(taps, 2);
    });

    testWidgets('a success toast taps success, a failure buzzes error', (t) async {
      await t.pumpWidget(_host(Builder(builder: (context) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: () => toast(context, 'Sent.', tone: ToastTone.success), child: const Text('ok')),
          TextButton(onPressed: () => toast(context, 'That code is wrong.', tone: ToastTone.error), child: const Text('no')),
          TextButton(onPressed: () => toast(context, 'Copied.'), child: const Text('plain')),
        ]);
      })));
      await t.tap(find.text('ok'));
      await t.pump();
      await t.tap(find.text('no'));
      await t.pump();
      await t.tap(find.text('plain'));
      await t.pumpAndSettle();
      expect(played, ['HapticFeedbackType.successNotification', 'HapticFeedbackType.errorNotification']);
    });
  });

  testWidgets('a press springs back to exactly where it started', (t) async {
    await t.pumpWidget(_host(Pressable(onTap: () {}, child: const SizedBox(width: 100, height: 50, child: Text('press')))));
    final gesture = await t.startGesture(t.getCenter(find.text('press')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    final pressed = t.widget<Transform>(find.descendant(of: find.byType(Pressable), matching: find.byType(Transform)).first).transform.entry(0, 0);
    expect(pressed, lessThan(1), reason: 'it sinks under the finger');
    await gesture.up();
    await t.pumpAndSettle();
    final rest = t.widget<Transform>(find.descendant(of: find.byType(Pressable), matching: find.byType(Transform)).first).transform.entry(0, 0);
    expect(rest, 1.0, reason: 'no thousandth of a press left behind');
    expect(t.widget<Opacity>(find.descendant(of: find.byType(Pressable), matching: find.byType(Opacity)).first).opacity, 1.0);
  });

  testWidgets('a long press catches, and does not also tap', (t) async {
    var taps = 0, holds = 0;
    await t.pumpWidget(_host(Pressable(onTap: () => taps++, onLongPress: () => holds++, child: const SizedBox(width: 100, height: 50, child: Text('hold')))));
    await t.longPress(find.text('hold'));
    await t.pumpAndSettle();
    expect((taps, holds), (0, 1));
  });

  group('numbers', () {
    testWidgets('rolling text rolls up as a count grows and down as it falls', (t) async {
      Widget at(int n) => _host(RollingNumber(n, style: const TextStyle(fontSize: 20)));
      await t.pumpWidget(at(4));
      await t.pumpWidget(at(5));
      await t.pump(const Duration(milliseconds: 60));
      // Mid-roll both are there; the new one is still below its resting line.
      expect(find.text('4'), findsOneWidget);
      final rising = t.getTopLeft(find.text('5')).dy;
      await t.pumpAndSettle();
      expect(find.text('4'), findsNothing);
      final rest = t.getTopLeft(find.text('5')).dy;
      expect(rising, greaterThan(rest), reason: 'a bigger number comes up from below');

      await t.pumpWidget(at(3));
      await t.pump(const Duration(milliseconds: 60));
      expect(t.getTopLeft(find.text('3')).dy, lessThan(rest), reason: 'a smaller one comes down from above');
      await t.pumpAndSettle();
    });

    testWidgets('a headline counts up to its value, and says the value once', (t) async {
      await t.pumpWidget(_host(const CountUp(505, style: TextStyle(fontSize: 30))));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('505'), findsNothing, reason: 'still counting');
      await t.pumpAndSettle();
      expect(find.text('505'), findsOneWidget);
      expect(find.bySemanticsLabel('505'), findsOneWidget);
    });

    testWidgets('reduced motion: the value is simply there', (t) async {
      await t.pumpWidget(_host(const CountUp(505), reduce: true));
      expect(find.text('505'), findsOneWidget);
    });
  });

  testWidgets('arrival: content fades and rises in, staggered, and ends in place', (t) async {
    await t.pumpWidget(_host(Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 3; i++) Reveal(index: i, child: Text('row $i')),
    ])));
    await t.pump(const Duration(milliseconds: 40));
    double alpha(int i) => t.widget<Opacity>(find.ancestor(of: find.text('row $i'), matching: find.byType(Opacity)).first).opacity;
    expect(alpha(0), greaterThan(alpha(2)), reason: 'the first row leads');
    await t.pumpAndSettle();
    expect([alpha(0), alpha(1), alpha(2)], [1.0, 1.0, 1.0]);
  });

  testWidgets('tabs fade through without losing a page\'s state', (t) async {
    final field = TextEditingController(text: 'half a thought');
    Widget at(int i) => _host(SizedBox(
          width: 300,
          height: 300,
          child: FadeThroughStack(index: i, children: [
            KeyedSubtree(key: const ValueKey('a'), child: TextField(controller: field)),
            const KeyedSubtree(key: ValueKey('b'), child: _Counter()),
          ]),
        ));
    await t.pumpWidget(at(1));
    await t.tap(find.text('count 0'));
    await t.pump();
    await t.pumpWidget(at(0));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.widget<FadeTransition>(find.ancestor(of: find.byType(TextField), matching: find.byType(FadeTransition)).first).opacity.value, lessThan(1));
    await t.pumpAndSettle();
    await t.pumpWidget(at(1));
    await t.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget, reason: 'the counter kept its state across the switch');
    expect(field.text, 'half a thought');
  });

  testWidgets('appear grows a banner in and folds it away', (t) async {
    Widget at(bool v) => _host(SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: [Appear(visible: v, child: const SizedBox(height: 60, child: Text('undo')))])));
    await t.pumpWidget(at(false));
    expect(find.text('undo'), findsNothing);
    await t.pumpWidget(at(true));
    await t.pump(const Duration(milliseconds: 60));
    final growing = t.getSize(find.byType(Appear)).height;
    expect(growing, inExclusiveRange(0, 60));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(Appear)).height, 60);
    await t.pumpWidget(at(false));
    await t.pumpAndSettle();
    expect(find.text('undo'), findsNothing);
    expect(t.getSize(find.byType(Appear)).height, 0);
  });

  testWidgets('a wrong try shakes, then rests where it was', (t) async {
    Widget at(int n) => _host(Shake(trigger: n, child: const Text('code')));
    await t.pumpWidget(at(0));
    final home = t.getTopLeft(find.text('code'));
    await t.pumpWidget(at(1));
    await t.pump(const Duration(milliseconds: 40));
    expect(t.getTopLeft(find.text('code')).dx, isNot(home.dx));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('code')), home);
  });

  testWidgets('an action toast takes its tap and goes', (t) async {
    var undone = 0;
    await t.pumpWidget(_host(Builder(builder: (context) {
      return TextButton(onPressed: () => toast(context, 'Removed.', action: 'Undo', onAction: () => undone++), child: const Text('remove'));
    })));
    await t.tap(find.text('remove'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Removed.'), findsNothing);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => TextButton(onPressed: () => setState(() => n++), child: Text('count $n'));
}
