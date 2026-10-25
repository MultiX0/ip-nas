// Long-term memory store: CRUD, retrieval (FTS5 BM25 + optional embeddings, fused by reciprocal rank),
// de-duplication and usage tracking.
import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import 'embedder.dart';
import 'memory_text.dart';

const kMemoryCategories = ['profile', 'preference', 'nas', 'project', 'general'];

String normalizeCategory(String? c) {
  final v = (c ?? '').trim().toLowerCase();
  if (kMemoryCategories.contains(v)) return v;
  if (v.startsWith('pref')) return 'preference';
  if (v.contains('profile') || v.contains('personal') || v.contains('identity')) return 'profile';
  if (v.contains('nas') || v.contains('home') || v.contains('device') || v.contains('server')) return 'nas';
  if (v.contains('project') || v.contains('work')) return 'project';
  return 'general';
}

class MemoryMatch {
  final Memory memory;
  final double similarity;
  const MemoryMatch(this.memory, this.similarity);
}

class MemoryRepo {
  MemoryRepo(this._db, this._embedder);
  final AppDb _db;
  final Embedder _embedder;
  static const _uuid = Uuid();
  final _queryVecs = <String, Float32List>{}; // query embedding cache (the context ring recomputes often)

  $MemoriesTable get _t => _db.memories;

  Stream<List<Memory>> watchAll() => (_db.select(_t)
        ..orderBy([(m) => OrderingTerm.desc(m.pinned), (m) => OrderingTerm.desc(m.updatedAt)]))
      .watch();

  Expression<bool> _inScope($MemoriesTable m, String? chatId) =>
      m.scope.equals('global') | (chatId == null ? const Constant(false) : m.chatId.equals(chatId));

  Future<List<Memory>> pinned(String? chatId) => (_db.select(_t)
        ..where((m) => m.enabled.equals(true) & m.pinned.equals(true) & _inScope(m, chatId))
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
      .get();

  Future<List<Memory>> byIds(Iterable<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(_t)..where((m) => m.id.isIn(ids.toList()))).get();
    final order = {for (final (i, id) in ids.indexed) id: i};
    rows.sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
    return rows;
  }

  /// BM25 ids (best first). FTS5's bm25() is lower-is-better.
  Future<List<String>> _ftsIds(String text, int limit) async {
    final q = ftsQuery(text);
    if (q == null) return const [];
    try {
      final rows = await _db.customSelect(
        'SELECT memory_id FROM memories_fts WHERE memories_fts MATCH ? ORDER BY bm25(memories_fts) LIMIT ?',
        variables: [Variable.withString(q), Variable.withInt(limit)],
        readsFrom: {_t},
      ).get();
      return [for (final r in rows) r.read<String>('memory_id')];
    } catch (_) {
      return const [];
    }
  }

  /// Relevant enabled memories for [query] (pinned ones excluded: they are always injected).
  Future<List<Memory>> retrieve(String query, {String? chatId, int limit = 8}) async {
    if (query.trim().isEmpty) return const [];
    final fts = await _ftsIds(query, 30);
    var vec = const <String>[];
    if (await _embedder.configured) vec = await _vectorIds(query, 30);
    // Reciprocal rank fusion (k = 60).
    final score = <String, double>{};
    for (final (i, id) in fts.indexed) {
      score[id] = (score[id] ?? 0) + 1 / (60 + i);
    }
    for (final (i, id) in vec.indexed) {
      score[id] = (score[id] ?? 0) + 1 / (60 + i);
    }
    if (score.isEmpty) return const [];
    final rows = await byIds(score.keys);
    final ok = rows
        .where((m) => m.enabled && !m.pinned && (m.scope == 'global' || m.chatId == chatId))
        .toList()
      ..sort((a, b) => (score[b.id] ?? 0).compareTo(score[a.id] ?? 0));
    return ok.take(limit).toList();
  }

  Future<List<String>> _vectorIds(String query, int top) async {
    var vec = _queryVecs[query];
    if (vec == null) {
      final q = await _embedder.embed([query]);
      if (q == null || q.isEmpty) return const [];
      vec = q.first;
      _queryVecs[query] = vec;
      if (_queryVecs.length > 32) _queryVecs.remove(_queryVecs.keys.first);
    }
    final rows = await (_db.select(_t)..where((m) => m.enabled.equals(true) & m.embedding.isNotNull())).get();
    final items = [
      for (final r in rows)
        if (r.embedding != null) (r.id, r.embedding!)
    ];
    final ranked = await rankByCosine(vec, items, top: top);
    return [
      for (final (id, s) in ranked)
        if (s >= 0.35) id
    ];
  }

  /// Search for the memory tool and the UI: FTS first, then a plain substring fallback.
  Future<List<Memory>> search(String query, {int limit = 10}) async {
    final ids = await _ftsIds(query, limit);
    final rows = await byIds(ids);
    if (rows.length >= limit) return rows;
    final like = '%${query.trim()}%';
    final extra = await (_db.select(_t)
          ..where((m) => m.content.like(like) & m.id.isNotIn(ids))
          ..limit(limit - rows.length))
        .get();
    return [...rows, ...extra];
  }

  /// Closest existing memory by normalised text similarity among FTS candidates.
  Future<MemoryMatch?> closest(String content) async {
    final ids = await _ftsIds(content, 12);
    final cands = await byIds(ids);
    MemoryMatch? best;
    for (final m in cands) {
      final s = textSimilarity(content, m.content);
      if (best == null || s > best.similarity) best = MemoryMatch(m, s);
    }
    return best;
  }

