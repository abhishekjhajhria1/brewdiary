// Scanning and tags — the twin of tests/scanCodes.test.ts (same cases).
import 'package:brewdiary_core/links.dart';
import 'package:test/test.dart';

void main() {
  const a = '3f2b8c1e-9d4a-4e6b-8f00-1a2b3c4d5e6f';
  const b = '00000000-0000-4000-8000-000000000001';

  group('a scan is read for what it is', () {
    test('our links: a table, a menu, the ready board', () {
      expect(classifyScan('https://bwdy.site/t/ab12cd34'), (kind: ScanKind.table, value: 'ab12cd34'));
      expect(classifyScan('https://www.bwdy.site/m/the-amber-room'), (kind: ScanKind.menu, value: 'the-amber-room'));
      expect(classifyScan('https://bwdy.site/ready/ab12cd34'), (kind: ScanKind.ready, value: 'ab12cd34'));
      expect(readyUrl('ab12cd34'), 'https://bwdy.site/ready/ab12cd34');
    });

    test('a look-alike host, another scheme, or a stale code is nothing', () {
      expect(classifyScan('https://bwdy.site.evil.com/t/ab12cd34').kind, ScanKind.unknown);
      expect(classifyScan('ftp://bwdy.site/t/ab12cd34').kind, ScanKind.unknown);
      expect(classifyScan('https://bwdy.site/t/short').kind, ScanKind.unknown);
      expect(classifyScan('hello').kind, ScanKind.unknown);
    });

    test('a guest card: the 6 letters, scanned or typed', () {
      expect(guestCardQr('k7m2pq'), 'bwdy:g:K7M2PQ');
      expect(classifyScan('bwdy:g:K7M2PQ'), (kind: ScanKind.guestCard, value: 'K7M2PQ'));
      expect(guestCodeFromScan(' k7m2pq '), 'K7M2PQ');
      expect(guestCodeFromScan('bwdy:g:K7M2P0'), isNull, reason: 'no 0, O, 1 or I in a code');
      expect(classifyScan('bwdy:g:nope').kind, ScanKind.unknown);
    });
  });

  group('a shopping list', () {
    test('ids pack to 22 characters and back', () {
      expect(packId(a).length, 22);
      expect(unpackId(packId(a)), a);
      expect(unpackId(packId(b)), b);
      expect(unpackId('short'), isNull);
    });

    test('round trip: the shop and its lines; the same product twice adds up', () {
      final qr = shopListQr('Cellar-Door', [(productId: a, qty: 2), (productId: b, qty: 1), (productId: a, qty: 1)]);
      expect(qr, startsWith('bwdy:l:cellar-door:'));
      final l = parseShopList(qr)!;
      expect(l.slug, 'cellar-door');
      expect(l.lines, [(productId: a, qty: 3), (productId: b, qty: 1)]);
      expect(classifyScan(qr).kind, ScanKind.shopList);
    });

    test('quantities stay 1–99; a broken list is nothing', () {
      expect(parseShopList(shopListQr('shop', [(productId: a, qty: 250)]))!.lines.single.qty, 99);
      expect(parseShopList('bwdy:l:shop:${packId(a)}.0'), isNull);
      expect(parseShopList('bwdy:l:shop:'), isNull);
      expect(parseShopList('bwdy:l:Bad Slug:${packId(a)}.1'), isNull);
      expect(parseShopList('bwdy:l:shop:zzz.1'), isNull);
    });

    test('packs the same as the website (a list made on the web scans at the till)', () {
      expect(packId(a), 'PyuMHp1KTmuPABorPE1ebw');
    });
  });

  group('an NFC tag holds the link in a few bytes', () {
    test('https:// becomes one byte, and reads back', () {
      final p = ndefUriPayload('https://bwdy.site/t/ab12cd34');
      expect(p.first, 4);
      expect(p.length, 1 + 'bwdy.site/t/ab12cd34'.length);
      expect(uriFromNdefPayload(p), 'https://bwdy.site/t/ab12cd34');
      expect(ndefUriPayload('https://www.bwdy.site/m/x1').first, 2);
      expect(uriFromNdefPayload([99, 65]), isNull);
      expect(uriFromNdefPayload(const []), isNull);
    });
  });
}
