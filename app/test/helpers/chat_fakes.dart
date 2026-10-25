// Fakes for testing the chat engine without a network: in-memory database and secure storage, a scripted model
// and a scripted NAS hub.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nur/core/contracts/chat_engine.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/core/contracts/nas.dart';
import 'package:nur/core/providers.dart';
import 'package:nur/data/db/app_db.dart' hide LlmModel, NasDevice;
import 'package:nur/features/chat/data/chat_repo.dart';
import 'package:nur/features/chat/engine/chat_engine_impl.dart';
import 'package:nur/features/chat/engine/chat_engine_provider.dart';
import 'package:nur/features/chat/engine/live_store.dart';
import 'package:nur/features/providers/llm_registry.dart';
import 'package:nur/features/wiring_chat.dart';
import 'package:nur/features/wiring_intelligence.dart';

class MemorySecureStorage extends FlutterSecureStorage {
  MemorySecureStorage();
  final data = <String, String>{};

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions,
      LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      data[key];

  @override
  Future<bool> containsKey({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      data.containsKey(key);

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
      WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions,
      AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    data.clear();
  }
}

/// A model that answers from a script. Background calls (chat titles, memory extraction, summaries) get fixed
/// answers, prewarms (max_tokens 1) go to [prewarm], everything else goes to [reply]. Every request is recorded.
class ScriptedLlm extends LlmClient {
  ScriptedLlm(this.reply, {this.delay = Duration.zero, this.prewarm});

  /// The events of one answer.
  List<LlmEvent> Function(LlmRequest req) reply;

  /// Pause between events, so a test can stop a reply while it streams.
  Duration delay;

  /// The events of a prewarm request (default: done at once).
  List<LlmEvent> Function(LlmRequest req)? prewarm;
  final requests = <LlmRequest>[];

  @override
  String get providerId => 'local';

  /// Requests of the chat itself (no title, memory, summary or prewarm calls).
  List<LlmRequest> get chatRequests => requests.where((r) => _background(r) == null && !isPrewarm(r)).toList();

  static bool isPrewarm(LlmRequest r) => r.maxTokens == 1;

  @override
  Future<List<LlmModel>> listModels() async => const [];

  @override
  Stream<LlmEvent> chat(LlmRequest request, {LlmCancelToken? cancel}) async* {
    requests.add(request);
    final events = _background(request) ?? (isPrewarm(request) ? (prewarm?.call(request) ?? const [DoneEvent('stop')]) : reply(request));
    for (final e in events) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (cancel?.isCancelled ?? false) {
        yield const DoneEvent('cancelled');
        return;
      }
      yield e;
    }
  }

  static List<LlmEvent>? _background(LlmRequest r) {
    final system = r.messages.isEmpty ? '' : r.messages.first.content;
    if (system.startsWith('You name chats')) return const [TextDelta('Test title'), DoneEvent('stop')];
    if (system.startsWith('You maintain the long-term memory')) return const [TextDelta('{"operations": []}'), DoneEvent('stop')];
    if (system.startsWith('You compress a conversation')) return const [TextDelta('## User goals\n- testing'), DoneEvent('stop')];
    return null;
  }
}

/// Text answer events.
List<LlmEvent> say(String text) => [TextDelta(text), const DoneEvent('stop')];

/// One tool call as the answer.
List<LlmEvent> callTool(String name, [Map<String, dynamic> args = const {}]) => [
      ToolCallEvent(LlmToolCall(id: 'call_${DateTime.now().microsecondsSinceEpoch}', name: name, argumentsJson: jsonEncode(args))),
      const DoneEvent('tool_calls'),
    ];

/// A round where the model has to answer: no tools, or tools only for an unchanged prompt (tool_choice none).
bool mustAnswer(LlmRequest r) => r.tools.isEmpty || r.toolChoice == 'none';

/// The latest user message of a request (without the hints the engine appends).
String lastUserText(LlmRequest r) => r.messages.lastWhere((m) => m.role == LlmRole.user).content;

class FakeNasHub implements NasHubClient {
  FakeNasHub({this.systemData, this.searchResults = const [], this.failWith, this.wait});

  Map<String, dynamic>? systemData;
  List<Map<String, dynamic>> searchResults;
  final searches = <String>[];

  /// When set, every call fails with this error.
  Object? failWith;

  /// When set, every call waits for it (a NAS that does not answer).
  Future<void>? wait;
  int calls = 0;
  final actions = <String>[];

  Future<T> _answer<T>(T Function() value) async {
    calls++;
    if (wait != null) await wait;
    if (failWith != null) throw failWith!;
    return value();
  }

