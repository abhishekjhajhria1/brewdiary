// Reading venue_insights() — pure, so it can be tested. Mirrors the rules in
// src/lib/venueAdvisor.ts and the Insights panel on the web: a hidden split stays
// hidden, an average over fewer than k tabs is never shown (it would point at a person).
import '../data/models.dart';

/// The suppression threshold — public.k_anon(). One number, everywhere.
const kAnon = 5;

class InsightsRead {
  /// % of guests who were returning — only when the split itself wasn't hidden.
  final int? returnRate;

  /// Average tab — only over kAnon or more tabs.
  final double? averageTab;

  /// Weekday indexes (0 = Sunday): the busiest, and the quietest that saw ANY visit (a
  /// weekday with none is "never open", which a quiet-night boost doesn't fix).
  final int? busiest;
  final int? deadest;
  const InsightsRead({this.returnRate, this.averageTab, this.busiest, this.deadest});
}

InsightsRead readInsights(VenueInsights ins) {
  int? rate;
  final n = ins.newGuests, r = ins.returningGuests;
  if (n != null && r != null && n + r > 0) rate = (100 * r / (n + r)).round();
  final avg = ins.tabs >= kAnon ? ins.takings / ins.tabs : null;
  final (busy, dead) = peakDays(ins.visitsByDow);
  return InsightsRead(returnRate: rate, averageTab: avg, busiest: busy, deadest: dead);
}

/// Busiest / deadest weekday from the 7-slot visit array (index 0 = Sunday).
(int?, int?) peakDays(List<int> visits) {
  if (visits.length < 7) return (null, null);
  int? busiest, deadest;
  for (var i = 0; i < 7; i++) {
    if (visits[i] <= 0) continue;
    if (busiest == null || visits[i] > visits[busiest]) busiest = i;
    if (deadest == null || visits[i] < visits[deadest]) deadest = i;
  }
  if (busiest == deadest) deadest = null; // one open day: nothing to compare
  return (busiest, deadest);
}

/// "+12% on the 30d before" — or null when there's nothing to compare against.
String? trendLine(double now, double before, String window) {
  if (before <= 0) return null;
  final pct = ((now - before) / before * 100).round();
  if (pct == 0) return 'level with $window';
  return '${pct > 0 ? '+' : ''}$pct% on $window';
}
