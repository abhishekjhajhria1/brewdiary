// Ninkasi's saved conversations, kept on this phone: pick one up where you left
// it, start a new one, rename or delete any. They also go into "Your diary, as a
// book". (Sending chats to the training set is separate — see TrainingStore.)
import 'package:flutter/foundation.dart';

import 'package:brewdiary_core/bartender.dart';
import 'package:brewdiary_core/date.dart';

import 'base.dart';

class Chat {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  const Chat({required this.id, required this.title, required this.createdAt, required this.updatedAt, required this.messages});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'messages': [for (final m in messages) m.toJson()],
      };

  static Chat? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      return Chat(
        id: raw['id'] as String,
        title: (raw['title'] as String?) ?? 'A chat',
        createdAt: DateTime.fromMillisecondsSinceEpoch((raw['createdAt'] as num).toInt()),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((raw['updatedAt'] as num).toInt()),
        messages: [
          for (final m in (raw['messages'] as List? ?? const []))
            if (m is Map && m['content'] is String) ChatMessage(m['role'] == 'user' ? ChatRole.user : ChatRole.assistant, m['content'] as String),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// A chat's title from its first question: short, one line.
String chatTitleFrom(String question) {
  final t = question.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return 'A chat';
  return t.length <= 42 ? t : '${t.substring(0, 40).trimRight()}…';
}

class ChatStore extends ChangeNotifier {
  static final instance = ChatStore();
  static const _key = 'brewdiary.chats.v1';
  static const _currentKey = 'brewdiary.chats.current';
  static const maxChats = 100;
  static const maxMessages = 200;

  /// Newest first.
  List<Chat> get chats {
    final list = (Prefs.getJson<List<dynamic>>(_key) ?? const []).map(Chat.tryParse).whereType<Chat>().toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String? get currentId => Prefs.getString(_currentKey);
  Chat? get current => chats.where((c) => c.id == currentId).firstOrNull;

  Future<void> _write(List<Chat> list) async {
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await Prefs.setJson(_key, [for (final c in list.take(maxChats)) c.toJson()]);
    notifyListeners();
  }

  /// Save [messages] into the current chat, starting one if there isn't one.
  Future<Chat> save(List<ChatMessage> messages) async {
    final now = appNow();
    final list = chats;
    final id = currentId;
    final i = id == null ? -1 : list.indexWhere((c) => c.id == id);
    final kept = messages.length > maxMessages ? messages.sublist(messages.length - maxMessages) : messages;
    final Chat chat;
    if (i >= 0) {
      chat = Chat(id: list[i].id, title: list[i].title, createdAt: list[i].createdAt, updatedAt: now, messages: kept);
      list[i] = chat;
    } else {
      final first = kept.where((m) => m.role == ChatRole.user).firstOrNull?.content ?? '';
      chat = Chat(id: newId(), title: chatTitleFrom(first), createdAt: now, updatedAt: now, messages: kept);
      list.add(chat);
      await Prefs.setString(_currentKey, chat.id);
    }
    await _write(list);
    return chat;
  }

  /// Leave the current chat; the next question starts a new one.
  Future<void> startNew() async {
    await Prefs.remove(_currentKey);
    notifyListeners();
  }

  Future<void> open(String id) async {
    await Prefs.setString(_currentKey, id);
    notifyListeners();
  }

  Future<void> rename(String id, String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await _write([for (final c in chats) c.id == id ? Chat(id: c.id, title: t.length > 60 ? t.substring(0, 60) : t, createdAt: c.createdAt, updatedAt: c.updatedAt, messages: c.messages) : c]);
  }

  Future<void> delete(String id) async {
    if (currentId == id) await Prefs.remove(_currentKey);
    await _write(chats.where((c) => c.id != id).toList());
  }
}
