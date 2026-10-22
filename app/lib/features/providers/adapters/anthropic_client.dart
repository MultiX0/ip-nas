// Anthropic Messages API adapter (SSE, extended thinking, tool_use, image blocks).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../../core/contracts/llm.dart';
import '../capabilities.dart';
import 'openai_compat_client.dart' show CapsLookup;
import 'stream_utils.dart';

class AnthropicClient extends LlmClient {
  AnthropicClient({required this.providerId, String baseUrl = 'https://api.anthropic.com', required String apiKey, Map<String, String> headers = const {}, CapsLookup? capsOf})
      : baseUrl = _normalize(baseUrl),
        _capsOf = capsOf ?? ((_) => null),
        _dio = buildDio(headers: {...headers, 'x-api-key': apiKey, 'anthropic-version': '2023-06-01'});

  @override
  final String providerId;
  final String baseUrl;
  final CapsLookup _capsOf;
  final Dio _dio;
  String get host => hostOf(baseUrl);

  /// Thinking blocks (with signatures) that preceded a tool_use, keyed by the first tool_use id.
  /// The API requires them to be replayed while a tool loop is in progress.
  final _thinkingByToolId = <String, List<Map<String, dynamic>>>{};

  static String _normalize(String u) {
    var s = trimSlash(u);
    if (s.endsWith('/v1')) s = s.substring(0, s.length - 3);
    return s;
  }

  /// Thinking budget for models before Claude 4.6 (`thinking.type: enabled`).
  static int budgetFor(ReasoningLevel l) => switch (l) {
        ReasoningLevel.minimal => 1024,
        ReasoningLevel.low => 2048,
        ReasoningLevel.medium => 4096,
        ReasoningLevel.high => 16000,
        ReasoningLevel.extra => 32000,
        ReasoningLevel.off => 0,
      };

  /// Model version as major * 100 + minor: claude-opus-4-8 is 408, claude-sonnet-4-20250514 is 400. Null for ids
  /// in the older claude-3-7-sonnet style.
  static int? _version(String id) {
    final m = RegExp(r'claude-(?:opus|sonnet|haiku|fable|mythos)-(\d+)(?:-(\d{1,2})(?!\d))?').firstMatch(id);
    return m == null ? null : int.parse(m[1]!) * 100 + int.parse(m[2] ?? '0');
  }

  static bool _frontier(String id) => id.contains('claude-fable') || id.contains('claude-mythos');

  /// Claude 4.6 and newer think adaptively (`thinking.type: adaptive` with an effort level); from Opus 4.7 and
  /// Sonnet 5 on, a fixed `budget_tokens` is rejected.
  static bool _adaptive(String id) => _frontier(id) || (_version(id) ?? 0) >= 406;

  /// Opus 4.7+, Sonnet 5+, Fable and Mythos: temperature is rejected, effort goes up to xhigh, and thinking text is
  /// only streamed when `display: summarized` is asked for.
  static bool _newApi(String id) => _frontier(id) || (_version(id) ?? 0) >= (id.contains('opus') ? 407 : 500);

  /// Opus 5+, Sonnet 5+, Fable and Mythos think even when `thinking` is left out.
  static bool _alwaysThinks(String id) => _frontier(id) || (_version(id) ?? 0) >= 500;

  static String _effort(ReasoningLevel l, String id) => switch (l) {
        ReasoningLevel.off || ReasoningLevel.minimal || ReasoningLevel.low => 'low',
        ReasoningLevel.medium => 'medium',
        ReasoningLevel.high => 'high',
        ReasoningLevel.extra => _newApi(id) ? 'xhigh' : 'max',
      };

  static ModelCapabilities capsFor(String id, {int? contextWindow}) {
    final adaptive = _adaptive(id);
    final reasoning = adaptive || guessCaps(id, preset: 'anthropic').reasoning;
    return ModelCapabilities(
      vision: !id.contains('claude-2') && !id.contains('instant'),
      tools: true,
      reasoning: reasoning,
      reasoningCanDisable: reasoning && !_alwaysThinks(id),
      reasoningLevels: !reasoning
          ? const []
          : adaptive
              ? const [ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high, ReasoningLevel.extra]
              : const [ReasoningLevel.minimal, ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high, ReasoningLevel.extra],
      contextWindow: contextWindow ?? 200000,
    );
  }

