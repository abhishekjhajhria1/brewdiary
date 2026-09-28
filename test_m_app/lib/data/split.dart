// Split — Splitwise-style shared tabs among friends. A port of src/lib/expenses.ts.
// Expenses + shares + settlements are stored; each pair's balance is DERIVED
// (computeBalances in core/misc.dart).
import '../core/misc.dart';
import 'auth.dart';
import 'base.dart';

class SplitApi {
  static Future<({List<Expense> expenses, List<Settlement> settlements})> load() async {
    final c = db;
    if (c == null || auth.meId == null) return (expenses: <Expense>[], settlements: <Settlement>[]);
    final results = await Future.wait([
      c.from('expenses').select('id, payer_id, description, amount, created_at, expense_shares(user_id, amount)').order('created_at', ascending: false),
      c.from('settlements').select('id, from_id, to_id, amount, created_at').order('created_at', ascending: false),
    ]);
    final expenses = rows(results[0])
        .map((r) => Expense(
              id: r['id'] as String,
              payerId: r['payer_id'] as String,
              description: r['description'] as String,
              amount: asDouble(r['amount']),
              createdAt: r['created_at'] as String,
              shares: rows(r['expense_shares']).map((s) => ExpenseShare(s['user_id'] as String, asDouble(s['amount']))).toList(),
            ))
        .toList();
    final settlements = rows(results[1])
        .map((r) => Settlement(
              id: r['id'] as String,
              fromId: r['from_id'] as String,
              toId: r['to_id'] as String,
              amount: asDouble(r['amount']),
              createdAt: r['created_at'] as String,
            ))
        .toList();
    return (expenses: expenses, settlements: settlements);
  }

  /// Split `amount` evenly among participants; `payerId` paid the whole thing.
  /// Client-generated id + no re-select (the SECURITY DEFINER read-policy gotcha).
  static Future<String?> addExpense({required String payerId, required String description, required double amount, required List<String> participantIds}) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    final parts = participantIds.toSet().toList();
    if (parts.isEmpty || amount <= 0 || description.trim().isEmpty) return 'invalid';
    final id = newId();
    try {
      await c.from('expenses').insert({'id': id, 'created_by': me, 'payer_id': payerId, 'description': description.trim(), 'amount': amount});
      final amounts = splitEvenly(amount, parts.length);
      await c.from('expense_shares').insert([
        for (var i = 0; i < parts.length; i++) {'expense_id': id, 'user_id': parts[i], 'amount': amounts[i]},
      ]);
      return null;
    } catch (e) {
      return '$e';
    } finally {
      splitRev.bump();
    }
  }

  static Future<void> deleteExpense(String id) async {
    await db?.from('expenses').delete().eq('id', id);
    splitRev.bump();
  }

  /// Record a payback that zeroes (or reduces) a balance.
  static Future<void> settleUp(String friendId, double amount, {required bool friendOwesMe}) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null || amount <= 0) return;
    await c.from('settlements').insert({
      'from_id': friendOwesMe ? friendId : me,
      'to_id': friendOwesMe ? me : friendId,
      'amount': amount,
      'created_by': me,
    });
    splitRev.bump();
  }
}
