// Ninkasi — a port of src/components/bartender/Bartender.tsx. Mistress of the bar.
// She reads your recent drinks + moods, what friends have been sharing, and the
// anonymous trends — then streams a reply from the website's /api/bartender route.
//
// Layout: a chat that scrolls under a frosted top bar, with the composer pinned
// below it — above the tab bar, or right on top of the keyboard while typing.
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
import '../widgets/page.dart';

/// Ninkasi on her own pushed page (from Discover), with a back button.
class BartenderPage extends StatelessWidget {
  const BartenderPage({super.key});
  @override
  Widget build(BuildContext context) => const Ambient(child: Scaffold(backgroundColor: Colors.transparent, body: BartenderScreen(inShell: false)));
}

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
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _busy = false;
  bool _offline = false;
  bool _under = false; // content scrolled under the top bar → frost it
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
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The list is reversed (newest at the bottom), so "the bottom" is offset 0.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: Motion.med, curve: Motion.curve);
    });
  }

  void _newChat() {
    if (_busy) return;
    setState(() {
      _messages.clear();
      _offline = false;
      _under = false;
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
      }
      TrainingStore.instance.log(user: content, assistant: acc);
    } catch (_) {
      if (mounted) setState(() => _messages[_messages.length - 1] = const ChatMessage(ChatRole.assistant, 'The bar went quiet for a moment — ask me again, love.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final under = _messages.isEmpty ? n.metrics.pixels > 4 : n.metrics.extentAfter > 4;
    if (under != _under) setState(() => _under = under);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mq = MediaQuery.of(context);
    final keyboard = KeyboardScope.isUp(context);
    final top = mq.padding.top + kTopBarHeight;
    final composerBottom = keyboard ? S.s : mq.padding.bottom + (widget.inShell ? kTabBarSpace : 0) + S.s;

    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: _messages.isEmpty ? _intro(context, top) : _chat(context, top),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBar(
              frosted: _under,
              back: !widget.inShell,
              title: AnimatedOpacity(
                opacity: _messages.isEmpty && !_under ? 0 : 1,
                duration: Motion.fast,
                child: Text(ninkasiName, style: T.sans(bd, size: 17, weight: FontWeight.w600)),
              ),
              actions: [if (_messages.isNotEmpty) IconBtn(Ph.notePencil, tooltip: 'New conversation', onTap: _busy ? null : _newChat)],
            ),
          ),
        ]),
      ),
      if (_offline) Padding(padding: const EdgeInsets.fromLTRB(S.gutter, S.xs, S.gutter, S.xs), child: Text(offlineNote, textAlign: TextAlign.center, style: T.caption(bd))),
      AnimatedPadding(
        duration: Motion.fast,
        curve: Motion.curve,
        padding: EdgeInsets.fromLTRB(S.l, S.xs, S.l, composerBottom),
        child: _composer(context),
      ),
    ]);
  }

  Widget _intro(BuildContext context, double top) {
    final bd = context.bd;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(S.gutter, top + S.s, S.gutter, S.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(ninkasiName, style: T.largeTitle(bd))),
        const SizedBox(height: S.s),
        Text("Mistress of the bar, named for the goddess who brewed for the gods. Tell her the mood — she knows what you've been pouring.", style: T.bodyMuted(bd)),
        const SectionHeader('Try asking', padding: EdgeInsets.only(top: S.x3, bottom: S.m)),
        Group(children: [
          for (final s in starters) GroupTile(title: s, trailing: Icon(Ph.arrowUpRight, size: 16, color: bd.faint), onTap: () => _send(s)),
        ]),
      ]),
    );
  }

  Widget _chat(BuildContext context, double top) {
    final bd = context.bd;
    final width = MediaQuery.sizeOf(context).width;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(S.l, top + S.s, S.l, S.s),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[_messages.length - 1 - i];
        final mine = m.role == ChatRole.user;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * (mine ? .78 : .86)),
            child: Container(
              margin: const EdgeInsets.only(bottom: S.m),
              padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: 11),
              decoration: BoxDecoration(
                color: mine ? bd.accent.withValues(alpha: bd.dark ? .2 : .22) : null,
                gradient: mine ? null : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bd.glassTop, bd.glass]),
                border: Border.all(color: mine ? bd.accent.withValues(alpha: .3) : bd.glassBorder, width: .8),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 6),
                  bottomRight: Radius.circular(mine ? 6 : 18),
                ),
              ),
              child: m.content.isEmpty
                  ? Text('Pouring…', style: T.body(bd, color: bd.faint).copyWith(fontStyle: FontStyle.italic))
                  : SelectableText(m.content, style: T.body(bd)),
            ),
          ),
        );
      },
    );
  }

  Widget _composer(BuildContext context) {
    final bd = context.bd;
    final ready = !_busy && _input.text.trim().isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(S.l, 4, 5, 4),
      decoration: BoxDecoration(
        color: bd.dark ? const Color(0xE61A1B22) : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: bd.glassBorder, width: .8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            onSubmitted: _send,
            textInputAction: TextInputAction.send,
            textCapitalization: TextCapitalization.sentences,
            style: T.body(bd),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              hintText: 'What are you in the mood for?',
              hintMaxLines: 1,
              hintStyle: T.body(bd, color: bd.faint),
            ),
          ),
        ),
        Semantics(
          button: true,
          enabled: ready,
          label: 'Ask Ninkasi',
          excludeSemantics: true,
          child: Pressable(
            enabled: ready,
            onTap: () => _send(_input.text),
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? bd.accent : bd.ink.withValues(alpha: .1)),
                  child: _busy
                      ? Padding(padding: const EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: bd.muted))
                      : Icon(PhBold.arrowUp, size: 18, color: ready ? bd.accentContrast : bd.faint),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
