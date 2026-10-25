// ChatEngine implementation: persistence, context assembly, streaming with throttled UI updates, tool loop,
// auto titles. Used by the chat UI and by voice calls (through the ChatEngine contract).
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/chat_engine.dart';
import '../../../core/contracts/intelligence.dart';
import '../../../core/contracts/llm.dart';
import '../../../core/providers.dart';
import '../../../data/db/app_db.dart' hide LlmModel;
import '../../context/prompts.dart' show timeNote;
import '../../context/turn_planner.dart';
import '../../providers/adapters/stream_utils.dart' show newCallId;
import '../../providers/capabilities.dart';
import '../../providers/foreground_gate.dart';
import '../../providers/llm_registry.dart';
import '../../skills/builtin_skills.dart' show skillQuickCard;
import '../../skills/skills_repo.dart' show skillsRepoProvider;
import '../../tools/tool_call_repair.dart';
import '../../voice/speech_text.dart' show stripDirections;
import '../../voice/voice_prompt.dart';
import '../data/chat_repo.dart';
import 'live_store.dart';
import 'reply_guard.dart';
import 'request_shaping.dart';

const _maxToolIterations = 8;

/// Small models (1-4 B) get at most this many tool rounds per reply, then must answer (a Pi does ~7 tokens/s).
const _maxSmallToolIterations = 3;

/// Max reply length for small models with thinking off: stops a looping 2 B model from writing for minutes.
const _smallMaxTokens = 1536;

/// Shown under a reply that reached the length limit.
const cutOffNote = 'The reply reached the length limit and was cut off. Ask me to continue.';

class _StreamResult {
  String text = '';
  String? error;
  bool cancelled = false;
  bool cutOff = false; // stopped by the max_tokens limit
  final calls = <LlmToolCall>[];
}

class ChatEngineImpl implements ChatEngine {
  ChatEngineImpl(this._ref) {
    // Messages left "streaming" by a crash or kill are marked cancelled.
    Future<void>(() async {
      try {
        await _ref.read(dbProvider).customUpdate("UPDATE messages SET status = 'cancelled' WHERE status = 'streaming'");
      } catch (_) {}
    });
  }

  final Ref _ref;
  final _cancels = <String, LlmCancelToken>{};

  ChatRepo get _repo => _ref.read(chatRepoProvider);
  LlmRegistry get _reg => _ref.read(llmRegistryProvider);
  LiveStore get _live => _ref.read(liveStoreProvider);
  ForegroundGate get _gate => _ref.read(foregroundGateProvider);

  bool isBusy(String chatId) => _live.isActive(chatId);


  /// When the user clearly asks Nur to remember something, save it right away (no model needed), so it never depends
  /// on a small model choosing to call memory_save. The model still answers normally afterwards.
  Future<void> _autoRemember(String chatId, String text) async {
    _remembered.remove(chatId);
    final fact = rememberedFact(text);
    if (fact == null) return;
    try {
      final r = await _ref.read(toolRuntimeProvider).execute(
            LlmToolCall(id: 'auto_remember_${DateTime.now().millisecondsSinceEpoch}', name: 'memory_save', argumentsJson: jsonEncode({'content': fact})),
            chatId: chatId,
            approve: (_, _) async => true,
          );
      // The small-model fast path only confirms "I'll remember" when the fact was really stored.
      if (!r.isError && !r.content.startsWith('Not saved')) _remembered[chatId] = fact;
    } catch (_) {/* not saved: the planner then lets the model answer */}
  }

  /// chatId -> fact saved by [_autoRemember] for the current turn.
  final _remembered = <String, String>{};

  /// chatId -> the message a failed planned tool left as the tip, so the error shows under its tool card.
  final _errorParent = <String, String>{};

  @override
  Stream<ReplyEvent> send(String? chatId, UserInput input, {void Function(String chatId)? onChatId}) {
    final out = StreamController<ReplyEvent>.broadcast();
    Future<void>(() async {
      try {
        final ready = await _prepareSend(chatId: chatId, input: input, onChatId: onChatId);
        await _autoRemember(ready.chatId, input.text);
        await _runTurn(ready.chatId, ready.parentId, ready.model, ready.settings, out: out, fromVoice: input.fromVoiceCall);
      } catch (e) {
        out.add(ReplyError(_plain(e)));
      } finally {
        await out.close();
      }
    });
    return out.stream;
  }

  /// UI entry point. Returns the chat id as soon as the user message is stored; the reply streams in the background.
  Future<String> sendFromUi({String? chatId, required UserInput input, String? modelRef, ChatSettings? settings}) async {
    final ready = await _prepareSend(chatId: chatId, input: input, modelRef: modelRef, settings: settings);
    unawaited(_autoRemember(ready.chatId, input.text).then((_) => _runTurn(ready.chatId, ready.parentId, ready.model, ready.settings)));
    return ready.chatId;
  }

  /// New assistant reply as a sibling branch of the existing one(s) under [userMessageId].
  Future<void> regenerate(String chatId, String userMessageId, {String? modelRef}) async {
    _ensureIdle(chatId);
    final chat = await _repo.getChat(chatId);
    final model = await _resolveModel(modelRef ?? chat?.modelRef);
    await _runTurn(chatId, userMessageId, model, ChatSettings.parse(chat?.settingsJson));
  }

  /// Retries a failed reply: removes the failed message and generates again from its user message.
  Future<void> retry(String chatId, Message failed) async {
    _ensureIdle(chatId);
    final t = await _repo.thread(chatId);
    final idx = t.path.indexWhere((m) => m.id == failed.id);
    if (idx < 0) return;
    final userIdx = t.path.sublist(0, idx).lastIndexWhere((m) => m.role == 'user');
    if (userIdx < 0) return;
    final user = t.path[userIdx];
    final groupFirst = t.path[userIdx + 1];
    // Drop the whole failed turn when it has no useful content, else keep it as a branch.
    if (groupFirst.status == 'error' || (groupFirst.content.isEmpty && groupFirst.toolCallsJson == null)) {
      await _repo.deleteSubtree(chatId, groupFirst.id);
    }
    await regenerate(chatId, user.id);
  }