  Future<List<Memory>> related(String text, {int limit = 12}) async => byIds(await _ftsIds(text, limit));

  /// Adds a memory unless a near-duplicate exists. A close refinement (more detailed / newer wording of the
  /// same fact) updates the existing row instead. Returns the id of the stored row and what happened.
  Future<(String, String)> remember(
    String content, {
    String category = 'general',
    String source = 'user',
    bool pinned = false,
    String scope = 'global',
    String? chatId,
  }) async {
    final text = content.trim();
    if (text.isEmpty) throw ArgumentError('Empty memory');
    if (isAboutAssistant(text)) return ('', 'Not saved: memories are only about the user, not about Nur.');
    final near = await closest(text);
    if (near != null && near.similarity >= 0.88) {
      if (text.length > near.memory.content.length + 8) {
        await update(near.memory.id, content: text);
        return (near.memory.id, 'updated');
      }
      return (near.memory.id, 'duplicate');
    }
    if (near != null && near.similarity >= 0.6 && normalizeCategory(category) == near.memory.category) {
      await update(near.memory.id, content: text);
      return (near.memory.id, 'updated');
    }
    final id = await add(text, category: category, source: source, pinned: pinned, scope: scope, chatId: chatId);
    return (id, 'added');
  }

  Future<String> add(String content,
      {String category = 'general', String source = 'user', bool pinned = false, String scope = 'global', String? chatId}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.into(_t).insert(MemoriesCompanion.insert(
          id: id,
          content: content.trim(),
          category: Value(normalizeCategory(category)),
          source: Value(source),
          pinned: Value(pinned),
          scope: Value(scope),
          chatId: Value(chatId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
    unawaited(_embedOne(id, content));
    return id;
  }

  Future<void> update(String id, {String? content, String? category, bool? pinned, bool? enabled}) async {
    await (_db.update(_t)..where((m) => m.id.equals(id))).write(MemoriesCompanion(
      content: content == null ? const Value.absent() : Value(content.trim()),
      category: category == null ? const Value.absent() : Value(normalizeCategory(category)),
      pinned: pinned == null ? const Value.absent() : Value(pinned),
      enabled: enabled == null ? const Value.absent() : Value(enabled),
      updatedAt: Value(DateTime.now()),
      embedding: content == null ? const Value.absent() : const Value(null),
    ));
    if (content != null) unawaited(_embedOne(id, content));
  }

  Future<void> delete(String id) => (_db.delete(_t)..where((m) => m.id.equals(id))).go();
  Future<void> deleteAll() => _db.delete(_t).go();

  /// Deletes memories matching [query] (strong text match). Returns the deleted rows.
  Future<List<Memory>> forget(String query, {int max = 5}) async {
    final cands = await search(query, limit: 20);
    final hits = <Memory>[];
    final qn = normalizeText(query);
    for (final m in cands) {
      final s = textSimilarity(query, m.content);
      if (s >= 0.5 || normalizeText(m.content).contains(qn)) hits.add(m);
      if (hits.length >= max) break;
    }
    for (final m in hits) {
      await delete(m.id);
    }
    return hits;
  }

  Future<void> markUsed(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    await _db.customUpdate(
      'UPDATE memories SET use_count = use_count + 1, last_used_at = ? WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      variables: [Variable.withDateTime(DateTime.now()), for (final id in ids) Variable.withString(id)],
      updates: {_t},
    );
  }

  Future<void> _embedOne(String id, String content) async {
    try {
      if (!await _embedder.configured) return;
      final v = await _embedder.embed([content]);
      if (v == null || v.isEmpty) return;
      await (_db.update(_t)..where((m) => m.id.equals(id))).write(MemoriesCompanion(embedding: Value(vectorToBlob(v.first))));
    } catch (_) {
      // Embeddings are an optional accelerator; FTS still works.
    }
  }

  /// Embeds memories that have no vector yet (after the user configures an embedding model).
  Future<int> backfillEmbeddings() async {
    if (!await _embedder.configured) return 0;
    final rows = await (_db.select(_t)..where((m) => m.embedding.isNull())).get();
    var n = 0;
    for (var i = 0; i < rows.length; i += 32) {
      final batch = rows.sublist(i, (i + 32).clamp(0, rows.length));
      final v = await _embedder.embed([for (final r in batch) r.content]);
      if (v == null || v.length != batch.length) break;
      for (var j = 0; j < batch.length; j++) {
        await (_db.update(_t)..where((m) => m.id.equals(batch[j].id))).write(MemoriesCompanion(embedding: Value(vectorToBlob(v[j]))));
        n++;
      }
    }
    return n;
  }
}

final embedderProvider = Provider<Embedder>((ref) => Embedder(ref.watch(dbProvider), ref.watch(secureStoreProvider)));
final memoryRepoProvider = Provider<MemoryRepo>((ref) => MemoryRepo(ref.watch(dbProvider), ref.watch(embedderProvider)));

final _aboutAssistant = RegExp(
    r"^\s*(i am|i'm|im|my name is|this is)\s+nur\b|^\s*nur\s+(is|was|can|will|helps|runs)\b|\b(the|an|your)\s+(ai\s+)?assistant\b|^\s*(أنا|انا)\s+نور|^\s*نور\s+(هو|هي|مساعد)",
    caseSensitive: false);

/// Small models sometimes "remember" their own identity ("I am Nur, the home NAS user."); those are never user facts.
bool isAboutAssistant(String text) => _aboutAssistant.hasMatch(text);
