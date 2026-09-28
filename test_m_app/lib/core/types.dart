// Core data shapes — a port of src/lib/types.ts.
// Only `Entry` rows are ever written; the mosaic, streaks, milestones, lexicon and
// recent-drinks are all DERIVED from entries (see derive.dart), never stored.

enum DrinkType {
  coffee,
  tea,
  beer,
  wine,
  cocktail,
  spirit,
  soft,
  other,

  /// A DRY DAY — a day you logged with nothing in the glass. It keeps the streak
  /// (the streak is for showing up to the diary, not for drinking) but it is not
  /// a drink: it never counts toward totals, the mosaic, or your lexicon.
  none;

  static DrinkType? parse(String? s) {
    if (s == null) return null;
    for (final t in DrinkType.values) {
      if (t.name == s) return t;
    }
    return null;
  }
}

class Photo {
  final String id;

  /// A remote URL once synced, or a local file path before upload.
  final String url;

  const Photo({required this.id, required this.url});

  bool get isLocal => !url.startsWith('http');

  Map<String, dynamic> toJson() => {'id': id, 'url': url};
  factory Photo.fromJson(Map<String, dynamic> j) => Photo(id: j['id'] as String, url: j['url'] as String);
}

enum EntryVisibility { private, friends }

class Entry {
  final String id;

  /// The calendar day this entry is FOR (YYYY-MM-DD). Backfillable.
  final String date;

  /// Actual moment it was created (ISO). Drives time-of-day; distinct from `date`.
  final String createdAt;
  final String drink;
  final DrinkType? type;

  /// One word for how the moment felt — never a rating.
  final String? mood;
  final String? note;
  final List<Photo>? photos;
  final String? venue;
  final List<String>? whoWith;
  final EntryVisibility visibility;

  const Entry({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.drink,
    this.type,
    this.mood,
    this.note,
    this.photos,
    this.venue,
    this.whoWith,
    this.visibility = EntryVisibility.private,
  });

  Entry copyWith({
    String? date,
    String? drink,
    DrinkType? Function()? type,
    String? Function()? mood,
    String? Function()? note,
    List<Photo>? Function()? photos,
    String? Function()? venue,
    List<String>? Function()? whoWith,
    EntryVisibility? visibility,
  }) {
    return Entry(
      id: id,
      date: date ?? this.date,
      createdAt: createdAt,
      drink: drink ?? this.drink,
      type: type != null ? type() : this.type,
      mood: mood != null ? mood() : this.mood,
      note: note != null ? note() : this.note,
      photos: photos != null ? photos() : this.photos,
      venue: venue != null ? venue() : this.venue,
      whoWith: whoWith != null ? whoWith() : this.whoWith,
      visibility: visibility ?? this.visibility,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'createdAt': createdAt,
        'drink': drink,
        if (type != null) 'type': type!.name,
        if (mood != null) 'mood': mood,
        if (note != null) 'note': note,
        if (photos != null) 'photos': photos!.map((p) => p.toJson()).toList(),
        if (venue != null) 'venue': venue,
        if (whoWith != null) 'whoWith': whoWith,
        'visibility': visibility.name,
      };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        date: j['date'] as String,
        createdAt: j['createdAt'] as String,
        drink: j['drink'] as String,
        type: DrinkType.parse(j['type'] as String?),
        mood: j['mood'] as String?,
        note: j['note'] as String?,
        photos: (j['photos'] as List?)?.map((p) => Photo.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
        venue: j['venue'] as String?,
        whoWith: (j['whoWith'] as List?)?.cast<String>(),
        visibility: j['visibility'] == 'friends' ? EntryVisibility.friends : EntryVisibility.private,
      );

  /// Validates a raw imported row — a bad file must never crash the app later.
  static Entry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final dayKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (m['id'] is! String || m['date'] is! String || m['createdAt'] is! String || m['drink'] is! String) return null;
    if (!dayKey.hasMatch(m['date'] as String)) return null;
    if (m['photos'] != null && m['photos'] is! List) return null;
    if (m['whoWith'] != null && m['whoWith'] is! List) return null;
    try {
      return Entry.fromJson(m);
    } catch (_) {
      return null;
    }
  }
}

/// The label a dry-day entry carries, so it reads as a sentence in a list.
const dryDayLabel = 'dry day';

/// 'none' is deliberately absent — a dry day is its own action in the log sheet.
const drinkTypes = <(DrinkType, String)>[
  (DrinkType.coffee, 'Coffee'),
  (DrinkType.tea, 'Tea'),
  (DrinkType.beer, 'Beer'),
  (DrinkType.wine, 'Wine'),
  (DrinkType.cocktail, 'Cocktail'),
  (DrinkType.spirit, 'Spirit'),
  (DrinkType.soft, 'Soft'),
  (DrinkType.other, 'Other'),
];
