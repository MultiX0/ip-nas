// OpenAI-compatible Chat Completions adapter: llama.cpp server, LM Studio, vLLM, OpenAI, OpenRouter, Groq,
// DeepSeek, Mistral, xAI, Together, Gemini (OpenAI endpoint) and the NAS hub proxy.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/contracts/llm.dart';
import '../capabilities.dart';
import '../sampling_presets.dart';
import 'stream_utils.dart';

typedef CapsLookup = ModelCapabilities? Function(String modelId);

/// Sampling for a model (family preset or user values); [thinking] = reasoning is on for the request.
typedef SamplingLookup = SamplingParams Function(String modelId, bool thinking);

class OpenAiCompatClient extends LlmClient {
  OpenAiCompatClient({
    required this.providerId,
    required String baseUrl,
    this.apiKey,
    this.preset,
    Map<String, String> headers = const {},
    CapsLookup? capsOf,
    SamplingLookup? samplingOf,
  })  : baseUrl = trimSlash(baseUrl),
        _capsOf = capsOf ?? ((_) => null),
        _samplingOf = samplingOf, // ignore: prefer_initializing_formals
        _dio = buildDio(headers: {
          ...headers,
          if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          if (preset == 'openrouter') 'X-Title': 'Nur',
        });

  @override
  final String providerId;
  final String baseUrl;
  final String? apiKey;
  final String? preset;
  final CapsLookup _capsOf;
  final SamplingLookup? _samplingOf;
  final Dio _dio;

  @visibleForTesting
  Dio get dio => _dio;

  String get host => hostOf(baseUrl);
  bool get isLlamaCpp => preset == 'llamacpp' || preset == 'nas';
  bool get isLocalTemplate => isLlamaCpp || preset == 'lmstudio' || preset == 'vllm' || preset == 'custom' || preset == null;

  /// Server root without the trailing `/v1` (llama.cpp serves /props and /tokenize there).
  String get rootUrl => baseUrl.endsWith('/v1') ? baseUrl.substring(0, baseUrl.length - 3) : baseUrl;

  @override
  Future<List<LlmModel>> listModels() async {
    final r = await _dio.get<dynamic>('$baseUrl/models');
    if ((r.statusCode ?? 0) >= 400) throw httpError(r.statusCode ?? 0, jsonEncodeSafe(r.data), host).message;
    final body = r.data is String ? jsonDecode(r.data as String) : r.data;
    final list = body is Map ? (body['data'] ?? body['models'] ?? const []) as List : (body is List ? body : const []);
    final props = isLlamaCpp || preset == null || preset == 'custom' ? await _llamaProps() : null;
    final out = <LlmModel>[];
    for (final m in list) {
      if (m is! Map) continue;
      var id = (m['id'] ?? m['name'] ?? m['model'])?.toString() ?? '';
      if (id.isEmpty) continue;
      if (preset == 'gemini' && id.startsWith('models/')) id = id.substring(7);
      if (_skip(id)) continue;
      var caps = guessCaps(id, preset: preset);
      caps = _fromMetadata(m.cast<String, dynamic>(), caps);
      if (props != null && list.length == 1) caps = _mergeProps(props, caps);
      // llama.cpp: the thinking budget is enforced live, so every level works for any reasoning model.
      if (isLlamaCpp && caps.reasoning) caps = withAllLevels(caps);
      final name = (m['name'] is String && preset == 'openrouter') ? m['name'] as String : _prettyName(id);
      out.add(LlmModel(providerId: providerId, modelId: id, displayName: name, caps: caps));
    }
    return out;
  }

  bool _skip(String id) {
    final l = id.toLowerCase();
    if (preset == 'openai') {
      return _hasAny(l, ['embedding', 'tts', 'whisper', 'dall-e', 'moderation', 'davinci', 'babbage', 'transcribe', 'realtime', 'audio', 'image', 'search', 'computer-use', 'codex']);
    }
    return _hasAny(l, ['embed', 'whisper', 'tts', 'moderation', 'rerank', 'guard']) && !l.contains('chat');
  }

  static bool _hasAny(String s, List<String> k) => k.any(s.contains);

  static String _prettyName(String id) {
    var s = id;
    final slash = s.lastIndexOf('/');
    if (slash >= 0 && slash < s.length - 1) s = s.substring(slash + 1);
    s = s.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
    return s;
  }

