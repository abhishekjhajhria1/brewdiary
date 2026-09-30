// Payroll (supabase/054): hours and pay for a period, per person — and the CSV an
// accountant opens (one row per person per day, then the totals). For owners and managers.
// A day is the day a shift started in the venue's time zone, so a night past midnight
// counts once. People are in NAME order: payroll is for pay, never a ranking. brewdiary
// reports hours and rates; overtime, tax and deductions are the payroll provider's.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/area.dart' show venueTimeZone;
import '../../logic/payroll.dart';
import '../../logic/roles.dart';
import '../../logic/rota.dart' show dateLabel;
import '../../logic/staff.dart' show formatMinutes;
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'team_screen.dart' show youLabel;
import 'timesheet_screen.dart';

class PayrollScreen extends StatefulWidget {
  final Venue venue;
  const PayrollScreen({super.key, required this.venue});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  PayPeriod _period = PayPeriod.thisWeek;

  String _role(String r) => r == 'left' ? 'left the team' : roleLabel(StaffRole.parse(r), widget.venue.kind);

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final v = widget.venue;
    final (from, to) = payPeriod(_period, DateTime.now());
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Payroll',
          back: true,
          tabBar: false,
          onRefresh: () async => shiftRev.bump(),
          children: [
            const DemoNote(),
            Wrap(spacing: S.s, runSpacing: S.s, children: [
              for (final p in PayPeriod.values) BdChip(p.label, active: p == _period, onTap: () => setState(() => _period = p)),
            ]),
            const SizedBox(height: S.s),
            Text(from == to ? dateLabel(from) : '${dateLabel(from)} – ${dateLabel(to)}', style: T.caption(bd)),
            const SizedBox(height: S.l),
            Loader<List<PayrollDay>>(
              load: () => Backend.i.payroll(v.id, from, to, tz: venueTimeZone(v.country, v.region)),
              refresh: Listenable.merge([shiftRev, staffRev]),
              deps: _period,
              retry: true,
              builder: (context, rows, loading) {
                if (rows == null) return const Skeleton(height: 260);
                final people = payrollTotals(rows);
                final worked = people.fold<int>(0, (n, p) => n + p.workedMinutes);
                final noRate = people.where((p) => p.missingRate && p.role != 'owner').map((p) => p.name).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  StatRow([
                    StatTile('Hours', formatMinutes(worked)),
                    StatTile('Pay', money(centsToAmount(payrollTotalCents(people)), v.currency, round: false)),
                  ]),
                  const SizedBox(height: S.l),
                  if (noRate.isNotEmpty) ...[
                    Glass(
                      padding: const EdgeInsets.all(S.l),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Ph.warning, size: 18, color: bd.accent),
                        const SizedBox(width: S.s),
                        Expanded(
                          child: Text(
                            'No rate for ${_names(noRate)} — their hours are in the file without pay. Tap a name to set one.',
                            style: T.sans(bd, size: 14),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: S.l),
                  ],
                  if (people.isEmpty)
                    const EmptyNote('No hours in this period.', icon: Ph.clock)
                  else
                    Group(children: [for (final p in people) _personTile(context, p)]),
                  const SizedBox(height: S.l),
                  BdButton('Share as CSV', icon: Ph.shareNetwork, kind: BtnKind.secondary, onTap: rows.isEmpty ? null : () => _share(context, rows, from, to)),
                  const SizedBox(height: S.m),
                  Text(
                    'By name, for pay — never a ranking. A shift counts on the day it started, in the venue\'s time zone. '
                    'Unpaid breaks come off; a shift keeps the rate it started at. brewdiary reports hours and rates — '
                    'overtime, tax and deductions are your payroll provider\'s.',
                    style: T.caption(bd),
                  ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _names(List<String> names) =>
      names.length <= 2 ? names.join(' and ') : '${names.take(2).join(', ')} and ${names.length - 2} more';

  Widget _personTile(BuildContext context, PayrollPerson p) {
    final bd = context.bd;
    final s = Session.instance;
    final me = p.userId == s.user?.id;
    final v = widget.venue;
    final mine = v.myRole;
    final target = StaffRole.parse(p.role);
    final canPay = !me && p.role != 'left' && p.role != 'owner' && s.can(Cap.manageTeam) && canGrant(mine, target);
    final actions = <SheetAction>[
      SheetAction(me ? 'My timesheet' : 'Their timesheet', icon: Ph.listChecks, onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimesheetScreen(venue: v, userId: p.userId, name: p.name)));
      }),
      if (canPay) SheetAction(p.rate == null ? 'Set their pay' : 'Change their pay', icon: Ph.wallet, onTap: () => payRateSheet(context, v, userId: p.userId, name: p.name)),
    ];
    return GroupTile(
      title: me ? youLabel(p.name) : p.name,
      subtitle: [
        _role(p.role),
        '${p.daysWorked} ${p.daysWorked == 1 ? 'day' : 'days'}',
        '${formatMinutes(p.workedMinutes)} worked',
        if (p.plannedMinutes > 0) '${formatMinutes(p.plannedMinutes)} planned',
        if (p.rate != null) '${money(p.rate!, v.currency, round: false)}/h',
      ].join(' · '),
      trailing: p.payCents != null
          ? Text(money(centsToAmount(p.payCents!), v.currency, round: false), style: T.sans(bd, size: 15, weight: FontWeight.w500).copyWith(fontFeatures: T.tnum))
          : (p.workedMinutes > 0 && p.role != 'owner' ? const ToneTag('no rate', Tone.wait) : null),
      onTap: () => showActions(context, title: p.name, actions: actions),
    );
  }

  Future<void> _share(BuildContext context, List<PayrollDay> rows, DateTime from, DateTime to) async {
    final v = widget.venue;
    final csv = payrollCsv(venue: v.name, currency: v.currency, from: from, to: to, rows: rows);
    final name = payrollFileName(v.name, from, to);
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(payrollFileBytes(csv)), mimeType: 'text/csv', name: name)],
        fileNameOverrides: [name],
        subject: 'Payroll — ${v.name}',
      ));
    } catch (_) {
      // No file sharing here (or it failed): the same CSV as text still reaches a mail or a chat.
      try {
        await SharePlus.instance.share(ShareParams(text: csv, subject: 'Payroll — ${v.name}'));
      } catch (_) {
        if (context.mounted) toast(context, 'Couldn\'t share the file — try again.');
      }
    }
  }
}

