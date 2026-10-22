// Registry of configured LLM providers, their clients and cached models (public API used by other modules).
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/contracts/llm.dart';
import '../../core/providers.dart';
import '../../data/db/app_db.dart' hide LlmModel;
import '../../data/db/app_db.dart' as d show LlmModel;
import 'adapters/anthropic_client.dart';
import 'adapters/ollama_client.dart';
import 'adapters/openai_compat_client.dart';
import 'capabilities.dart';
import 'sampling_presets.dart';

/// A model as the UI sees it: resolved capabilities plus user flags.
class ModelEntry {
  final LlmModel model;
  final ModelCapabilities detected;
  final ModelOverrides overrides;
  final bool favorite;
  final bool hidden;
  final String providerName;
  final String providerKind;
  final String? preset;
  const ModelEntry({
    required this.model,
    required this.detected,
    required this.overrides,
    required this.favorite,
    required this.hidden,
    required this.providerName,
    required this.providerKind,
    this.preset,
  });
  String get ref => model.ref;
  bool get isLocal => const {'llamacpp', 'ollama', 'lmstudio', 'vllm', 'nas'}.contains(preset) || providerKind == 'ollama' || providerKind == 'nas_hub';
}

class LlmRegistry {
  LlmRegistry(this._db, this._secure) {
    final p = Completer<void>(), m = Completer<void>();
    ready = Future.wait([p.future, m.future]).timeout(const Duration(seconds: 10), onTimeout: () => const []);
    _subs.add(_db.select(_db.llmProviders).watch().listen((rows) async {
      await _rebuildClients(rows);
      if (!p.isCompleted) p.complete();
    }, onError: (Object _) {
      if (!p.isCompleted) p.complete();
    }));
    _subs.add(_db.select(_db.llmModels).watch().listen((rows) {
      _modelRows = rows;
      _rebuildModels();
      if (!m.isCompleted) m.complete();
    }, onError: (Object _) {
      if (!m.isCompleted) m.complete();
    }));
  }

  final AppDb _db;
  final FlutterSecureStorage _secure;
  final _subs = <StreamSubscription<dynamic>>[];
  final _changes = StreamController<void>.broadcast();
  late final Future<void> ready;

  Map<String, LlmProvider> _providers = {};
  final Map<String, LlmClient> _clients = {};
  final Map<String, String> _keys = {};
  List<d.LlmModel> _modelRows = const [];
  Map<String, ModelEntry> _models = {};

  /// Fires whenever providers or models change.
  Stream<void> get changes => _changes.stream;


  LlmClient? clientFor(String providerId) => _clients[providerId];

  /// Visible models of enabled providers, favorites first.
  Future<List<LlmModel>> allModels() async {
    await ready;
    return entries().map((e) => e.model).toList();
  }

  LlmModel? modelByRef(String ref) => _models[ref]?.model;

  Stream<LlmModel?> watchDefaultModel() {
    StreamSubscription<String?>? a;
    StreamSubscription<void>? b;
    String? setting;
    String? lastKey;
    late final StreamController<LlmModel?> c;
    void emit({bool force = false}) {
      final m = resolveDefault(setting);
      final key = m == null ? '' : '${m.ref}|${m.displayName}|${jsonEncode(m.caps.toJson())}';
      if (!force && key == lastKey) return;
      lastKey = key;
      if (!c.isClosed) c.add(m);
    }

    c = StreamController<LlmModel?>(
      onListen: () async {
        await ready;
        setting = await _db.getSetting('default_model');
        emit(force: true);
        a = _db.watchSetting('default_model').listen((v) {
          setting = v;
          emit();
        });
        b = _changes.stream.listen((_) => emit());
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return c.stream;
  }


  List<ModelEntry> entries({bool includeHidden = false}) {
    final list = _models.values.where((e) => (includeHidden || !e.hidden) && (_providers[e.model.providerId]?.enabled ?? false)).toList();
    list.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      final p = a.providerName.toLowerCase().compareTo(b.providerName.toLowerCase());
      if (p != 0) return p;
      return a.model.displayName.toLowerCase().compareTo(b.model.displayName.toLowerCase());
    });
    return list;
  }

