// A pushed page in the house style (Discover, a party, a profile, Split).
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

class SubPage extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool scroll;
  const SubPage({super.key, this.title, required this.child, this.scroll = true});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final header = Glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Text('‹  Back', style: T.sans(bd, size: 14, color: bd.muted))),
        ),
        const Spacer(),
        if (title != null) Text(title!, style: T.serif(bd, size: 18, italic: true, color: bd.muted)),
        const SizedBox(width: 8),
      ]),
    );
    return Scaffold(
      backgroundColor: bd.base,
      body: Ambient(
        child: scroll
            ? ListView(padding: EdgeInsets.fromLTRB(16, top + 12, 16, bottom + 40), children: [header, const SizedBox(height: 24), child])
            : Padding(padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0), child: Column(children: [header, const SizedBox(height: 24), Expanded(child: child)])),
      ),
    );
  }
}
