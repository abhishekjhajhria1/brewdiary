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

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/drinks.dart';
import 'package:brewdiary_core/game.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/circles.dart';
import '../../data/entries.dart';
import '../../data/parties.dart';
import '../theme.dart';
import 'common.dart';
import 'game.dart';
import '../screens/photo_studio.dart';
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
  Unlocks? _unlocks;
  Timer? _unlockTimer;
  String? _editingId;
  Entry? _pendingDelete;
  Timer? _deleteTimer;
  String? _shareFor;

  @override
  void initState() {
    super.initState();
    _drinkFocus.addListener(() => setState(() {}));
    // On an empty day, go straight to typing once the sheet has settled. A day
    // that already has entries opens on them instead (to review, edit, share).
    if (_dayEntries.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) _drinkFocus.requestFocus();
          }));
    }
  }

  @override
  void dispose() {
    // Closing the sheet commits any still-pending remove.
    _unlockTimer?.cancel();
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
      final before = passportGame(entryStore.entries);
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
      _celebrate(before);
    }
    _reset();
    _flashLogged();
    _drinkFocus.requestFocus();
  }

  /// A dry day is a thing you DID — it keeps the streak and earns a spark, but is
  /// never counted as a drink. Only offered on a day with nothing logged yet.
  void _logDryDay() {
    HapticFeedback.lightImpact();
    final before = passportGame(entryStore.entries);
    entryStore.addEntry(date: widget.dateKey, drink: dryDayLabel, type: DrinkType.none, mood: _clean(_mood));
    _celebrate(before);
    _reset();
    _flashLogged();
  }

  /// What that save earned on the passport — a strip above the button for a few
  /// seconds, and a proper moment for a new rank.
  void _celebrate(PassportGame before) {
    final u = unlocksBetween(before, passportGame(entryStore.entries));
    if (u.isEmpty) return;
    HapticFeedback.mediumImpact();
    _unlockTimer?.cancel();
    setState(() => _unlocks = u);
    _unlockTimer = Timer(const Duration(milliseconds: 4200), () {
      if (mounted) setState(() => _unlocks = null);
    });
    final up = u.rankUp;
    if (up != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showRankUp(context, up);
      });
    }
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
        final count = visible.length;

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // header
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: S.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(formatDayLong(widget.dateKey), style: T.title(bd))),
                  const SizedBox(height: 4),
                  Text('${weekdaysLong[mondayIndex(d)]}${count > 0 ? ' · $count logged' : ''}', style: T.caption(bd)),
                ]),
              ),
            ),
            IconBtn(Ph.x, tooltip: 'Close', onTap: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: S.l),

          if (widget.plans.isNotEmpty) ...[
            Glass(
              padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Ph.calendarCheck, size: 16, color: bd.accentText),
                  const SizedBox(width: 6),
                  Text('Planned for this day', style: T.sans(bd, size: 13, weight: FontWeight.w600, color: bd.accentText)),
                ]),
                for (final p in widget.plans)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Expanded(child: Text(p.title, overflow: TextOverflow.ellipsis, style: T.row(bd))),
                      if (p.time != null) Text(p.time!.length >= 5 ? p.time!.substring(0, 5) : p.time!, style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: S.l),
          ],

          if (_pendingDelete != null) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(S.l, 2, 4, 2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), color: bd.ink.withValues(alpha: .06), border: Border.all(color: bd.line, width: .8)),
              child: Row(children: [
                Icon(Ph.trash, size: 17, color: bd.muted),
                const SizedBox(width: S.s),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Removed ', style: T.sans(bd, size: 14, color: bd.muted)),
                      TextSpan(text: _pendingDelete!.drink, style: T.sans(bd, size: 14)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextAction('Undo', accent: true, onTap: _undoRemove),
              ]),
            ),
            const SizedBox(height: S.l),
          ],

          if (visible.isNotEmpty) ...[
            Group(children: [for (final e in visible) _entryRow(e)]),
            const SizedBox(height: S.xxl),
          ],

          // What
          Label(_editingId != null ? 'Editing — what was it?' : 'What did you drink?'),
          const SizedBox(height: 4),
          LineField(
            controller: _drink,
            focusNode: _drinkFocus,
            size: 18,
            hint: 'A flat white, a negroni, a homebrew…',
            action: TextInputAction.done,
            onChanged: (_) => setState(() => _picked = false),
            onSubmitted: (_) => _submit(),
          ),
          if (showCanon)
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => _pick(canon.canonical),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: S.tap),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('≈ ', style: T.sans(bd, size: 14, color: bd.muted)),
                    Text(canon.canonical, style: T.sans(bd, size: 14, weight: FontWeight.w600)),
                    Text(' · tap to use', style: T.sans(bd, size: 14, color: bd.muted)),
                  ]),
                ),
              ),
            ),
          if (showSuggestions)
            Padding(
              padding: const EdgeInsets.only(top: S.s),
              child: Glass(
                radius: rCtl,
                padding: const EdgeInsets.symmetric(horizontal: S.l),
                child: Hairlines(children: [
                  for (final sug in suggestions)
                    Pressable(
                      onTap: () => _pick(sug),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.centerLeft,
                        child: Row(children: [
                          Expanded(child: Text(sug, style: T.row(bd))),
                          Icon(Ph.arrowUpRight, size: 15, color: bd.faint),
                        ]),
                      ),
                    ),
                ]),
              ),
            )
          else if (typing.isEmpty && widget.recentDrinks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: S.xs),
              child: Wrap(spacing: S.s, children: [
                for (final r in widget.recentDrinks) BdChip(r, active: _drink.text == r, onTap: () => _pick(r)),
              ]),
            ),

          // Mood
          const SizedBox(height: S.xl),
          const Label('A word for it?'),
          const SizedBox(height: 4),
          LineField(controller: _mood, size: 18, italic: true, hint: 'cozy, celebratory, ordinary…', caps: TextCapitalization.none, action: TextInputAction.done, onSubmitted: (_) => _submit(), onChanged: (_) => setState(() {})),
          if (widget.recentMoods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: S.xs),
              child: Wrap(spacing: S.s, children: [
                for (final r in widget.recentMoods) BdChip(r, active: _mood.text == r, onTap: () => setState(() => _mood.text = _mood.text == r ? '' : r)),
              ]),
            ),

          // Optionals
          const SizedBox(height: S.m),
          if (!_showMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction('Add a note, photo, place, who, kind', icon: Ph.plusCircle, onTap: () => setState(() => _showMore = true)),
            )
          else
            Container(
              margin: const EdgeInsets.only(top: S.s),
              padding: const EdgeInsets.only(top: S.xl),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line, width: .8))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Label('Note'),
                const SizedBox(height: S.s),
                GlassField(controller: _note, hint: 'A line about the moment…', maxLines: 3),
                const SizedBox(height: S.xl),
                Row(children: [
                  const Label('Photos'),
                  const Spacer(),
                  if (auth.isAuthed && db != null) Text('kept for a year', style: T.caption(context.bd)),
                ]),
                const SizedBox(height: S.s),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  for (final p in _photos) _photoTile(p),
                  if (_photos.length < 4)
                    Semantics(
                      button: true,
                      label: 'Add a photo',
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: _addPhotos,
                        child: Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: bd.glass, borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.lineStrong, width: .8)),
                          child: Icon(Ph.camera, size: 24, color: bd.muted),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: S.xl),
                const Label('Where'),
                const SizedBox(height: S.s),
                GlassField(controller: _venue, hint: 'Home, a bar, a city…', icon: Ph.mapPin, caps: TextCapitalization.words),
                const SizedBox(height: S.xl),
                const Label('Who with'),
                const SizedBox(height: S.s),
                GlassField(controller: _who, hint: 'Names, separated by commas', icon: Ph.users, caps: TextCapitalization.words),
                const SizedBox(height: S.xl),
                const Label('Kind'),
                const SizedBox(height: S.xs),
                Wrap(spacing: S.s, children: [
                  for (final t in drinkTypes) BdChip(t.$2, active: _type == t.$1, onTap: () => setState(() => _type = _type == t.$1 ? null : t.$1)),
                ]),
              ]),
            ),

          const SizedBox(height: S.xxl),
          if (_editingId != null)
            Row(children: [
              Expanded(child: BdButton('Cancel', kind: BtnKind.secondary, onTap: _reset)),
              const SizedBox(width: S.m),
              Expanded(child: BdButton('Save', onTap: _drink.text.trim().isEmpty ? null : _submit)),
            ])
          else ...[
            AnimatedSize(
              duration: Motion.med,
              curve: Motion.curve,
              child: _unlocks == null ? const SizedBox(width: double.infinity) : Padding(padding: const EdgeInsets.only(bottom: S.m), child: UnlockStrip(_unlocks!)),
            ),
            BdButton(
              _justLogged ? 'Logged' : 'Log',
              icon: _justLogged ? PhBold.check : null,
              onTap: _drink.text.trim().isEmpty ? null : _submit,
            ),
          ],
          if (dayIsEmpty) ...[
            const SizedBox(height: S.s),
            BdButton('Nothing today — log a dry day', kind: BtnKind.secondary, icon: Ph.drop, onTap: _logDryDay),
            const SizedBox(height: S.s),
            Text('A dry day keeps your streak — it never counts as a drink.', textAlign: TextAlign.center, style: T.caption(bd)),
          ],
        ]);
      },
    );
  }

  Widget _photoTile(Photo p) {
    final bd = context.bd;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rCtl),
            child: ColoredBox(
              color: bd.glass, // shows while a remote photo loads
              child: p.isLocal ? Image.file(File(p.url), fit: BoxFit.cover) : Image.network(p.url, fit: BoxFit.cover),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Semantics(
            button: true,
            label: 'Remove photo',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _photos = _photos.where((x) => x.id != p.id).toList()),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.all(5),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), shape: BoxShape.circle),
                    child: const Icon(PhBold.x, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _entryActions(Entry e) {
    final signedIn = auth.isAuthed && db != null;
    return showActions(context, title: e.drink, actions: [
      SheetAction('Edit', icon: Ph.pencilSimple, onTap: () => _loadForEdit(e)),
      if (signedIn) SheetAction(_shareFor == e.id ? 'Hide sharing' : 'Share with friends…', icon: Ph.usersThree, onTap: () => setState(() => _shareFor = _shareFor == e.id ? null : e.id)),
      SheetAction('Share with a photo', icon: Ph.camera, onTap: () => showPhotoStudio(context, NightStory.fromEntry(e), photo: e.photos?.firstOrNull?.url)),
      SheetAction('Share as a card', icon: Ph.image, onTap: () => showShareCard(context, e)),
      SheetAction('Remove', icon: Ph.trash, destructive: true, onTap: () => _requestRemove(e)),
    ]);
  }

  Widget _entryRow(Entry e) {
    final bd = context.bd;
    final signedIn = auth.isAuthed && db != null;
    final editing = _editingId == e.id;
    final shared = e.visibility == EntryVisibility.friends;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Edit ${e.drink}',
            child: Pressable(
              onTap: () => _loadForEdit(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.drink, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd, color: editing ? bd.accentText : bd.ink)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          if (editing) TextSpan(text: 'Editing · ', style: T.caption(bd, color: bd.accentText)),
                          if (e.mood != null) TextSpan(text: '${e.mood} · ', style: T.caption(bd).copyWith(fontStyle: FontStyle.italic)),
                          TextSpan(text: timeOfDayLabel(e.createdAt), style: T.caption(bd)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (shared) ...[
                      const SizedBox(width: 6),
                      Icon(Ph.usersThree, size: 13, color: bd.accentText),
                      const SizedBox(width: 3),
                      Text('Shared', style: T.caption(bd, color: bd.accentText)),
                    ],
                  ]),
                ]),
              ),
            ),
          ),
        ),
        IconBtn(Ph.dotsThree, tooltip: 'More for ${e.drink}', color: bd.muted, onTap: () => _entryActions(e)),
      ]),
      if (_shareFor == e.id && signedIn) Padding(padding: const EdgeInsets.only(bottom: S.m), child: _ShareRow(entry: e, dateKey: widget.dateKey)),
    ]);
  }
}

/// One row of audiences — all friends, each circle, each (recent) party.
class _ShareRow extends StatelessWidget {
  final Entry entry;
  final String dateKey;
  const _ShareRow({required this.entry, required this.dateKey});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
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
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Share this entry with', style: T.caption(bd)),
            Wrap(spacing: S.s, children: [
              BdChip('Friends', icon: friendsOn ? PhBold.check : Ph.usersThree, active: friendsOn, onTap: () => entryStore.setVisibility(entry.id, friendsOn ? EntryVisibility.private : EntryVisibility.friends)),
              for (final c in circles)
                BdChip(c.name, icon: inCircles.contains(c.id) ? PhBold.check : null, active: inCircles.contains(c.id), onTap: () => inCircles.contains(c.id) ? CirclesApi.unshare(entry.id, c.id) : CirclesApi.share(entry.id, c.id)),
              for (final p in parties)
                BdChip(p.name, icon: inParties.contains(p.id) ? PhBold.check : Ph.confetti, active: inParties.contains(p.id), onTap: () => inParties.contains(p.id) ? PartiesApi.unshare(entry.id, p.id) : PartiesApi.share(entry.id, p.id)),
            ]),
          ]);
        },
      ),
    );
  }
}
