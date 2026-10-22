// ContextAssembler: builds exactly what the model sees, measures it, and keeps it inside the window
// (auto-compaction with a structured summary, manual compaction, context reset), plus memory extraction.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/contracts/intelligence.dart';
import '../../core/contracts/llm.dart';
import '../../core/providers.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import '../memory/memory_extractor.dart';
import '../memory/memory_repo.dart';
import '../skills/skills_repo.dart';
import '../tools/tool_router.dart';
import '../tools/tool_runtime_impl.dart';
import 'history.dart';
import 'intel_settings.dart';
import 'llm_access.dart';
import 'prompts.dart';
import 'tokens.dart';

/// Slice labels (also used for colours in the UI).
class Slices {
  static const system = 'System prompt';
  static const memories = 'Memories';
  static const skills = 'Skills';
  static const tools = 'Tools';
  static const messages = 'Messages';
  static const images = 'Images';
  static const summary = 'Summary';
  static const order = [system, memories, skills, tools, summary, messages, images];
}

/// Everything the context sheet shows.
class ContextInfo {
  final ContextBreakdown breakdown;
  final String modelName;
  final bool windowKnown;
  final bool compacting;
  final String? lastError;
  final Set<String> excludedIds; // path messages no longer sent (compacted or before a reset)
  final Set<String> compactedIds; // covered by the active summary
  final int droppedForSpace; // oldest turns left out because the window is full
  final bool hasSummary;
  final int? reportedPromptTokens; // last prompt size reported by the backend
  const ContextInfo({
    required this.breakdown,
    required this.modelName,
    required this.windowKnown,
    this.compacting = false,
    this.lastError,
    this.excludedIds = const {},
    this.compactedIds = const {},
    this.droppedForSpace = 0,
    this.hasSummary = false,
    this.reportedPromptTokens,
  });
  static const empty = ContextInfo(breakdown: ContextBreakdown.empty, modelName: '', windowKnown: false);
}

class _Snapshot {
  final AssembledContext assembled;
  final ContextInfo info;
  final List<String> usedMemoryIds;
  final String? lastUserId;
  const _Snapshot(this.assembled, this.info, this.usedMemoryIds, this.lastUserId);
}

class NurContextAssembler implements ContextAssembler {
  NurContextAssembler(this._ref) : _counter = TokenCounter((id) => IntelLlm(_ref).clientFor(id));
  final Ref _ref;
  final TokenCounter _counter;
  static const _uuid = Uuid();

  final _compacting = <String, Future<void>>{};
  final _lastError = <String, String>{};
  final _cooldownUntil = <String, DateTime>{};
  final _countedUser = <String, String>{}; // chatId -> last user msg id whose memories were counted
  final _extractedUser = <String, String>{};
  final _extracting = <String>{};
  final _status = StreamController<String>.broadcast();

  AppDb get _db => _ref.read(dbProvider);
  IntelLlm get _llm => _ref.read(intelLlmProvider);
  MemoryRepo get _memory => _ref.read(memoryRepoProvider);

  void dispose() => _status.close();

  void _notify(String chatId) {
    if (!_status.isClosed) _status.add(chatId);
  }


  @override
  Future<AssembledContext> build({required String chatId, required LlmModel model}) async {
    final pending = _compacting[chatId];
    if (pending != null) {
      try {
        await pending.timeout(const Duration(minutes: 3));
      } catch (_) {}
    }
    final snap = await _snapshot(chatId, model, forRequest: true);
    if (snap.lastUserId != null && _countedUser[chatId] != snap.lastUserId) {
      _countedUser[chatId] = snap.lastUserId!;
      unawaited(_memory.markUsed(snap.usedMemoryIds).catchError((_) {}));
    }
    return snap.assembled;
  }

  int _window(LlmModel m, int fallback) => (m.caps.contextWindow ?? 0) > 0 ? m.caps.contextWindow! : fallback;

