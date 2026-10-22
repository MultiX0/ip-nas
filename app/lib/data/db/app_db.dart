// The app's local database (drift / SQLite). After changing a table, regenerate app_db.g.dart:
//   dart run build_runner build --delete-conflicting-outputs
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/utils/app_dirs.dart';

part 'app_db.g.dart';

/// A conversation. The visible thread is the path from the root to [activeLeafId] (branching on edit/regenerate).
class Chats extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('New chat'))();
  TextColumn get modelRef => text().nullable()(); // providerId::modelId
  TextColumn get systemPrompt => text().nullable()();
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))(); // reasoning level, temperature, tool toggles
  TextColumn get activeLeafId => text().nullable()();
  TextColumn get folder => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// kind: 'message' | 'summary' (compaction summary that replaces older turns in context) | 'context_reset' (marker: context starts after this)
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get chatId => text().references(Chats, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable()();
  TextColumn get role => text()(); // system | user | assistant | tool
  TextColumn get kind => text().withDefault(const Constant('message'))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get reasoning => text().nullable()();
  IntColumn get reasoningMs => integer().nullable()();
  TextColumn get toolCallsJson => text().nullable()(); // assistant: [{id,name,arguments}]
  TextColumn get toolCallId => text().nullable()(); // tool result
  TextColumn get toolName => text().nullable()();
  TextColumn get toolResultJson => text().nullable()(); // {content,isError,display}
  TextColumn get attachmentsJson => text().nullable()(); // [{type:'image', path, mime}]
  TextColumn get audioPath => text().nullable()(); // voice message
  TextColumn get modelRef => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('done'))(); // streaming | done | error | cancelled
  TextColumn get errorText => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  RealColumn get tokensPerSecond => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Long-term memory. scope: 'global' | 'chat'. source: 'user' | 'auto' | 'model'.
class Memories extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();
  TextColumn get category => text().withDefault(const Constant('general'))(); // profile, preference, nas, project, general
  TextColumn get scope => text().withDefault(const Constant('global'))();
  TextColumn get chatId => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('user'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))(); // always injected
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  BlobColumn get embedding => blob().nullable()(); // float32 little-endian, when an embedding model is set
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// kind: 'openai_compat' | 'ollama' | 'anthropic' | 'nas_hub'. API keys live in secure storage under `provider_key_<id>`.
class LlmProviders extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get preset => text().nullable()(); // openai, openrouter, groq, gemini, deepseek, mistral, xai, together, llamacpp, lmstudio, vllm ...
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get extraJson => text().withDefault(const Constant('{}'))(); // custom headers etc.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Cached model list + per-model overrides. id = providerId::modelId
class LlmModels extends Table {
  TextColumn get id => text()();
  TextColumn get providerId => text().references(LlmProviders, #id, onDelete: KeyAction.cascade)();
  TextColumn get modelId => text()();
  TextColumn get displayName => text()();
  TextColumn get capsJson => text().withDefault(const Constant('{}'))(); // ModelCapabilities (detected)
  TextColumn get overridesJson => text().withDefault(const Constant('{}'))(); // user overrides of caps / params
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

/// transport: 'http' (streamable HTTP) | 'sse'. Header secrets in secure storage under `mcp_hdr_<id>`.
class McpServers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get transport => text().withDefault(const Constant('http'))();
  TextColumn get url => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get toolsCacheJson => text().withDefault(const Constant('[]'))();
  TextColumn get disabledToolsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Agent skills (SKILL.md with name/description front matter + optional files).
class Skills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get body => text()(); // SKILL.md body (loaded on demand by the model)
  TextColumn get source => text().withDefault(const Constant('local'))(); // url / zip / builtin
  TextColumn get dir => text().nullable()(); // folder with extra files
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get installedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Paired NAS devices running Nur Hub. Token in secure storage under `nas_token_<id>`.
class NasDevices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get infoJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastSeen => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Chats, Messages, Memories, LlmProviders, LlmModels, McpServers, Skills, NasDevices, Settings])
class AppDb extends _$AppDb {
  AppDb([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'nur', native: const DriftNativeOptions(databaseDirectory: appFilesDir)));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Full-text search for chat search and memory retrieval (BM25).
          await customStatement("CREATE VIRTUAL TABLE messages_fts USING fts5(content, chat_id UNINDEXED, message_id UNINDEXED, tokenize='unicode61 remove_diacritics 2')");
          await customStatement("CREATE VIRTUAL TABLE memories_fts USING fts5(content, memory_id UNINDEXED, tokenize='unicode61 remove_diacritics 2')");
          await customStatement('''CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
            INSERT INTO messages_fts(content, chat_id, message_id) VALUES (new.content, new.chat_id, new.id); END''');
          await customStatement('''CREATE TRIGGER messages_au AFTER UPDATE OF content ON messages BEGIN
            DELETE FROM messages_fts WHERE message_id = old.id;
            INSERT INTO messages_fts(content, chat_id, message_id) VALUES (new.content, new.chat_id, new.id); END''');
          await customStatement('''CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
            DELETE FROM messages_fts WHERE message_id = old.id; END''');
          await customStatement('''CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN
            INSERT INTO memories_fts(content, memory_id) VALUES (new.content, new.id); END''');
          await customStatement('''CREATE TRIGGER memories_au AFTER UPDATE OF content ON memories BEGIN
            DELETE FROM memories_fts WHERE memory_id = old.id;
            INSERT INTO memories_fts(content, memory_id) VALUES (new.content, new.id); END''');
          await customStatement('''CREATE TRIGGER memories_ad AFTER DELETE ON memories BEGIN
            DELETE FROM memories_fts WHERE memory_id = old.id; END''');
          await customStatement('CREATE INDEX messages_chat_idx ON messages(chat_id, created_at)');
        },
        beforeOpen: (d) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // Chats that never got a message (opened then left) are not kept.
          await customStatement('DELETE FROM chats WHERE id NOT IN (SELECT DISTINCT chat_id FROM messages)');
        },
      );

  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;
  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  Stream<String?> watchSetting(String key) =>
      (select(settings)..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);
}
