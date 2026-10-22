// Chat persistence helpers: chats, branching threads, search, export.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/contracts/llm.dart';
import '../../../core/providers.dart';
import '../../../data/db/app_db.dart' hide LlmModel;

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Per-chat composer settings stored in Chats.settingsJson.
class ChatSettings {
  final ReasoningLevel? reasoning;
  final bool tools;
  const ChatSettings({this.reasoning, this.tools = true});
  factory ChatSettings.parse(String? s) {
    try {
      final j = jsonDecode(s ?? '{}') as Map<String, dynamic>;
      return ChatSettings(
        reasoning: ReasoningLevel.values.where((l) => l.name == j['reasoning']).firstOrNull,
        tools: j['tools'] != false,
      );
    } catch (_) {
      return const ChatSettings();
    }
  }
  String encode() => jsonEncode({if (reasoning != null) 'reasoning': reasoning!.name, 'tools': tools});
  ChatSettings copyWith({ReasoningLevel? reasoning, bool? tools}) => ChatSettings(reasoning: reasoning ?? this.reasoning, tools: tools ?? this.tools);
}

/// The visible thread of a chat plus the branch tree.
class ThreadData {
  final Chat? chat;
  final List<Message> path;
  final Map<String?, List<Message>> children;
  const ThreadData(this.chat, this.path, this.children);
  static const empty = ThreadData(null, [], {});
}

