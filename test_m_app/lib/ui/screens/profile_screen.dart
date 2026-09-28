// Opt-in public profile — a port of src/components/profile/PublicProfile.tsx.
// A streak mosaic and totals — never notes, never spend, never where.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/safety.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';

class PublicProfileScreen extends StatelessWidget {
  final String handle;
  const PublicProfileScreen({super.key, required this.handle});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<PublicProfileData?>(
      failed: (context, retry) => SubPage(title: '@$handle', large: false, child: LoadError(onRetry: retry)),
      load: () => DiscoverApi.publicProfile(handle),
      builder: (context, p, loading) {
        if (p == null) {
          return SubPage(
            title: '@$handle',
            large: false,
            child: loading
                ? const Column(children: [Skeleton(height: 80), SizedBox(height: S.m), Skeleton(height: 160)])
                : const EmptyNote("Nothing to see here — this profile is private, or the handle doesn't exist.", icon: Ph.lock),
          );
        }
        final social = p.socialHandle;
        final link = social != null && social.startsWith('http') ? Uri.tryParse(social) : null;
        Widget stat(int v, String label) => Expanded(
              child: Glass(
                padding: const EdgeInsets.all(S.l),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$v', style: T.serif(bd, size: 32).copyWith(fontFeatures: T.tnum)),
                  const SizedBox(height: 2),
                  Text(label, style: T.caption(bd)),
                ]),
              ),
            );
        return SubPage(
          title: p.displayName,
          subtitle: '@${p.handle}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [stat(p.total, 'logged'), const SizedBox(width: S.m), stat(p.kinds, 'kinds')]),
            const SectionHeader('Last 12 weeks'),
            Glass(padding: const EdgeInsets.all(S.l), child: RecentMosaic(counts: p.counts)),
            if (social != null && social.isNotEmpty) ...[
              const SizedBox(height: S.l),
              Group(children: [
                GroupTile(
                  icon: Ph.linkSimple,
                  title: social,
                  trailing: link == null ? null : Icon(Ph.arrowUpRight, size: 16, color: bd.faint),
                  onTap: link == null ? null : () => launchUrl(link, mode: LaunchMode.externalApplication),
                ),
              ]),
            ],
            const SizedBox(height: S.xl),
            Text('A mosaic and totals only — never notes, never spend, never where.', style: T.caption(bd)),
          ]),
        );
      },
    );
  }
}