  ModelEntry? entryByRef(String? ref) => ref == null ? null : _models[ref];

  /// Small-model mode (1-4 B local models): shorter prompt, fewer tools, tool-call repair, thinking off by default.
  /// The `smallModel` override wins; otherwise a local model whose name says <= ~4.5 B parameters.
  bool isSmallModel(LlmModel m) {
    final e = _models[m.ref];
    final forced = e?.overrides.smallModel;
    if (forced != null) return forced;
    if (e != null && !e.isLocal) return false;
    return isSmallByName(m.modelId);
  }

  /// Sampling for one request: "Recommended (auto)" family preset, the user's custom values, or nothing
  /// (server defaults). Only local backends use it (cloud APIs pick their own sampling).
  SamplingParams samplingFor(String ref, String modelId, {required bool thinking}) {
    final e = _models[ref];
    if (e != null && !e.isLocal) return SamplingParams.none;
    final ov = e?.overrides;
    final preset = recommendedSampling(modelId, thinking: thinking);
    switch (ov?.samplingMode ?? SamplingMode.auto) {
      case SamplingMode.server:
        return SamplingParams.none;
      case SamplingMode.custom:
        final c = ov?.samplingCustom ?? SamplingParams.none;
        return SamplingParams(
          temperature: c.temperature ?? preset.temperature,
          topP: c.topP ?? preset.topP,
          topK: c.topK ?? preset.topK,
          minP: c.minP ?? preset.minP,
          presencePenalty: c.presencePenalty ?? preset.presencePenalty,
          repeatPenalty: c.repeatPenalty ?? preset.repeatPenalty,
        );
      case SamplingMode.auto:
        return preset;
    }
  }
  List<LlmProvider> get providers => _providers.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  LlmProvider? provider(String id) => _providers[id];
  bool hasKey(String providerId) => (_keys[providerId] ?? '').isNotEmpty;

  LlmModel? resolveDefault(String? setting) {
    final visible = entries();
    if (setting != null && setting.isNotEmpty) {
      final e = _models[setting];
      if (e != null && (_providers[e.model.providerId]?.enabled ?? false)) return e.model;
    }
    if (visible.isEmpty) return null;
    return visible.first.model;
  }

  Future<LlmModel?> defaultModel() async {
    await ready;
    return resolveDefault(await _db.getSetting('default_model'));
  }

  Future<void> setDefault(String ref) => _db.setSetting('default_model', ref);

  Future<String> addProvider({required String kind, required String name, required String baseUrl, String? preset, String? apiKey, Map<String, dynamic> extra = const {}}) async {
    final id = '${preset ?? kind}_${const Uuid().v4().substring(0, 8)}';
    if (apiKey != null && apiKey.trim().isNotEmpty) await _secure.write(key: 'provider_key_$id', value: apiKey.trim());
    await _db.into(_db.llmProviders).insert(LlmProvidersCompanion.insert(
          id: id,
          kind: kind,
          name: name,
          baseUrl: baseUrl.trim(),
          preset: Value(preset),
          extraJson: Value(jsonEncode(extra)),
        ));
    await _reloadNow();
    return id;
  }

  Future<void> updateProvider(String id, {String? name, String? baseUrl, String? apiKey, bool? enabled}) async {
    if (apiKey != null) {
      if (apiKey.trim().isEmpty) {
        await _secure.delete(key: 'provider_key_$id');
      } else {
        await _secure.write(key: 'provider_key_$id', value: apiKey.trim());
      }
    }
    await (_db.update(_db.llmProviders)..where((t) => t.id.equals(id))).write(LlmProvidersCompanion(
      name: name == null ? const Value.absent() : Value(name),
      baseUrl: baseUrl == null ? const Value.absent() : Value(baseUrl.trim()),
      enabled: enabled == null ? const Value.absent() : Value(enabled),
    ));
    await _reloadNow();
  }

