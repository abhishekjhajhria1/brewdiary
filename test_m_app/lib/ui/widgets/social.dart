// Pieces shared by the social screens (Together, circles, parties, plans): an
// invite code with copy/share, a points row, the person-safety actions (report,
// block), and the report sheet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/base.dart';
import '../../data/safety.dart';
import '../theme.dart';
import 'common.dart';

/// An invite code you can copy — and share as a message when `shareText` is given.
class InviteCodeCard extends StatelessWidget {
  final String label;
  final String code;
  final String? shareText;

  /// The invite as a link (the website's "Copy link").
  final String? link;
  const InviteCodeCard({super.key, this.label = 'Invite code', required this.code, this.shareText, this.link});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.xs, S.m),
      child: Row(children: [
        Icon(Ph.ticket, size: 22, color: bd.muted),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: T.caption(bd)),
            const SizedBox(height: 2),
            SelectableText(code, maxLines: 1, style: T.sans(bd, size: 18, weight: FontWeight.w600, spacing: 1.5).copyWith(fontFeatures: T.tnum)),
          ]),
        ),
        IconBtn(Ph.copy, tooltip: 'Copy the code', color: bd.muted, onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          toast(context, 'Code copied');
        }),
        if (link != null)
          IconBtn(Ph.linkSimple, tooltip: 'Copy the link', color: bd.muted, onTap: () {
            Clipboard.setData(ClipboardData(text: link!));
            toast(context, 'Link copied');
          }),
        if (shareText != null) IconBtn(Ph.shareNetwork, tooltip: 'Share the invite', color: bd.muted, onTap: () => SharePlus.instance.share(ShareParams(text: shareText!))),
      ]),
    );
  }
}

/// One line of a points board: rank · face · name · sparks (+ vibe) · an optional
/// action, with a thin bar against the leader when [top] is given.
class PointsRow extends StatelessWidget {
  final int rank;
  final String name;
  final int sparks;
  final int vibe;
  final bool leads;
  final int? top;
  final Widget? trailing;
  const PointsRow({super.key, required this.rank, required this.name, required this.sparks, required this.vibe, this.leads = false, this.top, this.trailing});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final t = top;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(children: [
        SizedBox(width: 24, child: Text('$rank', style: T.sans(bd, size: 13, weight: FontWeight.w600, color: leads ? bd.accentText : bd.faint).copyWith(fontFeatures: T.tnum))),
        Initial(name.isEmpty ? '?' : name.characters.first.toUpperCase(), size: 30),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd))),
              Text.rich(TextSpan(children: [
                TextSpan(text: '$sparks', style: T.sans(bd, size: 15, weight: FontWeight.w600, color: leads ? bd.accentText : bd.ink).copyWith(fontFeatures: T.tnum)),
                TextSpan(text: ' sparks', style: T.caption(bd)),
                if (vibe > 0) ...[
                  TextSpan(text: '   $vibe', style: T.sans(bd, size: 15, weight: FontWeight.w600, color: bd.muted).copyWith(fontFeatures: T.tnum)),
                  TextSpan(text: ' vibe', style: T.caption(bd)),
                ],
              ])),
            ]),
            if (t != null) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 3,
                child: LayoutBuilder(
                  builder: (context, c) => Stack(children: [
                    Container(decoration: BoxDecoration(color: bd.line, borderRadius: BorderRadius.circular(2))),
                    Container(
                      width: t == 0 ? 0 : (c.maxWidth * sparks / t).clamp(sparks > 0 ? 3.0 : 0.0, c.maxWidth),
                      decoration: BoxDecoration(color: leads ? bd.accent : bd.accent.withValues(alpha: .45), borderRadius: BorderRadius.circular(2)),
                    ),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: S.xs), trailing!],
      ]),
    );
  }
}

/// One pour in a shared room: a face, the drink in serif with its mood, then who
/// and when.
class PourRow extends StatelessWidget {
  final String author;
  final String drink;
  final String? mood;
  final String meta;
  const PourRow({super.key, required this.author, required this.drink, this.mood, required this.meta});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Initial(author.isEmpty ? '?' : author.characters.first.toUpperCase(), size: 30),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: drink, style: T.serif(bd, size: 19, height: 1.2)),
              if (mood != null) TextSpan(text: ' · $mood', style: T.serif(bd, size: 16, italic: true, color: bd.muted, height: 1.2)),
            ])),
            const SizedBox(height: 2),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd)),
          ]),
        ),
      ]),
    );
  }
}

/// A list of pours in one glass card, hairlines between.
class PourList extends StatelessWidget {
  final List<PourRow> rows;
  const PourList(this.rows, {super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.xs),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: .8, color: bd.line),
          rows[i],
        ],
      ]),
    );
  }
}

/// The quiet safety affordance on every person: report (write-only, to the safety
/// team) or block.
Future<void> personActions(BuildContext context, {required String id, required String name, String? planId, VoidCallback? onBlocked}) {
  return showActions(context, title: name, actions: [
    SheetAction('Report $name', icon: Ph.flag, onTap: () => showReportSheet(context, id, name, planId: planId)),
    SheetAction('Block $name', icon: Ph.prohibit, destructive: true, onTap: () async {
      if (!await confirm(context, title: 'Block $name?', body: "You won't see each other, and any plan or join between you is withdrawn.", yes: 'Block')) return;
      await SafetyApi.block(id);
      plansRev.bump();
      onBlocked?.call();
      if (context.mounted) toast(context, "Blocked. You won't see each other.");
    }),
  ]);
}

/// Report someone — write-only, to the safety team, never back to anyone.
Future<void> showReportSheet(BuildContext context, String userId, String name, {String? planId}) {
  return showBdSheet(context, title: 'Report $name', builder: (_) => _ReportSheet(userId: userId, name: name, planId: planId));
}

class _ReportSheet extends StatefulWidget {
  final String userId;
  final String name;
  final String? planId;
  const _ReportSheet({required this.userId, required this.name, this.planId});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _note = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final err = await SafetyApi.report(widget.userId, _reason!, note: _note.text, planId: widget.planId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = err == null;
    });
    if (err != null) toast(context, err, tone: ToastTone.error);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (_sent) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Ph.shieldCheck, size: 32, color: bd.accentText),
        const SizedBox(height: S.m),
        Text('Thanks for telling us.', style: T.title(bd)),
        const SizedBox(height: S.s),
        Text('Our safety team will look at it. Nothing about this report is shared with ${widget.name}.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.xxl),
        BdButton('Done', onTap: () => Navigator.pop(context)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('What happened? Only our safety team sees this — never ${widget.name}.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.l),
      Group(children: [
        for (final r in reportReasons.entries)
          GroupTile(
            title: r.value,
            trailing: _reason == r.key ? Icon(PhBold.check, size: 18, color: bd.accentText) : null,
            onTap: () => setState(() => _reason = r.key),
          ),
      ]),
      const SizedBox(height: S.l),
      GlassField(controller: _note, hint: 'Anything we should know? (optional)', maxLines: 3),
      const SizedBox(height: S.xxl),
      BdButton('Send report', busy: _busy, onTap: _reason == null ? null : _send),
    ]);
  }
}
