// MCP server registry: connections, tool cache, per-tool switches, secure header storage.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/contracts/llm.dart';
import '../../core/providers.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import 'mcp_client.dart';

/// One MCP tool as exposed to the model (`mcp__<server>__<tool>`).
class McpToolBinding {
  final String specName;
  final String serverId;
  final String serverName;
  final McpTool tool;
  const McpToolBinding(this.specName, this.serverId, this.serverName, this.tool);
  LlmToolSpec get spec => LlmToolSpec(
        name: specName,
        description: '[MCP · $serverName] ${tool.description}'.trim(),
        parameters: _schema(tool.inputSchema),
      );
  static Map<String, dynamic> _schema(Map<String, dynamic> s) {
    final out = Map<String, dynamic>.from(s);
    out['type'] = 'object';
    out.putIfAbsent('properties', () => <String, dynamic>{});
    out.remove(r'$schema');
    return out;
  }
}

String _slug(String s, int max) {
  var v = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
  v = v.replaceAll(RegExp(r'^_|_$'), '');
  if (v.isEmpty) v = 'x';
  return v.length > max ? v.substring(0, max) : v;
}

String mcpSpecName(String serverName, String toolName) {
  final server = _slug(serverName, 20);
  final tool = toolName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  final name = 'mcp__${server}__$tool';
  if (name.length <= 64) return name;
  final h = toolName.hashCode.toUnsigned(20).toRadixString(36);
  return '${name.substring(0, 63 - h.length)}_$h';
}

class McpManager {
  McpManager(this._db, this._secure);
  final AppDb _db;
  final FlutterSecureStorage _secure;
  final _conns = <String, McpConnection>{};
  final _connecting = <String, Future<McpConnection>>{};
  static const _uuid = Uuid();

  Stream<List<McpServer>> watchServers() =>
      (_db.select(_db.mcpServers)..orderBy([(s) => OrderingTerm.asc(s.createdAt)])).watch();

  Future<Map<String, String>> headersFor(String id) async {
    final raw = await _secure.read(key: 'mcp_hdr_$id');
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from((jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v.toString())));
    } catch (_) {
      return {};
    }
  }

  static List<McpTool> toolsOf(McpServer s) {
    try {
      return [for (final t in jsonDecode(s.toolsCacheJson) as List) McpTool.fromJson(Map<String, dynamic>.from(t as Map))];
    } catch (_) {
      return const [];
    }
  }

  static Set<String> disabledOf(McpServer s) {
    try {
      return (jsonDecode(s.disabledToolsJson) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Connects and lists tools without saving (the "Test" button). Returns detected transport and tools.
  Future<(String, List<McpTool>)> test(String url, Map<String, String> headers, String transport) async {
    final (c, t) = await connectMcp(url, headers, transport);
    try {
      return (t, await c.listTools());
    } finally {
      await c.close();
    }
  }

  Future<String> add({required String name, required String url, required String transport, Map<String, String> headers = const {}}) async {
    final (detected, tools) = await test(url, headers, transport);
    final id = _uuid.v4();
    if (headers.isNotEmpty) await _secure.write(key: 'mcp_hdr_$id', value: jsonEncode(headers));
    await _db.into(_db.mcpServers).insert(McpServersCompanion.insert(
          id: id,
          name: name.trim().isEmpty ? Uri.parse(url).host : name.trim(),
          url: url.trim(),
          transport: Value(detected),
          toolsCacheJson: Value(jsonEncode([for (final t in tools) t.toJson()])),
          createdAt: Value(DateTime.now()),
        ));
    return id;
  }

  Future<McpConnection> _conn(McpServer s) async {
    final c = _conns[s.id];
    if (c != null) return c;
    return _connecting[s.id] ??= () async {
      try {
        final (conn, _) = await connectMcp(s.url, await headersFor(s.id), s.transport);
        _conns[s.id] = conn;
        return conn;
      } finally {
        _connecting.remove(s.id);
      }
    }();
  }

  Future<void> _drop(String id) async {
    final c = _conns.remove(id);
    if (c != null) await c.close();
  }

  Future<List<McpTool>> refresh(String id) async {
    final s = await (_db.select(_db.mcpServers)..where((t) => t.id.equals(id))).getSingle();
    await _drop(id);
    final tools = await (await _conn(s)).listTools();
    await (_db.update(_db.mcpServers)..where((t) => t.id.equals(id)))
        .write(McpServersCompanion(toolsCacheJson: Value(jsonEncode([for (final t in tools) t.toJson()]))));
    return tools;
  }

  Future<void> setEnabled(String id, bool v) async {
    if (!v) await _drop(id);
    await (_db.update(_db.mcpServers)..where((t) => t.id.equals(id))).write(McpServersCompanion(enabled: Value(v)));
  }

  Future<void> setToolEnabled(McpServer s, String tool, bool v) async {
    final d = disabledOf(s);
    v ? d.remove(tool) : d.add(tool);
    await (_db.update(_db.mcpServers)..where((t) => t.id.equals(s.id)))
        .write(McpServersCompanion(disabledToolsJson: Value(jsonEncode(d.toList()..sort()))));
  }

  Future<void> remove(String id) async {
    await _drop(id);
    await _secure.delete(key: 'mcp_hdr_$id');
    await (_db.delete(_db.mcpServers)..where((t) => t.id.equals(id))).go();
  }

  /// Enabled tools of enabled servers, from the cache (no network).
  Future<List<McpToolBinding>> bindings() async {
    final servers = await (_db.select(_db.mcpServers)..where((s) => s.enabled.equals(true))).get();
    final out = <McpToolBinding>[];
    final used = <String>{};
    for (final s in servers) {
      final off = disabledOf(s);
      for (final t in toolsOf(s)) {
        if (off.contains(t.name)) continue;
        var n = mcpSpecName(s.name, t.name);
        if (!used.add(n)) {
          n = mcpSpecName('${s.name}_${s.id.substring(0, 4)}', t.name);
          used.add(n);
        }
        out.add(McpToolBinding(n, s.id, s.name, t));
      }
    }
    return out;
  }

  Future<McpCallResult> call(String serverId, String tool, Map<String, dynamic> args) async {
    final s = await (_db.select(_db.mcpServers)..where((t) => t.id.equals(serverId))).getSingle();
    try {
      return await (await _conn(s)).callTool(tool, args);
    } on McpException {
      // One reconnect attempt (server restarted, session dropped, SSE stream closed).
      await _drop(serverId);
      return (await _conn(s)).callTool(tool, args);
    }
  }

  Future<void> dispose() async {
    final all = _conns.values.toList();
    _conns.clear();
    for (final c in all) {
      unawaited(c.close().catchError((_) {}));
    }
  }
}

final mcpManagerProvider = Provider<McpManager>((ref) {
  final m = McpManager(ref.watch(dbProvider), ref.watch(secureStoreProvider));
  ref.onDispose(m.dispose);
  return m;
});