  /// Edits a user message by creating a new sibling branch and replying to it.
  Future<void> editAndResend(String chatId, Message original, String newText) async {
    _ensureIdle(chatId);
    final chat = await _repo.getChat(chatId);
    final model = await _resolveModel(chat?.modelRef);
    final files = RegExp(r'\n*<file name="[^"]*">\n[\s\S]*?\n</file>').allMatches(original.content).map((m) => m.group(0)!).join();
    final id = newId();
    await _repo.insertMessage(MessagesCompanion.insert(
      id: id,
      chatId: chatId,
      role: 'user',
      parentId: Value(original.parentId),
      content: Value('$newText$files'),
      attachmentsJson: Value(original.attachmentsJson),
    ));
    await _repo.setLeaf(chatId, id);
    await _runTurn(chatId, id, model, ChatSettings.parse(chat?.settingsJson));
  }

  /// Switches the visible branch to [sibling] (and the newest path below it).
  Future<void> switchBranch(String chatId, Message sibling) async {
    final leaf = await _repo.deepestLeaf(chatId, sibling.id);
    await _repo.setLeaf(chatId, leaf);
  }

  @override
  void stop(String chatId) {
    _cancels[chatId]?.cancel();
  }

  final _prewarmedAt = <String, DateTime>{};
  final _prewarming = <String>{};
  final _prewarmCancels = <String, LlmCancelToken>{};