/// Set (or clear) someone's hourly rate. Only an owner or manager, for a role they manage,
/// and never their own — the database decides (set_staff_pay). The team history notes the
/// change, never the amount.
Future<void> payRateSheet(BuildContext context, Venue venue, {required String userId, required String name}) async {
  double? current;
  try {
    current = (await Backend.i.payRates(venue.id))[userId];
  } on BackendError catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  } catch (_) {
    if (context.mounted) toast(context, 'Couldn\'t load their rate — try again.');
    return;
  }
  if (!context.mounted) return;
  final ctl = TextEditingController(text: current == null ? '' : (current == current.roundToDouble() ? '${current.round()}' : current.toStringAsFixed(2)));
  String? err;
  var busy = false;
  await showBdSheet<void>(context, title: '$name\'s pay', builder: (ctx) {
    final bd = ctx.bd;
    return StatefulBuilder(builder: (ctx, set) {
      Future<void> save(double? rate) async {
        set(() {
          err = null;
          busy = true;
        });
        final ok = await runAction(ctx, () => Backend.i.setPayRate(venue.id, userId, rate), done: rate == null ? 'Rate cleared.' : 'Saved.');
        if (ctx.mounted) {
          set(() => busy = false);
          if (ok) Navigator.pop(ctx);
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'An hourly rate, before tax. Shifts from now on are paid at it; a shift keeps the rate it started at, '
          'and time worked with no rate uses this one. The team history notes that it changed — never the amount.',
          style: T.bodyMuted(bd),
        ),
        const SizedBox(height: S.l),
        LineField(
          controller: ctl,
          label: 'Per hour (${venue.currency})',
          hint: '250',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          error: err,
          autofocus: true,
        ),
        const SizedBox(height: S.xl),
        BdButton('Save', busy: busy, onTap: busy
            ? null
            : () {
                final rate = double.tryParse(ctl.text.trim().replaceAll(',', ''));
                if (rate == null || rate < 0 || rate > 100000) {
                  set(() => err = 'A number from 0 to 1,00,000.');
                  return;
                }
                save(rate);
              }),
        if (current != null) ...[
          const SizedBox(height: S.s),
          BdButton('Clear the rate', kind: BtnKind.quiet, onTap: busy ? null : () => save(null)),
        ],
      ]);
    });
  });
  ctl.dispose();
}
