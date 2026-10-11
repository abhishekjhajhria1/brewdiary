// Ninkasi — the bartender persona. A port of src/lib/bartender.ts. The system prompt
// itself lives server-side (the /api/bartender route); the app only needs the
// context block shape and the starters. There is no scripted stand-in: she is the
// real model or honestly away.

const ninkasiName = 'Ninkasi';

class BartenderContext {
  final List<String> recentDrinks;
  final List<String> moods;
  final int total;
  final List<String> friendsPouring;
  final List<String> trending;

  /// What they keep at home (You → Your bar), so Ninkasi can suggest what they can make.
  final List<String> homeBar;

  /// Their palate's top flavour notes.
  final List<String> palate;
  const BartenderContext({
    this.recentDrinks = const [],
    this.moods = const [],
    this.total = 0,
    this.friendsPouring = const [],
    this.trending = const [],
    this.homeBar = const [],
    this.palate = const [],
  });

  Map<String, dynamic> toJson() => {
        'recentDrinks': recentDrinks,
        'moods': moods,
        'total': total,
        'friendsPouring': friendsPouring,
        'trending': trending,
        if (homeBar.isNotEmpty) 'homeBar': homeBar,
        if (palate.isNotEmpty) 'palate': palate,
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