  @override
  NasDevice? get device => const NasDevice(id: 'nas', name: 'Test NAS', baseUrl: 'http://192.168.1.50:8770', token: 'token');
  @override
  bool get isPaired => true;
  @override
  String? get llmBaseUrl => 'http://192.168.1.50:8770/llm/v1';
  @override
  Future<Map<String, dynamic>> system() => _answer(() => systemData ?? const {});
  @override
  Future<List<Map<String, dynamic>>> containers() => _answer(() => const []);
  @override
  Future<Map<String, dynamic>> containerAction(String name, String action) => _answer(() {
        actions.add('$action $name');
        return const {'ok': true};
      });
  @override
  Future<List<Map<String, dynamic>>> search(String query, {int limit = 5}) {
    searches.add(query);
    return _answer(() => searchResults);
  }
  @override
  Future<Map<String, dynamic>> exec(String command) => _answer(() => const {'exit_code': 0, 'stdout': '', 'stderr': ''});
}

/// The registry with every provider answering through [llm].
class _FakeRegistry extends LlmRegistry {
  _FakeRegistry(super.db, super.secure, this.llm);
  final LlmClient llm;
  @override
  LlmClient? clientFor(String providerId) => llm;
}

/// A ProviderContainer wired like the app (main.dart) around fakes.
class ChatRig {
  ChatRig._(this.container, this.db, this.llm, this.hub);

  final ProviderContainer container;
  final AppDb db;
  final ScriptedLlm llm;
  final FakeNasHub hub;
  bool approve = true;

  static const modelRef = 'local::qwen3.5-2b-instruct-q4_0';

  ChatEngineImpl get engine => container.read(chatEngineImplProvider);
  ChatRepo get repo => container.read(chatRepoProvider);

  /// A small local model (2 B, so the turn planner and the small-model rules apply) with tools and optional thinking.
  static Future<ChatRig> create({ScriptedLlm? llm, FakeNasHub? hub, int contextWindow = 8192}) async {
    // Each test opens its own in-memory database.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDb(NativeDatabase.memory());
    final secure = MemorySecureStorage();
    final model = llm ?? ScriptedLlm((_) => say('ok'));
    final nas = hub ?? FakeNasHub();
    final container = ProviderContainer(overrides: [
      ...chatOverrides(),
      ...intelligenceOverrides(),
      dbProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(secure),
      nasHubProvider.overrideWithValue(nas),
      llmRegistryProvider.overrideWith((ref) {
        final r = _FakeRegistry(db, secure, model);
        ref.onDispose(r.dispose);
        return r;
      }),
    ]);
    final rig = ChatRig._(container, db, model, nas);
    container.read(toolApprovalBrokerProvider).register((_) async => rig.approve);
    await db.into(db.llmProviders).insert(LlmProvidersCompanion.insert(
        id: 'local', kind: 'openai_compat', name: 'llama.cpp', baseUrl: 'http://192.168.1.50:8080/v1', preset: const Value('llamacpp')));
    await db.into(db.llmModels).insert(LlmModelsCompanion.insert(
      id: modelRef,
      providerId: 'local',
      modelId: 'qwen3.5-2b-instruct-q4_0',
      displayName: 'Qwen3.5 2B',
      capsJson: Value(jsonEncode(ModelCapabilities(
        tools: true,
        reasoning: true,
        reasoningCanDisable: true,
        reasoningLevels: const [ReasoningLevel.medium],
        contextWindow: contextWindow,
      ).toJson())),
    ));
    final reg = container.read(llmRegistryProvider);
    await reg.ready;
    for (var i = 0; i < 50 && reg.modelByRef(modelRef) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await reg.setDefault(modelRef);
    return rig;
  }

  /// Sends one message through the ChatEngine contract and waits for the whole reply ([voice]: as in a voice call).
  Future<RigTurn> send(String? chatId, String text,
      {void Function(RigTurn t)? onText, void Function(RigTurn t)? onTool, bool voice = false}) async {
    final t = RigTurn()..chatId = chatId;
    await for (final ev in engine.send(chatId, UserInput(text, fromVoiceCall: voice), onChatId: (id) => t.chatId = id)) {
      switch (ev) {
        case ReplyText(:final delta):
          t.text.write(delta);
          onText?.call(t);
        case ReplyToolActivity(:final toolName):
          t.tools.add(toolName);
          onTool?.call(t);
        case ReplyDone(:final fullText):
          t.done = fullText;
        case ReplyError(:final message):
          t.errors.add(message);
      }
    }
    return t;
  }

  Future<List<Message>> path(String chatId) async => (await repo.thread(chatId)).path;

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

class RigTurn {
  String? chatId;
  final text = StringBuffer();
  final tools = <String>[];
  final errors = <String>[];
  String? done;
}
