// Create a venue: what kind of place, where it is, and — before anything is saved — what
// the law there lets its loyalty card do. The database has the final say; this screen
// explains the rule instead of letting someone bump into a refusal.
import 'package:brewdiary_core/jurisdiction.dart';
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/session.dart';
import '../../logic/slug.dart';
import '../../logic/venue_kinds.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'venues_screen.dart';

const _ukNations = [('ENG', 'England'), ('SCT', 'Scotland'), ('WAL', 'Wales'), ('NIR', 'Northern Ireland')];

class CreateVenueScreen extends StatefulWidget {
  const CreateVenueScreen({super.key});
  @override
  State<CreateVenueScreen> createState() => _CreateVenueScreenState();
}

class _CreateVenueScreenState extends State<CreateVenueScreen> {
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _city = TextEditingController();
  final _region = TextEditingController();
  VenueKind _kind = VenueKind.bar;
  bool _servesAlcohol = true;
  String _country = 'IN';
  String? _nation;
  bool _slugEdited = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _slug, _city, _region]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _regionValue => _country == 'GB' ? _nation : (_region.text.trim().isEmpty ? null : _region.text.trim().toUpperCase());

  String _lawNote() {
    final legal = legalClass(_kind, servesAlcohol: _servesAlcohol);
    final j = jurisdiction(_country, _regionValue);
    if (legal == LegalClass.noAlcohol) {
      return _kind.isCounter
          ? 'No alcohol sold here, so alcohol-promotion law doesn\'t shape your loyalty card — it counts visits, and any reward that isn\'t alcohol.'
          : 'No alcohol sold here, so alcohol-promotion law doesn\'t shape your loyalty card — visits or spend, any reward that isn\'t alcohol.';
    }
    if (!j.alcoholLegal) return j.note ?? 'Alcohol is prohibited here — only a place that sells no alcohol can join.';
    if (legal == LegalClass.offTrade) {
      if (!j.allowPerks || !j.allowOfftradePerks) {
        return 'A liquor store here can\'t run a loyalty card — at a shop, a visit is a purchase, and the law treats that as an alcohol loyalty scheme.';
      }
      return 'A liquor store\'s card counts visits (never spend) and its reward is never alcohol — our rule, stricter than the law.';
    }
    if (!j.allowPerks) return j.note ?? 'Loyalty perks aren\'t permitted for a place that serves alcohol here.';
    return j.note ?? (j.allowAlcoholReward ? 'Perks can count visits or spend; a reward can be a drink.' : 'Perks reward visits with something non-alcoholic.');
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final slug = (_slug.text.trim().isEmpty ? slugify(name) : _slug.text.trim()).toLowerCase();
    setState(() => _error = null);
    if (name.isEmpty) return setState(() => _error = 'Give your venue a name.');
    if (!isValidSlug(slug)) return setState(() => _error = 'Pick a web address: letters, numbers and hyphens, 2–40 characters.');
    setState(() => _busy = true);
    try {
      final v = await Backend.i.createVenue(
        name: name,
        slug: slug,
        city: _city.text,
        kind: _kind,
        servesAlcohol: _servesAlcohol,
        country: _country,
        region: _regionValue,
      );
      await Session.instance.refreshVenues();
      final fresh = Session.instance.venues.where((x) => x.id == v.id).firstOrNull ?? v;
      Session.instance.select(fresh);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on BackendError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'A new venue',
          back: true,
          tabBar: false,
          children: [
            LineField(
              controller: _name,
              label: 'Name',
              hint: 'The Amber Room',
              caps: TextCapitalization.words,
              onChanged: (v) {
                if (!_slugEdited) _slug.text = slugify(v);
                setState(() {});
              },
            ),
            if (_slugEdited) ...[
              const SizedBox(height: S.l),
              LineField(
                controller: _slug,
                label: 'Web address',
                hint: 'the-amber-room',
                caps: TextCapitalization.none,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ],
            // The web address follows the name; changing it is one tap, never a required step.
            Semantics(
              button: !_slugEdited,
              child: GestureDetector(
                onTap: _slugEdited ? null : () => setState(() => _slugEdited = true),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text.rich(TextSpan(style: T.caption(bd), children: [
                    TextSpan(text: 'bwdy.site/m/${_slug.text.isEmpty ? '…' : _slug.text} — on your table tags, fixed once you\'re verified. '),
                    if (!_slugEdited) TextSpan(text: 'Change', style: T.caption(bd).copyWith(color: bd.accentText, fontWeight: FontWeight.w600)),
                  ])),
                ),
              ),
            ),
            const SectionHeader('What kind of place'),
            Wrap(spacing: S.s, runSpacing: S.s, children: [
              for (final k in VenueKind.values)
                BdChip(k.label, icon: kindIcon(k), active: _kind == k, onTap: () => setState(() {
                      _kind = k;
                      if (k.alwaysAlcohol) _servesAlcohol = true;
                      if (k.neverAlcohol) _servesAlcohol = false;
                    })),
            ]),
            if (_kind.alcoholIsChoice)
              SettingRow(
                title: 'We serve alcohol',
                hint: 'Licensed to pour. It changes which loyalty rewards are lawful.',
                trailing: BdToggle(on: _servesAlcohol, label: 'Serves alcohol', onChanged: (v) => setState(() => _servesAlcohol = v)),
              ),
            if (_kind.neverAlcohol)
              Padding(
                padding: const EdgeInsets.only(top: S.s),
                child: Text('A ${_kind.label.toLowerCase()} sells no alcohol — if you do, create a liquor store instead.', style: T.caption(bd)),
              ),
            const SectionHeader('Where'),
            LineField(controller: _city, label: 'City', hint: 'Bengaluru', caps: TextCapitalization.words),
            const SizedBox(height: S.l),
            const Label('Country'),
            const SizedBox(height: 6),
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: S.l),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _country,
                  isExpanded: true,
                  dropdownColor: bd.sheet,
                  style: T.row(bd),
                  items: [for (final c in knownCountries) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
                  onChanged: (v) => setState(() {
                    _country = v ?? 'IN';
                    _nation = null;
                    _region.clear();
                  }),
                ),
              ),
            ),
            if (_country == 'GB') ...[
              const SizedBox(height: S.m),
              Wrap(spacing: S.s, runSpacing: S.s, children: [
                for (final n in _ukNations) BdChip(n.$2, active: _nation == n.$1, onTap: () => setState(() => _nation = n.$1)),
              ]),
            ],
            if (_country == 'US' || _country == 'IN') ...[
              const SizedBox(height: S.l),
              LineField(
                controller: _region,
                label: _country == 'US' ? 'State (two letters)' : 'State (optional)',
                hint: _country == 'US' ? 'NY' : 'KA',
                caps: TextCapitalization.characters,
                maxLength: 3,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: S.xl),
            Glass(
              padding: const EdgeInsets.all(S.l),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Ph.scales, size: 20, color: bd.muted),
                const SizedBox(width: S.m),
                Expanded(child: Text(_lawNote(), style: T.sans(bd, size: 14, color: bd.muted, height: 1.5))),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: S.m),
              Semantics(liveRegion: true, child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
            ],
            const SizedBox(height: S.xl),
            BdButton('Create venue', busy: _busy, onTap: _create),
            const SizedBox(height: S.m),
            Text('Next: ask us to verify you (Setup). Until then rooms and the menu draft work, but loyalty rewards and tabs wait.', style: T.caption(bd)),
            const SizedBox(height: S.x3),
          ],
        ),
      ),
    );
  }
}