  @override
  Future<List<LlmModel>> listModels() async {
    final r = await _dio.get<dynamic>('$baseUrl/v1/models', queryParameters: {'limit': 100});
    if ((r.statusCode ?? 0) >= 400) throw httpError(r.statusCode ?? 0, jsonEncodeSafe(r.data), host).message;
    final d = r.data is String ? jsonDecode(r.data as String) : r.data;
    final list = (d is Map ? d['data'] as List? : null) ?? const [];
    return [
      for (final m in list)
        if (m is Map && m['id'] != null)
          LlmModel(
            providerId: providerId,
            modelId: m['id'].toString(),
            displayName: (m['display_name'] ?? m['id']).toString(),
            caps: capsFor(m['id'].toString(), contextWindow: (m['max_input_tokens'] as num?)?.toInt()),
          ),
    ];
  }

  List<Map<String, dynamic>> _content(LlmMessage m) {
    switch (m.role) {
      case LlmRole.user:
        return [
          for (final i in m.images) {'type': 'image', 'source': {'type': 'base64', 'media_type': i.mimeType, 'data': base64Encode(i.bytes)}},
          if (m.content.isNotEmpty || m.images.isEmpty) {'type': 'text', 'text': m.content.isEmpty ? '.' : m.content},
        ];
      case LlmRole.assistant:
        final thinking = m.toolCalls.isNotEmpty ? _thinkingByToolId[m.toolCalls.first.id] : null;
        return [
          ...?thinking,
          if (m.content.trim().isNotEmpty) {'type': 'text', 'text': m.content},
          for (final c in m.toolCalls) {'type': 'tool_use', 'id': c.id, 'name': c.name, 'input': tryJsonObject(c.argumentsJson) ?? {}},
        ];
      case LlmRole.tool:
        return [
          {'type': 'tool_result', 'tool_use_id': m.toolCallId ?? '', 'content': m.content.isEmpty ? '(empty)' : m.content},
        ];
      case LlmRole.system:
        return const [];
    }
  }

  Map<String, dynamic> buildBody(LlmRequest req) {
    final id = req.modelId;
    final caps = _capsOf(id) ?? capsFor(id);
    final system = req.messages.where((m) => m.role == LlmRole.system).map((m) => m.content).where((s) => s.isNotEmpty).join('\n\n');
    final msgs = <Map<String, dynamic>>[];
    for (final m in req.messages) {
      if (m.role == LlmRole.system) continue;
      final role = m.role == LlmRole.assistant ? 'assistant' : 'user';
      final blocks = _content(m);
      if (blocks.isEmpty) continue;
      if (msgs.isNotEmpty && msgs.last['role'] == role) {
        (msgs.last['content'] as List).addAll(blocks);
      } else {
        msgs.add({'role': role, 'content': [...blocks]});
      }
    }
    var thinking = caps.reasoning && req.reasoning != ReasoningLevel.off;
    // While a tool loop is running, every assistant tool_use must carry its thinking block; if we lost it, turn thinking off.
    if (thinking) {
      final lastUser = req.messages.lastIndexWhere((m) => m.role == LlmRole.user);
      for (final m in req.messages.skip(lastUser + 1)) {
        if (m.role == LlmRole.assistant && m.toolCalls.isNotEmpty && !_thinkingByToolId.containsKey(m.toolCalls.first.id)) thinking = false;
      }
    }
    final adaptive = _adaptive(id);
    // "Off" on a model that always thinks becomes the lowest effort.
    final effort = thinking ? _effort(req.reasoning, id) : (caps.reasoning && _alwaysThinks(id) ? 'low' : null);
    final budget = budgetFor(req.reasoning);
    final int maxTokens;
    if (adaptive) {
      // Adaptive thinking has no fixed budget and shares max_tokens with the answer, so keep room for both.
      maxTokens = math.max(req.maxTokens ?? 32000, thinking || _alwaysThinks(id) ? 8192 : 0);
    } else {
      final wanted = req.maxTokens ?? (thinking ? budget + 8192 : 8192);
      maxTokens = thinking && wanted <= budget ? budget + 4096 : wanted;
    }
    return {
      'model': id,
      'max_tokens': maxTokens,
      if (system.isNotEmpty) 'system': system,
      'messages': msgs,
      'stream': req.stream,
      if (req.temperature != null && !thinking && !_newApi(id)) 'temperature': req.temperature,
      if (thinking && adaptive) 'thinking': {'type': 'adaptive', if (_newApi(id)) 'display': 'summarized'},
      if (thinking && !adaptive) 'thinking': {'type': 'enabled', 'budget_tokens': budget},
      if (adaptive && effort != null) 'output_config': {'effort': effort},
      if (req.tools.isNotEmpty) 'tools': [for (final t in req.tools) {'name': t.name, 'description': t.description, 'input_schema': t.parameters}],
    };
  }

