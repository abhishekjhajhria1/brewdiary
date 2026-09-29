// Pickers in the house style — glass sheets instead of the stock Material dialogs.
// Dates are day-month-year wheels (no US-only mm/dd/yyyy typing), countries are a
// searchable list with a check on the current one. Every picker returns null when
// dismissed, so call sites only act on a real choice.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/jurisdiction.dart';
import '../../core/money.dart';
import '../theme.dart';
import 'common.dart';

Future<DateTime?> pickDate(BuildContext context, {required DateTime initial, DateTime? first, DateTime? last, String title = 'Pick a date'}) {
  final now = appNow();
  final lo = first ?? DateTime(now.year - 5);
  final hi = last ?? DateTime(now.year + 3, 12, 31);
  var value = initial.isBefore(lo) ? lo : (initial.isAfter(hi) ? hi : initial);
  return showBdSheet<DateTime>(context, title: title, builder: (ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          dateOrder: DatePickerDateOrder.dmy,
          initialDateTime: value,
          minimumDate: lo,
          maximumDate: hi,
          onDateTimeChanged: (d) => value = d,
        ),
      ),
      const SizedBox(height: S.l),
      BdButton('Done', onTap: () => Navigator.pop(ctx, DateTime(value.year, value.month, value.day))),
    ]);
  });
}

Future<TimeOfDay?> pickTime(BuildContext context, {required TimeOfDay initial, String title = 'Pick a time'}) {
  final now = appNow();
  var value = DateTime(now.year, now.month, now.day, initial.hour, initial.minute);
  return showBdSheet<TimeOfDay>(context, title: title, builder: (ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: value,
          minuteInterval: 5,
          use24hFormat: MediaQuery.of(ctx).alwaysUse24HourFormat,
          onDateTimeChanged: (d) => value = d,
        ),
      ),
      const SizedBox(height: S.l),
      BdButton('Done', onTap: () => Navigator.pop(ctx, TimeOfDay(hour: value.hour, minute: value.minute))),
    ]);
  });
}

/// "12 Mar 2026" — the app's written date.
String writtenDate(DateTime d) => '${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';

/// Pick a researched country (plus "Somewhere else" → strict defaults).
Future<String?> pickCountry(BuildContext context, {required String current, bool includeElsewhere = true}) {
  return showBdSheet<String>(context, title: 'Where you are', scroll: false, builder: (ctx) => _CountryList(current: current, includeElsewhere: includeElsewhere));
}

class _CountryList extends StatefulWidget {
  final String current;
  final bool includeElsewhere;
  const _CountryList({required this.current, required this.includeElsewhere});
  @override
  State<_CountryList> createState() => _CountryListState();
}

class _CountryListState extends State<_CountryList> {
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final q = _q.text.trim().toLowerCase();
    final items = [
      ...knownCountries,
      if (widget.includeElsewhere) ('ZZ', 'Somewhere else'),
    ].where((c) => q.isEmpty || c.$2.toLowerCase().contains(q) || c.$1.toLowerCase() == q).toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(S.gutter, 4, S.gutter, S.s),
        child: GlassField(controller: _q, hint: 'Search', icon: Ph.magnifyingGlass, onChanged: (_) => setState(() {}), caps: TextCapitalization.words),
      ),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.xxl + MediaQuery.of(context).padding.bottom),
          itemCount: items.length,
          separatorBuilder: (_, _) => Divider(height: 1, thickness: .8, color: bd.line),
          itemBuilder: (ctx, i) {
            final c = items[i];
            final selected = c.$1 == widget.current;
            final age = minDrinkingAge(c.$1 == 'ZZ' ? null : c.$1);
            return Semantics(
              selected: selected,
              button: true,
              child: Pressable(
                onTap: () => Navigator.pop(ctx, c.$1),
                child: SizedBox(
                  height: 54,
                  child: Row(children: [
                    Expanded(child: Text(c.$2, style: T.row(bd))),
                    Text('$age+', style: T.caption(bd)),
                    SizedBox(width: 36, child: selected ? Icon(Ph.check, size: 18, color: bd.accentText) : null),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

Future<String?> pickCurrency(BuildContext context, {required String current}) {
  return showBdSheet<String>(context, title: 'Currency', builder: (ctx) {
    final bd = ctx.bd;
    return Hairlines(children: [
      for (final c in supportedCurrencies)
        Pressable(
          onTap: () => Navigator.pop(ctx, c),
          child: SizedBox(
            height: 52,
            child: Row(children: [
              SizedBox(width: 44, child: Text(currencySymbol(c), style: T.row(bd, color: bd.muted))),
              Expanded(child: Text(c, style: T.row(bd))),
              if (c == current) Icon(Ph.check, size: 18, color: bd.accentText),
            ]),
          ),
        ),
    ]);
  });
}

/// A tappable field that opens a picker — looks like an input, reads like a value.
class PickerField extends StatelessWidget {
  final String? label;
  final String value;
  final bool placeholder;
  final VoidCallback onTap;
  final IconData icon;
  const PickerField({super.key, this.label, required this.value, required this.onTap, this.placeholder = false, this.icon = Ph.caretDown});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (label != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Label(label!)),
      Semantics(
        button: true,
        label: label,
        value: value,
        child: Pressable(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.lineStrong))),
            child: Row(children: [
              Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 16, color: placeholder ? bd.faint : bd.ink))),
              Icon(icon, size: 18, color: bd.faint),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// A date field that opens the house date wheels ("Today" when it's today).
class DateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  final String? label;
  final String placeholder;
  const DateField({super.key, required this.value, required this.onChanged, this.first, this.last, this.label, this.placeholder = 'Pick a date'});
  @override
  Widget build(BuildContext context) {
    final v = value;
    return PickerField(
      label: label,
      value: v == null ? placeholder : (toKey(v) == todayKey() ? 'Today' : writtenDate(v)),
      placeholder: v == null,
      icon: Ph.calendarBlank,
      onTap: () async {
        final picked = await pickDate(context, initial: v ?? appNow(), first: first, last: last, title: label ?? 'Pick a date');
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// A time field that opens the house time wheel.
class TimeField extends StatelessWidget {
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay> onChanged;
  final String? label;
  final String placeholder;
  const TimeField({super.key, required this.value, required this.onChanged, this.label, this.placeholder = 'Pick a time'});
  @override
  Widget build(BuildContext context) {
    final v = value;
    return PickerField(
      label: label,
      value: v == null ? placeholder : v.format(context),
      placeholder: v == null,
      icon: Ph.clock,
      onTap: () async {
        final picked = await pickTime(context, initial: v ?? const TimeOfDay(hour: 20, minute: 0), title: label ?? 'Pick a time');
        if (picked != null) onChanged(picked);
      },
    );
  }
}