  /// Sends the prefix of the next turn (same system text, tools and history, plus the time note as the user turn)
  /// with max_tokens 1, so llama.cpp caches it. Local models only (a cloud call costs money), and the same
  /// prefix at most once a minute. Never throws.
  @override
  Future<void> prewarm(String? chatId, {bool fromVoiceCall = false}) async {
    final slot = chatId ?? '';
    if (_prewarming.contains(slot)) return;
    _prewarming.add(slot);
    final cancel = LlmCancelToken();
    _prewarmCancels[slot] = cancel;
    try {
      if (chatId != null && isBusy(chatId)) return;
      final chat = chatId == null ? null : await _repo.getChat(chatId);
      final model = await _resolveModel(chat?.modelRef);
      final entry = _reg.entryByRef(model.ref);
      if (entry == null || !entry.isLocal) return;
      final client = _reg.clientFor(model.providerId);
      if (client == null) return;
      final settings = ChatSettings.parse(chat?.settingsJson);
      final allowTools = settings.tools && model.caps.tools;
      final ctx = await _assemble(slot, model, allowTools);
      final (voiceHint, voiceReminder) = fromVoiceCall ? await _voicePrompt(slot) : ('', '');
      final shaped = _shapeMessages(ctx.messages, model,
          small: _reg.isSmallModel(model), voiceHint: voiceHint, voiceReminder: voiceReminder);
      final key = '${model.ref}|$fromVoiceCall|${Object.hashAll([
            for (final m in shaped) '${m.role.name}:${m.content}:${m.toolCalls.length}',
            for (final t in ctx.tools) t.name,
          ])}';
      final last = _prewarmedAt[key];
      if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) return;
      _prewarmedAt[key] = DateTime.now();
      if (_prewarmedAt.length > 32) _prewarmedAt.remove(_prewarmedAt.keys.first);
      // Many templates need a user turn; the real message starts with the same time note, so even part of it is cached.
      final req = LlmRequest(
        modelId: model.modelId,
        messages: [...shaped, LlmMessage(LlmRole.user, timeNote(DateTime.now()))],
        tools: allowTools ? ctx.tools : const [],
        reasoning: _levelFor(model, settings, voice: fromVoiceCall),
        temperature: entry.overrides.temperature,
        maxTokens: 1,
      );
      if (cancel.isCancelled) return;
      await for (final ev in client.chat(req, cancel: cancel).timeout(const Duration(minutes: 5))) {
        if (ev is ErrorEvent) break;
      }
    } catch (_) {
      // Best effort: without a warm cache the real turn only starts a bit slower.
    } finally {
      _prewarming.remove(slot);
      if (identical(_prewarmCancels[slot], cancel)) _prewarmCancels.remove(slot);
    }
  }


  void _ensureIdle(String chatId) {
    if (isBusy(chatId)) throw 'A reply is still being written. Stop it first.';
  }

  String _plain(Object e) => e is String ? e : e.toString().replaceFirst(RegExp(r'^(Exception|Bad state|StateError): ?'), '');

  Future<LlmModel> _resolveModel(String? ref) async {
    await _reg.ready;
    LlmModel? m = ref == null ? null : _reg.modelByRef(ref);
    m ??= await _reg.defaultModel();
    if (m == null) throw 'No model is set up yet. Add a provider in Settings > Models & providers.';
    if (_reg.clientFor(m.providerId) == null) throw 'The provider for ${m.displayName} is not available.';
    return m;
  }

  Future<({String chatId, String parentId, LlmModel model, ChatSettings settings})> _prepareSend({
    String? chatId,
    required UserInput input,
    String? modelRef,
    ChatSettings? settings,
    void Function(String chatId)? onChatId,
  }) async {
    if (chatId != null) _ensureIdle(chatId);
    final chat = chatId == null ? null : await _repo.getChat(chatId);
    final model = await _resolveModel(modelRef ?? chat?.modelRef);
    final s = settings ?? ChatSettings.parse(chat?.settingsJson);
    var id = chat?.id;
    if (id == null) {
      id = await _repo.createChat(modelRef: model.ref, settings: s);
    } else {
      await _repo.updateChat(id, ChatsCompanion(modelRef: Value(model.ref), settingsJson: Value(s.encode())));
    }
    onChatId?.call(id);
    _live.setActive(id, '');
    try {
      final thread = await _repo.thread(id);
      final parent = thread.path.isEmpty ? null : thread.path.last.id;
      final atts = await saveImages(input.images);
      final userId = newId();
      await _repo.insertMessage(MessagesCompanion.insert(
        id: userId,
        chatId: id,
        role: 'user',
        parentId: Value(parent),
        content: Value(input.text),
        attachmentsJson: Value(atts.isEmpty ? null : jsonEncode(atts)),
        audioPath: Value(input.audioPath),
      ));
      await _repo.setLeaf(id, userId);
      return (chatId: id, parentId: userId, model: model, settings: s);
    } catch (e) {
      _live.setActive(id, null);
      rethrow;
    }
  }

  ReasoningLevel _levelFor(LlmModel model, ChatSettings s, {bool voice = false}) {
    final caps = model.caps;
    if (voice) return effectiveLevel(caps, caps.reasoningCanDisable ? ReasoningLevel.off : ReasoningLevel.low);
    final want = s.reasoning ?? _reg.entryByRef(model.ref)?.overrides.defaultReasoning ?? ReasoningLevel.medium;
    return effectiveLevel(caps, want);
  }

  Future<void> _runTurn(String chatId, String parentId, LlmModel model, ChatSettings settings,
      {StreamController<ReplyEvent>? out, bool fromVoice = false}) async {
    final cancel = LlmCancelToken();
    _cancels[chatId] = cancel;
    _live.setActive(chatId, '');
    // Titles, memory extraction and summaries wait while this reply is written; a running one stops.
    final lease = _gate.hold();
    // A prewarm still running would make this reply queue behind it on a one-slot server (a fresh voice chat
    // prewarms 30-40 s on a Pi).
    for (final p in _prewarmCancels.values.toList()) {
      p.cancel();
    }
    final client = _reg.clientFor(model.providerId);
    final full = StringBuffer();
    var tip = parentId;
    var completed = false;
    // Voice calls: detailed spoken-style prompt (+ Drama 3 emotion tags unless switched off in Voice settings).
    final (voiceHint, voiceReminder) = fromVoice ? await _voicePrompt(chatId) : ('', '');
    final small = _reg.isSmallModel(model);
    final maxIter = small ? _maxSmallToolIterations : _maxToolIterations;
    // Calls already run in this reply (tool + arguments); a repeat is answered from the earlier result instead.
    final seenCalls = <String>{};
    // A tool that fails a second time in one reply will not start working: the model has to answer instead.
    final failedTools = <String>{};
    var forceAnswer = false;
    // Small models: when a tool cannot run at all (NAS unreachable, no access) or a second call fails in one reply,
    // the turn ends with an error shown as an error (asked to explain the errors, they make up the data).
    var failures = 0;
    ({String tool, String error})? lastFailure;
    // Small models: the turn planner runs the tools a clear request needs and frames the model's answer
    // (see context/turn_planner.dart). The model always writes the reply.
    var turnHint = '';
    TurnPlan? plan;
    var userText = '';
    // One retry when the reply guard finds the wrong language or an unbacked action claim.
    var retries = 0;
    double? retryTemperature;
    var ranTools = false;
    try {
      if (client == null) throw 'The provider for ${model.displayName} is not available.';
      if (small) {
        final p = await _runPlan(chatId, tip, model, settings, out, fromVoice, seenCalls, cancel);
        if (p != null) {
          plan = p.plan;
          userText = p.userText;
          tip = p.tip;
          turnHint = p.hint;
          ranTools = p.ranTools;
        }
      }
      for (var iter = 0; !cancel.isCancelled && iter <= maxIter + retries; iter++) {
        await _repo.setLeaf(chatId, tip);
        // The tool list stays in every round; a round that must answer sends tool_choice "none" (same prompt start).
        final offerTools = settings.tools && model.caps.tools;
        final allowTools = offerTools && iter < maxIter && !forceAnswer && !(plan?.noTools ?? false);
        final ctx = await _assemble(chatId, model, offerTools);
        if (cancel.isCancelled) break;
        final messages = _shapeMessages(ctx.messages, model,
            small: small, voiceHint: voiceHint, voiceReminder: voiceReminder, turnHint: turnHint);
        final aid = newId();
        await _repo.insertMessage(MessagesCompanion.insert(
          id: aid,
          chatId: chatId,
          role: 'assistant',
          parentId: Value(tip),
          status: const Value('streaming'),
          modelRef: Value(model.ref),
        ));
        await _repo.setLeaf(chatId, aid);
        final level = _levelFor(model, settings, voice: fromVoice);
        final req = LlmRequest(
          modelId: model.modelId,
          messages: messages,
          tools: ctx.tools,
          toolChoice: allowTools || ctx.tools.isEmpty ? null : 'none',
          reasoning: level,
          temperature: retryTemperature ?? _reg.entryByRef(model.ref)?.overrides.temperature,
          maxTokens: small && level == ReasoningLevel.off ? _smallMaxTokens : null,
        );
        // An explicit request for a language ("say it in Arabic") turns the language checks off.
        final lang = asksForLanguage(userText) ? '' : (plan?.lang ?? detectLang(userText));
        final allowIntro = plan != null && (plan.intent == TurnIntent.greeting || plan.intent == TurnIntent.identity);
        final gate = small && userText.isNotEmpty ? _LeadGate(userText, lang, allowIntro, canBlock: retries == 0) : null;
        final r = await _streamOne(chatId, aid, client, req, cancel, out, gate: gate);
        if (r.error == null && !r.cancelled) {
          await _repairCalls(chatId, aid, r, {if (allowTools) for (final t in req.tools) t.name}, plan?.lang,
              failure: lastFailure, voice: fromVoice);
        }
        // Small models sometimes write a whole answer, call a tool anyway and answer again after it (a voice call said
        // everything twice). A written answer ends the turn; a short "let me check" before a call does not.
        if (small && r.calls.isNotEmpty && r.error == null && !r.cancelled && looksAnswered(r.text)) {
          r.calls.clear();
          await _repo.updateMessage(aid, const MessagesCompanion(toolCallsJson: Value(null)));
        }
        // Drama 3 direction tags are for the voice only; keep the saved chat text clean.
        if (fromVoice && r.text.contains(RegExp(r'\[[^\]\n]{1,40}\]|</?(emphasis|whisper)>'))) {
          r.text = stripDirections(r.text);
          await _repo.updateMessage(aid, MessagesCompanion(content: Value(r.text)));
        }
        if (r.text.isNotEmpty) {
          if (full.isNotEmpty) full.write('\n\n');
          full.write(r.text);
        }
        final prevTip = tip;
        tip = aid;
        if (r.error != null) {
          out?.add(ReplyError(r.error!));
          break;
        }
        if (r.cancelled || cancel.isCancelled) break;
        if (r.calls.isEmpty) {
          if (small && userText.isNotEmpty) {
            // Reply guard: drop re-introductions / echoes / unasked greetings; retry once on the wrong language or
            // an action claimed without a tool.
            final g = guardReply(r.text,
                userText: userText,
                lang: lang,
                allowIntro: allowIntro,
                toolsRan: ranTools,
                retried: retries > 0);
            // A streamed (spoken) reply can only be replaced while nothing of it went out yet.
            final canRetry = out == null || (gate?.blocked ?? false) || r.text.trim().isEmpty;
            if (g.retryHint != null && retries == 0 && canRetry && !cancel.isCancelled) {
              retries = 1;
              retryTemperature = 0.3;
              forceAnswer = true;
              turnHint = [if (turnHint.isNotEmpty) turnHint, g.retryHint!].join('\n');
              // The rejected reply is removed from the thread and from the reply text.
              await _repo.deleteSubtree(chatId, aid);
              tip = prevTip;
              final drop = r.text;
              final s = full.toString();
              if (drop.isNotEmpty && s.endsWith(drop)) {
                full.clear();
                full.write(s.substring(0, s.length - drop.length).trimRight());
              }
              continue;
            }
            if (g.changed && g.text != r.text) {
              final s = full.toString();
              if (r.text.isNotEmpty && s.endsWith(r.text)) {
                full.clear();
                full.write('${s.substring(0, s.length - r.text.length)}${g.text}');
              }
              r.text = g.text;
              await _repo.updateMessage(aid, MessagesCompanion(content: Value(g.text)));
            }
          }
          completed = true;
          break;
        }
        for (final call in r.calls) {
          out?.add(ReplyToolActivity(call.name));
          final tid = newId();
          await _repo.insertMessage(MessagesCompanion.insert(
            id: tid,
            chatId: chatId,
            role: 'tool',
            parentId: Value(tip),
            toolCallId: Value(call.id),
            toolName: Value(call.name),
            status: const Value('streaming'),
          ));
          tip = tid;
          await _repo.setLeaf(chatId, tid);
          final repeat = !seenCalls.add(toolCallKey(call.name, call.argumentsJson));
          if (repeat) forceAnswer = true;
          final ToolResult res;
          if (cancel.isCancelled) {
            res = const ToolResult('Cancelled by the user.', isError: true);
          } else if (repeat) {
            res = ToolResult('You already called ${call.name} with these arguments in this reply; its result is above. '
                'Do not call it again. Answer the user now.');
          } else {
            res = await _execTool(chatId, call, cancel: cancel);
            ranTools = true;
            if (res.isError && !failedTools.add(call.name)) forceAnswer = true;
            if (res.isError && res.content != ToolResult.declined.content) {
              // A NAS that cannot be reached (or a tool that is off) will not work on another try either.
              failures += res.unavailable ? 2 : 1;
              lastFailure = (tool: call.name, error: res.content);
            }
            // After an action that changes things, reading the same state again is legitimate.
            if (_riskOf(call) != ToolRisk.safe) seenCalls.clear();
          }
          final resultJson = await compute(_encodeResult, {'content': res.content, 'isError': res.isError, 'display': res.display});
          await _repo.updateMessage(tid, MessagesCompanion(
            content: Value(res.content),
            toolResultJson: Value(resultJson),
            status: Value(res.isError ? 'error' : 'done'),
          ));
        }
        if (cancel.isCancelled) break;
        if (small && failures >= 2 && lastFailure != null) {
          await _repo.setLeaf(chatId, tip);
          throw '${lastFailure.tool} failed: ${lastFailure.error}';
        }
      }
      await _repo.setLeaf(chatId, tip);
    } catch (e) {
      final msg = _plain(e);
      out?.add(ReplyError(msg));
      // Surface the problem in the thread as a failed assistant message.
      try {
        final eid = newId();
        await _repo.insertMessage(MessagesCompanion.insert(
          id: eid,
          chatId: chatId,
          role: 'assistant',
          parentId: Value(_errorParent.remove(chatId) ?? tip),
          status: const Value('error'),
          errorText: Value(msg),
          modelRef: Value(model.ref),
        ));
        await _repo.setLeaf(chatId, eid);
      } catch (_) {}
    } finally {
      lease.release();
      _cancels.remove(chatId);
      _remembered.remove(chatId);
      _errorParent.remove(chatId);
      _live.setActive(chatId, null);
    }
    out?.add(ReplyDone(full.toString()));
    if (completed) unawaited(_afterTurn(chatId, model, voice: fromVoice));
  }

  /// Runs the turn planner for the latest user message: a fixed reply (no model), tool calls the app makes itself
  /// (recorded in the thread like model calls, approvals included), an answer composed from their data, or the hint
  /// that frames the model's answer. Null when the planner does not apply (images, no user message).
  Future<({TurnPlan plan, String userText, String tip, String hint, bool ranTools})?> _runPlan(String chatId, String tip,
      LlmModel model, ChatSettings settings, StreamController<ReplyEvent>? out, bool voice, Set<String> seen, LlmCancelToken cancel) async {
    final t = await _repo.thread(chatId);
    final path = [for (final m in t.path) if (m.kind == 'message') m];
    final ui = path.lastIndexWhere((m) => m.role == 'user');
    if (ui < 0 || path[ui].attachmentsJson != null) return null;
    final userText = path[ui].content;
    // Apps known from the latest container list in this chat (for "restart it" and name matching).
    var items = const <Map>[];
    for (final m in path.reversed) {
      if (m.role != 'tool' || m.toolName != 'docker_list') continue;
      final d = _displayOf(m);
      if (d?['type'] == 'containers' && d?['items'] is List) {
        items = (d!['items'] as List).whereType<Map>().toList();
        break;
      }
    }
    final known = [for (final x in items) '${x['name']}'];
    final before = path.sublist(0, ui).reversed.where((m) => m.role == 'user' || m.role == 'assistant').map((m) => m.content);
    final ctx = PlanContext(
      priorUserTurns: path.where((m) => m.role == 'user').length - 1,
      knownApps: known,
      lastApp: lastMentionedApp(before, known),
      voice: voice,
    );
    final plan = planTurn(userText, ctx: ctx);
    if (plan.intent == TurnIntent.remember) {
      // Tell the model what really happened, so it never claims a save that did not happen.
      final saved = _remembered[chatId] != null;
      final note = saved
          ? '(Nur saved this to memory. Confirm it in one short sentence.)'
          : await _memoryOn()
              ? '(Saving to memory failed. Say so in one short sentence.)'
              : '(Memory is switched off in Settings, so nothing was saved. Say so in one short sentence.)';
      return (plan: plan, userText: userText, tip: tip, hint: '${await _hintFor(plan, model, '')}\n$note'.trim(), ranTools: false);
    }
    if (plan.calls.isEmpty || !settings.tools) {
      return (plan: plan, userText: userText, tip: tip, hint: await _hintFor(plan, model, ''), ranTools: false);
    }
    final data = <String, Map<String, dynamic>>{
      if (items.isNotEmpty) 'containers': {'type': 'containers', 'items': items},
    };
    var p = plan;
    var ran = false;
    final toolText = StringBuffer();
    for (final c in plan.calls) {
      var args = c.args;
      if (c.tool == 'docker_action') {
        final real = resolveAppName(((data['containers']?['items'] as List?) ?? const []).whereType<Map>().toList(), plan.app ?? '');
        if (real == null) break; // composeAnswer says the app was not found
        p = p.copyWith(app: real);
        args = {'name': real, 'action': plan.action};
      }
      final call = LlmToolCall(id: newCallId(), name: c.tool, argumentsJson: jsonEncode(args));
      final aid = newId();
      await _repo.insertMessage(MessagesCompanion.insert(
        id: aid,
        chatId: chatId,
        role: 'assistant',
        parentId: Value(tip),
        modelRef: Value(model.ref),
        toolCallsJson: Value(jsonEncode([call.toJson()])),
      ));
      out?.add(ReplyToolActivity(call.name));
      final tid = newId();
      await _repo.insertMessage(MessagesCompanion.insert(
        id: tid,
        chatId: chatId,
        role: 'tool',
        parentId: Value(aid),
        toolCallId: Value(call.id),
        toolName: Value(call.name),
        status: const Value('streaming'),
      ));
      tip = tid;
      await _repo.setLeaf(chatId, tid);
      final res = await _execTool(chatId, call, cancel: cancel);
      ran = true;
      seen.add(toolCallKey(call.name, call.argumentsJson));
      final resultJson = await compute(_encodeResult, {'content': res.content, 'isError': res.isError, 'display': res.display});
      await _repo.updateMessage(tid, MessagesCompanion(
        content: Value(res.content),
        toolResultJson: Value(resultJson),
        status: Value(res.isError ? 'error' : 'done'),
      ));
      // Stopped while the tool ran: no answer (the loop in _runTurn does not start either).
      if (cancel.isCancelled) return (plan: p, userText: userText, tip: tip, hint: '', ranTools: true);
      toolText.writeln(res.content);
      if (res.display != null) data['${res.display!['type']}'] = res.display!;
      if (c.tool != 'docker_action' && res.isError) {
        // A tool the request depends on failed (NAS unreachable, no access): an error, never a made-up answer.
        _errorParent[chatId] = tip;
        throw '${c.tool} failed: ${res.content}';
      }
    }
    final data4model = model.caps.tools ? '' : toolText.toString().trim();
    final hint = await _hintFor(p, model, data4model.length > 1500 ? data4model.substring(0, 1500) : data4model);
    return (plan: p, userText: userText, tip: tip, hint: hint, ranTools: ran);
  }

  Future<String> _hintFor(TurnPlan p, LlmModel model, String data) async => turnHint(p,
      skillCard: p.skill == null ? '' : await _skillCard(p.skill!),
      langCard: p.lang == 'ar' ? await _skillCard('arabic-conversation') : '',
      data: data);

  /// The quick card of an enabled skill ('' when the skill is missing or switched off).
  Future<String> _skillCard(String name) async {
    try {
      final skills = await _ref.read(skillsRepoProvider).enabledSkills();
      final s = skills.where((s) => s.name == name).firstOrNull;
      return s == null ? '' : skillQuickCard(s.body);
    } catch (_) {
      return '';
    }
  }

  Future<bool> _memoryOn() async {
    final v = await _ref.read(dbProvider).getSetting('memory_enabled');
    return v != 'false' && v != '0';
  }

  Map<String, dynamic>? _displayOf(Message m) {
    try {
      final j = jsonDecode(m.toolResultJson ?? '');
      return j is Map && j['display'] is Map ? (j['display'] as Map).cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<_StreamResult> _streamOne(String chatId, String aid, LlmClient client, LlmRequest req, LlmCancelToken cancel, StreamController<ReplyEvent>? out,
      {_LeadGate? gate}) async {
    final res = _StreamResult();
    final live = _live.start(chatId, aid);
    final text = StringBuffer();
    final reasoning = StringBuffer();
    DateTime? rStart;
    int? rMs;
    UsageEvent? usage;
    var dirty = false;
    var holdOut = false;
    var tail = '';
    void closeReasoning() {
      if (rStart != null && rMs == null) rMs = DateTime.now().difference(rStart).inMilliseconds;
    }

    void flush() {
      if (!dirty) return;
      dirty = false;
      live.value = LiveMessage(content: text.toString(), reasoning: reasoning.toString(), reasoningStart: rStart, reasoningMs: rMs);
    }

    final timer = Timer.periodic(const Duration(milliseconds: 33), (_) => flush());
    var lastPersist = DateTime.now();
    Future<void> pending = Future.value();
    try {
      await for (final ev in client.chat(req, cancel: cancel)) {
        switch (ev) {
          case TextDelta(text: final t):
            closeReasoning();
            text.write(t);
            dirty = true;
            // A tool call written as text (small models) is not part of the reply: keep it out of voice / API streams.
            if (out != null && !holdOut) {
              tail = '$tail$t';
              if (tail.length > 64) tail = tail.substring(tail.length - 64);
              holdOut = _textCallMarker.hasMatch(tail);
              if (!holdOut) {
                // Small models: the first sentence is held until the lead gate checked it (language, greeting,
                // self-introduction, repeated question), so a voice call never speaks it.
                final emit = gate == null ? t : gate.feed(t);
                if (emit.isNotEmpty) out.add(ReplyText(emit));
              }
            }
          case ReasoningDelta(text: final t):
            rStart ??= DateTime.now();
            reasoning.write(t);
            dirty = true;
          case ToolCallEvent(:final call):
            closeReasoning();
            res.calls.add(call);
          case UsageEvent():
            usage = ev;
          case DoneEvent(:final finishReason):
            if (finishReason == 'cancelled') res.cancelled = true;
            if (finishReason == 'length') res.cutOff = true;
          case ErrorEvent(:final message):
            res.error = message;
        }
        if (DateTime.now().difference(lastPersist).inMilliseconds > 500) {
          lastPersist = DateTime.now();
          final c = text.toString(), r = reasoning.toString();
          pending = pending.then((_) => _repo.updateMessage(aid, MessagesCompanion(content: Value(c), reasoning: Value(r.isEmpty ? null : r))).catchError((Object _) {}));
        }
      }
    } catch (e) {
      res.error = _plain(e);
    } finally {
      timer.cancel();
    }
    closeReasoning();
    if (out != null && gate != null && !holdOut && res.calls.isEmpty) {
      final rest = gate.flush();
      if (rest.isNotEmpty) out.add(ReplyText(rest));
    }
    if (cancel.isCancelled && res.error == null) res.cancelled = true;
    if (res.error == 'Cancelled') {
      res.error = null;
      res.cancelled = true;
    }
    res.text = text.toString();
    await pending;
    final status = res.error != null ? 'error' : (res.cancelled ? 'cancelled' : 'done');
    await _repo.updateMessage(aid, MessagesCompanion(
      content: Value(res.text),
      reasoning: Value(reasoning.isEmpty ? null : reasoning.toString()),
      reasoningMs: Value(rMs),
      toolCallsJson: Value(res.calls.isEmpty ? null : jsonEncode(res.calls.map((c) => c.toJson()).toList())),
      status: Value(status),
      // A reply stopped by the length limit stays a normal reply; the note tells the user it is not complete.
      errorText: Value(res.error ?? (res.cutOff && !res.cancelled && res.calls.isEmpty ? cutOffNote : null)),
      promptTokens: Value(usage?.promptTokens),
      completionTokens: Value(usage?.completionTokens),
      tokensPerSecond: Value(usage?.tokensPerSecond),
    ));
    dirty = true;
    flush();
    _live.end(aid);
    _live.setActive(chatId, '');
    return res;
  }

  /// What the context assembler builds, or the plain history when that fails, so the chat keeps working.
  Future<AssembledContext> _assemble(String chatId, LlmModel model, bool allowTools) async {
    try {
      final a = await _ref.read(contextAssemblerProvider).build(chatId: chatId, model: model);
      return AssembledContext(messages: a.messages, tools: allowTools ? a.tools : const [], breakdown: a.breakdown);
    } catch (e) {
      debugPrint('Context assembly failed, sending the plain history: $e');
    }
    final messages = await _plainContext(chatId, model);
    var tools = const <LlmToolSpec>[];
    if (allowTools) {
      try {
        tools = await _ref.read(toolRuntimeProvider).toolsFor(chatId);
      } catch (_) {}
    }
    return AssembledContext(messages: messages, tools: tools, breakdown: ContextBreakdown.empty);
  }

  Future<List<LlmMessage>> _plainContext(String chatId, LlmModel model) async {
    final t = await _repo.thread(chatId);
    var path = t.path.where((m) => m.status != 'streaming' || m.role == 'tool').toList();
    final reset = path.lastIndexWhere((m) => m.kind == 'context_reset');
    if (reset >= 0) path = path.sublist(reset + 1);
    final now = DateTime.now();
    final out = <LlmMessage>[
      LlmMessage(LlmRole.system,
          'You are Nur, a helpful, friendly AI assistant in a self-hosted app. Answer in the language the user writes in. '
          'Use Markdown when it helps. Today is ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.'
          '${t.chat?.systemPrompt?.isNotEmpty == true ? '\n\n${t.chat!.systemPrompt}' : ''}'),
    ];
    final summary = path.lastIndexWhere((m) => m.kind == 'summary');
    if (summary >= 0) {
      out.add(LlmMessage(LlmRole.system, 'Summary of the earlier conversation:\n${path[summary].content}'));
      path = path.sublist(summary + 1);
    }
    final toolIds = {for (final m in path) if (m.role == 'tool' && m.toolCallId != null) m.toolCallId!};
    for (final m in path) {
      if (m.kind != 'message') continue;
      switch (m.role) {
        case 'user':
          out.add(LlmMessage(LlmRole.user, m.content, images: model.caps.vision ? await loadImages(m) : const []));
        case 'assistant':
          if (m.status == 'error') continue;
          var calls = toolCallsOf(m);
          if (calls.any((c) => !toolIds.contains(c.id))) calls = const [];
          if (m.content.trim().isEmpty && calls.isEmpty) continue;
          out.add(LlmMessage(LlmRole.assistant, m.content, toolCalls: calls));
        case 'tool':
          out.add(LlmMessage(LlmRole.tool, m.content, toolCallId: m.toolCallId, toolName: m.toolName, isError: m.status == 'error'));
      }
    }
    return out;
  }

  /// Voice-call system prompt and per-turn reminder (same text for the real turn and the prewarm request).
  Future<(String, String)> _voicePrompt(String chatId) async {
    var direction = true;
    try {
      direction = await _ref.read(dbProvider).getSetting('voice_direction') != 'false';
    } catch (_) {}
    var hint = buildVoiceSystemPrompt(direction: direction);
    final reminder = direction ? voiceTurnReminderDirection : voiceTurnReminder;
    // Context awareness across chats: the call knows what the user talked about recently (titles only, cheap).
    // Facts about the user come from long-term memory (context assembler); this chat's history is sent as usual.
    try {
      final db = _ref.read(dbProvider);
      final recent = await (db.select(db.chats)
            ..where((c) => c.id.isNotValue(chatId) & c.archived.equals(false))
            ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)])
            ..limit(6))
          .get();
      final titles = recent.map((c) => c.title.trim()).where((t) => t.isNotEmpty && t != 'New chat').toList();
      if (titles.isNotEmpty) {
        hint += '\nRECENT CONVERSATIONS with this user (newest first; refer to them naturally if the user mentions them): '
            '${titles.join(' | ')}.';
      }
    } catch (_) {}
    return (hint, reminder);
  }

  /// Request-only changes to the assembled messages (see request_shaping.dart).
  List<LlmMessage> _shapeMessages(List<LlmMessage> input, LlmModel model,
          {required bool small, String voiceHint = '', String voiceReminder = '', String turnHint = ''}) =>
      shapeMessages(input,
          vision: model.caps.vision,
          small: small,
          voiceHint: voiceHint,
          voiceReminder: voiceReminder,
          turnHint: turnHint,
          toolsCapable: model.caps.tools);

  ToolRisk _riskOf(LlmToolCall call) {
    try {
      return _ref.read(toolRuntimeProvider).riskOf(call);
    } catch (_) {
      return ToolRisk.needsApproval;
    }
  }

  /// Fixes tool calls from small models: calls written as plain text (`<tool_call>{..}`, `<function=..>`, LFM and
  /// Gemma formats) become real calls, and almost-JSON arguments are repaired. Only tools offered in this request count.
  Future<void> _repairCalls(String chatId, String aid, _StreamResult r, Set<String> offered, String? lang,
      {({String tool, String error})? failure, bool voice = false}) async {
    if (offered.isEmpty) {
      // No calls allowed in this round, but the model still wrote call markup (or a server ignored tool_choice
      // "none"): never run them or show raw XML.
      if (!_textCallMarker.hasMatch(r.text) && r.calls.isEmpty) return;
      var t = r.text.replaceAll(_textCallBlock, '').trim();
      // Nothing but call markup: an error, never an answer the app writes for the model.
      if (t.isEmpty) throw failure != null ? '${failure.tool} failed: ${failure.error}' : 'The model replied with a tool call only and no answer.';
      r.text = t;
      final dropped = r.calls.isNotEmpty;
      r.calls.clear();
      await _repo.updateMessage(aid, MessagesCompanion(content: Value(t), toolCallsJson: dropped ? const Value(null) : const Value.absent()));
      return;
    }
    var changed = false;
    if (r.calls.isEmpty) {
      final found = extractTextToolCalls(r.text, offered);
      if (found.isEmpty) return;
      r.text = found.remainingText;
      for (final (i, c) in found.calls.indexed) {
        r.calls.add(LlmToolCall(id: newCallId(i), name: c.name, argumentsJson: c.argumentsJson));
      }
      changed = true;
    } else {
      for (var i = 0; i < r.calls.length; i++) {
        final c = r.calls[i];
        final fixed = normalizeArgumentsJson(c.argumentsJson);
        if (fixed != c.argumentsJson) {
          r.calls[i] = LlmToolCall(id: c.id, name: c.name, argumentsJson: fixed);
          changed = true;
        }
      }
    }
    if (!changed) return;
    await _repo.updateMessage(aid, MessagesCompanion(
      content: Value(r.text),
      toolCallsJson: Value(jsonEncode(r.calls.map((c) => c.toJson()).toList())),
    ));
  }

  /// Runs one tool. Stop ends the wait at once: a NAS that does not answer would otherwise keep the reply busy for
  /// up to a minute. The tool may still finish in the background; its result is dropped, and an approval given after
  /// the stop counts as a no.
  Future<ToolResult> _execTool(String chatId, LlmToolCall call, {LlmCancelToken? cancel}) async {
    const stoppedResult = ToolResult('Cancelled by the user.', isError: true);
    if (cancel?.isCancelled ?? false) return stoppedResult;
    final broker = _ref.read(toolApprovalBrokerProvider);
    Future<ToolResult> run() async {
      try {
        return await _ref.read(toolRuntimeProvider).execute(call, chatId: chatId, approve: (c, risk) async {
          if (risk == ToolRisk.safe) return true;
          final ok = await broker.request(ApprovalRequest(chatId, c, risk));
          return ok && !(cancel?.isCancelled ?? false);
        });
      } catch (e) {
        return ToolResult('The tool failed: ${_plain(e)}', isError: true);
      }
    }

    if (cancel == null) return run();
    final stopped = Completer<ToolResult>();
    cancel.onCancel(() {
      if (!stopped.isCompleted) stopped.complete(stoppedResult);
    });
    return Future.any([run(), stopped.future]);
  }

  /// Background work after a finished turn: memory extraction, automatic summary and the chat title.
  /// On a local server they also replace the chat's cached prompt, so the chat is read in again afterwards while
  /// the user reads (the next reply stops that early); otherwise reply 2 of a new chat re-read the whole prompt.
  Future<void> _afterTurn(String chatId, LlmModel model, {required bool voice}) async {
    try {
      await Future.wait([
        _ref.read(contextAssemblerProvider).afterTurn(chatId: chatId, model: model),
        _maybeTitle(chatId, model),
      ]);
      if (voice || !_ref.mounted || isBusy(chatId)) return;
      if (_reg.entryByRef(model.ref)?.isLocal ?? false) await prewarm(chatId);
    } catch (e) {
      if (_ref.mounted) debugPrint('afterTurn failed: $e');
    }
  }

  /// Chats with a title job waiting or running.
  final _titling = <String>{};

  Future<void> _maybeTitle(String chatId, LlmModel model, {bool useModel = true}) async {
    if (!_titling.add(chatId)) return;
    try {
      // A model title waits while a reply or a voice call holds the model (see foreground_gate.dart).
      if (useModel) await _gate.whenFree();
      final t = await _repo.thread(chatId);
      if (t.chat == null || t.chat!.title != 'New chat') return;
      // Titled from the first message, also when the first reply was stopped or failed and the chat went on.
      final users = t.path.where((m) => m.role == 'user').toList();
      if (users.isEmpty) return;
      final user = stripFileBlocks(users.first.content);
      final fallback = _fallbackTitle(user);
      final client = _reg.clientFor(model.providerId);
      String title = '';
      if (client != null && useModel && user.trim().isNotEmpty) {
        // Only the user's first message: small models otherwise title the answer ("1598 MB RAM, 60.6 C").
        final canSkipThinking = !model.caps.reasoning || model.caps.reasoningCanDisable;
        final req = LlmRequest(
          modelId: model.modelId,
          messages: [
            const LlmMessage(LlmRole.system, _titleSystem),
            LlmMessage(LlmRole.user, 'Request: ${_clip(user.trim().replaceAll(RegExp(r'\s+'), ' '), 400)}\nTitle:'),
          ],
          reasoning: canSkipThinking ? ReasoningLevel.off : effectiveLevel(model.caps, ReasoningLevel.minimal),
          temperature: 0.2,
          maxTokens: canSkipThinking ? 16 : null,
        );
        try {
          title = await _gate.background((stop) async {
            final buf = StringBuffer();
            await for (final ev in client.chat(req, cancel: stop).timeout(const Duration(seconds: 45))) {
              if (ev is TextDelta) buf.write(ev.text);
              if (ev is ErrorEvent) break;
            }
            return cleanTitle(buf.toString(), user);
          });
        } on BackgroundCancelled {
          return; // a reply needed the model: the chat is named after the next turn
        }
      }
      if (title.isEmpty || title.length > 80) title = fallback;
      final again = await _repo.getChat(chatId);
      if (again != null && again.title == 'New chat' && title.isNotEmpty) await _repo.rename(chatId, title);
    } catch (e) {
      // After the app shut down (provider disposed) there is nothing to report.
      if (_ref.mounted) debugPrint('auto title failed: $e');
    } finally {
      _titling.remove(chatId);
    }
  }

  static const _titleSystem = 'You name chats. Write a 2-6 word title that says what the user is asking about, in the language '
      'of the request. Do not answer the request and do not use numbers from an answer. No quotes, emojis or final punctuation. '
      'Output the title only.\n\n'
      'Request: How much RAM is available on my NAS and what is the CPU temperature?\nTitle: NAS RAM and temperature\n\n'
      'Request: كم الذاكرة المتاحة في الجهاز الآن؟\nTitle: حالة ذاكرة الجهاز';

  static String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}...';

  static String _fallbackTitle(String text) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(6).join(' ');
    return words.length > 48 ? '${words.substring(0, 48)}...' : words;
  }
}

