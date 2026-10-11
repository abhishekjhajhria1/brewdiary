// Phone orders that go straight to the bar and the kitchen (059): the switch, pickup
// points and their numbers, "Collected", the pause, the ready board, a sweet shop's
// counter, and the ticket printer — on paper, over a real socket, and printing by itself
// when an order lands.
import 'dart:io';

import 'package:brewdiary_bar/data/backend.dart';
import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/data/prefs.dart';
import 'package:brewdiary_bar/data/session.dart';
import 'package:brewdiary_bar/device/printer.dart';
import 'package:brewdiary_bar/logic/kot.dart';
import 'package:brewdiary_bar/logic/service.dart';
import 'package:brewdiary_bar/ui/screens/ready_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

OrderLine _l(String name, int qty, {String status = 'sent', String? note, int? seat, String source = 'guest', int? pickup, String tab = 't1'}) =>
    OrderLine(id: '$tab$name$qty', tabId: tab, name: name, unitPrice: 450, qty: qty, note: note, seat: seat, status: status, source: source, createdAt: DateTime(2026, 10, 11, 21, 5), pickupNo: pickup);

/// A pretend printer on this machine: every connection's bytes, joined.
Future<(ServerSocket, List<int>)> _printer() async {
  final got = <int>[];
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) => s.listen(got.addAll));
  return (server, got);
}

