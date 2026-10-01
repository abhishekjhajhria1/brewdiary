// Ninkasi — a port of src/components/bartender/Bartender.tsx. Mistress of the bar.
// She reads your recent drinks + moods, what friends have been sharing, and the
// anonymous trends — then streams a reply from the website's /api/bartender route.
//
// Layout: a chat that scrolls under a frosted top bar, with the composer pinned
// below it — above the tab bar, or right on top of the keyboard while typing.
import 'package:flutter/material.dart';

import 'package:brewdiary_core/bartender.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../data/auth.dart';
import '../../data/bartender_api.dart';
import '../../data/chats.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/safety.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/moments.dart';
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
    _messages.addAll(ChatStore.instance.current?.messages ?? const []);
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
    ChatStore.instance.startNew();
    setState(() {
      _messages.clear();
      _offline = false;
      _under = false;
    });
  }

  void _openChat(Chat c) {
    ChatStore.instance.open(c.id);
    setState(() {
      _messages
        ..clear()
        ..addAll(c.messages);
      _offline = false;
    });
    _toBottom();
  }

  /// Every saved conversation: open one, rename it, or delete it.
  Future<void> _chats() async {
    if (_busy) return;
    await showBdSheet<void>(context, title: 'Your chats with $ninkasiName', builder: (ctx) => _ChatList(onOpen: (c) {
          Navigator.pop(ctx);
          _openChat(c);
        }, onNew: () {
          Navigator.pop(ctx);
          _newChat();
        }, onDeletedCurrent: () {
          if (mounted) setState(_messages.clear);
        }));
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
      await ChatStore.instance.save([...history, ChatMessage(ChatRole.assistant, acc)]);
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
              title: AnimatedSwitcher(
                duration: Motion.fast,
                child: _messages.isEmpty && !_under && widget.inShell
                    ? const Align(key: ValueKey('w'), alignment: Alignment.centerLeft, child: Wordmark())
                    : Text(ninkasiName, key: const ValueKey('t'), style: T.sans(bd, size: 17, weight: FontWeight.w600)),
              ),
              actions: [
                if (ChatStore.instance.chats.isNotEmpty) IconBtn(Ph.chatsCircle, tooltip: 'Your chats', onTap: _busy ? null : _chats),
                if (_messages.isNotEmpty) IconBtn(Ph.notePencil, tooltip: 'New conversation', onTap: _busy ? null : _newChat)
                else if (widget.inShell) ...(siteHeaderActions?.call(context) ?? const []),
              ],
            ),
          ),
        ]),
      ),
      if (_offline) Padding(padding: const EdgeInsets.fromLTRB(S.gutter, S.xs, S.gutter, S.xs), child: Text(offlineNote, textAlign: TextAlign.center, style: T.caption(bd))),
      AnimatedPadding(
        duration: Motion.fast,
        curve: Motion.curve,
        padding: EdgeInsets.fromLTRB(sideGutter(context) - 4, S.xs, sideGutter(context) - 4, composerBottom),
        child: _composer(context),
      ),
    ]);
  }

  Widget _intro(BuildContext context, double top) {
    final bd = context.bd;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(sideGutter(context), top + S.s, sideGutter(context), S.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(ninkasiName, style: T.largeTitle(bd))),
        const SizedBox(height: S.s),
        Text("Mistress of the bar, named for the goddess who brewed for the gods. Tell her the mood — she knows what you've been pouring.", style: T.bodyMuted(bd)),
        const SectionHeader('Try asking', padding: EdgeInsets.only(top: S.x3, bottom: S.m)),
        // The website's starters: glass pills, one tap to ask.
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final s in starters)
            Semantics(
              button: true,
              child: Pressable(
                onTap: () => _send(s),
                child: Container(
                  constraints: const BoxConstraints(minHeight: S.tap),
                  padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bd.glassTop, bd.glass]),
                    borderRadius: BorderRadius.circular(rCtl),
                    border: Border.all(color: bd.glassBorder, width: .8),
                  ),
                  child: Text(s, style: T.body(bd)),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _chat(BuildContext context, double top) {
    final bd = context.bd;
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, kContentMaxWidth + 2 * S.gutter);
    final side = sideGutter(context) - 4;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(side, top + S.s, side, S.s),
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
                  ? TypingDots(color: bd.muted)
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
                  child: Icon(PhBold.arrowUp, size: 18, color: ready ? bd.accentContrast : bd.faint),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The saved conversations, newest first.
class _ChatList extends StatelessWidget {
  final ValueChanged<Chat> onOpen;
  final VoidCallback onNew;
  final VoidCallback onDeletedCurrent;
  const _ChatList({required this.onOpen, required this.onNew, required this.onDeletedCurrent});

  Future<void> _manage(BuildContext context, Chat c) async {
    final store = ChatStore.instance;
    await showActions(context, title: c.title, actions: [
      SheetAction('Rename', icon: Ph.pencilSimple, onTap: () async {
        final name = TextEditingController(text: c.title);
        final v = await showBdSheet<String>(context, title: 'Rename chat', builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlassField(controller: name, autofocus: true, maxLength: 60, action: TextInputAction.done, onSubmitted: (t) => Navigator.pop(ctx, t)),
              const SizedBox(height: S.m),
              BdButton('Save', onTap: () => Navigator.pop(ctx, name.text)),
            ]));
        name.dispose();
        if (v != null) await store.rename(c.id, v);
      }),
      SheetAction('Delete', icon: Ph.trash, destructive: true, onTap: () async {
        if (!await confirm(context, title: 'Delete this chat?', body: 'It\'s removed from this phone.', yes: 'Delete')) return;
        final wasCurrent = store.currentId == c.id;
        await store.delete(c.id);
        if (wasCurrent) onDeletedCurrent();
      }),
    ]);
  }

  String _when(DateTime d) {
    final k = toKey(d);
    if (k == todayKey()) return 'Today, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return formatDayLongYear(k);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: ChatStore.instance,
      builder: (context, _) {
        final store = ChatStore.instance;
        final chats = store.chats;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BdButton('New chat', kind: BtnKind.secondary, icon: Ph.notePencil, onTap: onNew),
          const SizedBox(height: S.m),
          if (chats.isEmpty) const EmptyNote('No saved chats yet.'),
          if (chats.isNotEmpty)
            Group(children: [
              for (final c in chats)
                Pressable(
                  onTap: () => onOpen(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.s),
                    child: Row(children: [
                      Icon(c.id == store.currentId ? PhFill.checkCircle : Ph.chatCircle, size: 20, color: c.id == store.currentId ? bd.accentText : bd.faint),
                      const SizedBox(width: S.m),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd)),
                          const SizedBox(height: 2),
                          Text('${_when(c.updatedAt)} · ${(c.messages.length / 2).ceil()} ${c.messages.length <= 2 ? 'question' : 'questions'}', style: T.caption(bd)),
                        ]),
                      ),
                      IconBtn(Ph.dotsThree, tooltip: 'Rename or delete ${c.title}', onTap: () => _manage(context, c)),
                    ]),
                  ),
                ),
            ]),
          const SizedBox(height: S.s),
          Text('Kept on this phone. They also go into your diary book.', style: T.caption(bd)),
        ]);
      },
    );
  }
}
