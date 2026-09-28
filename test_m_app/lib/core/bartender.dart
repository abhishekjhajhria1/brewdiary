// Ninkasi — the bartender persona. A port of src/lib/bartender.ts. The system prompt
// itself lives server-side (the /api/bartender route); the app only needs the
// context block shape, the starters, and the scripted fallback for when the
// server is unreachable.

const ninkasiName = 'Ninkasi';

class BartenderContext {
  final List<String> recentDrinks;
  final List<String> moods;
  final int total;
  final List<String> friendsPouring;
  final List<String> trending;
  const BartenderContext({
    this.recentDrinks = const [],
    this.moods = const [],
    this.total = 0,
    this.friendsPouring = const [],
    this.trending = const [],
  });

  Map<String, dynamic> toJson() => {
        'recentDrinks': recentDrinks,
        'moods': moods,
        'total': total,
        'friendsPouring': friendsPouring,
        'trending': trending,
      };
}

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String content;
  const ChatMessage(this.role, this.content);
  Map<String, dynamic> toJson() => {'role': role.name, 'content': content};
}

const starters = [
  'What should I pour tonight, Ninkasi?',
  'Something cozy and low-effort.',
  "Pour from what I've been drinking.",
  'A beautiful drink with no alcohol.',
];

/// Scripted reply when the server can't be reached — Ninkasi still speaks, in character.
String fallbackReply(List<ChatMessage> messages, [BartenderContext? ctx]) {
  final users = messages.where((m) => m.role == ChatRole.user).toList();
  final last = users.isEmpty ? '' : users.last.content.toLowerCase();
  final recent = (ctx?.recentDrinks.isNotEmpty ?? false) ? ctx!.recentDrinks.first : null;

  if (RegExp(r'non.?alcohol|na |mocktail|sober|no alcohol').hasMatch(last)) {
    return 'Then let me pour you something bright, darling — lime and soda over crushed ice, a few mint leaves crushed under the spoon, a whisper of honey. Or a cold-brew over ice with a splash of milk, if the night wants quiet. No spirit, all pleasure.';
  }
  if (RegExp(r'cozy|cosy|nightcap|warm|wind down|relax').hasMatch(last)) {
    return recent != null
        ? "You've been keeping company with $recent, I see. For a cozy night I'd set down an Old Fashioned — two ounces of bourbon, a sugar cube, two dashes of bitters, one great piece of ice, an orange peel pressed over the top. Prefer to stay clear-headed? Warm chamomile and honey does the same gentle work."
        : "A cozy night asks for an Old Fashioned, love — bourbon, a sugar cube, two dashes of bitters, one big piece of ice, an orange peel pressed over the glass. Or warm chamomile with honey, if you'd rather keep your head clear.";
  }
  return recent != null
      ? "Lately it's been $recent in your glass. Tonight, step one door over with me — if it's coffee, a cortado; if it's wine, a dry riesling; if it's beer, a saison with a little pepper to it. Tell me the mood you're chasing and I'll pour more precisely."
      : "Tell me the mood you're chasing tonight — cozy, celebratory, clear-headed, or merely curious — and what you tend to like, and I'll pour you something worth writing down.";
}

const offlineNote = "Ninkasi can't reach the bar server right now — she's pouring from memory.";