final _textCallMarker = RegExp(r'<tool_call>|<function=|<\|tool_call_start\|>');

/// Text that already answers: two or more sentences and at least 100 characters (a preface before a tool call is
/// one short sentence).
bool looksAnswered(String text) {
  final t = text.replaceAll(_textCallBlock, '').trim();
  if (t.length < 100) return false;
  return RegExp(r'[.!?\u061F](\s|$)').allMatches(t).length >= 2;
}
final _textCallBlock = RegExp(r'<tool_call>[\s\S]*?(</tool_call>|$)|<function=[\s\S]*?(</function>|$)|<\|tool_call_start\|>[\s\S]*?(<\|tool_call_end\|>|$)');

/// Cleans a model-written chat title: first line, no "Title:" prefix, quotes, markdown or trailing punctuation, at
/// most 6 words. Returns '' (use the fallback) when it is empty, too long, or carries numbers the user never wrote
/// (the model titled the answer instead of the question).
String cleanTitle(String raw, String userText) {
  var t = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  t = t.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  t = t.replaceAll(RegExp(r'[*_`#]+'), '').trim();
  t = t.replaceAll(RegExp(r'^(title|العنوان)\s*[:：]\s*', caseSensitive: false), '');
  // Quotes (straight, curly, angle) around the title and punctuation at its end.
  t = t.replaceAll(RegExp(r'''^["'\u201C\u201D\u00AB\u00BB\s]+|["'\u201C\u201D\u00AB\u00BB.。!?؟,،:;\s]+$'''), '').trim();
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || t.length > 60) return '';
  final userDigits = RegExp(r'\d+').allMatches(userText).map((m) => m[0]).toSet();
  if (RegExp(r'\d+').allMatches(t).any((m) => !userDigits.contains(m[0]))) return '';
  return words.take(6).join(' ');
}

