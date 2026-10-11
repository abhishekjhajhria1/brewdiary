// What's in brewdiary — every feature in one quiet list: what it is, where it
// lives, and a tap that takes you there. Opened from the calendar's first-time
// card and from You → Settings → About.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Tab;

import 'package:brewdiary_core/date.dart';
import '../../app.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../home_widget.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/moments.dart' show openLog;
import '../widgets/page.dart';
import '../../device/scan.dart';
import 'discover_screen.dart';
import 'morning_after.dart';
import 'photo_studio.dart';
import 'split_screen.dart';
import 'taste_card.dart';
import 'tonight_sheet.dart';

Future<void> showGuide(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen()));

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final cloud = auth.isAuthed && db != null;
    final nav = Navigator.of(context);

    // Leave the guide, then go: to a tab, or to a page from the shell.
    void tab(Tab t) {
      nav.popUntil((r) => r.isFirst);
      Shell.goTo(t);
    }

    void then(void Function(BuildContext root) go) {
      nav.popUntil((r) => r.isFirst);
      final root = navigatorKey.currentState?.overlay?.context;
      if (root != null) go(Shell.contextOrNull ?? root);
    }

    Widget row(IconData icon, String title, String where, {VoidCallback? onTap}) => GroupTile(icon: icon, title: title, subtitle: where, chevron: onTap != null, onTap: onTap);

    return SubPage(
      title: "What's in brewdiary",
      subtitle: 'Everything, and where it lives. Tap one to go there.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Your diary'),
        const SizedBox(height: S.s),
        Group(children: [
          row(Ph.handTap, 'Log a drink', 'Calendar → tap a day. A coffee counts; a dry day keeps your streak.', onTap: () => then((c) => openLog(c, todayKey(), cheer: cloud))),
          row(Ph.squaresFour, 'The year at a glance', 'Calendar → the grid button at the top. Darker the more you logged.', onTap: () => tab(Tab.calendar)),
          row(Ph.shareNetwork, 'Share a night', 'In any day: "Share this night" — your photo with one small sticker.', onTap: () => then((c) {
                final last = entryStore.entries.isEmpty ? todayKey() : entryStore.entries.map((e) => e.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
                final photo = entryStore.entries.where((e) => e.date == last).expand((e) => e.photos ?? const []).firstOrNull?.url;
                showPhotoStudio(c, NightStory.fromDay(last, entryStore.entries, currency: PlaceStore.instance.currency), photo: photo);
              })),
          row(Ph.identificationCard, 'Your taste passport', 'Calendar → the passport under the month. Miles for variety, never volume.', onTap: () => then((c) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const TasteCardScreen())))),
          row(Ph.bookOpen, 'Your words, photos and history', 'The You tab — search every drink, word, note and place.', onTap: () => tab(Tab.you)),
          row(Ph.filePdf, 'Your diary as a book', 'You → Settings → Your data: a PDF of every night.', onTap: () => tab(Tab.you)),
        ]),
        const SizedBox(height: S.xl),
        const Label('With friends'),
        const SizedBox(height: S.s),
        Group(children: [
          row(Ph.usersThree, 'The feed', 'Together → Feed: what friends chose to share. Cheers and comments.', onTap: () => tab(Tab.together)),
          row(Ph.calendarPlus, 'Plans, circles and parties', 'Together → the tabs at the top. A party can be at a bar.', onTap: () => tab(Tab.together)),
          row(Ph.receipt, 'Split the bill', 'Together → Split. Who paid which round, settled when you like.', onTap: cloud ? () => then((c) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const SplitScreen()))) : null),
          row(Ph.compass, 'Discover', 'The amber DISCOVER at the top of every tab: places near you.', onTap: () => then((c) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const DiscoverScreen())))),
          row(Ph.chatCircle, 'Ninkasi', 'The Ninkasi tab: ask what to drink, or what you can make at home.', onTap: () => tab(Tab.ninkasi)),
        ]),
        const SizedBox(height: S.xl),
        const Label('At the bar'),
        const SizedBox(height: S.s),
        Group(children: [
          row(Ph.qrCode, "The menu, from the table or the counter", 'Tap the tag or scan the QR. Order from it when the place allows — at a counter you get a number, and a buzz when it\'s ready.', onTap: () => then(scanToOpen)),
          row(Ph.identificationBadge, 'Your guest card', 'A 6-letter code the bartender types — your taste for tonight, never your diary.', onTap: cloud ? () => then(showGuestCard) : null),
        ]),
        const SizedBox(height: S.xl),
        const Label('Looking after you'),
        const SizedBox(height: S.s),
        Group(children: [
          row(Ph.moonStars, 'Tonight', 'Calendar → "Out tonight?": water nudges, a ride home, send a friend where you are.', onTap: () => then(showTonight)),
          row(Ph.drop, 'The morning after', 'The morning after a night out, on the calendar: what actually helps.', onTap: () => then(showMorningAfter)),
          row(Ph.gauge, 'Gentle limits and a reminder', 'You → Settings. Off unless you want them.', onTap: () => tab(Tab.you)),
        ]),
        if (!kIsWeb && Platform.isAndroid) ...[
          const SizedBox(height: S.xl),
          const Label('On your home screen'),
          const SizedBox(height: S.s),
          const HomeScreenWidgets(),
        ],
        const SizedBox(height: S.l),
        Text('Nothing in brewdiary rewards drinking more — streaks keep going on dry days, and miles come from trying new things.', textAlign: TextAlign.center, style: T.caption(bd)),
      ]),
    );
  }
}

/// The three home-screen widgets, each with "Add" — Android puts it on the home
/// screen for you (where the launcher allows; otherwise it says how).
class HomeScreenWidgets extends StatelessWidget {
  const HomeScreenWidgets({super.key});

  @override
  Widget build(BuildContext context) {
    Future<void> add(String which) async {
      final ok = await HomeWidget.pin(which);
      if (!ok && context.mounted) toast(context, 'Long-press your home screen, tap Widgets, then find brewdiary.');
    }

    Widget tile(IconData icon, String title, String what, String which) => GroupTile(
          icon: icon,
          title: title,
          subtitle: what,
          trailing: TextAction('Add', accent: true, onTap: () => add(which)),
        );

    return Group(children: [
      tile(Ph.squaresFour, 'This month', 'Your mosaic, darker the more you logged. Tap it to open the diary.', 'mosaic'),
      tile(Ph.plusCircle, 'Quick log', '+ Water, + Cigarette for today, in one tap (with Undo).', 'quick'),
      tile(Ph.receipt, 'Split', "What you're owed and what you owe. Tap it to open Split.", 'split'),
    ]);
  }
}