  Future<void> deleteProvider(String id) async {
    await _secure.delete(key: 'provider_key_$id');
    await (_db.delete(_db.llmModels)..where((t) => t.providerId.equals(id))).go();
    await (_db.delete(_db.llmProviders)..where((t) => t.id.equals(id))).go();
  }

  Future<String?> apiKey(String providerId) => _secure.read(key: 'provider_key_$providerId');

  /// Lists models from the server and caches them (keeps user overrides, names and flags).
  Future<int> refreshModels(String providerId) async {
    await ready;
    final client = _clients[providerId];
    if (client == null) throw 'Provider is not configured';
    final models = await client.listModels();
    final existing = await (_db.select(_db.llmModels)..where((t) => t.providerId.equals(providerId))).get();
    final byId = {for (final r in existing) r.id: r};
    final seen = <String>{};
    await _db.batch((b) {
      for (final m in models) {
        seen.add(m.ref);
        final old = byId[m.ref];
        if (old == null) {
          b.insert(_db.llmModels, LlmModelsCompanion.insert(id: m.ref, providerId: providerId, modelId: m.modelId, displayName: m.displayName, capsJson: Value(jsonEncode(m.caps.toJson()))));
        } else {
          b.update(_db.llmModels, LlmModelsCompanion(capsJson: Value(jsonEncode(m.caps.toJson()))), where: (t) => t.id.equals(m.ref));
        }
      }
      for (final r in existing) {
        if (!seen.contains(r.id) && !r.favorite) b.deleteWhere(_db.llmModels, (t) => t.id.equals(r.id));
      }
    });
    return models.length;
  }

