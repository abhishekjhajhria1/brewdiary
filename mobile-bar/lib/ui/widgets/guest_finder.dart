// Finding a guest without searching everyone (056): the people who opened this
// venue's table or menu link tonight — with the taste they shared — and the
// 6-letter code a guest shows from their own phone. Used by the till and the guest
// book. A bartender reads the taste to make something the guest will like.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import 'common.dart';

/// A guest's shared taste as small chips: "Nothing with alcohol tonight" first.
class TasteChips extends StatelessWidget {
  final GuestTaste taste;
  final bool compact;
  const TasteChips(this.taste, {super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget chip(String text, {bool strong = false}) => Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
          decoration: BoxDecoration(
            color: strong ? bd.accent.withValues(alpha: .18) : bd.glass,
            borderRadius: BorderRadius.circular(rCtl),
            border: Border.all(color: strong ? bd.accent.withValues(alpha: .5) : bd.line, width: .8),
          ),
          child: Text(text, style: T.sans(bd, size: compact ? 12 : 13, weight: strong ? FontWeight.w600 : FontWeight.w500, color: strong ? bd.accentText : bd.ink)),
        );
    if (taste.isEmpty) return Text('Shared, but nothing logged yet.', style: T.caption(bd));
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (taste.dryTonight) chip('Nothing with alcohol tonight', strong: true),
      if (taste.allergies.isNotEmpty) chip('Allergic: ${taste.allergies.join(', ')}', strong: true),
      if (taste.avoid.isNotEmpty) chip('Not: ${taste.avoid.join(', ')}', strong: true),
      for (final d in taste.diet) chip(d),
      for (final x in taste.into) chip(x),
      if (taste.flavours.isNotEmpty) chip('likes ${taste.flavours.join(', ')}'),
      if (taste.sweetness != null) chip(switch (taste.sweetness) { 'dry' => 'not sweet', 'sweet' => 'on the sweet side', _ => 'balanced sweetness' }),
      for (final u in taste.usually) chip('usually $u'),
      for (final m in taste.moods) chip(m),
      if (taste.alcoholFreeOften && !taste.dryTonight) chip('often alcohol-free'),
    ]);
  }
}

/// "In tonight" + "Their code". [onPick] gets the chosen guest; [pickLabel] is the
/// button word ("Punch", "Open").
class GuestFinder extends StatefulWidget {
  final Venue venue;
  final ValueChanged<ProfileHit> onPick;
  final String pickLabel;
  const GuestFinder({super.key, required this.venue, required this.onPick, this.pickLabel = 'Open'});
  @override
  State<GuestFinder> createState() => _GuestFinderState();
}

class _GuestFinderState extends State<GuestFinder> {
  final _code = TextEditingController();
  bool _looking = false;
  String? _miss;
  int _misses = 0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final code = _code.text.trim();
    if (code.length != 6 || _looking) return;
    setState(() {
      _looking = true;
      _miss = null;
    });
    try {
      final hit = await Backend.i.findGuestByCode(widget.venue.id, code);
      if (!mounted) return;
      if (hit == null) {
        Haptics.error();
        setState(() {
          _misses++;
          _miss = 'No guest with that code — codes last 10 minutes; ask them for a fresh one.';
        });
      } else {
        Haptics.success();
        _code.clear();
        widget.onPick(hit);
      }
    } catch (e) {
      if (mounted) {
        Haptics.error();
        setState(() {
          _misses++;
          _miss = e is BackendError ? e.message : 'Couldn\'t look that up — try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.can(Cap.tasteShare)) ...[
        const SectionHeader('In tonight'),
        Loader<List<GuestTonight>>(
          load: () => Backend.i.guestsTonight(widget.venue.id),
          refresh: floorRev,
          retry: true,
          builder: (context, guests, loading) {
            if (guests == null) return const Skeleton(height: 120);
            if (guests.isEmpty) {
              return Text('When guests open your menu or a table\'s link on brewdiary — and have said yes to sharing — they show here with their taste.', style: T.caption(bd));
            }
            return Group(children: [
              for (final g in guests)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.s),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Initial(g.name.isEmpty ? '?' : g.name[0].toUpperCase(), size: 36),
                      const SizedBox(width: S.m),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(g.name, style: T.row(bd)),
                          Text([if (g.tableLabel != null) 'Table ${g.tableLabel}' else 'Opened the menu', if (g.handle.isNotEmpty) '@${g.handle}'].join(' · '), style: T.caption(bd)),
                        ]),
                      ),
                      AccentPill(widget.pickLabel, onTap: () => widget.onPick(g.hit)),
                    ]),
                    const SizedBox(height: S.s),
                    TasteChips(g.taste, compact: true),
                  ]),
                ),
            ]);
          },
        ),
      ],
      const SectionHeader('Their code'),
      Shake(
        trigger: _misses,
        child: Row(children: [
          Expanded(
            child: GlassField(
              controller: _code,
              hint: 'The 6 letters on their guest card',
              icon: Ph.identificationBadge,
              caps: TextCapitalization.characters,
              maxLength: 6,
              onChanged: (t) {
                setState(() => _miss = null);
                // The sixth letter looks itself up — one less tap at a busy till.
                if (t.trim().length == 6) _find();
              },
              onSubmitted: (_) => _find(),
            ),
          ),
          const SizedBox(width: S.s),
          SizedBox(width: 96, child: BdButton('Find', kind: BtnKind.secondary, busy: _looking, onTap: _code.text.trim().length == 6 ? _find : null)),
        ]),
      ),
      Appear(visible: _miss != null, child: _miss == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: S.s), child: Text(_miss!, style: T.sans(bd, size: 13, color: bd.tone(Tone.late))))),
      const SizedBox(height: S.s),
      Text('Guests find their code under Taste passport › Show my guest card. Nobody is searched by name.', style: T.caption(bd)),
    ]);
  }
}
