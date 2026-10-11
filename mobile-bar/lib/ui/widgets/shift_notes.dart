// The pre-shift note (058): what the shift lead wants everyone to know tonight ("walk-in
// is off — push the paneer", "party of 12 at 9"). It sits at the top of wherever each
// role lands — the floor, the till, the kitchen — until the end of the night. Everyone
// taps "Got it"; the shift lead and managers see who has, by name, in name order — never
// a ranking. They write it from here too.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import 'bits.dart';
import 'common.dart';

String timeWord(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

String namesWord(List<String> names) => switch (names.length) {
      0 => 'Nobody else has seen it yet.',
      1 => 'Seen by ${names.first}.',
      2 => 'Seen by ${names.first} and ${names.last}.',
      _ => 'Seen by ${names.sublist(0, names.length - 1).join(', ')} and ${names.last}.',
    };

class ShiftNotesCard extends StatelessWidget {
  final Venue venue;
  const ShiftNotesCard({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final lead = Session.instance.can(Cap.approveVoids);
    return Loader<ShiftNotes>(
      load: () => Backend.i.shiftNotes(venue.id),
      refresh: notesRev,
      builder: (context, notes, loading) {
        if (notes == null) return const SizedBox.shrink();
        if (notes.preshift.isEmpty) {
          if (!lead) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: S.l),
            child: Align(alignment: Alignment.centerLeft, child: BdChip('Write tonight\'s pre-shift note', icon: Ph.clipboardText, onTap: () => writeNote(context, venue, 'preshift'))),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final n in notes.preshift) Padding(padding: const EdgeInsets.only(bottom: S.l), child: Reveal(child: _NoteCard(note: n, lead: lead))),
        ]);
      },
    );
  }
}

class _NoteCard extends StatefulWidget {
  final ShiftNote note;
  final bool lead;
  const _NoteCard({required this.note, required this.lead});
  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  /// Once you've got it, the note folds to one line for the rest of the night — a tap
  /// opens it again.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final note = widget.note;
    final lead = widget.lead;
    if (note.seenByMe && !_open) {
      return Semantics(
        button: true,
        label: 'Pre-shift note from ${note.author}: ${note.body}. Tap to open.',
        excludeSemantics: true,
        child: Glass(
          onTap: () => setState(() => _open = true),
          padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.m),
          child: Row(children: [
            Icon(Ph.clipboardText, size: 18, color: bd.accentText),
            const SizedBox(width: S.s),
            Expanded(child: Text(note.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 15))),
            const SizedBox(width: S.s),
            Icon(Ph.caretDown, size: 16, color: bd.faint),
          ]),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(S.l),
      decoration: BoxDecoration(color: bd.accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(rTile), border: Border.all(color: bd.accent.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Ph.clipboardText, size: 18, color: bd.accentText),
          const SizedBox(width: S.s),
          Expanded(child: Text('PRE-SHIFT · ${note.author.toUpperCase()} · ${timeWord(note.createdAt).toUpperCase()}', style: T.label(bd, color: bd.accentText))),
        ]),
        const SizedBox(height: S.s),
        Text(note.body, style: T.serif(bd, size: 19, height: 1.35)),
        const SizedBox(height: S.m),
        Row(children: [
          Expanded(
            child: note.seenBy != null
                ? Text(namesWord(note.seenBy!), style: T.caption(bd))
                : (note.seenByMe ? Text('You\'ve got it.', style: T.caption(bd)) : const SizedBox.shrink()),
          ),
          if (!note.seenByMe) BdButton('Got it', expand: false, height: 40, icon: Ph.check, kind: BtnKind.secondary, onTap: () => runAction(context, () => Backend.i.markNoteSeen(note.id))),
          if (lead && note.seenByMe) TextAction('Take down', onTap: () async {
            final yes = await confirm(context, title: 'Take the note down?', body: 'It stays in the record; it just stops showing tonight.', yes: 'Take down');
            if (yes && context.mounted) await runAction(context, () => Backend.i.endNote(note.id));
          }),
          if (note.seenByMe) IconBtn(Ph.caretUp, tooltip: 'Fold the note', color: bd.faint, onTap: () => setState(() => _open = false)),
        ]),
      ]),
    );
  }
}

/// Write a pre-shift note or a log entry.
Future<void> writeNote(BuildContext context, Venue venue, String kind) async {
  final body = TextEditingController();
  final post = await showBdSheet<bool>(context, title: kind == 'preshift' ? 'Tonight\'s pre-shift note' : 'A log entry', builder: (ctx) {
    final bd = ctx.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        kind == 'preshift'
            ? 'Everyone on the team sees it at the top of their screen until the end of the night, and taps "Got it".'
            : 'For the next manager: what broke, who called, what\'s owed. Only supervisors and managers read the log.',
        style: T.bodyMuted(bd),
      ),
      if (kind == 'preshift') ...[
        const SizedBox(height: S.m),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final start in const ['86 tonight: ', 'Big party at ', 'Alcohol-free pick: ', 'Short-staffed: ']) BdChip(start.trim(), onTap: () {
                body.text = start;
                body.selection = TextSelection.collapsed(offset: start.length);
              }),
        ]),
      ],
      const SizedBox(height: S.l),
      LineField(controller: body, label: kind == 'preshift' ? 'The note' : 'The entry', maxLines: 5, maxLength: 1000, autofocus: true),
      const SizedBox(height: S.l),
      BdButton(kind == 'preshift' ? 'Put it up' : 'Add to the log', onTap: () => Navigator.pop(ctx, true)),
    ]);
  });
  final text = body.text.trim();
  body.dispose();
  if (post != true || !context.mounted) return;
  await runAction(context, () => Backend.i.postNote(venue.id, newId(), kind, text), done: kind == 'preshift' ? 'Up for tonight.' : 'Logged.');
}
