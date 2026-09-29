// The guest book — a first-party CRM. Find a guest who's been here, see the history
// THIS venue made (visits, tabs, rewards) and keep your own notes and tags. Never their
// diary, never another venue: the database has no function that could hand you either.
// The guest can see and delete every note kept on them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'tonight_screen.dart';

class GuestsScreen extends StatefulWidget {
  final Venue venue;
  const GuestsScreen({super.key, required this.venue});
  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<ProfileHit> _hits = const [];
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      return setState(() {
        _hits = const [];
        _searched = false;
      });
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await Backend.i.searchPeople(q);
        if (mounted) {
          setState(() {
            _hits = r;
            _searched = true;
          });
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ScrollPage(
      title: 'Guests',
      subtitle: widget.venue.name,
      children: [
        const DemoNote(),
        Text('Your own notes on the regulars you serve — first-party only: never their diary, never another venue. They can see and erase anything you keep.', style: T.caption(bd)),
        const SizedBox(height: S.m),
        GlassField(controller: _q, hint: 'Find a guest by name or @handle', icon: Ph.magnifyingGlass, onChanged: _search, caps: TextCapitalization.none),
        const SizedBox(height: S.m),
        if (_searched && _hits.isEmpty) const EmptyNote('No one by that name or handle.'),
        if (_hits.isNotEmpty)
          Group(children: [
            for (final p in _hits)
              GroupTile(
                title: p.name,
                subtitle: '@${p.handle}',
                chevron: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuestDetailScreen(venue: widget.venue, guestId: p.id, name: p.name))),
              ),
          ]),
      ],
    );
  }
}

class GuestDetailScreen extends StatelessWidget {
  final Venue venue;
  final String guestId;
  final String name;
  const GuestDetailScreen({super.key, required this.venue, required this.guestId, required this.name});

  static final _day = DateFormat('d MMM y');

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: Loader<GuestCard?>(
          load: () => Backend.i.guestCard(venue.id, guestId),
          refresh: guestsRev,
          failed: (context, retry) => ScrollPage(title: name, back: true, tabBar: false, children: [LoadError(onRetry: retry)]),
          builder: (context, card, loading) {
            final c = card ?? const GuestCard();
            return ScrollPage(
              title: name,
              back: true,
              tabBar: false,
              children: [
                if (card == null && loading)
                  const Skeleton(height: 160)
                else if (!c.beenHere)
                  const EmptyNote('They haven\'t been here yet — a book opens once they join a room or you punch their card.')
                else ...[
                  StatRow([
                    StatTile('Visits', '${c.visits}'),
                    StatTile('Rewards claimed', '${c.perksClaimed}', hint: c.hasEarned ? 'one is ready now' : null, accent: c.hasEarned),
                    if (s.can(Cap.recordSpend)) StatTile('Tabs', '${c.tabs}', hint: c.tabs > 0 ? money(c.totalSpend, venue.currency) : null),
                  ]),
                  const SizedBox(height: S.m),
                  Text(
                    [
                      if (c.firstSeen != null) 'First here ${_day.format(c.firstSeen!.toLocal())}',
                      if (c.lastSeen != null) 'last ${_day.format(c.lastSeen!.toLocal())}',
                    ].join(' · '),
                    style: T.caption(bd),
                  ),
                  if (s.can(Cap.redeemPerk) && venue.verified) ...[
                    const SizedBox(height: S.m),
                    BdButton('Their rewards', kind: BtnKind.secondary, icon: Ph.gift, onTap: () => showPerksSheet(context, venue, guestId, name)),
                  ],
                  const SectionHeader('Your notes'),
                  _NoteEditor(venue: venue, guestId: guestId, card: c, editable: s.can(Cap.guestNotes)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  final Venue venue;
  final String guestId;
  final GuestCard card;
  final bool editable;
  const _NoteEditor({required this.venue, required this.guestId, required this.card, required this.editable});
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _body = TextEditingController(text: widget.card.note);
  late final _tag = TextEditingController();
  late List<String> _tags = [...widget.card.tags];
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await runAction(context, () => Backend.i.setGuestNote(widget.venue.id, widget.guestId, _body.text, _tags), done: 'Saved.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (!widget.editable) {
      return Text(widget.card.note.isEmpty ? 'No notes yet.' : widget.card.note, style: T.body(bd));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlassField(controller: _body, hint: 'Likes it less sweet · celebrating a new job this month', maxLines: 5, maxLength: 2000),
      const SizedBox(height: S.m),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (final t in _tags) BdChip(t, icon: Ph.x, onTap: () => setState(() => _tags.remove(t))),
        if (_tags.length < 12)
          SizedBox(
            width: 170,
            child: GlassField(
              controller: _tag,
              hint: 'Add a tag',
              maxLength: 24,
              action: TextInputAction.done,
              onSubmitted: (t) {
                final clean = t.trim();
                if (clean.isNotEmpty && !_tags.contains(clean)) setState(() => _tags = [..._tags, clean]);
                _tag.clear();
              },
            ),
          ),
      ]),
      const SizedBox(height: S.l),
      BdButton('Save notes', busy: _busy, onTap: _save),
      const SizedBox(height: S.s),
      Text('Keep it kind and useful — the guest can read every word and delete it.', style: T.caption(bd)),
    ]);
  }
}