  /// Returns null on success or a readable error.
  Future<String?> testConnection(String providerId) async {
    try {
      final n = await refreshModels(providerId);
      return n == 0 ? 'Connected, but the server lists no models.' : null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> updateModel(String ref, {String? displayName, ModelOverrides? overrides, bool? favorite, bool? hidden}) async {
    await (_db.update(_db.llmModels)..where((t) => t.id.equals(ref))).write(LlmModelsCompanion(
      displayName: displayName == null ? const Value.absent() : Value(displayName),
      overridesJson: overrides == null ? const Value.absent() : Value(jsonEncode(overrides.toJson())),
      favorite: favorite == null ? const Value.absent() : Value(favorite),
      hidden: hidden == null ? const Value.absent() : Value(hidden),
    ));
  }


  Future<void> _reloadNow() async => _rebuildClients(await _db.select(_db.llmProviders).get());

  Future<void> _rebuildClients(List<LlmProvider> rows) async {
    final next = {for (final r in rows) r.id: r};
    for (final r in rows) {
      var key = await _secure.read(key: 'provider_key_${r.id}').catchError((Object _) => null);
      if ((key == null || key.isEmpty) && r.kind == 'nas_hub') {
        final nasId = _extra(r)['nasId'];
        if (nasId is String) key = await _secure.read(key: 'nas_token_$nasId').catchError((Object _) => null);
      }
      _keys[r.id] = key ?? '';
    }
    _providers = next;
    _clients
      ..clear()
      ..addAll({for (final r in rows) r.id: _makeClient(r, _keys[r.id] ?? '')});
    _rebuildModels();
    // A provider added from anywhere (e.g. NAS pairing) gets its model list fetched once, in the background.
    for (final r in rows) {
      if (!r.enabled || _autoRefreshed.contains(r.id)) continue;
      if (_modelRows.any((m) => m.providerId == r.id)) continue;
      _autoRefreshed.add(r.id);
      unawaited(refreshModels(r.id).then((_) {}, onError: (Object _) => _autoRefreshed.remove(r.id)));
    }
  }

  final Set<String> _autoRefreshed = {};

  Map<String, dynamic> _extra(LlmProvider r) {
    try {
      final j = jsonDecode(r.extraJson);
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  LlmClient _makeClient(LlmProvider r, String key) {
    final extra = _extra(r);
    final headers = <String, String>{};
    final h = extra['headers'];
    if (h is Map) h.forEach((k, v) => headers['$k'] = '$v');
    ModelCapabilities? capsOf(String modelId) => _models['${r.id}::$modelId']?.model.caps;
    int? numCtxOf(String modelId) => _models['${r.id}::$modelId']?.overrides.contextWindow;
    SamplingParams samplingOf(String modelId, bool thinking) => samplingFor('${r.id}::$modelId', modelId, thinking: thinking);
    if (r.kind == 'ollama' || (r.kind == 'nas_hub' && extra['runtime'] == 'ollama')) {
      return OllamaClient(
          providerId: r.id, baseUrl: r.baseUrl, apiKey: key, headers: headers, capsOf: capsOf, numCtxOf: numCtxOf, samplingOf: samplingOf);
    }
    if (r.kind == 'anthropic') {
      return AnthropicClient(providerId: r.id, baseUrl: r.baseUrl, apiKey: key, headers: headers, capsOf: capsOf);
    }
    return OpenAiCompatClient(
      providerId: r.id,
      baseUrl: r.baseUrl,
      apiKey: key,
      preset: r.kind == 'nas_hub' ? 'nas' : (r.preset ?? 'custom'),
      headers: headers,
      capsOf: capsOf,
      samplingOf: samplingOf,
    );
  }

  void _rebuildModels() {
    final out = <String, ModelEntry>{};
    for (final r in _modelRows) {
      final p = _providers[r.providerId];
      if (p == null) continue;
      ModelCapabilities detected;
      ModelOverrides ov;
      try {
        detected = ModelCapabilities.fromJson((jsonDecode(r.capsJson) as Map).cast<String, dynamic>());
      } catch (_) {
        detected = const ModelCapabilities();
      }
      try {
        ov = ModelOverrides.fromJson((jsonDecode(r.overridesJson) as Map).cast<String, dynamic>());
      } catch (_) {
        ov = const ModelOverrides();
      }
      final caps = ov.apply(detected);
      // Small local models answer faster and loop less with thinking off (Qwen3.5-2B card: "more prone to thinking
      // loops"); the user can still pick a level per chat or set a default in the model settings.
      final local = const {'llamacpp', 'ollama', 'lmstudio', 'vllm'}.contains(p.preset) || p.kind == 'ollama' || p.kind == 'nas_hub';
      final small = ov.smallModel ?? (local && isSmallByName(r.modelId));
      if (small && ov.defaultReasoning == null && caps.reasoning && caps.reasoningCanDisable) ov = ov.withDefaultReasoning(ReasoningLevel.off);
      final m = LlmModel(providerId: p.id, modelId: r.modelId, displayName: r.displayName, caps: caps);
      out[m.ref] = ModelEntry(
        model: m,
        detected: detected,
        overrides: ov,
        favorite: r.favorite,
        hidden: r.hidden,
        providerName: p.name,
        providerKind: p.kind,
        preset: p.kind == 'nas_hub' ? 'nas' : p.preset,
      );
    }
    _models = out;
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _changes.close();
  }
}

final llmRegistryProvider = Provider<LlmRegistry>((ref) {
  final r = LlmRegistry(ref.watch(dbProvider), ref.watch(secureStoreProvider));
  ref.onDispose(r.dispose);
  return r;
});

/// All visible model entries (re-emits when providers/models change).
final modelEntriesProvider = StreamProvider<List<ModelEntry>>((ref) async* {
  final reg = ref.watch(llmRegistryProvider);
  await reg.ready;
  yield reg.entries();
  await for (final _ in reg.changes) {
    yield reg.entries();
  }
});

/// Configured providers (re-emits on change).
final providersListProvider = StreamProvider<List<LlmProvider>>((ref) async* {
  final reg = ref.watch(llmRegistryProvider);
  await reg.ready;
  yield reg.providers;
  await for (final _ in reg.changes) {
    yield reg.providers;
  }
});

final defaultModelProvider = StreamProvider<LlmModel?>((ref) => ref.watch(llmRegistryProvider).watchDefaultModel());
