// Ninkasi — a port of src/components/bartender/Bartender.tsx. Mistress of the bar.
// She reads your recent drinks + moods, what friends have been sharing, and the
// anonymous trends — then streams a reply from the website's /api/bartender route.
import 'package:flutter/material.dart';

import '../../core/bartender.dart';
import '../../core/derive.dart';
import '../../data/auth.dart';
import '../../data/bartender_api.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/safety.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BartenderScreen extends StatefulWidget {
  /// Inside the tab shell the composer sits above the tab bar; pushed, it doesn't.
  final bool inShell;
  const BartenderScreen({super.key, this.inShell = true});
  @override
  State<BartenderScreen> createState() => _BartenderScreenState();
}

class _BartenderScreenState extends State<BartenderScreen> {
  final List<ChatMessage> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  bool _offline = false;
  List<String> _friendsPouring = const [];
  List<String> _trending = const [];

  @override
  void initState() {
    super.initState();
    if (auth.isAuthed && db != null) {
      FriendsApi.feed().then((f) => _friendsPouring = f.map((e) => e.drink).toSet().take(5).toList()).catchError((_) => <String>[]);
      DiscoverApi.tasteTrends().then((t) => _trending = t.where((x) => x.kind == 'drink').map((x) => x.name).take(5).toList()).catchError((_) => <String>[]);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send(String text) async {
    final content = text.trim();
    if (content.isEmpty || _busy) return;
    final entries = entryStore.entries;
    final history = [..._messages, ChatMessage(ChatRole.user, content)];
    setState(() {
      _messages
        ..clear()
        ..addAll(history)
        ..add(const ChatMessage(ChatRole.assistant, ''));
      _input.clear();
      _busy = true;
    });
    _toBottom();

    final ctx = BartenderContext(
      recentDrinks: recentDrinks(entries, 6),
      moods: recentMoods(entries, 6),
      total: entries.length,
      friendsPouring: _friendsPouring,
      trending: _trending,
    );
    final stream = BartenderApi.ask(history, ctx, collect: TrainingStore.instance.collecting);
    stream.mode.then((m) {
      if (mounted) setState(() => _offline = m != 'live');
    });
    var acc = '';
    try {
      await for (final t in stream.text) {
        acc = t;
        if (!mounted) return;
        setState(() => _messages[_messages.length - 1] = ChatMessage(ChatRole.assistant, acc));
        _toBottom();
      }
      TrainingStore.instance.log(user: content, assistant: acc);
    } catch (_) {
      if (mounted) setState(() => _messages[_messages.length - 1] = const ChatMessage(ChatRole.assistant, 'The bar went quiet for a moment — ask me again, love.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(ninkasiName, style: T.serif(bd, size: 54, height: .92)),
      const SizedBox(height: 8),
      Text("Mistress of the bar, named for the goddess who brewed for the gods. Tell her the mood — she knows what you've been pouring.", style: T.sans(bd, color: bd.muted, height: 1.5)),
      const SizedBox(height: 12),
      Expanded(
        child: _messages.isEmpty
            ? SingleChildScrollView(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in starters)
                    Glass(radius: rCtl, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), onTap: () => _send(s), child: Text(s, style: T.sans(bd, size: 14, color: bd.muted))),
                ]),
              )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  final mine = m.role == ChatRole.user;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (mine ? .75 : .82)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? bd.glassStrong : bd.glass,
                          border: Border.all(color: bd.glassBorder),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(mine ? 16 : 6),
                            bottomRight: Radius.circular(mine ? 6 : 16),
                          ),
                        ),
                        child: m.content.isEmpty ? Text('pouring…', style: T.sans(bd, color: bd.faint)) : SelectableText(m.content, style: T.sans(bd, height: 1.55)),
                      ),
                    ),
                  );
                },
              ),
      ),
      if (_offline) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(offlineNote, style: T.sans(bd, size: 12, color: bd.faint))),
      Padding(
        // Keep the composer above the tab bar (or the keyboard when it's open).
        padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : safeBottom + (widget.inShell ? 92 : 16)),
        child: Glass(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                onChanged: (_) => setState(() {}),
                onSubmitted: _send,
                textInputAction: TextInputAction.send,
                style: T.sans(bd),
                decoration: InputDecoration(border: InputBorder.none, isDense: true, hintText: 'What are you in the mood for?', hintStyle: T.sans(bd, color: bd.faint)),
              ),
            ),
            Pressable(
              enabled: !_busy && _input.text.trim().isNotEmpty,
              onTap: () => _send(_input.text),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(color: _busy || _input.text.trim().isEmpty ? bd.ink.withValues(alpha: .1) : bd.accent, borderRadius: BorderRadius.circular(rCtl)),
                child: Text(_busy ? '…' : 'Ask', style: T.sans(bd, size: 14, weight: FontWeight.w500, color: _busy || _input.text.trim().isEmpty ? bd.faint : bd.accentContrast)),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
