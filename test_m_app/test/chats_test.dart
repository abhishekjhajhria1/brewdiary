// Ninkasi's saved chats: a question starts one, answers keep it going, a new
// chat leaves the old one where it was, and any chat can be renamed or deleted.
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/chats.dart';
import 'package:brewdiary_core/bartender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  setUp(() async {
    configureForTests();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  const q1 = ChatMessage(ChatRole.user, 'Something smoky but not too strong, for a long evening with friends?');
  const a1 = ChatMessage(ChatRole.assistant, 'A mezcal highball, love.');

  test('the first question starts a chat and names it', () async {
    final s = ChatStore.instance;
    final c = await s.save([q1, a1]);
    expect(s.chats.single.id, c.id);
    expect(s.currentId, c.id);
    expect(c.title, endsWith('…'));
    expect(c.title.length, lessThanOrEqualTo(42));
  });

  test('a new chat leaves the old one; opening switches back', () async {
    final s = ChatStore.instance;
    final first = await s.save([q1, a1]);
    await s.startNew();
    expect(s.current, isNull);
    final second = await s.save([const ChatMessage(ChatRole.user, 'Tea?'), const ChatMessage(ChatRole.assistant, 'Oolong.')]);
    expect(s.chats.length, 2);
    expect(second.title, 'Tea?');
    await s.open(first.id);
    expect(s.current!.messages.length, 2);
    await s.save([q1, a1, const ChatMessage(ChatRole.user, 'And to eat?'), const ChatMessage(ChatRole.assistant, 'Fries.')]);
    expect(s.chats.first.id, first.id, reason: 'the chat you just used comes first');
    expect(s.chats.first.messages.length, 4);
  });

  test('rename and delete', () async {
    final s = ChatStore.instance;
    final c = await s.save([q1, a1]);
    await s.rename(c.id, '  Smoky ideas ');
    expect(s.chats.single.title, 'Smoky ideas');
    await s.delete(c.id);
    expect(s.chats, isEmpty);
    expect(s.currentId, isNull);
  });
}
