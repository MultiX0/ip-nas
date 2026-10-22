// Riverpod providers for the chat UI.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_db.dart' hide LlmModel;
import 'data/chat_repo.dart';

/// Visible thread of a chat, recomputed when the chat or any of its messages change.
final threadProvider = StreamProvider.autoDispose.family<ThreadData, String>((ref, chatId) {
  final repo = ref.watch(chatRepoProvider);
  Chat? chat;
  List<Message>? msgs;
  final c = StreamController<ThreadData>();
  void emit() {
    if (msgs != null) c.add(buildThread(chat, msgs!));
  }

  final a = repo.watchChat(chatId).listen((v) {
    chat = v;
    emit();
  }, onError: c.addError);
  final b = repo.watchMessages(chatId).listen((v) {
    msgs = v;
    emit();
  }, onError: c.addError);
  ref.onDispose(() {
    a.cancel();
    b.cancel();
    c.close();
  });
  return c.stream;
});

final chatListProvider = StreamProvider.autoDispose.family<List<Chat>, bool>((ref, archived) => ref.watch(chatRepoProvider).watchChats(archived: archived));

/// Display items derived from a thread.
sealed class ChatItem {
  const ChatItem();
  String get key;
}

class UserItem extends ChatItem {
  final Message msg;
  final List<Message> siblings;
  const UserItem(this.msg, this.siblings);
  @override
  String get key => msg.id;
}

class AssistantItem extends ChatItem {
  final String? userId;
  final List<Message> group; // assistant messages of one turn (tool loop iterations)
  final Map<String, Message> toolResults; // tool messages by toolCallId
  final List<Message> siblings; // alternative replies to the same user message
  const AssistantItem(this.userId, this.group, this.toolResults, this.siblings);
  Message get first => group.first;
  Message get last => group.last;
  @override
  String get key => group.first.id;
  String get fullText => group.map((m) => m.content.trim()).where((s) => s.isNotEmpty).join('\n\n');
}

class MarkerItem extends ChatItem {
  final Message msg;
  const MarkerItem(this.msg);
  @override
  String get key => msg.id;
}

List<ChatItem> buildItems(ThreadData t) {
  final items = <ChatItem>[];
  String? lastUser;
  List<Message>? group;
  Map<String, Message>? tools;
  void close() {
    if (group != null && group!.isNotEmpty) {
      final first = group!.first;
      final sibs = (t.children[first.parentId] ?? [first]).where((m) => m.role == 'assistant').toList();
      items.add(AssistantItem(lastUser, group!, tools!, sibs.isEmpty ? [first] : sibs));
    }
    group = null;
    tools = null;
  }

  for (final m in t.path) {
    if (m.kind != 'message') {
      close();
      items.add(MarkerItem(m));
      continue;
    }
    switch (m.role) {
      case 'user':
        close();
        lastUser = m.id;
        final sibs = (t.children[m.parentId] ?? [m]).where((x) => x.role == 'user').toList();
        items.add(UserItem(m, sibs.isEmpty ? [m] : sibs));
      case 'assistant':
        group ??= [];
        tools ??= {};
        group!.add(m);
      case 'tool':
        if (group == null) continue;
        if (m.toolCallId != null) tools![m.toolCallId!] = m;
    }
  }
  close();
  return items;
}
