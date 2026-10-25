// Shared streaming helpers for LLM adapters: dio setup, SSE / NDJSON parsing, <think> tag splitting,
// tool-call assembly and readable HTTP error mapping.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException, SocketException;

import 'package:dio/dio.dart';

import '../../../core/contracts/llm.dart';

Dio buildDio({Map<String, String> headers = const {}}) => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      // Local models may spend minutes processing a long prompt before the first byte arrives.
      receiveTimeout: const Duration(minutes: 10),
      headers: headers,
      validateStatus: (_) => true,
    ));

String trimSlash(String s) => s.endsWith('/') ? trimSlash(s.substring(0, s.length - 1)) : s;

/// One Server-Sent Event.
class SseEvent {
  final String? event;
  final String data;
  const SseEvent(this.event, this.data);
}

/// Parses an SSE byte stream. Handles chunks split anywhere (including inside UTF-8 sequences),
/// CRLF line endings, multi-line `data:` fields and `:` keep-alive comments.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  String? event;
  final data = StringBuffer();
  var hasData = false;
  await for (final line in bytes.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (hasData) yield SseEvent(event, data.toString());
      event = null;
      data.clear();
      hasData = false;
      continue;
    }
    if (line.startsWith(':')) continue; // keep-alive / comment
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        if (hasData) data.write('\n');
        data.write(value);
        hasData = true;
    }
  }
  if (hasData) yield SseEvent(event, data.toString());
}


/// Routes inline `<think>...</think>` content to [ReasoningDelta], everything else to [TextDelta].
/// Tags split across chunks are held back until they can be decided.
class ThinkTagSplitter {
  static const _open = '<think>';
  static const _close = '</think>';
  bool _inThink = false;
  String _pending = '';
  bool _sawText = false;

  List<LlmEvent> feed(String chunk) {
    final out = <LlmEvent>[];
    var s = _pending + chunk;
    _pending = '';
    while (s.isNotEmpty) {
      if (!_inThink && !canOpen) {
        _emit(out, s);
        break;
      }
      final tag = _inThink ? _close : _open;
      final i = s.indexOf(tag);
      if (i >= 0) {
        final before = s.substring(0, i);
        // Visible text before the tag in the same chunk: the tag is part of the answer.
        if (!_inThink && before.trim().isNotEmpty) {
          _emit(out, s);
          break;
        }
        _emit(out, before);
        _inThink = !_inThink;
        s = s.substring(i + tag.length);
        if (!_inThink) s = s.replaceFirst(RegExp(r'^\s+'), '');
        continue;
      }
      // Hold back a possible partial tag at the end.
      var keep = 0;
      for (var k = tag.length - 1; k > 0; k--) {
        if (s.length >= k && s.endsWith(tag.substring(0, k))) {
          keep = k;
          break;
        }
      }
      _emit(out, s.substring(0, s.length - keep));
      _pending = s.substring(s.length - keep);
      break;
    }
    return out;
  }

  List<LlmEvent> flush() {
    final out = <LlmEvent>[];
    _emit(out, _pending);
    _pending = '';
    return out;
  }

  void _emit(List<LlmEvent> out, String t) {
    if (t.isEmpty) return;
    if (_inThink) {
      out.add(ReasoningDelta(t));
    } else {
      // Only a `<think>` at the very start of the reply opens a reasoning block.
      if (!_sawText && t.trim().isEmpty) return;
      _sawText = true;
      out.add(TextDelta(t));
    }
  }

  /// After visible text started, later `<think>` tags are kept as text.
  bool get canOpen => !_sawText;
}

/// Collects streamed tool-call fragments by index (OpenAI style).
class ToolCallAssembler {
  final _calls = <int, _PartialCall>{};

  void add(Map<String, dynamic> d) {
    final index = (d['index'] as num?)?.toInt() ?? _calls.length;
    final p = _calls.putIfAbsent(index, _PartialCall.new);
    final id = d['id'];
    if (id is String && id.isNotEmpty) p.id = id;
    final f = d['function'];
    if (f is Map) {
      final name = f['name'];
      if (name is String && name.isNotEmpty) p.name += p.name == name ? '' : name;
      final args = f['arguments'];
      if (args is String) {
        p.args.write(args);
      } else if (args is Map) {
        p.args.write(jsonEncode(args));
      }
    }
  }

  bool get isEmpty => _calls.isEmpty;

