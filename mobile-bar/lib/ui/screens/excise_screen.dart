// The excise register — for a liquor store: every bottle's opening, received, sold and
// closing, day by day, read from the same ledger the till writes (050). Shared as CSV
// to fill the state's own form. Managers and owners only.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../logic/counter.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

class ExciseScreen extends StatefulWidget {
  final Venue venue;
  const ExciseScreen({super.key, required this.venue});
  @override
  State<ExciseScreen> createState() => _ExciseScreenState();
}

class _ExciseScreenState extends State<ExciseScreen> {
  int _days = 1;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: _days - 1));
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Excise register',
          subtitle: widget.venue.name,
          back: true,
          tabBar: false,
          maxWidth: kWideMaxWidth,
          children: [
            Segmented<int>(options: const [(1, 'Today'), (7, '7 days'), (30, '30 days')], value: _days, onChanged: (d) => setState(() => _days = d)),
            const SizedBox(height: S.l),
            Loader<List<RegisterRow>>(
              load: () => Backend.i.exciseRegister(widget.venue.id, from, to),
              deps: '$_days',
              refresh: stockRev,
              retry: true,
              builder: (context, rows, loading) {
                if (rows == null) return const Skeleton(height: 200);
                if (rows.isEmpty) return const EmptyNote('No alcohol on the shelf yet — the register lists every bottle you stock.');
                final lastDay = rows.map((r) => r.day).reduce((a, b) => a.isAfter(b) ? a : b);
                final latest = rows.where((r) => r.day == lastDay).toList();
                final totals = {
                  for (final r in rows) r.productId: (rows.where((x) => x.productId == r.productId).fold<(int, int)>((0, 0), (s, x) => (s.$1 + x.received, s.$2 + x.sold))),
                };
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Glass(
                    padding: const EdgeInsets.all(S.l),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingTextStyle: T.label(bd),
                        dataTextStyle: T.sans(bd, size: 14).copyWith(fontFeatures: T.tnum),
                        columnSpacing: S.l,
                        columns: const [
                          DataColumn(label: Text('BOTTLE')),
                          DataColumn(label: Text('OPENING'), numeric: true),
                          DataColumn(label: Text('IN'), numeric: true),
                          DataColumn(label: Text('SOLD'), numeric: true),
                          DataColumn(label: Text('CLOSING'), numeric: true),
                        ],
                        rows: [
                          for (final r in latest)
                            DataRow(cells: [
                              DataCell(Text('${r.brand == null ? '' : '${r.brand} '}${r.name}${r.size == null ? '' : ' ${r.size!.toStringAsFixed(0)} ml'}')),
                              DataCell(Text('${rows.firstWhere((x) => x.productId == r.productId).opening}')),
                              DataCell(Text('${totals[r.productId]!.$1}')),
                              DataCell(Text('${totals[r.productId]!.$2}')),
                              DataCell(Text('${r.closing}')),
                            ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: S.s),
                  Text('Opening is the start of the period, closing the end of it; breakages and counts are in the CSV. Read from the till\'s own ledger.', style: T.caption(bd)),
                  const SizedBox(height: S.l),
                  BdButton('Share as CSV', icon: Ph.shareNetwork, kind: BtnKind.secondary, onTap: () => SharePlus.instance.share(ShareParams(text: registerCsv(rows), subject: 'Excise register — ${widget.venue.name}'))),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}