ThreadData buildThread(Chat? chat, List<Message> all) {
  final byId = {for (final m in all) m.id: m};
  final children = <String?, List<Message>>{};
  for (final m in all) {
    (children[m.parentId] ??= []).add(m);
  }
  for (final l in children.values) {
    l.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  Message? leaf = chat?.activeLeafId == null ? null : byId[chat!.activeLeafId];
  if (leaf == null && all.isNotEmpty) {
    leaf = all.reduce((a, b) => b.createdAt.isAfter(a.createdAt) ? b : a);
  }
  final path = <Message>[];
  final seen = <String>{};
  var cur = leaf;
  while (cur != null && seen.add(cur.id)) {
    path.add(cur);
    cur = cur.parentId == null ? null : byId[cur.parentId];
  }
  return ThreadData(chat, path.reversed.toList(), children);
}

class ChatRepo {
  ChatRepo(this.db);
  final AppDb db;

  Stream<Chat?> watchChat(String id) => (db.select(db.chats)..where((c) => c.id.equals(id))).watchSingleOrNull();
  Future<Chat?> getChat(String id) => (db.select(db.chats)..where((c) => c.id.equals(id))).getSingleOrNull();

  Stream<List<Message>> watchMessages(String chatId) =>
      (db.select(db.messages)..where((m) => m.chatId.equals(chatId))..orderBy([(m) => OrderingTerm.asc(m.createdAt)])).watch();
  Future<List<Message>> messages(String chatId) =>
      (db.select(db.messages)..where((m) => m.chatId.equals(chatId))..orderBy([(m) => OrderingTerm.asc(m.createdAt)])).get();

  Future<ThreadData> thread(String chatId) async => buildThread(await getChat(chatId), await messages(chatId));

  Stream<List<Chat>> watchChats({bool archived = false}) => (db.select(db.chats)
        ..where((c) => c.archived.equals(archived))
        ..orderBy([(c) => OrderingTerm.desc(c.pinned), (c) => OrderingTerm.desc(c.updatedAt)]))
      .watch();

  Future<String> createChat({String? modelRef, ChatSettings? settings}) async {
    final id = newId();
    await db.into(db.chats).insert(ChatsCompanion.insert(
          id: id,
          modelRef: Value(modelRef),
          settingsJson: Value((settings ?? const ChatSettings()).encode()),
        ));
    return id;
  }

  Future<void> updateChat(String id, ChatsCompanion c) => (db.update(db.chats)..where((t) => t.id.equals(id))).write(c);
  Future<void> setLeaf(String chatId, String? leafId) =>
      updateChat(chatId, ChatsCompanion(activeLeafId: Value(leafId), updatedAt: Value(DateTime.now())));
  Future<void> touch(String chatId) => updateChat(chatId, ChatsCompanion(updatedAt: Value(DateTime.now())));
  Future<void> rename(String id, String title) => updateChat(id, ChatsCompanion(title: Value(title)));
  Future<void> setPinned(String id, bool v) => updateChat(id, ChatsCompanion(pinned: Value(v)));
  Future<void> setArchived(String id, bool v) => updateChat(id, ChatsCompanion(archived: Value(v)));
  Future<void> setModel(String id, String ref) => updateChat(id, ChatsCompanion(modelRef: Value(ref)));
  Future<void> setSettings(String id, ChatSettings s) => updateChat(id, ChatsCompanion(settingsJson: Value(s.encode())));

  Future<void> deleteChat(String id) async {
    final msgs = await messages(id);
    await (db.delete(db.messages)..where((m) => m.chatId.equals(id))).go();
    await (db.delete(db.chats)..where((c) => c.id.equals(id))).go();
    // Remove stored attachments in the background.
    for (final m in msgs) {
      for (final a in attachmentsOf(m)) {
        final path = a['path'];
        if (path is String) File(path).delete().ignore();
      }
      if (m.audioPath != null) File(m.audioPath!).delete().ignore();
    }
  }

  Future<void> insertMessage(MessagesCompanion m) => db.into(db.messages).insert(m);
  Future<void> updateMessage(String id, MessagesCompanion m) => (db.update(db.messages)..where((t) => t.id.equals(id))).write(m);
  Future<Message?> message(String id) => (db.select(db.messages)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Deletes a message and its whole subtree.
  Future<void> deleteSubtree(String chatId, String id) async {
    final all = await messages(chatId);
    final kids = <String?, List<String>>{};
    for (final m in all) {
      (kids[m.parentId] ??= []).add(m.id);
    }
    final del = <String>[];
    void walk(String x) {
      del.add(x);
      for (final c in kids[x] ?? const <String>[]) {
        walk(c);
      }
    }

    walk(id);
    await (db.delete(db.messages)..where((m) => m.id.isIn(del))).go();
  }

  /// Follows the newest child from [id] down to a leaf.
  Future<String> deepestLeaf(String chatId, String id) async {
    final t = buildThread(null, await messages(chatId));
    var cur = id;
    while (true) {
      final kids = t.children[cur];
      if (kids == null || kids.isEmpty) return cur;
      cur = kids.last.id;
    }
  }

  /// Searches chat titles and message bodies (FTS5), newest chat first. The snippet is null for a title match.
  Future<List<(Chat, String?)>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
    final snippets = <String, String>{};
    try {
      final rows = await db.customSelect(
        "SELECT chat_id, snippet(messages_fts, 0, '', '', '...', 10) AS snip FROM messages_fts WHERE messages_fts MATCH ? ORDER BY rank LIMIT 60",
        variables: [Variable.withString(words)],
      ).get();
      for (final r in rows) {
        snippets.putIfAbsent(r.read<String>('chat_id'), () => r.read<String>('snip'));
      }
    } catch (_) {
      // Input FTS5 cannot parse: the title search below still runs.
    }
    final like = '%${q.replaceAll('%', '').replaceAll('_', '')}%';
    final byTitle = await (db.select(db.chats)..where((c) => c.title.like(like))..orderBy([(c) => OrderingTerm.desc(c.updatedAt)])..limit(40)).get();
    final out = <String, (Chat, String?)>{for (final c in byTitle) c.id: (c, null)};
    if (snippets.isNotEmpty) {
      final chats = await (db.select(db.chats)..where((c) => c.id.isIn(snippets.keys.toList()))).get();
      for (final c in chats) {
        out.putIfAbsent(c.id, () => (c, snippets[c.id]));
      }
    }
    final list = out.values.toList()..sort((a, b) => b.$1.updatedAt.compareTo(a.$1.updatedAt));
    return list;
  }

  Future<String> exportMarkdown(String chatId) async {
    final t = await thread(chatId);
    final b = StringBuffer('# ${t.chat?.title ?? 'Chat'}\n\n');
    for (final m in t.path) {
      if (m.kind != 'message') continue;
      switch (m.role) {
        case 'user':
          b.writeln('## You\n\n${stripFileBlocks(m.content).trim()}\n');
        case 'assistant':
          if (m.content.trim().isEmpty) continue;
          b.writeln('## Assistant\n\n${m.content.trim()}\n');
      }
    }
    return b.toString();
  }
}

final chatRepoProvider = Provider<ChatRepo>((ref) => ChatRepo(ref.watch(dbProvider)));

List<Map<String, dynamic>> attachmentsOf(Message m) {
  if (m.attachmentsJson == null || m.attachmentsJson!.isEmpty) return const [];
  try {
    return (jsonDecode(m.attachmentsJson!) as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  } catch (_) {
    return const [];
  }
}

List<LlmToolCall> toolCallsOf(Message m) {
  if (m.toolCallsJson == null || m.toolCallsJson!.isEmpty) return const [];
  try {
    return (jsonDecode(m.toolCallsJson!) as List).whereType<Map>().map((e) => LlmToolCall.fromJson(e.cast<String, dynamic>())).toList();
  } catch (_) {
    return const [];
  }
}

final _fileBlock = RegExp(r'\n*<file name="([^"]*)">\n[\s\S]*?\n</file>', multiLine: true);
String stripFileBlocks(String s) => s.replaceAll(_fileBlock, '').trimRight();
List<String> fileNamesIn(String s) => _fileBlock.allMatches(s).map((m) => m.group(1) ?? 'file').toList();

Future<Directory> attachmentsDir() async {
  final d = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'nur', 'attachments'));
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

/// Saves images to app storage, returns attachmentsJson entries.
Future<List<Map<String, dynamic>>> saveImages(List<LlmImage> images) async {
  if (images.isEmpty) return const [];
  final dir = await attachmentsDir();
  final out = <Map<String, dynamic>>[];
  for (final img in images) {
    final ext = switch (img.mimeType) { 'image/png' => 'png', 'image/webp' => 'webp', 'image/gif' => 'gif', _ => 'jpg' };
    final f = File(p.join(dir.path, '${newId()}.$ext'));
    await f.writeAsBytes(img.bytes, flush: true);
    out.add({'type': 'image', 'path': f.path, 'mime': img.mimeType});
  }
  return out;
}

Future<List<LlmImage>> loadImages(Message m) async {
  final out = <LlmImage>[];
  for (final a in attachmentsOf(m)) {
    if (a['type'] != 'image' || a['path'] is! String) continue;
    try {
      out.add(LlmImage(await File(a['path'] as String).readAsBytes(), (a['mime'] as String?) ?? 'image/jpeg'));
    } on FileSystemException {
      // The file was deleted: the message is sent without it.
    }
  }
  return out;
}