String _encodeResult(Map<String, dynamic> m) {
  try {
    return jsonEncode(m);
  } catch (_) {
    // The display data is not JSON-encodable; keep the text result.
    return jsonEncode({'content': m['content'], 'isError': m['isError']});
  }
}

/// Holds back the first sentence of a small model's streamed reply until it is checked (reply_guard.dart): a
/// self-introduction, an unasked greeting or the repeated question is dropped before anything is shown or spoken, and
/// a reply in the wrong language is not emitted at all (the engine retries it once).
class _LeadGate {
  _LeadGate(this.userText, this.lang, this.allowIntro, {this.canBlock = true});
  final bool canBlock;
  final String userText;
  final String lang;
  final bool allowIntro;
  final _buf = StringBuffer();
  bool opened = false;
  bool blocked = false;

  static final _end = RegExp(r'[.!?؟\n]\s');

  String feed(String delta) {
    if (blocked) return '';
    if (opened) return delta;
    _buf.write(delta);
    final s = _buf.toString();
    if (_end.hasMatch(s) || s.length >= 160) return _decide(s);
    return '';
  }

  String flush() => blocked || opened ? '' : _decide(_buf.toString());

  String _decide(String s) {
    final letters = RegExp(r'[A-Za-z؀-ۿ]').allMatches(s).length;
    final g = guardReply(s, userText: userText, lang: lang, allowIntro: allowIntro, toolsRan: true);
    if (canBlock && g.issues.contains('language') && letters >= 12) {
      blocked = true;
      return '';
    }
    opened = true;
    if (!g.changed) return s;
    final trailing = RegExp(r'\s+$').firstMatch(s)?[0] ?? '';
    return '${g.text}$trailing';
  }
}
