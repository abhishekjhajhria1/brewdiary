// Small pure helpers ported from several web modules (geohash.ts, plans.ts,
// challenges.ts, expenses.ts, verify.ts, waterPref.ts). Kept together because each
// is a handful of lines and none touches I/O.
import 'date.dart';

// ── geohash (trends.ts / geohash.ts) ─────────────────────────────────────────
/// ~20 km cell: fine enough for "your area", coarse enough to never pinpoint anyone.
const areaPrecision = 4;
const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

String encodeGeohash(double lat, double lon, [int precision = areaPrecision]) {
  var idx = 0, bit = 0;
  var evenBit = true;
  final hash = StringBuffer();
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  while (hash.length < precision) {
    if (evenBit) {
      final mid = (lonMin + lonMax) / 2;
      if (lon >= mid) {
        idx = idx * 2 + 1;
        lonMin = mid;
      } else {
        idx = idx * 2;
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        idx = idx * 2 + 1;
        latMin = mid;
      } else {
        idx = idx * 2;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bit == 5) {
      hash.write(_base32[idx]);
      bit = 0;
      idx = 0;
    }
  }
  return hash.toString();
}

// ── plans.ts ─────────────────────────────────────────────────────────────────
/// Tidy a tag list: trimmed, lowercased, de-duped, capped in count and length.
List<String> dedupeTags(List<String>? tags) {
  if (tags == null) return [];
  final seen = <String>{};
  final out = <String>[];
  for (final raw in tags) {
    var t = raw.trim().toLowerCase();
    if (t.length > 24) t = t.substring(0, 24);
    if (t.isNotEmpty && seen.add(t)) {
      out.add(t);
      if (out.length >= 8) break;
    }
  }
  return out;
}

// ── challenges.ts ────────────────────────────────────────────────────────────
/// Longest consecutive-day run in a set of ISO dates.
int longestRun(List<String> dates) {
  if (dates.isEmpty) return 0;
  final days = dates.toSet().toList()..sort();
  var best = 1, run = 1;
  for (var i = 1; i < days.length; i++) {
    final prev = DateTime.parse('${days[i - 1]}T00:00:00Z');
    final cur = DateTime.parse('${days[i]}T00:00:00Z');
    if (cur.difference(prev).inDays == 1) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

// ── expenses.ts (Split) ──────────────────────────────────────────────────────
class ExpenseShare {
  final String userId;
  final double amount;
  const ExpenseShare(this.userId, this.amount);
}

class Expense {
  final String id;
  final String payerId;
  final String description;
  final double amount;
  final String createdAt;
  final List<ExpenseShare> shares;
  const Expense({required this.id, required this.payerId, required this.description, required this.amount, required this.createdAt, required this.shares});
}

class Settlement {
  final String id;
  final String fromId;
  final String toId;
  final double amount;
  final String createdAt;
  const Settlement({required this.id, required this.fromId, required this.toId, required this.amount, required this.createdAt});
}

/// Net balance per other-user id. Positive = they owe you; negative = you owe them.
Map<String, double> computeBalances(List<Expense> expenses, List<Settlement> settlements, String me) {
  final bal = <String, double>{};
  void add(String id, double delta) => bal[id] = (bal[id] ?? 0) + delta;

  for (final e in expenses) {
    for (final s in e.shares) {
      if (s.userId == e.payerId) continue;
      if (e.payerId == me) {
        add(s.userId, s.amount);
      } else if (s.userId == me) {
        add(e.payerId, -s.amount);
      }
    }
  }
  for (final st in settlements) {
    if (st.fromId == me) {
      add(st.toId, st.amount);
    } else if (st.toId == me) {
      add(st.fromId, -st.amount);
    }
  }
  bal.removeWhere((_, v) => v.abs() < 0.005);
  return bal;
}

/// Even split with the last participant absorbing the rounding remainder, so the
/// shares always sum to the total.
List<double> splitEvenly(double amount, int parts) {
  final each = (amount / parts * 100).round() / 100;
  return List.generate(parts, (i) => i == parts - 1 ? ((amount - each * (parts - 1)) * 100).round() / 100 : each);
}

// ── verify.ts — the free TRUST LEVEL ─────────────────────────────────────────
enum TrustLevel { fresh, active, established, trusted }

const trustLabel = {TrustLevel.fresh: 'New here', TrustLevel.active: 'Active', TrustLevel.established: 'Established', TrustLevel.trusted: 'Trusted'};

class TrustSignals {
  final int tenureDays;
  final int activeDays;
  final int friends;
  final bool presenceChecked;
  final int vouches;
  const TrustSignals({required this.tenureDays, required this.activeDays, required this.friends, this.presenceChecked = false, this.vouches = 0});
}

double trustScore(TrustSignals s) {
  final tenure = (s.tenureDays > 90 ? 90 : s.tenureDays) / 9;
  final active = (s.activeDays > 30 ? 30 : s.activeDays) / 3;
  final social = (s.friends > 8 ? 8 : s.friends) * 1.25;
  final presence = s.presenceChecked ? 8 : 0;
  final vouched = (s.vouches > 5 ? 5 : s.vouches) * 3;
  return tenure + active + social + presence + vouched;
}

/// Free signals alone top out at 'established' (max 30 < 34) — 'trusted' needs a
/// strong signal (a live check or vouches).
TrustLevel trustLevelFrom(TrustSignals s) {
  final score = trustScore(s);
  if (score >= 34) return TrustLevel.trusted;
  if (score >= 14) return TrustLevel.established;
  if (score >= 4) return TrustLevel.active;
  return TrustLevel.fresh;
}

// ── waterPref.ts ─────────────────────────────────────────────────────────────
/// 750 → "750 ml", 1500 → "1.5 L".
String formatVolume(int ml) {
  if (ml >= 1000) return '${(ml / 1000).toStringAsFixed(ml % 1000 == 0 ? 0 : 1)} L';
  return '$ml ml';
}

// ── age.ts ───────────────────────────────────────────────────────────────────
int ageFrom(DateTime dob, [DateTime? now]) {
  final n = now ?? appNow();
  var age = n.year - dob.year;
  final m = n.month - dob.month;
  if (m < 0 || (m == 0 && n.day < dob.day)) age--;
  return age;
}