  /// OpenRouter / Together / Groq expose context and modalities in /models.
  ModelCapabilities _fromMetadata(Map<String, dynamic> m, ModelCapabilities c) {
    var vision = c.vision, tools = c.tools, reasoning = c.reasoning;
    var levels = c.reasoningLevels;
    final top = m['top_provider'];
    final rawCtx = m['context_length'] ?? m['context_window'] ?? m['max_context_length'] ?? (top is Map ? top['context_length'] : null);
    int? ctx = rawCtx is num ? rawCtx.toInt() : c.contextWindow;
    final arch = m['architecture'];
    if (arch is Map && arch['input_modalities'] is List) vision = (arch['input_modalities'] as List).contains('image');
    final sp = m['supported_parameters'];
    if (sp is List) {
      tools = sp.contains('tools');
      if (sp.contains('reasoning') || sp.contains('include_reasoning')) {
        reasoning = true;
        if (levels.isEmpty) levels = const [ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high];
      }
    }
    final meta = m['meta'];
    if (meta is Map && meta['n_ctx_train'] is num && ctx == null) ctx = (meta['n_ctx_train'] as num).toInt();
    return ModelCapabilities(
      vision: vision,
      tools: tools,
      reasoning: reasoning,
      reasoningCanDisable: reasoning && (c.reasoningCanDisable || preset == 'openrouter'),
      reasoningLevels: reasoning ? levels : const [],
      contextWindow: ctx,
    );
  }