  Future<_Snapshot> _snapshot(String chatId, LlmModel model, {required bool forRequest}) async {
    final db = _db;
    final now = DateTime.now();
    final fallbackWindow = await db.intSetting(IntelKeys.fallbackWindow, 8192);
    final window = _window(model, fallbackWindow);
    final memoryOn = await db.boolSetting(IntelKeys.memoryEnabled);

    final chat = chatId.isEmpty ? null : await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
    final all = chat == null
        ? const <Message>[]
        : await (db.select(db.messages)
              ..where((m) => m.chatId.equals(chatId))
              ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
            .get();
    final path = activePath(all, chat?.activeLeafId);
    final view = resolveContext(path, all);
    var msgs = view.messages;
    final lastUser = msgs.lastWhere((m) => m.role == 'user', orElse: () => _noMsg);
    final lastUserId = identical(lastUser, _noMsg) ? null : lastUser.id;

    var tools = const <LlmToolSpec>[];
    if (model.caps.tools || model.providerId.isEmpty) {
      try {
        tools = await _ref.read(nurToolRuntimeProvider).toolsFor(chatId);
      } catch (_) {}
    }
    if (!model.caps.tools && model.providerId.isNotEmpty) tools = const [];

    // Small local models (1-4 B): a short prompt, at most 7 routed tools with one-line descriptions.
    final small = _llm.isSmallModel(model);
    if (small && tools.isNotEmpty) {
      tools = routeTools(
        [for (final m in msgs) if (m.role == 'user') m.content],
        tools,
        called: [for (final m in msgs) if (m.role == 'assistant') ...parseToolCalls(m.toolCallsJson).map((c) => c.name)],
      ).map(compactTool).toList();
    }

    var pinned = const <Memory>[];
    var retrieved = const <Memory>[];
    if (memoryOn) {
      try {
        pinned = await _memory.pinned(chat?.id);
        if (lastUserId != null) retrieved = await _memory.retrieve(lastUser.content, chatId: chat?.id, limit: small ? 4 : 8);
      } catch (_) {}
    }

    // Only the skill index goes into the prompt; bodies are loaded with load_skill.
    var skills = const <Skill>[];
    if (tools.any((t) => t.name == 'load_skill')) {
      try {
        skills = await _ref.read(skillsRepoProvider).enabledSkills();
      } catch (_) {}
    }

    final memoryTools = memoryOn && tools.any((t) => t.name.startsWith('memory_'));
    final persona = small
        ? compactPersona(tools: tools.isNotEmpty, memory: memoryTools, now: now)
        : basePersona(tools: tools.isNotEmpty, memory: memoryTools, now: now);
    final chatPrompt = (chat?.systemPrompt ?? '').trim();
    final sysText = chatPrompt.isEmpty ? persona : '$persona\n\n# Instructions for this chat\n$chatPrompt';
    final pinnedText = pinned.isEmpty ? '' : memoriesBlock([for (final m in pinned) m.content]);
    final skillsText = skills.isEmpty ? '' : skillsBlock([for (final s in skills) (s.name, s.description)]);
    final summaryText = view.summary == null ? '' : summaryBlock(view.summary!.content.trim());
    final lastUserText = lastUserId == null ? '' : (msgs.where((m) => m.id == lastUserId).firstOrNull?.content ?? '');
    final note = lastUserId == null || isSmallTalk(lastUserText) ? '' : memoriesNote([for (final m in retrieved) m.content]);
    final toolsJson = tools.isEmpty
        ? ''
        : jsonEncode([
            for (final t in tools) {'type': 'function', 'function': {'name': t.name, 'description': t.description, 'parameters': t.parameters}}
          ]);

    final vision = model.caps.vision;
    String msgText(Message m) {
      final calls = m.role == 'assistant' ? (m.toolCallsJson ?? '') : '';
      final body = m.role == 'tool'
          ? toolResultText(m)
          : (m.role == 'user' && m.id == lastUserId && wantsTime(m.content) ? '${timeNote(m.createdAt)}${m.content}' : m.content);
      return calls.isEmpty ? body : '$body\n$calls';
    }

    final items = <TokenItem>[
      TokenItem('sys:${sysText.hashCode}', sysText),
      TokenItem('pin:${pinnedText.hashCode}', pinnedText),
      TokenItem('note:${note.hashCode}', note),
      TokenItem('skills:${skillsText.hashCode}', skillsText),
      TokenItem('sum:${summaryText.hashCode}', summaryText),
      TokenItem('tools:${toolsJson.hashCode}', toolsJson),
      for (final m in msgs) TokenItem(m.status == 'streaming' ? '~${m.id}' : m.id, msgText(m)),
    ];
    final streamingIdx = <int>{
      for (var i = 0; i < msgs.length; i++)
        if (msgs[i].status == 'streaming') i + 6
    };
    final exactItems = [for (var i = 0; i < items.length; i++) if (!streamingIdx.contains(i)) items[i]];
    final counted = await _counter.count(model, exactItems, maxUncached: forRequest ? 24 : 12);
    final counts = List<int>.filled(items.length, 0);
    var k = 0;
    for (var i = 0; i < items.length; i++) {
      if (streamingIdx.contains(i)) {
        counts[i] = estimateTokens(items[i].text);
      } else {
        counts[i] = counted.counts[k++];
      }
    }
    final msgTokens = [for (var i = 0; i < msgs.length; i++) counts[i + 6] + kPerMessageOverhead];
    final imageCounts = [for (final m in msgs) m.role == 'user' && vision ? imageRefs(m).length : 0];

    final sysTokens = counts[0] + kPerMessageOverhead;
    final memTokens = counts[1] + counts[2];
    final skillTokens = counts[3];
    final sumTokens = counts[4];
    final toolTokens = counts[5];
    int fixed() => sysTokens + memTokens + skillTokens + sumTokens + toolTokens;

    // Keep inside the window: drop the oldest whole turns (never splitting a tool exchange).
    var dropped = 0;
    if (forRequest) {
      final reserve = math.min(8192, math.max(1024, (window * 0.15).round()));
      final budget = window - reserve;
      var used = fixed() + msgTokens.fold(0, (a, b) => a + b) + imageCounts.fold(0, (a, b) => a + b) * kImageTokens;
      var from = 0;
      final starts = turnStarts(msgs);
      var t = 0;
      while (used > budget) {
        while (t < starts.length && starts[t] <= from) {
          t++;
        }
        if (t >= starts.length) break; // only the last turn is left
        for (var i = from; i < starts[t]; i++) {
          used -= msgTokens[i] + imageCounts[i] * kImageTokens;
          dropped++;
        }
        from = starts[t];
      }
      if (from > 0) {
        msgs = msgs.sublist(from);
        msgTokens.removeRange(0, from);
        imageCounts.removeRange(0, from);
      }
    }

    final out = <LlmMessage>[];
    final sys = StringBuffer(sysText);
    if (pinnedText.isNotEmpty) sys.write('\n\n$pinnedText');
    if (skillsText.isNotEmpty) sys.write('\n\n$skillsText');
    if (summaryText.isNotEmpty) sys.write('\n\n$summaryText');
    out.add(LlmMessage(LlmRole.system, sys.toString()));
    final history = <LlmMessage>[];
    for (final m in msgs) {
      switch (m.role) {
        case 'user':
          var text = m.content;
          final refs = imageRefs(m);
          var images = const <LlmImage>[];
          if (refs.isNotEmpty) {
            if (vision && forRequest) {
              images = await _loadImages(refs);
            } else if (!vision) {
              text = '$text\n\n[${refs.length} image(s) attached. This model cannot see images.]';
            }
          }
          if (m.id == lastUserId && wantsTime(m.content)) text = '${timeNote(m.createdAt)}$text';
          if (m.id == lastUserId && note.isNotEmpty) text = '$text$note';
          history.add(LlmMessage(LlmRole.user, text, images: images));
        case 'assistant':
          history.add(LlmMessage(LlmRole.assistant, m.content, toolCalls: parseToolCalls(m.toolCallsJson), reasoning: m.reasoning));
        case 'tool':
          history.add(LlmMessage(LlmRole.tool, toolResultText(m), toolCallId: m.toolCallId, toolName: m.toolName));
      }
    }
    out.addAll(pairToolMessages(history));

    final images = imageCounts.fold(0, (a, b) => a + b) * kImageTokens;
    final messagesTokens = msgTokens.fold(0, (a, b) => a + b);
    final breakdown = ContextBreakdown(
      contextWindow: window,
      exact: counted.exact && streamingIdx.isEmpty,
      slices: [
        ContextSlice(Slices.system, sysTokens),
        ContextSlice(Slices.memories, memTokens),
        ContextSlice(Slices.skills, skillTokens),
        ContextSlice(Slices.tools, toolTokens),
        ContextSlice(Slices.summary, sumTokens),
        ContextSlice(Slices.messages, messagesTokens),
        ContextSlice(Slices.images, images),
      ],
    );
    final lastAssistant = msgs.lastWhere((m) => m.role == 'assistant' && m.promptTokens != null, orElse: () => _noMsg);
    final info = ContextInfo(
      breakdown: breakdown,
      modelName: model.displayName,
      windowKnown: (model.caps.contextWindow ?? 0) > 0,
      compacting: _compacting.containsKey(chatId),
      lastError: _lastError[chatId],
      excludedIds: view.excludedIds,
      compactedIds: view.compactedIds,
      droppedForSpace: dropped,
      hasSummary: view.summary != null,
      reportedPromptTokens: identical(lastAssistant, _noMsg) ? null : lastAssistant.promptTokens,
    );
    return _Snapshot(
      AssembledContext(messages: out, tools: tools, breakdown: breakdown),
      info,
      [for (final m in pinned) m.id, for (final m in retrieved) m.id],
      lastUserId,
    );
  }

  Future<List<LlmImage>> _loadImages(List<ImageRef> refs) async {
    final out = <LlmImage>[];
    for (final r in refs) {
      try {
        final f = File(r.path);
        if (await f.exists()) out.add(LlmImage(await f.readAsBytes(), r.mime));
      } catch (_) {}
    }
    return out;
  }


  Future<LlmModel> _modelFor(Chat? chat, LlmModel? def) async {
    await _llm.ready();
    final byChat = _llm.modelByRef(chat?.modelRef);
    if (byChat != null) return byChat;
    if (def != null) return def;
    final d = await _llm.defaultModel();
    return d ?? const LlmModel(providerId: '', modelId: '', displayName: 'No model selected');
  }

  Stream<ContextInfo> watchInfo(String chatId) {
    late final StreamController<ContextInfo> ctl;
    final subs = <StreamSubscription<dynamic>>[];
    Timer? timer;
    var running = false, dirty = false;
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    LlmModel? def;

    late final Future<void> Function() recompute;

    void schedule() {
      if (timer?.isActive ?? false) return;
      final since = DateTime.now().difference(last);
      const gap = Duration(milliseconds: 900);
      timer = Timer(since > gap ? const Duration(milliseconds: 120) : gap - since, () => unawaited(recompute()));
    }

    recompute = () async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      try {
        final db = _db;
        final chat = chatId.isEmpty ? null : await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
        final model = await _modelFor(chat, def);
        final snap = await _snapshot(chatId, model, forRequest: false);
        if (!ctl.isClosed) ctl.add(snap.info);
      } catch (e) {
        debugPrint('context breakdown failed: $e');
      } finally {
        running = false;
        last = DateTime.now();
        if (dirty && !ctl.isClosed) {
          dirty = false;
          schedule();
        }
      }
    };

    ctl = StreamController<ContextInfo>(
      onListen: () {
        final db = _db;
        subs.add(db
            .tableUpdates(TableUpdateQuery.onAllTables([db.messages, db.chats, db.memories, db.skills, db.settings, db.mcpServers]))
            .listen((_) => schedule()));
        subs.add(_llm.watchDefaultModel().listen((m) {
          def = m;
          schedule();
        }, onError: (_) {}));
        subs.add(_llm.changes.listen((_) => schedule(), onError: (_) {}));
        subs.add(_status.stream.where((id) => id == chatId).listen((_) => schedule()));
        schedule();
      },
      onCancel: () async {
        timer?.cancel();
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return ctl.stream;
  }

  @override
  Stream<ContextBreakdown> watchBreakdown(String chatId) => watchInfo(chatId).map((i) => i.breakdown);


  @override
  Future<void> afterTurn({required String chatId, required LlmModel model}) async {
    try {
      unawaited(_maybeExtract(chatId, model));
      final db = _db;
      if (!await db.boolSetting(IntelKeys.autoCompact)) return;
      if (_compacting.containsKey(chatId)) return;
      final until = _cooldownUntil[chatId];
      if (until != null && DateTime.now().isBefore(until)) return;
      final threshold = (await db.doubleSetting(IntelKeys.autoCompactThreshold, 0.8)).clamp(0.3, 0.98);
      final snap = await _snapshot(chatId, model, forRequest: false);
      final b = snap.assembled.breakdown;
      if (b.contextWindow <= 0) return;
      // The backend's own count of the last prompt is authoritative when it is larger than ours.
      final reported = snap.info.reportedPromptTokens ?? 0;
      final used = math.max(b.used, reported);
      if (used / b.contextWindow < threshold) return;
      unawaited(_startCompaction(chatId, model, auto: true).catchError((_) {}));
    } catch (e) {
      debugPrint('afterTurn failed: $e');
    }
  }

  Future<void> _maybeExtract(String chatId, LlmModel model) async {
    if (_extracting.contains(chatId)) return;
    try {
      final db = _db;
      if (!await db.boolSetting(IntelKeys.memoryEnabled) || !await db.boolSetting(IntelKeys.memoryAutoExtract)) return;
      final chat = await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
      if (chat == null) return;
      final all = await (db.select(db.messages)..where((m) => m.chatId.equals(chatId))).get();
      final path = activePath(all, chat.activeLeafId).where((m) => !isMarker(m)).toList();
      final ui = path.lastIndexWhere((m) => m.role == 'user');
      if (ui < 0) return;
      final user = path[ui];
      if (_extractedUser[chatId] == user.id) return;
      final reply = path.skip(ui + 1).where((m) => m.role == 'assistant' && m.content.trim().isNotEmpty).map((m) => m.content).join('\n');
      if (path.skip(ui + 1).any((m) => m.status == 'streaming')) return;
      _extracting.add(chatId);
      _extractedUser[chatId] = user.id;
      await _ref.read(memoryExtractorProvider).extract(model: model, userText: user.content, assistantText: reply, chatId: chatId);
    } catch (e) {
      debugPrint('memory extraction failed: $e');
    } finally {
      _extracting.remove(chatId);
    }
  }


  @override
  Future<void> compact({required String chatId, required LlmModel model}) => _startCompaction(chatId, model, auto: false);

  Future<void> _startCompaction(String chatId, LlmModel model, {required bool auto}) {
    final existing = _compacting[chatId];
    if (existing != null) return existing;
    final f = _compact(chatId, model, auto: auto);
    _compacting[chatId] = f;
    _lastError.remove(chatId);
    _notify(chatId);
    return f.then((_) {
      _cooldownUntil.remove(chatId);
    }, onError: (Object e) {
      final msg = e is StateError ? e.message : e.toString();
      _lastError[chatId] = msg;
      _cooldownUntil[chatId] = DateTime.now().add(const Duration(minutes: 5));
      if (!auto) throw e;
    }).whenComplete(() {
      _compacting.remove(chatId);
      _notify(chatId);
    });
  }

  Future<void> _compact(String chatId, LlmModel model, {required bool auto}) async {
    final db = _db;
    final chat = await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
    if (chat == null) throw StateError('This chat does not exist.');
    final all = await (db.select(db.messages)..where((m) => m.chatId.equals(chatId))).get();
    final path = activePath(all, chat.activeLeafId);
    if (path.any((m) => m.status == 'streaming')) throw StateError('Wait for the reply to finish before compacting.');
    final view = resolveContext(path, all);
    final msgs = view.messages;
    final starts = turnStarts(msgs);
    if (starts.length < 2) throw StateError('Not enough conversation to compact yet.');
    final window = _window(model, await db.intSetting(IntelKeys.fallbackWindow, 8192));

    // Keep up to the last 4 turns, fewer when they alone would fill more than half the window.
    final est = [for (final m in msgs) estimateTokens(m.role == 'tool' ? toolResultText(m) : m.content) + kPerMessageOverhead];
    var keep = math.min(4, starts.length - 1);
    int keptTokens(int k) => est.sublist(starts[starts.length - k]).fold(0, (a, b) => a + b);
    while (keep > 1 && keptTokens(keep) > window * 0.5) {
      keep--;
    }
    final cut = starts[starts.length - keep];
    final covered = msgs.sublist(0, cut);
    if (covered.isEmpty) throw StateError('Not enough conversation to compact yet.');

    final prev = view.summary?.content.trim();
    final lines = [
      for (final m in covered)
        (m.role, m.content, m.toolCallsJson, m.role == 'tool' ? toolResultText(m) : null, m.toolName),
    ];
    final chunkTokens = math.max(1500, (window * 0.6).round() - 1500);
    final (chunks, arabicShare) = await _chunksAsync(lines, chunkTokens);
    final lang = arabicShare > 0.3
        ? 'Write the summary in Arabic (the conversation is mainly in Arabic).'
        : 'Write the summary in the main language of the conversation.';
    final maxTokens = (window * 0.12).round().clamp(400, 1500);
    var summary = prev ?? '';
    for (final (i, chunk) in chunks.indexed) {
      final user = StringBuffer();
      if (summary.isNotEmpty) user.write('EXISTING SUMMARY of even earlier messages (merge it in, keep what still matters):\n$summary\n\n');
      user.write('CONVERSATION${chunks.length > 1 ? ' (part ${i + 1}/${chunks.length})' : ''}:\n$chunk\n\n$lang Produce the updated summary now.');
      summary = await _llm.complete(model, [LlmMessage(LlmRole.system, summarizerSystem), LlmMessage(LlmRole.user, user.toString())],
          temperature: 0.2, maxTokens: maxTokens, timeout: const Duration(minutes: 5));
      if (summary.trim().isEmpty) throw StateError('The model returned an empty summary.');
    }

    // Store the summary; originals stay in the DB and in the visible thread.
    final fresh = await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
    final leaf = fresh?.activeLeafId ?? path.last.id;
    final id = _uuid.v4();
    await db.into(db.messages).insert(MessagesCompanion.insert(
          id: id,
          chatId: chatId,
          parentId: Value(leaf),
          role: 'system',
          kind: const Value(kSummaryKind),
          content: Value(summary.trim()),
          toolResultJson: Value(jsonEncode({
            'anchor': covered.last.id,
            'covered': covered.length,
            'tokens_before': est.fold(0, (a, b) => a + b),
            'auto': auto,
            'model': model.ref,
          })),
          modelRef: Value(model.ref),
          createdAt: Value(DateTime.now()),
        ));
    await _moveLeafIfIdle(chatId, leaf, id);
  }

  /// Puts a marker at the end of the visible thread, unless the chat moved on meanwhile.
  Future<void> _moveLeafIfIdle(String chatId, String expectedLeaf, String markerId) async {
    final db = _db;
    await db.transaction(() async {
      final c = await (db.select(db.chats)..where((t) => t.id.equals(chatId))).getSingleOrNull();
      if (c == null || (c.activeLeafId != null && c.activeLeafId != expectedLeaf)) return;
      final streaming = await (db.select(db.messages)..where((m) => m.chatId.equals(chatId) & m.status.equals('streaming'))).get();
      if (streaming.isNotEmpty) return;
      await (db.update(db.chats)..where((t) => t.id.equals(chatId)))
          .write(ChatsCompanion(activeLeafId: Value(markerId), updatedAt: Value(DateTime.now())));
    });
  }

  @override
  Future<void> clearContext({required String chatId}) async {
    final db = _db;
    final chat = await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
    if (chat == null) return;
    final all = await (db.select(db.messages)..where((m) => m.chatId.equals(chatId))).get();
    final path = activePath(all, chat.activeLeafId);
    if (path.isEmpty) return;
    final anchor = path.last;
    if (anchor.kind == kResetKind) return;
    final id = _uuid.v4();
    await db.into(db.messages).insert(MessagesCompanion.insert(
          id: id,
          chatId: chatId,
          parentId: Value(anchor.id),
          role: 'system',
          kind: const Value(kResetKind),
          content: const Value('Context cleared'),
          toolResultJson: Value(jsonEncode({'anchor': anchor.id})),
          createdAt: Value(DateTime.now()),
        ));
    await _moveLeafIfIdle(chatId, chat.activeLeafId ?? anchor.id, id);
    _notify(chatId);
  }
}

final _noMsg = Message(
  id: '',
  chatId: '',
  role: '',
  kind: '',
  content: '',
  status: '',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Future<(List<String>, double)> _chunksAsync(List<(String, String, String?, String?, String?)> lines, int chunkTokens) async {
  try {
    return await Isolate.run(() => _transcriptChunks(lines, chunkTokens));
  } catch (_) {
    return _transcriptChunks(lines, chunkTokens);
  }
}

/// Renders the covered messages as a transcript and splits it into chunks of ~[chunkTokens]. Runs in an isolate.
(List<String>, double) _transcriptChunks(List<(String, String, String?, String?, String?)> lines, int chunkTokens) {
  String clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)} [...]';
  final chunks = <String>[];
  var buf = StringBuffer();
  var tokens = 0;
  var arabic = 0, total = 0;
  for (final (role, content, calls, toolText, toolName) in lines) {
    final String line;
    switch (role) {
      case 'user':
        line = 'User: $content';
      case 'assistant':
        final c = parseToolCalls(calls);
        final callsText = c.isEmpty ? '' : '\n${c.map((x) => 'Assistant called tool ${x.name}(${clip(x.argumentsJson, 300)})').join('\n')}';
        line = content.trim().isEmpty && callsText.isNotEmpty ? callsText.trim() : 'Assistant: $content$callsText';
      case 'tool':
        line = 'Tool result (${toolName ?? 'tool'}): ${clip(toolText ?? '', 1500)}';
      default:
        continue;
    }
    for (final c in line.codeUnits) {
      total++;
      if (c >= 0x0600 && c <= 0x06FF) arabic++;
    }
    final t = estimateTokens(line);
    if (tokens + t > chunkTokens && tokens > 0) {
      chunks.add(buf.toString());
      buf = StringBuffer();
      tokens = 0;
    }
    buf.writeln(clip(line, chunkTokens * 3));
    buf.writeln();
    tokens += t;
  }
  if (tokens > 0) chunks.add(buf.toString());
  return (chunks, total == 0 ? 0.0 : arabic / total);
}

final nurContextAssemblerProvider = Provider<NurContextAssembler>((ref) {
  final a = NurContextAssembler(ref);
  ref.onDispose(a.dispose);
  return a;
});

/// Live context info for the ring / sheet ('' = a chat that does not exist yet).
final contextInfoProvider = StreamProvider.autoDispose.family<ContextInfo, String>(
    (ref, chatId) => ref.watch(nurContextAssemblerProvider).watchInfo(chatId));