  @override
  Stream<LlmEvent> chat(LlmRequest request, {LlmCancelToken? cancel}) async* {
    final ct = linkCancel(cancel);
    final sw = Stopwatch()..start();
    Response<ResponseBody> r;
    try {
      r = await _dio.post<ResponseBody>('$baseUrl/v1/messages',
          data: buildBody(request), options: Options(responseType: ResponseType.stream, headers: {'Accept': 'text/event-stream'}), cancelToken: ct);
    } catch (e) {
      yield isCancel(e) ? const DoneEvent('cancelled') : dioError(e, host);
      return;
    }
    if ((r.statusCode ?? 0) >= 400) {
      yield await errorFromStreamResponse(r, host);
      return;
    }
    final blocks = <int, Map<String, dynamic>>{};
    final argBuf = <int, StringBuffer>{};
    final calls = <LlmToolCall>[];
    final thinkingBlocks = <Map<String, dynamic>>[];
    var input = 0, output = 0;
    var stop = 'stop';
    Duration? first;
    try {
      await for (final ev in parseSse(r.data!.stream)) {
        if (cancel?.isCancelled ?? false) break;
        final j = tryJsonObject(ev.data);
        if (j == null) continue;
        switch (j['type']) {
          case 'message_start':
            final u = (j['message'] as Map?)?['usage'];
            if (u is Map) input = ((u['input_tokens'] as num?)?.toInt() ?? 0) + ((u['cache_read_input_tokens'] as num?)?.toInt() ?? 0) + ((u['cache_creation_input_tokens'] as num?)?.toInt() ?? 0);
          case 'content_block_start':
            final i = (j['index'] as num).toInt();
            final b = Map<String, dynamic>.from(j['content_block'] as Map);
            blocks[i] = b;
            if (b['type'] == 'tool_use') argBuf[i] = StringBuffer();
            if (b['type'] == 'thinking') b['thinking'] = b['thinking'] ?? '';
          case 'content_block_delta':
            final i = (j['index'] as num).toInt();
            final d = j['delta'] as Map;
            switch (d['type']) {
              case 'text_delta':
                first ??= sw.elapsed;
                yield TextDelta(d['text'] as String);
              case 'thinking_delta':
                first ??= sw.elapsed;
                final t = d['thinking'] as String;
                blocks[i]?['thinking'] = '${blocks[i]?['thinking'] ?? ''}$t';
                yield ReasoningDelta(t);
              case 'signature_delta':
                blocks[i]?['signature'] = '${blocks[i]?['signature'] ?? ''}${d['signature']}';
              case 'input_json_delta':
                argBuf[i]?.write(d['partial_json'] ?? '');
            }
          case 'content_block_stop':
            final i = (j['index'] as num).toInt();
            final b = blocks[i];
            if (b == null) break;
            if (b['type'] == 'tool_use') {
              final args = argBuf[i]?.toString().trim() ?? '';
              calls.add(LlmToolCall(id: b['id'] as String, name: b['name'] as String, argumentsJson: args.isEmpty ? '{}' : args));
            } else if (b['type'] == 'thinking' || b['type'] == 'redacted_thinking') {
              thinkingBlocks.add({...b});
            }
          case 'message_delta':
            final d = j['delta'];
            if (d is Map && d['stop_reason'] != null) {
              stop = switch (d['stop_reason']) { 'end_turn' => 'stop', 'tool_use' => 'tool_calls', 'max_tokens' => 'length', final s => s.toString() };
            }
            final u = j['usage'];
            if (u is Map) output = (u['output_tokens'] as num?)?.toInt() ?? output;
          case 'error':
            final e = j['error'];
            yield ErrorEvent('Anthropic: ${e is Map ? e['message'] : e}');
            return;
        }
      }
    } catch (e) {
      yield (isCancel(e) || (cancel?.isCancelled ?? false)) ? const DoneEvent('cancelled') : dioError(e, host);
      return;
    }
    if (cancel?.isCancelled ?? false) {
      yield const DoneEvent('cancelled');
      return;
    }
    if (calls.isNotEmpty && thinkingBlocks.isNotEmpty) {
      _thinkingByToolId[calls.first.id] = thinkingBlocks;
      if (_thinkingByToolId.length > 64) _thinkingByToolId.remove(_thinkingByToolId.keys.first);
    }
    for (final c in calls) {
      yield ToolCallEvent(c);
    }
    double? tps;
    if (first != null && output > 0) {
      final secs = (sw.elapsed - first).inMilliseconds / 1000;
      if (secs > 0.05) tps = output / secs;
    }
    yield UsageEvent(promptTokens: input, completionTokens: output, tokensPerSecond: tps);
    yield DoneEvent(calls.isNotEmpty ? 'tool_calls' : stop);
  }
}
