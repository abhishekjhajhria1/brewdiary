// Date and time pickers for the rota, time off and corrections: the platform's wheel in one
// of our sheets (thumb-reachable, both themes), 24-hour, in 5-minute steps where a time is
// involved. A PickerRow is the field that opens one.
import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'common.dart';

DateTime _roundTo(DateTime t, int minutes) {
  final m = (t.minute / minutes).round() * minutes;
  return DateTime(t.year, t.month, t.day, t.hour).add(Duration(minutes: m));
}

Future<DateTime?> _wheel(BuildContext context, {required String title, required DateTime initial, required CupertinoDatePickerMode mode, DateTime? min, DateTime? max}) {
  var picked = mode == CupertinoDatePickerMode.date ? DateTime(initial.year, initial.month, initial.day) : _roundTo(initial, 5);
  return showBdSheet<DateTime>(context, title: title, scroll: false, builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 200,
        child: CupertinoDatePicker(
          mode: mode,
          initialDateTime: picked,
          minimumDate: min,
          maximumDate: max,
          use24hFormat: true,
          minuteInterval: mode == CupertinoDatePickerMode.date ? 1 : 5,
          onDateTimeChanged: (d) => picked = d,
        ),
      ),
      const SizedBox(height: S.l),
      BdButton('Done', onTap: () => Navigator.pop(ctx, picked)),
    ]);
  });
}

/// A time on [day]'s date (the caller decides whether it runs past midnight).
Future<DateTime?> pickTime(BuildContext context, DateTime initial, {String title = 'Time'}) =>
    _wheel(context, title: title, initial: initial, mode: CupertinoDatePickerMode.time);

Future<DateTime?> pickDate(BuildContext context, DateTime initial, {String title = 'Day', DateTime? min, DateTime? max}) =>
    _wheel(context, title: title, initial: initial, mode: CupertinoDatePickerMode.date, min: min, max: max);

Future<DateTime?> pickDateTime(BuildContext context, DateTime initial, {String title = 'When', DateTime? max}) =>
    _wheel(context, title: title, initial: initial, mode: CupertinoDatePickerMode.dateAndTime, max: max);

/// A labelled value that opens a picker: "STARTS  18:00".
class PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData icon;
  const PickerRow({super.key, required this.label, required this.value, required this.onTap, this.icon = Ph.clock});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: Glass(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.m),
        child: Row(children: [
          Icon(icon, size: 18, color: bd.faint),
          const SizedBox(width: S.s),
          Expanded(child: Label(label)),
          Text(value, style: T.sans(bd, size: 16, weight: FontWeight.w500).copyWith(fontFeatures: T.tnum)),
        ]),
      ),
    );
  }
}
