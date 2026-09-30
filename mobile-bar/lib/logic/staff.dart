// Staff access (supabase/053): the words and small rules around adding an employee with
// the owner's code, pausing someone's access, the team's history and the time clock.
// Pure functions, so the tests can hold every sentence to account. The DATABASE decides
// who may do what; this only says it plainly.

/// Where someone stands on a team: waiting for a manager's yes, working, or paused.
enum StaffStatus {
  pending('pending'),
  active('active'),
  locked('locked');

  final String db;
  const StaffStatus(this.db);

  /// Anything unknown reads as active: a database a migration behind has no status yet.
  static StaffStatus parse(String? s) => StaffStatus.values.firstWhere((x) => x.db == s, orElse: () => StaffStatus.active);
}

/// Why the owner's code didn't let someone in (claim_staff_enrolment's `error`).
enum ClaimError {
  notFound('not_found'),
  closed('closed'),
  expired('expired'),
  tooMany('too_many'),
  wrongCode('wrong_code'),
  locked('locked');

  final String db;
  const ClaimError(this.db);
  static ClaimError parse(String? s) => ClaimError.values.firstWhere((x) => x.db == s, orElse: () => ClaimError.notFound);
}

/// The sentence for a code that didn't work. [left] is the tries left after a wrong one.
String claimMessage(ClaimError e, {int? left, String? addedBy}) {
  final who = (addedBy == null || addedBy.trim().isEmpty) ? 'your manager' : addedBy.trim();
  return switch (e) {
    ClaimError.wrongCode => left == null
        ? 'That\'s not the code — check it with $who.'
        : 'That\'s not the code — ${left == 1 ? '1 try' : '$left tries'} left.',
    ClaimError.tooMany => 'Too many wrong tries — ask $who for a new code.',
    ClaimError.expired => 'That code has run out — ask $who for a new one.',
    ClaimError.closed => 'That code was replaced or cancelled — ask $who for the new one.',
    ClaimError.notFound => 'That code isn\'t for this account — sign in with the email $who added.',
    ClaimError.locked => 'Your access here is paused — talk to $who.',
  };
}

/// The code as typed: digits only, at most six (a pasted "482 913" still works).
String codeDigits(String typed) {
  final d = typed.replaceAll(RegExp(r'\D'), '');
  return d.length > 6 ? d.substring(0, 6) : d;
}

// The same shapes the database checks (enrol_staff, set_staff_details), so the form can
// say what's wrong before it asks.
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _phone = RegExp(r'^\+?[0-9 ()-]{6,20}$');
bool validStaffEmail(String s) {
  final t = s.trim();
  return t.length <= 254 && _email.hasMatch(t);
}

bool validStaffPhone(String s) => _phone.hasMatch(s.trim());

/// "a server", "an owner", "kitchen staff" — a role word in a sentence.
String roleWithArticle(String roleWord) {
  final w = roleWord.trim().toLowerCase();
  if (w == 'kitchen') return 'kitchen staff';
  return '${RegExp(r'^[aeiou]').hasMatch(w) ? 'an' : 'a'} $w';
}

/// What the employee is sent, with the code in it. The code only works with [email].
String enrolShareText({required String venue, required String roleWord, required String email, required String code, int hours = 48}) =>
    'You\'ve been added to $venue on brewdiary bar as ${roleWithArticle(roleWord)}. '
    'Install brewdiary bar, sign in with $email, and type this code: $code. It works for $hours hours, once.';

/// "runs out in 31h" / "runs out in 40 min" / "ran out".
String codeLifeLeft(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left.inMinutes <= 0) return 'ran out';
  if (left.inMinutes < 60) return 'runs out in ${left.inMinutes} min';
  return 'runs out in ${left.inHours}h';
}

/// "Please report to Arjun (manager)." — or a plain line when nobody was named.
String reportLine(String? reportTo, String? reportToRole) {
  final who = reportTo?.trim() ?? '';
  if (who.isEmpty) return 'Please talk to the owner or a manager.';
  final role = (reportToRole == null || reportToRole.isEmpty) ? '' : ' ($reportToRole)';
  return 'Please report to $who$role.';
}

/// Minutes as hours: "0m", "45m", "3h", "7h 05m".
String formatMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Monday 00:00 of [now]'s week, local time: where "this week's hours" start.
DateTime weekStart(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// One line of the team's history. [roleWord] turns a role's key ('server') into the
/// venue's word for it ('Server'; a café's 'Barista').
String describeStaffEvent({
  required String kind,
  String? actor,
  String? subject,
  Map<String, dynamic> detail = const {},
  required String Function(String roleDb) roleWord,
}) {
  final a = (actor == null || actor.isEmpty) ? 'Someone' : actor;
  final s = (subject == null || subject.isEmpty) ? 'someone' : subject;
  final named = (detail['name'] as String?)?.trim();
  final who = (named == null || named.isEmpty) ? 'someone' : named;
  String role(String key) => (detail[key] is String) ? roleWord(detail[key] as String).toLowerCase() : 'staff';
  String asRole(String key) => roleWithArticle(role(key));
  final reason = (detail['reason'] as String?)?.trim();
  return switch (kind) {
    'enrolled' => '$a added $who as ${asRole('role')}',
    'code_reissued' => '$a made a new code for $who',
    'enrolment_revoked' => '$a cancelled $who\'s code',
    'requested' => '$s asked to join as ${asRole('role')}',
    'joined' => switch (detail['via']) {
        'code' => '$s joined as ${asRole('role')} with the owner\'s code',
        'created' => '$s created the venue',
        _ => '$a added $s as ${asRole('role')}',
      },
    'approved' => '$a approved $s as ${asRole('role')}',
    'declined' => '$a said no to $s',
    'role_changed' => '$a made $s ${asRole('to')} (was ${role('from')})',
    'locked' => reason == null || reason.isEmpty ? '$a paused $s\'s access' : '$a paused $s\'s access: \u201c$reason\u201d',
    'unlocked' => '$a gave $s access again',
    'removed' => '$a removed $s from the team',
    'left' => '$s left the team',
    'details_changed' => '$a updated $s\'s details',
    'shift_ended_by_manager' => '$a clocked $s out',
    _ => '$a changed something for $s',
  };
}
