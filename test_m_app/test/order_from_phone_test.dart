// Ordering from a table or a counter (059): how an order goes in, your number, where it's
// got to, what a liquor store won't take by phone, the shelf's list for the till, and the
// link on an NFC tag.
import 'dart:typed_data';

import 'package:brewdiary/app.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/table_order.dart';
import 'package:brewdiary/device/scan.dart';
import 'package:brewdiary/ui/screens/menu_screen.dart';
import 'package:brewdiary/ui/screens/shelf_screen.dart';
import 'package:brewdiary_core/links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'helpers.dart';

const _prefs = {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'};

void main() {
  group('an order, as you follow it', () {
    test('a pickup order: your number, the steps, the words', () {
      final o = OrderStatus.fromJson({
        'id': 'r1',
        'status': 'making',
        'created_at': '2026-10-11T15:30:00Z',
        'venue_name': 'Third Wave',
        'point': 'Counter',
        'point_kind': 'pickup',
        'pickup_no': 42,
        'lines': [
          {'name': 'Flat white', 'qty': 2, 'status': 'preparing'},
        ],
      });
      expect(o.pickupNo, 42);
      expect(o.atPickup, isTrue);
      expect(o.step, 1);
      expect(o.words, 'being made');
      expect(o.live, isTrue);
      expect(OrderStatus.fromJson({'id': 'r1', 'status': 'ready', 'point': 'Counter', 'point_kind': 'pickup'}).words, 'ready — collect it at Counter');
      expect(OrderStatus.fromJson({'id': 'r1', 'status': 'ready'}).words, 'ready — on its way to you');
      expect(OrderStatus.fromJson({'id': 'r1', 'status': 'declined', 'decline_reason': 'kitchen\'s closed'}).words, 'declined — kitchen\'s closed');
      expect(OrderStatus.fromJson({'id': 'r1', 'status': 'served'}).live, isFalse);
    });

    test('a place\'s link says how it takes orders', () {
      final t = TableInfo.fromRow('ab12cd34', {
        'venue_slug': 'cellar-door',
        'venue_name': 'Cellar Door',
        'venue_kind': 'store',
        'table_label': 'Counter',
        'table_service': true,
        'point_kind': 'pickup',
        'orders_direct': true,
        'orders_paused': false,
        'orders_anon': true,
        'legal_class': 'off_trade',
      });
      expect((t.isPickup, t.ordersDirect, t.ordersAnon, t.offTrade, t.isCounter), (true, true, true, true, true));
    });

  });

  test('a tag\'s link reads back from its NDEF record', () {
    final m = NdefMessage(records: [
      NdefRecord(typeNameFormat: TypeNameFormat.wellKnown, type: Uint8List.fromList(const [0x55]), identifier: Uint8List(0), payload: Uint8List.fromList(ndefUriPayload('https://bwdy.site/t/ab12cd34'))),
    ]);
    expect(linkOnTag(m), 'https://bwdy.site/t/ab12cd34');
    expect(linkOnTag(null), isNull);
    expect(linkOnTag(NdefMessage(records: [NdefRecord(typeNameFormat: TypeNameFormat.media, type: Uint8List.fromList('text/plain'.codeUnits), identifier: Uint8List(0), payload: Uint8List(3))])), isNull);
  });

  group('on screen', () {
    setUpAll(loadFonts);

    testWidgets('this phone\'s order secret: made once, kept, never empty', (t) async {
      await bootApp(t, prefs: _prefs, signedIn: true);
      final a = deviceSecret();
      expect(a, matches(RegExp(r'^[0-9a-f]{48}$')));
      expect(deviceSecret(), a);
      expect(Prefs.getString('brewdiary.order.device'), a);
    });

    testWidgets('at a counter, straight in: no calls, an Order button, your number when it\'s placed', (t) async {
      await bootApp(t, prefs: _prefs, signedIn: true, size: const Size(390, 1400));
      const counter = TableInfo(code: 'ab12cd34', venueSlug: 'soka', venueName: 'Soka', tableLabel: 'Bar counter', tableService: true, pointKind: 'pickup', ordersDirect: true);
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MenuView(menu: sampleMenu(), table: counter, previewOrdering: true)));
      await t.pumpAndSettle();
      expect(find.textContaining('Order here and get a number'), findsOneWidget);
      expect(find.text('Call staff'), findsNothing, reason: 'nobody comes over to a counter');
      await t.tap(find.byTooltip('Add Negroni').first);
      await t.pumpAndSettle();
      expect(find.text('Order'), findsOneWidget);
      expect(find.textContaining('goes straight to the bar and the kitchen'), findsOneWidget);
    });

    testWidgets('a liquor store: bottles are bought at the counter, the tonic can be ordered', (t) async {
      await bootApp(t, prefs: _prefs, signedIn: true, size: const Size(390, 1400));
      const store = TableInfo(code: 'ab12cd34', venueSlug: 'cellar-door', venueName: 'Soka', venueKind: 'store', tableLabel: 'Counter', tableService: true, pointKind: 'pickup', ordersDirect: true, legalClass: 'off_trade');
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MenuView(menu: sampleMenu(), table: store, previewOrdering: true)));
      await t.pumpAndSettle();
      expect(find.byTooltip('Add Negroni'), findsNothing);
      expect(find.byTooltip('Add Garden Spritz'), findsWidgets);
      expect(find.text('at the counter'), findsWidgets);
      expect(find.text('The shelf — make a list'), findsOneWidget);
      await t.scrollUntilVisible(find.textContaining('Bottles are bought at the counter'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('the law asks for an ID check'), findsOneWidget);
    });

    testWidgets('paused in the rush: it says so, and the basket asks you to order at the bar', (t) async {
      await bootApp(t, prefs: _prefs, signedIn: true, size: const Size(390, 1400));
      const paused = TableInfo(code: 'ab12cd34', venueSlug: 'soka', venueName: 'Soka', tableLabel: 'T4', tableService: true, ordersPaused: true);
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MenuView(menu: sampleMenu(), table: paused, previewOrdering: true)));
      await t.pumpAndSettle();
      expect(find.textContaining('paused phone orders'), findsOneWidget);
      expect(find.text('Call staff'), findsOneWidget, reason: 'a table can still call someone over');
    });

    testWidgets('your order: the number big, the four steps, ready glows', (t) async {
      await bootApp(t, prefs: _prefs, size: const Size(390, 900));
      final o = OrderStatus.fromJson({'id': 'r1', 'status': 'ready', 'point': 'Bar counter', 'point_kind': 'pickup', 'pickup_no': 7, 'lines': [{'name': 'Negroni', 'qty': 1, 'status': 'ready'}]});
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => Scaffold(body: Center(child: OrderCard(order: o)))));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Your number is 7'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 3 of 4: Ready'), findsOneWidget);
      expect(find.text('ready — collect it at Bar counter'), findsOneWidget);
      expect(find.text('Collected'), findsOneWidget, reason: 'a counter\'s last step is collecting, not being served');
    });

    testWidgets('a shop\'s shelf: a list, kept on the phone, shown as a code the till scans', (t) async {
      await bootApp(t, prefs: _prefs, size: const Size(390, 1400));
      const whisky = '3f2b8c1e-9d4a-4e6b-8f00-1a2b3c4d5e6f';
      const tonic = '00000000-0000-4000-8000-000000000001';
      const shelf = Shelf(venueName: 'Cellar Door', currency: 'INR', items: [
        ShelfItem(id: whisky, name: 'Single Malt', brand: 'Amrut', category: 'spirit', size: 750, unit: 'ml', price: 3200, mrp: 3400, alcohol: true),
        ShelfItem(id: tonic, name: 'Tonic Water', category: 'soft', size: 300, unit: 'ml', price: 60),
        ShelfItem(id: '00000000-0000-4000-8000-000000000002', name: 'Cashews', category: 'food', price: 900, byWeight: true),
      ]);
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const ShelfScreen(slug: 'cellar-door', preview: shelf)));
      await t.pumpAndSettle();
      expect(find.text('750 ml · ₹3,200 · MRP ₹3,400'), findsOneWidget);
      expect(find.textContaining('weighed'), findsOneWidget, reason: 'by weight: weighed at the counter, not listed');
      await t.tap(find.byTooltip('Add Amrut Single Malt to the list'));
      await t.pump();
      await t.tap(find.byTooltip('Add Tonic Water to the list'));
      await t.pump();
      await t.tap(find.byTooltip('Add Tonic Water to the list'));
      await t.pumpAndSettle();
      expect(savedList('cellar-door'), {whisky: 1, tonic: 2});
      expect(find.textContaining('the law asks for an ID check'), findsOneWidget);

      await t.tap(find.text('Show it at the till'));
      await t.pumpAndSettle();
      final qr = t.widget<QrImageView>(find.byType(QrImageView));
      final list = parseShopList((qr.key! as ValueKey<String>).value)!;
      expect(list.slug, 'cellar-door');
      expect(list.lines, [(productId: whisky, qty: 1), (productId: tonic, qty: 2)]);
    });
  });
}
