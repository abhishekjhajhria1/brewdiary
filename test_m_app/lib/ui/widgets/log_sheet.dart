// The log window — a port of src/components/log/LogSheet.tsx. Tap a day, log a drink
// in a breath. Autocomplete from your own history first, a gentle "≈ tidy name"
// nudge, optional note/photos/place/who/kind, an undoable remove, and a dry-day
// action that keeps the streak. Sharing is a separate deliberate act per entry.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/date.dart';
import '../../core/drinks.dart';
import '../../core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/circles.dart';
import '../../data/entries.dart';
import '../../data/parties.dart';
import '../theme.dart';
import 'common.dart';
import 'share_card.dart';

Future<void> showLogSheet(
  BuildContext context, {
  required String dateKey,
  List<({String title, String? time})> plans = const [],
  required List<String> recentDrinks,
  required List<String> recentMoods,
}) {
  return showBdSheet(
    context,
    builder: (_) => LogSheet(dateKey: dateKey, plans: plans, recentDrinks: recentDrinks, recentMoods: recentMoods),
  );
}

class LogSheet extends StatefulWidget {
  final String dateKey;
  final List<({String title, String? time})> plans;
  final List<String> recentDrinks;
  final List<String> recentMoods;
  const LogSheet({super.key, required this.dateKey, this.plans = const [], required this.recentDrinks, required this.recentMoods});
  @override
  State<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<LogSheet> {
  final _drink = TextEditingController();
  final _mood = TextEditingController();
  final _note = TextEditingController();
  final _venue = TextEditingController();
  final _who = TextEditingController();
  final _drinkFocus = FocusNode();

  bool _picked = false; // just accepted a name → hush suggestions till they type again
  bool _showMore = false;
  DrinkType? _type;
  List<Photo> _photos = [];
  bool _justLogged = false;
  String? _editingId;
  Entry? _pendingDelete;
  Timer? _deleteTimer;
  String? _shareFor;

  @override
  void initState() {
    super.initState();
    _drinkFocus.addListener(() => setState(() {}));
    // Focus the drink field once the sheet has settled.
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _drinkFocus.requestFocus();
        }));
  }

  @override
  void dispose() {
    // Closing the sheet commits any still-pending remove.
    _deleteTimer?.cancel();
    if (_pendingDelete != null) entryStore.deleteEntry(_pendingDelete!.id);
    for (final c in [_drink, _mood, _note, _venue, _who]) {
      c.dispose();
    }
    _drinkFocus.dispose();
    super.dispose();
  }

  List<Entry> get _dayEntries => entryStore.entries.where((e) => e.date == widget.dateKey).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Your full drink vocabulary (distinct, most-recent-first) powers autocomplete.
  List<String> get _history {
    final seen = <String>{};
    final out = <String>[];
    final sorted = [...entryStore.entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final e in sorted) {
      final name = e.drink.trim();
      if (name.isNotEmpty && seen.add(name.toLowerCase())) out.add(name);
    }
    return out;
  }

  void _reset() {
    _drink.clear();
    _mood.clear();
    _note.clear();
    _venue.clear();
    _who.clear();
    setState(() {
      _type = null;
      _photos = [];
      _showMore = false;
      _editingId = null;
    });
  }

  void _loadForEdit(Entry e) {
    setState(() {
      _editingId = e.id;
      _drink.text = e.drink;
      _picked = true;
      _mood.text = e.mood ?? '';
      _note.text = e.note ?? '';
      _venue.text = e.venue ?? '';
      _who.text = e.whoWith?.join(', ') ?? '';
      _type = e.type;
      _photos = [...?e.photos];
      _showMore = (e.note?.isNotEmpty ?? false) || (e.venue?.isNotEmpty ?? false) || (e.whoWith?.isNotEmpty ?? false) || e.type != null || (e.photos?.isNotEmpty ?? false);
    });
    _drinkFocus.requestFocus();
  }

  void _pick(String name) {
    setState(() {
      _drink.text = name;
      _drink.selection = TextSelection.collapsed(offset: name.length);
      _picked = true;
      _type ??= canonicalize(name).type;
    });
  }

  String? _clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _submit() {
    if (_drink.text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final who = _who.text.trim().isEmpty ? null : _who.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (_editingId != null) {
      final prev = entryStore.entries.where((e) => e.id == _editingId).firstOrNull;
      if (prev != null) {
        final photosChanged = prev.photos?.map((p) => p.id).join(',') != _photos.map((p) => p.id).join(',');
        entryStore.updateEntry(
          prev.copyWith(
            drink: _drink.text.trim(),
            mood: () => _clean(_mood),
            note: () => _clean(_note),
            venue: () => _clean(_venue),
            type: () => _type,
            whoWith: () => who,
            photos: () => _photos.isEmpty ? null : _photos,
          ),
          photosChanged: photosChanged,
        );
      }
    } else {
      entryStore.addEntry(
        date: widget.dateKey,
        drink: _drink.text,
        mood: _clean(_mood),
        note: _clean(_note),
        venue: _clean(_venue),
        type: _type,
        whoWith: who,
        photos: _photos.isEmpty ? null : _photos,
      );
    }
    _reset();
    _flashLogged();
    _drinkFocus.requestFocus();
  }

  /// A dry day is a thing you DID — it keeps the streak and earns a spark, but is
  /// never counted as a drink. Only offered on a day with nothing logged yet.
  void _logDryDay() {
    HapticFeedback.lightImpact();
    entryStore.addEntry(date: widget.dateKey, drink: dryDayLabel, type: DrinkType.none, mood: _clean(_mood));
    _reset();
    _flashLogged();
  }

  void _flashLogged() {
    setState(() => _justLogged = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _justLogged = false);
    });
  }

  void _requestRemove(Entry e) {
    if (_pendingDelete != null && _pendingDelete!.id != e.id) entryStore.deleteEntry(_pendingDelete!.id);
    _deleteTimer?.cancel();
    if (_editingId == e.id) _reset();
    setState(() => _pendingDelete = e);
    _deleteTimer = Timer(const Duration(seconds: 5), () {
      if (_pendingDelete != null) entryStore.deleteEntry(_pendingDelete!.id);
      if (mounted) setState(() => _pendingDelete = null);
    });
  }

  void _undoRemove() {
    _deleteTimer?.cancel();
    setState(() => _pendingDelete = null);
  }

  Future<void> _addPhotos() async {
    final remaining = 4 - _photos.length;
    if (remaining <= 0) return;
    try {
      final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 82, limit: remaining);
      if (picked.isEmpty) return;
      // Copy into the app's own storage so a local (signed-out) entry keeps its photo.
      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/photos');
      if (!photosDir.existsSync()) photosDir.createSync(recursive: true);
      final added = <Photo>[];
      for (final x in picked.take(remaining)) {
        final id = newId();
        final dest = '${photosDir.path}/$id.jpg';
        await File(x.path).copy(dest);
        added.add(Photo(id: id, url: dest));
      }
      setState(() => _photos = [..._photos, ...added].take(4).toList());
    } catch (e) {
      if (mounted) toast(context, "Couldn't open your photos.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: entryStore,
      builder: (context, _) {
        final d = parseKey(widget.dateKey);
        final visible = _dayEntries.where((e) => e.id != _pendingDelete?.id).toList();
        final typing = _drink.text.trim();
        final suggestions = typing.isNotEmpty && !_picked ? suggestDrinks(_drink.text, _history, 6) : <String>[];
        final showSuggestions = _drinkFocus.hasFocus && !_picked && suggestions.isNotEmpty;
        final canon = typing.isNotEmpty ? canonicalize(typing) : null;
        final showCanon = !_picked && canon != null && canon.matched && canon.canonical.toLowerCase() != typing.toLowerCase();
        final dayIsEmpty = _dayEntries.isEmpty && _editingId == null;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // header
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatDayLong(widget.dateKey), style: T.serif(bd, size: 32)),
                const SizedBox(height: 4),
                Label(weekdaysLong[mondayIndex(d)]),
              ]),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(padding: const EdgeInsets.all(6), child: Text('×', style: T.sans(bd, size: 26, color: bd.muted))),
            ),
          ]),
          const SizedBox(height: 18),

          if (widget.plans.isNotEmpty) ...[
            Glass(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Label('Planned for this day', color: bd.accent),
                for (final p in widget.plans)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Expanded(child: Text(p.title, overflow: TextOverflow.ellipsis, style: T.sans(bd))),
                      if (p.time != null) Text(p.time!.length >= 5 ? p.time!.substring(0, 5) : p.time!, style: T.sans(bd, size: 12, color: bd.faint)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
          ],

          if (_pendingDelete != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.line)),
              child: Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: 'Removed ', style: T.sans(bd, size: 14, color: bd.muted)),
                    TextSpan(text: _pendingDelete!.drink, style: T.sans(bd, size: 14)),
                  ])),
                ),
                TextAction('Undo', accent: true, onTap: _undoRemove),
              ]),
            ),
            const SizedBox(height: 18),
          ],

          if (visible.isNotEmpty) ...[
            Hairlines(children: [for (final e in visible) _entryRow(e)]),
            const SizedBox(height: 18),
          ],

          // What
          const Label('What did you drink?'),
          const SizedBox(height: 6),
          LineField(
            controller: _drink,
            focusNode: _drinkFocus,
            size: 18,
            hint: 'A flat white, a negroni, a homebrew…',
            onChanged: (_) => setState(() => _picked = false),
            onSubmitted: (_) => _submit(),
          ),
          if (showCanon)
            GestureDetector(
              onTap: () => _pick(canon.canonical),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '≈ ', style: T.sans(bd, size: 12, color: bd.muted)),
                  TextSpan(text: canon.canonical, style: T.sans(bd, size: 12)),
                  TextSpan(text: ' · tap to use', style: T.sans(bd, size: 12, color: bd.muted)),
                ])),
              ),
            ),
          if (showSuggestions)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.line)),
              child: Column(children: [
                for (var i = 0; i < suggestions.length; i++)
                  InkWell(
                    onTap: () => _pick(suggestions[i]),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: i == suggestions.length - 1 ? null : Border(bottom: BorderSide(color: bd.line))),
                      child: Text(suggestions[i], style: T.sans(bd)),
                    ),
                  ),
              ]),
            )
          else if (typing.isEmpty && widget.recentDrinks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in widget.recentDrinks) BdChip(r, active: _drink.text == r, onTap: () => _pick(r)),
              ]),
            ),

          // Mood
          const SizedBox(height: 24),
          const Label('A word for it?'),
          const SizedBox(height: 6),
          LineField(controller: _mood, size: 18, italic: true, hint: 'cozy, celebratory, ordinary…', caps: TextCapitalization.none, onSubmitted: (_) => _submit(), onChanged: (_) => setState(() {})),
          if (widget.recentMoods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in widget.recentMoods) BdChip(r, active: _mood.text == r, onTap: () => setState(() => _mood.text = r)),
              ]),
            ),

          // Optionals
          const SizedBox(height: 24),
          if (!_showMore)
            GestureDetector(
              onTap: () => setState(() => _showMore = true),
              child: Text('add note · photo · place · who · kind', style: T.sans(bd, size: 14, color: bd.muted)),
            )
          else
            Container(
              padding: const EdgeInsets.only(top: 20),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Label('Note'),
                const SizedBox(height: 6),
                GlassField(controller: _note, hint: 'A line about the moment…', maxLines: 3),
                const SizedBox(height: 20),
                const Label('Photos'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in _photos)
                    Stack(clipBehavior: Clip.none, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(rCtl),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: p.isLocal ? Image.file(File(p.url), fit: BoxFit.cover) : Image.network(p.url, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: GestureDetector(
                          onTap: () => setState(() => _photos = _photos.where((x) => x.id != p.id).toList()),
                          child: Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: bd.ink, shape: BoxShape.circle),
                            child: Text('×', style: T.sans(bd, size: 12, color: bd.base, height: 1)),
                          ),
                        ),
                      ),
                    ]),
                  if (_photos.length < 4)
                    GestureDetector(
                      onTap: _addPhotos,
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.lineStrong)),
                        child: Text('+', style: T.sans(bd, size: 22, color: bd.faint)),
                      ),
                    ),
                ]),
                const SizedBox(height: 20),
                const Label('Where'),
                const SizedBox(height: 6),
                GlassField(controller: _venue, hint: 'Home, a bar, a city…'),
                const SizedBox(height: 20),
                const Label('Who with'),
                const SizedBox(height: 6),
                GlassField(controller: _who, hint: 'Comma-separated names', caps: TextCapitalization.words),
                const SizedBox(height: 20),
                const Label('Kind'),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in drinkTypes) BdChip(t.$2, active: _type == t.$1, onTap: () => setState(() => _type = _type == t.$1 ? null : t.$1)),
                ]),
              ]),
            ),

          if (_editingId != null) Padding(padding: const EdgeInsets.only(top: 20), child: TextAction('cancel edit', onTap: _reset)),
          const SizedBox(height: 12),
          InkButton(
            _editingId != null ? 'Save changes' : (_justLogged ? 'Logged ✓' : 'Log'),
            uppercase: false,
            onTap: _drink.text.trim().isEmpty ? null : _submit,
          ),
          if (dayIsEmpty) ...[
            const SizedBox(height: 8),
            LineButton('Nothing today — log a dry day', onTap: _logDryDay),
          ],
        ]);
      },
    );
  }

  Widget _entryRow(Entry e) {
    final bd = context.bd;
    final signedIn = auth.isAuthed && db != null;
    final editing = _editingId == e.id;
    final shared = e.visibility == EntryVisibility.friends;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _loadForEdit(e),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(e.drink, overflow: TextOverflow.ellipsis, style: T.sans(bd, color: editing ? bd.accent : bd.ink))),
                  if (editing) const Padding(padding: EdgeInsets.only(left: 8), child: Label('editing')),
                ]),
                const SizedBox(height: 2),
                Text.rich(TextSpan(children: [
                  if (e.mood != null) TextSpan(text: '${e.mood} · ', style: T.sans(bd, size: 12, color: bd.muted).copyWith(fontStyle: FontStyle.italic)),
                  TextSpan(text: timeOfDayLabel(e.createdAt), style: T.sans(bd, size: 12, color: bd.muted)),
                ])),
              ]),
            ),
          ),
          if (signedIn) TextAction(shared ? 'Shared' : 'Share', accent: shared || _shareFor == e.id, onTap: () => setState(() => _shareFor = _shareFor == e.id ? null : e.id)),
          const SizedBox(width: 10),
          TextAction('Card', onTap: () => showShareCard(context, e)),
          const SizedBox(width: 10),
          TextAction('Remove', faint: true, onTap: () => _requestRemove(e)),
        ]),
        if (_shareFor == e.id && signedIn) _ShareRow(entry: e, dateKey: widget.dateKey),
      ]),
    );
  }
}

