// Ollama native API adapter (/api/chat NDJSON streaming, think, images, tools; /api/show capabilities).
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/contracts/llm.dart';
import '../capabilities.dart';
import '../sampling_presets.dart';
import 'openai_compat_client.dart' show CapsLookup, OpenAiCompatClient, SamplingLookup;
import 'stream_utils.dart';

class OllamaClient extends LlmClient {
  OllamaClient({required this.providerId, required String baseUrl, String? apiKey, Map<String, String> headers = const {}, CapsLookup? capsOf, this.numCtxOf, this.samplingOf})
      : baseUrl = _normalize(baseUrl),
        _capsOf = capsOf ?? ((_) => null),
        _dio = buildDio(headers: {...headers, if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'});

  @override
  final String providerId;
  final String baseUrl;
  final CapsLookup _capsOf;
  /// Context size the user explicitly set for a model (sent as num_ctx). Ollama's default is used otherwise.
  final int? Function(String modelId)? numCtxOf;
  /// Family sampling preset or the user's values (sent as options).
  final SamplingLookup? samplingOf;
  final Dio _dio;
  String get host => hostOf(baseUrl);

  static String _normalize(String u) {
    var s = trimSlash(u);
    if (s.endsWith('/api')) s = s.substring(0, s.length - 4);
    if (s.endsWith('/v1')) s = s.substring(0, s.length - 3);
    return s;
  }

  dynamic _decode(dynamic d) => d is String ? jsonDecode(d) : d;

  @override
  Future<List<LlmModel>> listModels() async {
    final r = await _dio.get<dynamic>('$baseUrl/api/tags');
    if ((r.statusCode ?? 0) >= 400) throw httpError(r.statusCode ?? 0, jsonEncodeSafe(r.data), host).message;
    final d = _decode(r.data);
    final models = (d is Map ? d['models'] as List? : null) ?? const [];
    final ids = [for (final m in models) if (m is Map && (m['name'] ?? m['model']) != null) (m['name'] ?? m['model']).toString()];
    // Probe capabilities a few at a time.
    final out = <LlmModel>[];
    for (var i = 0; i < ids.length; i += 4) {
      final batch = ids.skip(i).take(4);
      out.addAll(await Future.wait(batch.map((id) async {
        final caps = await probe(id) ?? guessCaps(id, preset: 'ollama');
        return LlmModel(providerId: providerId, modelId: id, displayName: id.endsWith(':latest') ? id.substring(0, id.length - 7) : id, caps: caps);
      })));
    }
    return out.where((m) => !m.modelId.contains('embed')).toList();
  }

  Future<ModelCapabilities?> probe(String modelId) async {
    try {
      final r = await _dio.post<dynamic>('$baseUrl/api/show', data: {'model': modelId}, options: Options(receiveTimeout: const Duration(seconds: 15)));
      if ((r.statusCode ?? 0) >= 400) return null;
      final d = _decode(r.data);
      if (d is! Map) return null;
      final capList = (d['capabilities'] as List?)?.map((e) => e.toString()).toList();
      final guess = guessCaps(modelId, preset: 'ollama');
      int? ctx;
      final info = d['model_info'];
      if (info is Map) {
        for (final e in info.entries) {
          if (e.key.toString().endsWith('.context_length') && e.value is num) ctx = (e.value as num).toInt();
        }
      }
      if (capList == null) return guess;
      final thinking = capList.contains('thinking');
      final oss = modelId.contains('gpt-oss');
      return ModelCapabilities(
        vision: capList.contains('vision'),
        tools: capList.contains('tools'),
        reasoning: thinking,
        reasoningCanDisable: thinking && !oss,
        reasoningLevels: !thinking ? const [] : (oss ? const [ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high] : const [ReasoningLevel.medium]),
        contextWindow: ctx ?? guess.contextWindow,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _message(LlmMessage m) => switch (m.role) {
        LlmRole.system => {'role': 'system', 'content': m.content},
        LlmRole.user => {
            'role': 'user',
            'content': m.content,
            if (m.images.isNotEmpty) 'images': [for (final i in m.images) base64Encode(i.bytes)],
          },
        LlmRole.assistant => {
            'role': 'assistant',
            'content': m.content,
            if (m.toolCalls.isNotEmpty)
              'tool_calls': [
                for (final c in m.toolCalls) {'function': {'name': c.name, 'arguments': tryJsonObject(c.argumentsJson) ?? {}}},
              ],
          },
        LlmRole.tool => {'role': 'tool', 'content': m.content, if (m.toolName != null) 'tool_name': m.toolName},
      };

  Map<String, dynamic> buildBody(LlmRequest req) {
    final caps = _capsOf(req.modelId) ?? guessCaps(req.modelId, preset: 'ollama');
    final body = <String, dynamic>{
      'model': req.modelId,
      'messages': OpenAiCompatClient.normalizeSystem(req.messages).map(_message).toList(),
      'stream': req.stream,
      if (req.tools.isNotEmpty)
        'tools': [
          for (final t in req.tools) {'type': 'function', 'function': {'name': t.name, 'description': t.description, 'parameters': t.parameters}},
        ],
      'options': {
        ...(samplingOf?.call(req.modelId, thinkingOn(caps, req.reasoning)) ?? SamplingParams.none).toOllamaOptions(),
        if (req.temperature != null) 'temperature': req.temperature,
        if (req.maxTokens != null) 'num_predict': req.maxTokens,
        if (numCtxOf?.call(req.modelId) != null) 'num_ctx': numCtxOf!(req.modelId),
      },
    };
    if (caps.reasoning) {
      if (req.modelId.contains('gpt-oss')) {
        body['think'] = effortName(req.reasoning, hasMinimal: false);
      } else if (req.reasoning == ReasoningLevel.off) {
        if (caps.reasoningCanDisable) body['think'] = false;
      } else {
        body['think'] = true;
      }
    }
    return body;
  }

  @override
  Stream<LlmEvent> chat(LlmRequest request, {LlmCancelToken? cancel}) async* {
    final ct = linkCancel(cancel);
    Response<ResponseBody> r;
    try {
      r = await _dio.post<ResponseBody>('$baseUrl/api/chat', data: buildBody(request), options: Options(responseType: ResponseType.stream), cancelToken: ct);
    } catch (e) {
      yield isCancel(e) ? const DoneEvent('cancelled') : dioError(e, host);
      return;
    }
    if ((r.statusCode ?? 0) >= 400) {
      yield await errorFromStreamResponse(r, host);
      return;
    }
    final think = ThinkTagSplitter();
    final calls = <LlmToolCall>[];
    String finish = 'stop';
    try {
      await for (final j in parseNdjson(r.data!.stream)) {
        if (cancel?.isCancelled ?? false) break;
        if (j['error'] != null) {
          yield ErrorEvent('$host: ${j['error']}');
          return;
        }
        final msg = j['message'];
        if (msg is Map) {
          final th = msg['thinking'];
          if (th is String && th.isNotEmpty) yield ReasoningDelta(th);
          final c = msg['content'];
          if (c is String && c.isNotEmpty) {
            for (final e in think.feed(c)) {
              yield e;
            }
          }
          final tc = msg['tool_calls'];
          if (tc is List) {
            for (final t in tc) {
              final f = t is Map ? t['function'] : null;
              if (f is Map && f['name'] != null) {
                final args = f['arguments'];
                calls.add(LlmToolCall(
                  id: (t['id'] as String?) ?? newCallId(calls.length),
                  name: f['name'].toString(),
                  argumentsJson: args is String ? args : jsonEncode(args ?? {}),
                ));
              }
            }
          }
        }
        if (j['done'] == true) {
          finish = (j['done_reason'] as String?) ?? 'stop';
          for (final e in think.flush()) {
            yield e;
          }
          for (final c in calls) {
            yield ToolCallEvent(c);
          }
          final evalCount = (j['eval_count'] as num?)?.toInt() ?? 0;
          final evalNs = (j['eval_duration'] as num?)?.toInt() ?? 0;
          yield UsageEvent(
            promptTokens: (j['prompt_eval_count'] as num?)?.toInt() ?? 0,
            completionTokens: evalCount,
            tokensPerSecond: evalNs > 0 ? evalCount / (evalNs / 1e9) : null,
          );
          yield DoneEvent(calls.isNotEmpty ? 'tool_calls' : finish);
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
    for (final e in think.flush()) {
      yield e;
    }
    for (final c in calls) {
      yield ToolCallEvent(c);
    }
    yield DoneEvent(calls.isNotEmpty ? 'tool_calls' : finish);
  }
}