void main() {
  group('the ticket on paper', () {
    test('a pickup ticket: the number big, what to make, the notes — never a price or a name', () {
      final lines = kotLines(station: 'Bar', where: 'Pickup 7', pickupNo: 7, lines: [_l('Negroni', 2, note: 'no ice', pickup: 7), _l('Kokum Cooler', 1, pickup: 7)], at: DateTime(2026, 10, 11, 21, 5), fromPhone: true);
      expect(lines.first, 'PICKUP 7');
      expect(lines[1], 'BAR - PHONE ORDER - 21:05');
      expect(lines, containsAllInOrder(['2 x Negroni', '   > no ice', '1 x Kokum Cooler']));
      expect(lines.join('\n'), isNot(contains('450')), reason: 'no prices on a kitchen ticket');
    });

    test('a table ticket says the table; a seat and a reprint are marked', () {
      final lines = kotLines(station: 'Kitchen', where: 'T4', lines: [_l('Masala Fries', 1, seat: 2, source: 'staff')], at: DateTime(2026, 10, 11, 9, 30), reprint: true);
      expect(lines.take(3), ['** REPRINT **', 'T4', 'KITCHEN - 09:30']);
      expect(lines, contains('   seat 2'));
    });

    test('what a receipt printer can\'t show is made plain; long names wrap', () {
      expect(printable('Crème brûlée — “house” · ₹'), 'Creme brulee - "house" - Rs ');
      expect(printable('मसाला'), '?????');
      expect(wrap('1 x A very long cocktail name that goes on', 16), ['1 x A very long', 'cocktail name', 'that goes on']);
      expect(wrap('Supercalifragilistic', 8), ['Supercal', 'ifragili', 'stic']);
    });

    test('a printer\'s address: an IP, a port if it isn\'t 9100', () {
      expect(parsePrinter('192.168.1.50'), (host: '192.168.1.50', port: 9100));
      expect(parsePrinter(' 10.0.0.7:9101 '), (host: '10.0.0.7', port: 9101));
      expect(parsePrinter('http://printer'), isNull);
      expect(parsePrinter('10.0.0.7:99999'), isNull);
    });

    test('only new lines print, a ticket per table or number', () {
      final now = [_l('Negroni', 1, tab: 'a'), _l('Gimlet', 1, tab: 'a'), _l('Fries', 1, tab: 'b'), _l('Old', 1, tab: 'c', status: 'ready')];
      final todo = unprinted(now, {'aNegroni1'});
      expect(todo.keys, ['a', 'b']);
      expect(todo['a']!.map((l) => l.name), ['Gimlet']);
    });

    test('the bytes reach a printer on the network, and end with a cut', () async {
      final (server, got) = await _printer();
      addTearDown(server.close);
      await sendToPrinter('127.0.0.1:${server.port}', kotBytes(station: 'Bar', where: 'Pickup 7', pickupNo: 7, lines: [_l('Negroni', 2, pickup: 7)], at: DateTime(2026, 10, 11, 21, 5)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(String.fromCharCodes(got), contains('PICKUP 7'));
      expect(got.sublist(got.length - 4), [0x1d, 0x56, 66, 0]);
    });

    test('a printer that isn\'t there says so, in words', () async {
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = free.port;
      await free.close();
      expect(() => sendToPrinter('127.0.0.1:$port', [0]), throwsA(isA<PrinterError>().having((e) => e.message, 'message', contains('didn\'t answer'))));
      expect(() => sendToPrinter('not a printer!', [0]), throwsA(isA<PrinterError>()));
    });
  });

  group('walk-throughs', () {
    setUpAll(loadFonts);

    testWidgets('straight in: the switch, a pickup point, its ticket by number, collected', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1800));
      await tapText(t, 'The Amber Room');
      await tapText(t, 'MORE');
      await tapText(t, 'Floor setup');
      await tapText(t, 'STRAIGHT IN');
      expect(Session.instance.venue!.ordersDirect, isTrue);
      expect(find.text('Paused for the rush'), findsOneWidget);
      expect(find.text('Without an account'), findsOneWidget);

      await tapInView(t, 'Add a pickup point');
      await t.enterText(find.byType(TextField).first, 'Bar counter');
      await tapInSheet(t, 'Save');
      await tapInView(t, 'Bar counter');
      expect(find.text('Write an NFC sticker'), findsOneWidget);
      expect(find.text('Ready board on this screen'), findsOneWidget);
      Navigator.of(t.element(find.text('Write an NFC sticker'))).pop();
      await t.pumpAndSettle();

      final point = (await backend.tables('demo-bar')).firstWhere((x) => x.isPickup);
      expect(point.label, 'Bar counter');
      backend.guestOrder(point.code, [(item: 'm1', qty: 2), (item: 'm5', qty: 1)]);
      Navigator.of(t.element(find.text('Floor').first)).pop();
      await t.pumpAndSettle();
      await tapText(t, 'FLOOR');
      expect(find.text('Bar counter'), findsNothing, reason: 'a pickup point isn\'t a table on the floor');
      expect(find.text('Pickup 1'), findsOneWidget, reason: 'its order is a tab at the bar, by number');

      await tapInView(t, 'Bar tickets');
      expect(_labelled('Pickup number 1'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == 'ordered from a phone'), findsWidgets);
      expect(find.text('to collect · check ID when you hand it over'), findsOneWidget, reason: 'a Negroni, handed over at a counter');

      // The bar makes its half; the kitchen its half. Then it's handed over.
      for (final l in (await backend.stationLines('demo-bar', 'counter')).where((l) => l.pickupNo == 1)) {
        await backend.setLineStatus(l.id, 'preparing');
        await backend.setLineStatus(l.id, 'ready');
      }
      await t.pumpAndSettle();
      expect((await backend.pickupBoard(point.code)).single.ready, isTrue, reason: 'the board says ready');
      await tapInView(t, 'Collected');
      expect(await backend.pickupBoard(point.code), isEmpty, reason: 'collected: off the board');
      expect(_labelled('Pickup number 1'), findsNothing);
    });

    testWidgets('confirm mode: a pickup point\'s order waits for an OK, then gets its number', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1600));
      await backend.saveTable('demo-bar', const VenueTable(id: 'pk', label: 'Window', code: '', kind: 'pickup'), isNew: true);
      final code = (await backend.tables('demo-bar')).firstWhere((x) => x.id == 'pk').code;
      backend.guestOrder(code, [(item: 'm4', qty: 1)]);
      final req = (await backend.inbox('demo-bar')).firstWhere((i) => i.tableId == 'pk');
      await backend.acceptRequest(req.id, 'ignored-for-a-pickup');
      final tab = (await backend.openTabs('demo-bar')).firstWhere((x) => x.pickupPoint == 'pk');
      expect(tab.pickupNo, 1);
      expect(tab.name, 'Pickup 1');
    });

    testWidgets('the bar pauses phone orders in a rush, and takes them again', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1600));
      await tapText(t, 'The Amber Room');
      await tapInView(t, 'Bar tickets');
      expect(find.text('phone orders wait for an OK'), findsOneWidget);
      await tapText(t, 'Pause phone orders');
      expect(Session.instance.venue!.ordersPaused, isTrue);
      expect(find.text('phone orders paused'), findsOneWidget);
      expect(() => backend.guestOrder('demot003', [(item: 'm4', qty: 1)]), throwsA(isA<BackendError>()));
      await tapText(t, 'Take phone orders again');
      expect(Session.instance.venue!.ordersPaused, isFalse);
    });

    testWidgets('the ready board: numbers being made, numbers ready — never a name', (t) async {
      final backend = await bootApp(t, size: const Size(1280, 800));
      await backend.updateVenue('demo-bar', ordersDirect: true);
      await backend.saveTable('demo-bar', const VenueTable(id: 'pk', label: 'Bar counter', code: '', kind: 'pickup'), isNew: true);
      final code = (await backend.tables('demo-bar')).firstWhere((x) => x.id == 'pk').code;
      backend.guestOrder(code, [(item: 'm1', qty: 1)]);
      backend.guestOrder(code, [(item: 'm4', qty: 1)]);
      final second = (await backend.stationLines('demo-bar', 'bar')).firstWhere((l) => l.pickupNo == 2);
      await backend.setLineStatus(second.id, 'preparing');
      await backend.setLineStatus(second.id, 'ready');

      navigator(t).push(MaterialPageRoute(builder: (_) => ReadyBoardScreen(venueName: 'The Amber Room', code: code)));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Number 1 is being made'), findsOneWidget);
      expect(find.bySemanticsLabel('Number 2 is ready'), findsOneWidget);
      expect(find.text('Negroni'), findsNothing, reason: 'what someone ordered stays off the wall');
      navigator(t).pop();
      await t.pumpAndSettle();
    });

    testWidgets('a sweet shop: a counter QR, phone orders on the till, collected by number', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1600));
      await backend.saveTable('demo-sweets', const VenueTable(id: 'ctr', label: 'Counter', code: '', kind: 'pickup'), isNew: true);
      expect(() => backend.saveTable('demo-sweets', const VenueTable(id: 'tx', label: 'T1', code: ''), isNew: true), throwsA(isA<BackendError>()), reason: 'a counter still has no tables');
      await backend.saveMenuItem('demo-sweets', const MenuItem(id: 'k9', section: 'Boxes', name: 'Boxed Laddoo', price: 150, kind: 'food', noAlcohol: true, station: 'none'), isNew: true);
      await backend.updateVenue('demo-sweets', tableService: true, ordersDirect: true);
      final code = (await backend.tables('demo-sweets')).single.code;
      backend.guestOrder(code, [(item: 'k1', qty: 1), (item: 'k9', qty: 1)]);

      await tapText(t, 'Mithai Mahal');
      await tapText(t, 'Phone orders');
      expect(find.text('Orders'), findsWidgets);
      expect(_labelled('Pickup number 1'), findsOneWidget);
      expect(find.text('Kaju Katli (250 g)'), findsOneWidget);
      final lines = await backend.stationLines('demo-sweets', 'counter');
      expect(lines.firstWhere((l) => l.name == 'Boxed Laddoo').status, 'ready', reason: 'nothing to make: ready at once');
    });

    testWidgets('a new phone order prints at the bar\'s ticket printer by itself', (t) async {
      // The socket itself is proven above; here, what the station sends and when.
      final sent = <String>[];
      printSender = (address, bytes) async => sent.add('$address|${String.fromCharCodes(bytes)}');
      addTearDown(() => printSender = sendToPrinter);
      final backend = await bootApp(t, size: const Size(390, 1600));
      await setPrinter('demo-bar', 'bar', '192.168.1.50');
      await backend.updateVenue('demo-bar', ordersDirect: true);
      await tapText(t, 'The Amber Room');
      await tapInView(t, 'Bar tickets');
      expect(find.text('Printing at 192.168.1.50'), findsOneWidget);
      expect(sent, isEmpty, reason: 'what was already on screen isn\'t printed');

      backend.guestOrder('demot003', [(item: 'm2', qty: 2)]);
      await t.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single, startsWith('192.168.1.50|'));
      expect(sent.single, contains('T3'));
      expect(sent.single, contains('2 x Espresso Martini'));
      expect(sent.single, contains('PHONE ORDER'));
      expect(sent.single, isNot(contains('Negroni')));

      // The next read prints nothing new; another order prints once more.
      floorRev.bump();
      await t.pumpAndSettle();
      expect(sent, hasLength(1));
      backend.guestOrder('demot004', [(item: 'm4', qty: 1)]);
      await t.pumpAndSettle();
      expect(sent, hasLength(2));
      expect(tickets(await backend.stationLines('demo-bar', 'bar')).any((x) => x.where == 'T3' && x.fromPhone), isTrue);
    });
  });
}

/// A widget's own semantics label, on screen or scrolled off it.
Finder _labelled(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

NavigatorState navigator(WidgetTester t) => t.state<NavigatorState>(find.byType(Navigator).first);
