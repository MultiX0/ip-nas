// Minimal MCP client: Streamable HTTP (spec 2025-06-18) and the legacy HTTP+SSE transport (2024-11-05).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

const kMcpProtocol = '2025-06-18';
const kMcpLegacyProtocol = '2024-11-05';

class McpException implements Exception {
  final String message;
  const McpException(this.message);
  @override
  String toString() => message;
}

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  const McpTool(this.name, this.description, this.inputSchema);
  Map<String, dynamic> toJson() => {'name': name, 'description': description, 'inputSchema': inputSchema};
  factory McpTool.fromJson(Map<String, dynamic> j) => McpTool(
        (j['name'] ?? '').toString(),
        (j['description'] ?? j['title'] ?? '').toString(),
        j['inputSchema'] is Map ? Map<String, dynamic>.from(j['inputSchema'] as Map) : const {'type': 'object', 'properties': {}},
      );
}

class McpCallResult {
  final String text;
  final bool isError;
  const McpCallResult(this.text, this.isError);
}

class SseEvent {
  final String event;
  final String data;
  const SseEvent(this.event, this.data);
}

/// Parses a text/event-stream byte stream into events.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = <String>[];
  await for (final line in bytes.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield SseEvent(event, data.join('\n'));
      event = 'message';
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final i = line.indexOf(':');
    final field = i < 0 ? line : line.substring(0, i);
    var value = i < 0 ? '' : line.substring(i + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') event = value;
    if (field == 'data') data.add(value);
  }
  if (data.isNotEmpty) yield SseEvent(event, data.join('\n'));
}

abstract class McpConnection {
  Future<void> initialize();
  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic>? params, Duration? timeout]);
  Future<void> close();

  Future<List<McpTool>> listTools() async {
    final out = <McpTool>[];
    String? cursor;
    for (var page = 0; page < 20; page++) {
      final r = await request('tools/list', {'cursor': ?cursor});
      for (final t in (r['tools'] as List? ?? const [])) {
        if (t is Map) out.add(McpTool.fromJson(Map<String, dynamic>.from(t)));
      }
      cursor = r['nextCursor'] as String?;
      if (cursor == null || cursor.isEmpty) break;
    }
    return out;
  }

  Future<McpCallResult> callTool(String name, Map<String, dynamic> args, {Duration timeout = const Duration(minutes: 2)}) async {
    final r = await request('tools/call', {'name': name, 'arguments': args}, timeout);
    return McpCallResult(contentToText(r), r['isError'] == true);
  }
}

String contentToText(Map<String, dynamic> r) {
  final parts = <String>[];
  for (final c in (r['content'] as List? ?? const [])) {
    if (c is! Map) continue;
    switch (c['type']) {
      case 'text':
        parts.add((c['text'] ?? '').toString());
      case 'image':
      case 'audio':
        final len = ((c['data'] ?? '') as String).length * 3 ~/ 4;
        parts.add('[${c['type']}: ${c['mimeType'] ?? 'binary'}, ~${(len / 1024).toStringAsFixed(0)} KB]');
      case 'resource':
        final res = c['resource'];
        if (res is Map) parts.add((res['text'] ?? '[resource ${res['uri'] ?? ''}]').toString());
      case 'resource_link':
        parts.add('[${c['name'] ?? 'link'}](${c['uri'] ?? ''})');
      default:
        parts.add(jsonEncode(c));
    }
  }
  if (parts.isEmpty && r['structuredContent'] != null) parts.add(jsonEncode(r['structuredContent']));
  return parts.join('\n');
}

Map<String, dynamic> _rpcResult(Map<String, dynamic> msg) {
  final err = msg['error'];
  if (err is Map) throw McpException('MCP error ${err['code'] ?? ''}: ${err['message'] ?? 'unknown error'}');
  final r = msg['result'];
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

Map<String, dynamic> get _clientInit => {
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'Nur', 'version': '0.1.0'},
    };