  Future<Map<String, dynamic>?> _llamaProps() async {
    try {
      final r = await _dio.get<dynamic>('$rootUrl/props', options: Options(receiveTimeout: const Duration(seconds: 8)));
      if ((r.statusCode ?? 0) >= 400) return null;
      final d = r.data is String ? jsonDecode(r.data as String) : r.data;
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  ModelCapabilities _mergeProps(Map<String, dynamic> p, ModelCapabilities c) {
    final gen = p['default_generation_settings'];
    final ctx = (p['n_ctx'] ?? (gen is Map ? gen['n_ctx'] : null)) as num?;
    final mod = p['modalities'];
    final vision = mod is Map ? mod['vision'] == true : c.vision;
    final tpl = (p['chat_template'] ?? '').toString();
    final tools = tpl.isEmpty ? c.tools : (tpl.contains('tools') || tpl.contains('tool_call'));
    final effort = tpl.contains('reasoning_effort');
    final toggle = tpl.contains('enable_thinking');
    final think = effort || toggle || tpl.contains('<think>') || tpl.contains('reasoning_content') || c.reasoning;
    return ModelCapabilities(
      vision: vision,
      tools: tools,
      reasoning: think,
      reasoningCanDisable: think && (toggle || c.reasoningCanDisable),
      reasoningLevels: !think
          ? const []
          // llama.cpp: every level is meaningful because the thinking budget is enforced live (see chat()).
          : const [ReasoningLevel.minimal, ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high, ReasoningLevel.extra],
      contextWindow: ctx?.toInt() ?? c.contextWindow,
    );
  }

  @override
  Future<int?> countTokens(String modelId, String text) async {
    if (!isLlamaCpp) return null;
    try {
      final r = await _dio.post<dynamic>('$rootUrl/tokenize', data: {'content': text, 'model': modelId}); // router mode picks the model by name
      final d = r.data is String ? jsonDecode(r.data as String) : r.data;
      if (d is Map && d['tokens'] is List) return (d['tokens'] as List).length;
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _message(LlmMessage m) {
    switch (m.role) {
      case LlmRole.system:
        return {'role': 'system', 'content': m.content};
      case LlmRole.user:
        if (m.images.isEmpty) return {'role': 'user', 'content': m.content};
        return {
          'role': 'user',
          'content': [
            if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
            for (final img in m.images) {'type': 'image_url', 'image_url': {'url': dataUrl(img)}},
          ],
        };
      case LlmRole.assistant:
        return {
          'role': 'assistant',
          'content': m.content.isEmpty && m.toolCalls.isNotEmpty ? null : m.content,
          if (m.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in m.toolCalls) {'id': c.id, 'type': 'function', 'function': {'name': c.name, 'arguments': c.argumentsJson}},
            ],
        };
      case LlmRole.tool:
        return {'role': 'tool', 'tool_call_id': m.toolCallId ?? '', 'content': m.content, if (preset == 'mistral' && m.toolName != null) 'name': m.toolName};
    }
  }

  Map<String, dynamic> buildBody(LlmRequest req) {
    final caps = _capsOf(req.modelId) ?? guessCaps(req.modelId, preset: preset);
    // "Answer without tools": llama.cpp keeps the tool list in the prompt with tool_choice none, so the cached prompt
    // stays valid (without the list it re-reads the whole chat, 30 s or more on a Pi). Other servers get no tools.
    final noCalls = req.toolChoice == 'none';
    final sendTools = req.tools.isNotEmpty && (!noCalls || isLlamaCpp);
    final body = <String, dynamic>{
      'model': req.modelId,
      'messages': normalizeSystem(req.messages).map(_message).toList(),
      'stream': req.stream,
      if (req.stream && preset != 'mistral') 'stream_options': {'include_usage': true},
      if (req.temperature != null) 'temperature': req.temperature,
      if (req.maxTokens != null) (preset == 'openai' ? 'max_completion_tokens' : 'max_tokens'): req.maxTokens,
      if (sendTools)
        'tools': [
          for (final t in req.tools) {'type': 'function', 'function': {'name': t.name, 'description': t.description, 'parameters': t.parameters}},
        ],
      if (sendTools && noCalls) 'tool_choice': 'none',
    };
    if (isLlamaCpp) {
      body['timings_per_token'] = false;
      // Reuse the KV cache of the previous request for the unchanged prefix (system prompt + tools + history).
      body['cache_prompt'] = true;
    }
    _applySampling(body, req, caps);
    if (caps.reasoning) _applyReasoning(body, req.reasoning, caps);
    // Reasoning models on OpenAI reject custom temperature.
    if (preset == 'openai' && caps.reasoning) body.remove('temperature');
    return body;
  }

  /// Family sampling preset ("Recommended (auto)") or the user's values, for local backends only.
  /// An explicit request temperature (model override, title/summary calls) always wins.
  void _applySampling(Map<String, dynamic> body, LlmRequest req, ModelCapabilities caps) {
    if (!isLocalTemplate || _samplingOf == null) return;
    final s = _samplingOf(req.modelId, thinkingOn(caps, req.reasoning));
    if (s.isEmpty) return;
    s.toOpenAiBody().forEach((k, v) {
      if (k == 'temperature' && req.temperature != null) return;
      body[preset == 'vllm' && k == 'repeat_penalty' ? 'repetition_penalty' : k] = v;
    });
  }

  void _applyReasoning(Map<String, dynamic> body, ReasoningLevel level, ModelCapabilities caps) {
    final off = level == ReasoningLevel.off;
    final effort = effortName(level, hasMinimal: false);
    final multiLevel = caps.reasoningLevels.length > 1;
    switch (preset) {
      case 'openai':
        body['reasoning_effort'] = effortName(level, hasXHigh: true);
      case 'openrouter':
        body['reasoning'] = off ? {'enabled': false} : {'effort': effortName(level)};
      case 'gemini':
        body['reasoning_effort'] = off ? 'none' : effort;
      case 'groq':
        if (multiLevel) {
          body['reasoning_effort'] = effort;
        } else {
          body['reasoning_effort'] = off ? 'none' : 'default';
        }
        body['reasoning_format'] = 'parsed';
      case 'xai':
        if (multiLevel) body['reasoning_effort'] = level == ReasoningLevel.high ? 'high' : 'low';
      case 'deepseek' || 'mistral' || 'together' || 'anthropic':
        break;
      default:
        // llama.cpp / LM Studio / vLLM / custom: `reasoning_effort` (none|minimal|low|medium|high|xhigh) for templates
        // that read it, `enable_thinking` for templates with an on/off switch, and on llama.cpp a live token budget.
        if (off) {
          if (caps.reasoningCanDisable) body['chat_template_kwargs'] = {'enable_thinking': false};
          if (isLlamaCpp) body['reasoning_effort'] = 'none';
        } else {
          final e = effortName(level, hasXHigh: true);
          body['reasoning_effort'] = e;
          body['chat_template_kwargs'] = {'reasoning_effort': e, if (caps.reasoningCanDisable) 'enable_thinking': true};
          if (isLlamaCpp && reasoningBudgets[level] != null) body['reasoning_control'] = true;
        }
    }
  }

  @override
  Stream<LlmEvent> chat(LlmRequest request, {LlmCancelToken? cancel}) async* {
    final ct = linkCancel(cancel);
    final sw = Stopwatch()..start();
    Response<ResponseBody> r;
    try {
      r = await _dio.post<ResponseBody>('$baseUrl/chat/completions',
          data: buildBody(request), options: Options(responseType: ResponseType.stream, headers: {'Accept': 'text/event-stream'}), cancelToken: ct);
    } catch (e) {
      yield isCancel(e) ? const DoneEvent('cancelled') : dioError(e, host);
      return;
    }
    if ((r.statusCode ?? 0) >= 400) {
      yield await errorFromStreamResponse(r, host);
      return;
    }
    final think = ThinkTagSplitter();
    final tools = ToolCallAssembler();
    // Live thinking budget (llama.cpp): count streamed reasoning tokens and ask the server to end thinking at the limit.
    final budget = isLlamaCpp && request.reasoning != ReasoningLevel.off ? reasoningBudgets[request.reasoning] : null;
    var reasoningTokens = 0;
    var budgetSent = false;
    String? completionId;
    String? finish;
    var sawDone = false;
    int? promptTokens, completionTokens;
    double? tps;
    var completionChars = 0;
    Duration? firstToken;
    try {
      await for (final ev in parseSse(r.data!.stream)) {
        if (cancel?.isCancelled ?? false) break;
        final data = ev.data.trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') {
          sawDone = true;
          break;
        }
        final j = tryJsonObject(data);
        if (j == null) continue;
        final err = j['error'];
        if (err != null) {
          final msg = err is Map ? (err['message'] ?? err.toString()).toString() : err.toString();
          yield ErrorEvent('$host: $msg', statusCode: err is Map ? (err['code'] as num?)?.toInt() : null);
          return;
        }
        final usage = j['usage'];
        if (usage is Map) {
          promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? promptTokens;
          completionTokens = (usage['completion_tokens'] as num?)?.toInt() ?? completionTokens;
        }
        final timings = j['timings'];
        if (timings is Map) {
          tps = (timings['predicted_per_second'] as num?)?.toDouble() ?? tps;
          promptTokens ??= (timings['prompt_n'] as num?)?.toInt();
          completionTokens ??= (timings['predicted_n'] as num?)?.toInt();
        }
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final ch = choices.first as Map;
        final delta = (ch['delta'] ?? ch['message']) as Map?;
        if (delta != null) {
          final rc = delta['reasoning_content'] ?? delta['reasoning'] ?? delta['thinking'];
          if (rc is String && rc.isNotEmpty) {
            firstToken ??= sw.elapsed;
            yield ReasoningDelta(rc);
            completionId ??= j['id'] as String?;
            reasoningTokens++; // llama.cpp streams one token per chunk
            if (budget != null && !budgetSent && reasoningTokens >= budget && completionId != null) {
              budgetSent = true;
              unawaited(_endReasoning(completionId, request.modelId));
            }
          }
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            firstToken ??= sw.elapsed;
            completionChars += content.length;
            for (final e in think.feed(content)) {
              yield e;
            }
          }
          final tc = delta['tool_calls'];
          if (tc is List) {
            for (final t in tc) {
              if (t is Map) tools.add(t.cast<String, dynamic>());
            }
          }
        }
        final fr = ch['finish_reason'];
        if (fr is String && fr.isNotEmpty) finish = fr;
      }
    } catch (e) {
      if (isCancel(e) || (cancel?.isCancelled ?? false)) {
        yield const DoneEvent('cancelled');
      } else {
        yield dioError(e, host);
      }
      return;
    }
    if (cancel?.isCancelled ?? false) {
      yield const DoneEvent('cancelled');
      return;
    }
    for (final e in think.flush()) {
      yield e;
    }
    // Neither a finish_reason nor [DONE]: the server stopped in the middle (crash, restart, dropped connection).
    // The text so far stays, half-streamed tool calls are dropped.
    if (!sawDone && finish == null) {
      yield cutOffError(host);
      return;
    }
    final calls = tools.build();
    for (final c in calls) {
      yield ToolCallEvent(c);
    }
    if (tps == null && completionTokens != null && firstToken != null) {
      final secs = (sw.elapsed - firstToken).inMilliseconds / 1000;
      if (secs > 0.05) tps = completionTokens / secs;
    }
    if (promptTokens != null || completionTokens != null) {
      yield UsageEvent(promptTokens: promptTokens ?? 0, completionTokens: completionTokens ?? (completionChars / 4).round(), tokensPerSecond: tps);
    }
    yield DoneEvent(calls.isNotEmpty ? 'tool_calls' : (finish ?? 'stop'));
  }

  /// llama.cpp `/v1/chat/completions/control`: finish the thinking block now so the model moves on to the answer.
  Future<void> _endReasoning(String id, String modelId) async {
    try {
      await _dio.post<dynamic>('$baseUrl/chat/completions/control', data: {'id': id, 'action': 'reasoning_end', 'model': modelId});
    } catch (_) {/* older llama.cpp: thinking simply runs to its natural end */}
  }

  static ModelCapabilities withAllLevels(ModelCapabilities c) => ModelCapabilities(
        vision: c.vision,
        tools: c.tools,
        reasoning: true,
        reasoningCanDisable: c.reasoningCanDisable,
        reasoningLevels: const [ReasoningLevel.minimal, ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high, ReasoningLevel.extra],
        contextWindow: c.contextWindow,
      );

  /// Many chat templates (Qwen, Llama, Gemma) accept only ONE system message, and only at the start
  /// ("System message must be at the beginning"). Merge every system message into a single leading one;
  /// a system message that appears later (e.g. a mid-chat note) becomes part of that leading block too.
  static List<LlmMessage> normalizeSystem(List<LlmMessage> msgs) {
    final sys = [for (final m in msgs) if (m.role == LlmRole.system && m.content.trim().isNotEmpty) m.content.trim()];
    if (sys.length <= 1 && (msgs.isEmpty || msgs.first.role == LlmRole.system || sys.isEmpty)) return msgs;
    return [LlmMessage(LlmRole.system, sys.join('\n\n')), for (final m in msgs) if (m.role != LlmRole.system) m];
  }
}
