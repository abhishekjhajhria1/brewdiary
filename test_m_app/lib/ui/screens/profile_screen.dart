// Opt-in public profile — a port of src/components/profile/PublicProfile.tsx.
// A streak mosaic and totals — never notes, never spend, never where.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/safety.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mosaic.dart';
import '../widgets/sub_page.dart';

class PublicProfileScreen extends StatelessWidget {
  final String handle;
  const PublicProfileScreen({super.key, required this.handle});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SubPage(
      title: 'profile',
      child: Loader<PublicProfileData?>(
        load: () => DiscoverApi.publicProfile(handle),
        builder: (context, p, loading) {
          if (loading && p == null) return const Skeleton(height: 200);
          if (p == null) {
            return Column(children: [
              const SizedBox(height: 40),
              Text('Nothing to see here.', style: T.serif(bd, size: 26)),
              const SizedBox(height: 8),
              Text("This profile is private, or the handle doesn't exist.", textAlign: TextAlign.center, style: T.sans(bd, size: 14, color: bd.muted)),
            ]);
          }
          final social = p.socialHandle;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Initial(p.displayName.isEmpty ? '?' : p.displayName[0].toUpperCase(), size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.displayName, style: T.serif(bd, size: 30)),
                  Text('@${p.handle}', style: T.sans(bd, size: 14, color: bd.faint)),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text('${p.total}', style: T.sans(bd, size: 26, weight: FontWeight.w600)),
                    const Label('logged'),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text('${p.kinds}', style: T.sans(bd, size: 26, weight: FontWeight.w600)),
                    const Label('kinds'),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Label('Last 12 weeks', color: bd.faint),
            const SizedBox(height: 12),
            Glass(padding: const EdgeInsets.all(16), child: RecentMosaic(counts: p.counts)),
            if (social != null && social.isNotEmpty) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  final uri = social.startsWith('http') ? Uri.tryParse(social) : null;
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Text(social, style: T.sans(bd, color: bd.accent)),
              ),
            ],
            const SizedBox(height: 24),
            Text('A mosaic and totals only — never notes, never spend, never where.', style: T.sans(bd, size: 12, color: bd.faint)),
          ]);
        },
      ),
    );
  }
}