  List<LlmToolCall> build() {
    final keys = _calls.keys.toList()..sort();
    final out = <LlmToolCall>[];
    for (final k in keys) {
      final p = _calls[k]!;
      if (p.name.isEmpty) continue;
      var args = p.args.toString().trim();
      if (args.isEmpty) args = '{}';
      out.add(LlmToolCall(id: p.id ?? newCallId(k), name: p.name, argumentsJson: args));
    }
    _calls.clear();
    return out;
  }
}

class _PartialCall {
  String? id;
  String name = '';
  final args = StringBuffer();
}

int _callSeq = 0;
String newCallId([int i = 0]) => 'call_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${i}_${_callSeq++}';

/// Reads an error body from a streamed response (status >= 400) and returns a readable message.
Future<ErrorEvent> errorFromStreamResponse(Response<ResponseBody> r, String host) async {
  var body = '';
  try {
    final chunks = await r.data!.stream.timeout(const Duration(seconds: 10)).toList();
    body = utf8.decode(chunks.expand((c) => c).toList(), allowMalformed: true);
  } catch (_) {}
  return httpError(r.statusCode ?? 0, body, host);
}

/// A stream that ended without the server's end marker: the server stopped or the connection dropped mid-reply.
ErrorEvent cutOffError(String host) =>
    ErrorEvent('The reply from $host stopped before it was complete. The model server may have stopped or restarted.');

ErrorEvent httpError(int status, String body, String host) {
  String? detail;
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final e = j['error'];
      if (e is Map) {
        detail = (e['message'] ?? e['type'])?.toString();
      } else if (e is String) {
        detail = e;
      }
      detail ??= (j['message'] ?? j['detail'])?.toString();
    }
  } catch (_) {
    if (body.trim().isNotEmpty && body.length < 300) detail = body.trim();
  }
  final base = switch (status) {
    400 => 'The server rejected the request',
    401 => 'API key missing or rejected',
    403 => 'Access denied by $host',
    404 => 'Model or endpoint not found on $host',
    408 => 'The server timed out',
    413 => 'The request is too large for the model',
    422 => 'The server could not process the request',
    429 => 'Rate limit or quota reached, try again shortly',
    500 || 502 || 503 || 504 => '$host had a server error ($status)',
    _ => 'Request failed ($status)',
  };
  return ErrorEvent(detail == null || detail.isEmpty ? base : '$base: $detail', statusCode: status);
}

ErrorEvent dioError(Object e, String host) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return ErrorEvent('Could not reach $host (timed out). Is the server running and reachable?');
      case DioExceptionType.connectionError:
        return ErrorEvent('Could not connect to $host. Check the address and that the server is running.');
      case DioExceptionType.receiveTimeout:
        return ErrorEvent('$host stopped responding.');
      case DioExceptionType.sendTimeout:
        return ErrorEvent('Sending the request to $host timed out.');
      case DioExceptionType.badCertificate:
        return ErrorEvent('$host presented an invalid TLS certificate.');
      case DioExceptionType.badResponse:
        final r = e.response;
        return httpError(r?.statusCode ?? 0, r?.data is String ? r!.data as String : jsonEncodeSafe(r?.data), host);
      case DioExceptionType.cancel:
        return const ErrorEvent('Cancelled');
      default:
        if (e.error is HttpException || e.error is SocketException) return cutOffError(host);
        return ErrorEvent('Network error talking to $host: ${e.message ?? e.error ?? 'unknown'}');
    }
  }
  // The connection closed while the reply was streaming (server stopped, proxy lost its model server).
  if (e is HttpException || e is SocketException) return cutOffError(host);
  if (e is FormatException) return ErrorEvent('$host sent a response Nur could not read (${e.message}).');
  if (e is TimeoutException) return ErrorEvent('$host did not answer in time.');
  return ErrorEvent('Unexpected error: $e');
}

String jsonEncodeSafe(Object? o) {
  try {
    return o == null ? '' : jsonEncode(o);
  } catch (_) {
    return o.toString();
  }
}

String hostOf(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  return u.hasPort ? '${u.host}:${u.port}' : u.host;
}

/// Wires an [LlmCancelToken] to a dio [CancelToken].
CancelToken linkCancel(LlmCancelToken? t) {
  final c = CancelToken();
  t?.onCancel(() {
    if (!c.isCancelled) c.cancel('cancelled');
  });
  return c;
}

bool isCancel(Object e) => e is DioException && e.type == DioExceptionType.cancel;

String dataUrl(LlmImage img) => 'data:${img.mimeType};base64,${base64Encode(img.bytes)}';

Map<String, dynamic>? tryJsonObject(String s) {
  try {
    final j = jsonDecode(s);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  }
}