/// Streamable HTTP transport: every message is a POST; responses are JSON or an SSE stream.
class StreamableHttpConnection extends McpConnection {
  StreamableHttpConnection(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  String? _session;
  String _protocol = kMcpProtocol;
  int _id = 0;
  bool _ready = false;

  Map<String, String> get _h => {
        ...headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        if (_ready) 'MCP-Protocol-Version': _protocol,
        'Mcp-Session-Id': ?_session,
      };

  @override
  Future<void> initialize() async {
    _session = null;
    _ready = false;
    final r = await _post({'jsonrpc': '2.0', 'id': ++_id, 'method': 'initialize', 'params': {'protocolVersion': kMcpProtocol, ..._clientInit}},
        const Duration(seconds: 20));
    _protocol = (r?['result']?['protocolVersion'] as String?) ?? kMcpProtocol;
    if (r != null) _rpcResult(r);
    _ready = true;
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'}, const Duration(seconds: 10));
  }

  @override
  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic>? params, Duration? timeout]) async {
    if (!_ready) await initialize();
    Map<String, dynamic> msg() => {'jsonrpc': '2.0', 'id': ++_id, 'method': method, 'params': ?params};
    try {
      final r = await _post(msg(), timeout ?? const Duration(seconds: 30));
      if (r == null) throw const McpException('The MCP server sent no response.');
      return _rpcResult(r);
    } on _SessionExpired {
      await initialize();
      final r = await _post(msg(), timeout ?? const Duration(seconds: 30));
      if (r == null) throw const McpException('The MCP server sent no response.');
      return _rpcResult(r);
    }
  }

  Future<Map<String, dynamic>?> _post(Map<String, dynamic> body, Duration timeout) async {
    final id = body['id'];
    final cancel = CancelToken();
    try {
      final res = await _dio
          .post<ResponseBody>(url,
              data: jsonEncode(body),
              cancelToken: cancel,
              options: Options(headers: _h, responseType: ResponseType.stream, validateStatus: (_) => true))
          .timeout(timeout);
      final status = res.statusCode ?? 0;
      final sid = res.headers.value('mcp-session-id');
      if (sid != null && sid.isNotEmpty) _session = sid;
      final stream = res.data?.stream;
      if (status == 404 && _session != null && body['method'] != 'initialize') {
        _session = null;
        _ready = false;
        throw const _SessionExpired();
      }
      if (status >= 400) {
        final text = stream == null ? '' : await _readAll(stream, 2000);
        throw McpException('HTTP $status${text.isEmpty ? '' : ': ${text.trim()}'}');
      }
      if (id == null || status == 202 || stream == null) {
        if (stream != null) unawaited(stream.drain<void>().catchError((_) {}));
        return null;
      }
      final ct = (res.headers.value('content-type') ?? '').toLowerCase();
      if (ct.contains('text/event-stream')) {
        await for (final e in parseSse(stream).timeout(timeout)) {
          if (e.data.isEmpty) continue;
          dynamic j;
          try {
            j = jsonDecode(e.data);
          } catch (_) {
            continue;
          }
          for (final m in (j is List ? j : [j])) {
            if (m is Map && m['id'] == id && (m.containsKey('result') || m.containsKey('error'))) {
              cancel.cancel();
              return Map<String, dynamic>.from(m);
            }
          }
        }
        throw const McpException('The MCP server closed the stream without an answer.');
      }
      final text = await _readAll(stream, 20 * 1024 * 1024);
      if (text.trim().isEmpty) return null;
      final j = jsonDecode(text);
      for (final m in (j is List ? j : [j])) {
        if (m is Map && m['id'] == id) return Map<String, dynamic>.from(m);
      }
      return null;
    } on TimeoutException {
      cancel.cancel();
      throw const McpException('The MCP server did not answer in time.');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return null;
      throw McpException(e.message ?? 'Network error: ${e.type.name}');
    }
  }

  @override
  Future<void> close() async {
    if (_session != null) {
      try {
        await _dio.delete<void>(url, options: Options(headers: _h, validateStatus: (_) => true)).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _dio.close(force: true);
  }
}

class _SessionExpired implements Exception {
  const _SessionExpired();
}

Future<String> _readAll(Stream<List<int>> s, int max) async {
  final b = BytesBuilder(copy: false);
  await for (final chunk in s) {
    b.add(chunk);
    if (b.length > max) break;
  }
  return utf8.decode(b.takeBytes(), allowMalformed: true);
}

/// Legacy HTTP+SSE: GET opens an event stream whose first `endpoint` event names the POST URL;
/// responses come back as `message` events on the stream.
class LegacySseConnection extends McpConnection {
  LegacySseConnection(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  StreamSubscription<SseEvent>? _sub;
  CancelToken? _cancel;
  Uri? _endpoint;
  int _id = 0;
  bool _ready = false;

  Future<void> _connect() async {
    await _teardown();
    _cancel = CancelToken();
    final endpoint = Completer<Uri>();
    final res = await _dio.get<ResponseBody>(url,
        cancelToken: _cancel,
        options: Options(
            headers: {...headers, 'Accept': 'text/event-stream'}, responseType: ResponseType.stream, validateStatus: (_) => true));
    if ((res.statusCode ?? 0) >= 400 || res.data == null) {
      throw McpException('HTTP ${res.statusCode}: could not open the SSE stream.');
    }
    _sub = parseSse(res.data!.stream).listen((e) {
      if (e.event == 'endpoint') {
        if (!endpoint.isCompleted) endpoint.complete(Uri.parse(url).resolve(e.data.trim()));
        return;
      }
      dynamic j;
      try {
        j = jsonDecode(e.data);
      } catch (_) {
        return;
      }
      for (final m in (j is List ? j : [j])) {
        if (m is! Map) continue;
        final id = m['id'];
        if (m.containsKey('method') && id != null) {
          // Server-to-client request (e.g. ping): answer with an empty result.
          unawaited(_send({'jsonrpc': '2.0', 'id': id, 'result': <String, dynamic>{}}).catchError((_) {}));
        } else if (id is int && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(Map<String, dynamic>.from(m));
        }
      }
    }, onError: (Object e) => _failAll('The MCP SSE stream failed: $e'), onDone: () => _failAll('The MCP server closed the SSE stream.'));
    _endpoint = await endpoint.future.timeout(const Duration(seconds: 15),
        onTimeout: () => throw const McpException('The server did not announce its message endpoint (is this an SSE MCP URL?).'));
  }

  void _failAll(String why) {
    _ready = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(McpException(why));
    }
    _pending.clear();
  }

  Future<void> _send(Map<String, dynamic> msg) async {
    final ep = _endpoint;
    if (ep == null) throw const McpException('Not connected.');
    final r = await _dio.postUri<void>(ep,
        data: jsonEncode(msg),
        options: Options(headers: {...headers, 'Content-Type': 'application/json'}, validateStatus: (_) => true));
    if ((r.statusCode ?? 0) >= 400) throw McpException('HTTP ${r.statusCode} from the MCP message endpoint.');
  }

  Future<Map<String, dynamic>> _rpc(String method, Map<String, dynamic>? params, Duration timeout) async {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    try {
      await _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
      return _rpcResult(await c.future.timeout(timeout));
    } on TimeoutException {
      throw const McpException('The MCP server did not answer in time.');
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<void> initialize() async {
    await _connect();
    await _rpc('initialize', {'protocolVersion': kMcpLegacyProtocol, ..._clientInit}, const Duration(seconds: 20));
    await _send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    _ready = true;
  }

  @override
  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic>? params, Duration? timeout]) async {
    if (!_ready) await initialize();
    return _rpc(method, params, timeout ?? const Duration(seconds: 30));
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    _cancel?.cancel();
    _cancel = null;
  }

  @override
  Future<void> close() async {
    _failAll('Connection closed.');
    await _teardown();
    _dio.close(force: true);
  }
}

/// Connects with the requested transport; 'auto' tries Streamable HTTP first, then legacy SSE.
Future<(McpConnection, String)> connectMcp(String url, Map<String, String> headers, String transport) async {
  if (transport == 'sse') {
    final c = LegacySseConnection(url, headers);
    try {
      await c.initialize();
    } catch (_) {
      await c.close();
      rethrow;
    }
    return (c, 'sse');
  }
  final h = StreamableHttpConnection(url, headers);
  try {
    await h.initialize();
    return (h, 'http');
  } catch (e) {
    await h.close();
    if (transport == 'http') rethrow;
    final s = LegacySseConnection(url, headers);
    try {
      await s.initialize();
      return (s, 'sse');
    } catch (_) {
      await s.close();
      throw McpException('Could not connect: $e');
    }
  }
}
