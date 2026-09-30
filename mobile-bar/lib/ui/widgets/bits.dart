// Small pieces the venue screens share: numbers, tags, the QR box, and one way to run
// an action and say what happened.
import 'package:brewdiary_core/money.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/backend.dart';
import '../../logic/roles.dart';
import '../../logic/venue_kinds.dart';
import '../theme.dart';
import 'common.dart';

/// Money in the venue's own currency (₹1,23,456; €1.234,56).
String money(num amount, String currency, {bool round = true}) => formatMoney(amount, currency, round);

/// A hidden split (fewer than 5 people) is "—", never 0 — "nobody" and "we're not
/// telling you" are different facts, and showing 0 for both leaks the first.
String countOrHidden(int? n) => n == null ? '—' : '$n';

/// Run [f]; on success show [done] (if any), on failure the backend's plain sentence.
Future<bool> runAction(BuildContext context, Future<void> Function() f, {String? done}) async {
  try {
    await f();
    if (done != null && context.mounted) toast(context, done);
    return true;
  } on BackendError catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (_) {
    if (context.mounted) toast(context, 'Something went wrong — try again.');
  }
  return false;
}

/// A number with a caption under it.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final bool accent;
  const StatTile(this.label, this.value, {super.key, this.hint, this.accent = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Label(label),
        const SizedBox(height: 6),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.serif(bd, size: 28, color: accent ? bd.accentText : bd.ink).copyWith(fontFeatures: T.tnum)),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint!, style: T.caption(bd))),
      ]),
    );
  }
}

/// Two stat tiles side by side, wrapping on a narrow phone.
class StatRow extends StatelessWidget {
  final List<Widget> tiles;
  const StatRow(this.tiles, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 520 ? 3 : 2;
        final w = (c.maxWidth - S.m * (perRow - 1)) / perRow;
        return Wrap(spacing: S.m, runSpacing: S.m, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      });
}

/// A status word in its tone, with a dot — never colour alone.
class ToneTag extends StatelessWidget {
  final String text;
  final Tone tone;
  const ToneTag(this.text, this.tone, {super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final c = bd.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: c.withValues(alpha: .55), width: .8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: T.sans(bd, size: 12, weight: FontWeight.w500, color: c)),
      ]),
    );
  }
}

String roleLabel(StaffRole r, VenueKind kind) => switch (r) {
      StaffRole.owner => 'Owner',
      StaffRole.manager => 'Manager',
      StaffRole.supervisor => 'Shift lead',
      StaffRole.bartender => staffWord(kind),
      StaffRole.server => 'Server',
      StaffRole.host => 'Host',
      StaffRole.kitchen => 'Kitchen',
    };

String roleBlurb(StaffRole r) => switch (r) {
      StaffRole.owner => 'Everything, including deleting the venue.',
      StaffRole.manager => 'Everything but deleting the venue: menu, perks, team, numbers.',
      StaffRole.supervisor => 'Runs a shift: approvals, cash-up, the live board.',
      StaffRole.bartender => 'The bar: tabs, perks, vibe, the guest book.',
      StaffRole.server => 'Tables: orders, tabs, perks, the guest book.',
      StaffRole.host => 'The door: bookings, seating, who\'s in tonight.',
      StaffRole.kitchen => 'The kitchen screen, the 86 list, stock counts.',
    };

/// A scannable code on a white card (scanners need contrast, whatever the theme).
class QrBox extends StatelessWidget {
  final String data;
  final double size;
  const QrBox(this.data, {super.key, this.size = 220});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'QR code for $data',
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(rTile)),
          child: QrImageView(data: data, size: size, backgroundColor: Colors.white, padding: EdgeInsets.zero),
        ),
      );
}

/// The demo ribbon: honest about the numbers being made up.
class DemoNote extends StatelessWidget {
  const DemoNote({super.key});
  @override
  Widget build(BuildContext context) {
    if (!Backend.i.isDemo) return const SizedBox.shrink();
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.l),
      child: Row(children: [
        Icon(Ph.info, size: 16, color: bd.faint),
        const SizedBox(width: 6),
        Expanded(child: Text('Demo venue — made-up data that never leaves this phone.', style: T.caption(bd))),
      ]),
    );
  }
}