/// One row of audiences — all friends, each circle, each (recent) party.
class _ShareRow extends StatelessWidget {
  final Entry entry;
  final String dateKey;
  const _ShareRow({required this.entry, required this.dateKey});

  @override
  Widget build(BuildContext context) {
    final friendsOn = entry.visibility == EntryVisibility.friends;
    final cutoff = toKey(addDays(parseKey(dateKey), -14));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Loader<(List<Circle>, List<Party>, Set<String>, Set<String>)>(
        refresh: Listenable.merge([circlesRev, partiesRev]),
        load: () async {
          final r = await Future.wait<Object>([
            CirclesApi.mine(),
            PartiesApi.mine(),
            CirclesApi.sharesForEntry(entry.id),
            PartiesApi.sharesForEntry(entry.id),
          ]);
          return (
            r[0] as List<Circle>,
            (r[1] as List<Party>).where((p) => p.date.compareTo(cutoff) >= 0).toList(),
            r[2] as Set<String>,
            r[3] as Set<String>,
          );
        },
        builder: (context, data, loading) {
          final circles = data?.$1 ?? const <Circle>[];
          final parties = data?.$2 ?? const <Party>[];
          final inCircles = data?.$3 ?? const <String>{};
          final inParties = data?.$4 ?? const <String>{};
          return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Padding(padding: EdgeInsets.only(right: 4), child: Label('to')),
            BdChip(friendsOn ? 'Friends ✓' : 'Friends', active: friendsOn, onTap: () => entryStore.setVisibility(entry.id, friendsOn ? EntryVisibility.private : EntryVisibility.friends)),
            for (final c in circles)
              BdChip(inCircles.contains(c.id) ? '${c.name} ✓' : c.name,
                  active: inCircles.contains(c.id), onTap: () => inCircles.contains(c.id) ? CirclesApi.unshare(entry.id, c.id) : CirclesApi.share(entry.id, c.id)),
            for (final p in parties)
              BdChip(inParties.contains(p.id) ? '${p.name} ✓' : p.name,
                  active: inParties.contains(p.id), onTap: () => inParties.contains(p.id) ? PartiesApi.unshare(entry.id, p.id) : PartiesApi.share(entry.id, p.id)),
          ]);
        },
      ),
    );
  }
}
