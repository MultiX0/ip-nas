// ToolRuntime implementation: built-in tools + MCP tools, approvals, timeouts, result truncation.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/intelligence.dart';
import '../../core/contracts/llm.dart';
import '../../core/providers.dart';
import '../context/intel_settings.dart';
import '../mcp/mcp_client.dart';
import '../mcp/mcp_manager.dart';
import '../skills/skills_repo.dart';
import 'builtin_tools.dart';
import 'nas_http.dart';
import 'text_utils.dart';
import 'tool_call_repair.dart';

/// Names of tools turned off in Settings > Tools. Unset means only the opt-in tools are off.
Future<Set<String>> disabledBuiltinTools(Ref ref) async {
  final db = ref.read(dbProvider);
  final raw = await db.getSetting(IntelKeys.toolsDisabled);
  if (raw == null) return {for (final t in builtinTools) if (!t.defaultEnabled) t.name};
  return db.stringSetSetting(IntelKeys.toolsDisabled);
}

class NurToolRuntime implements ToolRuntime {
  NurToolRuntime(this._ref);
  final Ref _ref;
  final _byName = {for (final t in builtinTools) t.name: t};
  Map<String, McpToolBinding> _mcp = {};

  Future<String> _execMode() async => (await _ref.read(dbProvider).getSetting(IntelKeys.execMode)) == 'admin' ? 'admin' : 'safe';

  Future<Map<String, dynamic>> _chatSettings(String chatId) async {
    if (chatId.isEmpty) return const {};
    final db = _ref.read(dbProvider);
    final chat = await (db.select(db.chats)..where((c) => c.id.equals(chatId))).getSingleOrNull();
    if (chat == null) return const {};
    try {
      final j = jsonDecode(chat.settingsJson);
      return j is Map<String, dynamic> ? j : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<LlmToolSpec>> toolsFor(String chatId) async {
    final cs = await _chatSettings(chatId);
    if (cs['tools_enabled'] == false || cs['tools'] == false) return const [];
    final chatOff = {for (final e in (cs['disabled_tools'] as List? ?? const [])) e.toString()};
    final off = await disabledBuiltinTools(_ref);
    final db = _ref.read(dbProvider);
    final memoryOn = await db.boolSetting(IntelKeys.memoryEnabled);
    final hasSkills = (await _ref.read(skillsRepoProvider).enabledSkills()).isNotEmpty;
    final specs = <LlmToolSpec>[];
    for (final t in builtinTools) {
      if (off.contains(t.name) || chatOff.contains(t.name)) continue;
      if (t.group == 'memory' && !memoryOn) continue;
      if (t.name == 'load_skill' && !hasSkills) continue;
      specs.add(LlmToolSpec(name: t.name, description: t.description, parameters: t.parameters));
    }
    try {
      final bindings = await _ref.read(mcpManagerProvider).bindings();
      _mcp = {for (final b in bindings) b.specName: b};
      for (final b in bindings) {
        if (chatOff.contains(b.specName)) continue;
        specs.add(b.spec);
      }
    } catch (_) {
      // MCP cache unreadable: built-in tools still work.
    }
    return specs;
  }

  @override
  ToolRisk riskOf(LlmToolCall call) {
    final t = _byName[call.name];
    if (t == null) return ToolRisk.needsApproval; // MCP and unknown tools
    try {
      final a = _args(call.argumentsJson);
      // The exec mode is kept current by the settings listener in nurToolRuntimeProvider.
      return t.risk(a, _lastExecMode);
    } catch (_) {
      return ToolRisk.needsApproval;
    }
  }

  String _lastExecMode = 'safe';

  static Map<String, dynamic> _args(String json) {
    final t = json.trim();
    if (t.isEmpty) return {};
    // Small models often send almost-JSON (trailing commas, single quotes, code fences, double-encoded strings).
    final v = repairArguments(t);
    if (v != null) return v;
    throw const FormatException('Arguments must be a JSON object');
  }

  @override
  Future<ToolResult> execute(LlmToolCall call, {required String chatId, required ToolApprover approve}) async {
    final db = _ref.read(dbProvider);
    final max = (await db.intSetting(IntelKeys.toolResultMax, 6000)).clamp(1000, 100000);
    _lastExecMode = await _execMode();
    Map<String, dynamic> args;
    try {
      args = _args(call.argumentsJson);
    } catch (_) {
      return ToolResult('Invalid arguments: expected a JSON object, got: ${truncateMiddle(call.argumentsJson, 300)}', isError: true);
    }
    final builtin = _byName[call.name];
    McpToolBinding? mcp = _mcp[call.name];
    if (builtin == null && mcp == null && call.name.startsWith('mcp__')) {
      final bindings = await _ref.read(mcpManagerProvider).bindings();
      _mcp = {for (final b in bindings) b.specName: b};
      mcp = _mcp[call.name];
    }
    if (builtin == null && mcp == null) {
      return ToolResult('Unknown tool "${call.name}".', isError: true);
    }
    if (builtin != null && (await disabledBuiltinTools(_ref)).contains(builtin.name)) {
      return ToolResult('The tool "${call.name}" is turned off in Settings > Tools.', isError: true);
    }
    final risk = builtin != null ? builtin.risk(args, _lastExecMode) : ToolRisk.needsApproval;
    if (risk != ToolRisk.safe) {
      bool ok;
      try {
        ok = await approve(call, risk);
      } catch (_) {
        ok = false;
      }
      if (!ok) return const ToolResult('The user declined to run this tool. Do not retry it; ask how to proceed.', isError: true);
    }
    try {
      ToolResult r;
      if (builtin != null) {
        r = await builtin.run(args, ToolCtx(_ref, chatId, _lastExecMode)).timeout(builtin.timeout);
      } else {
        final res = await _ref.read(mcpManagerProvider).call(mcp!.serverId, mcp.tool.name, args).timeout(const Duration(minutes: 3));
        r = ToolResult(res.text.isEmpty ? '(empty result)' : res.text, isError: res.isError);
      }
      final content = await formatAndTruncate(r.content, max);
      return ToolResult(content, isError: r.isError, display: r.display);
    } on TimeoutException {
      return ToolResult('The tool "${call.name}" timed out.', isError: true);
    } on NasNotConnected catch (e) {
      return ToolResult(e.toString(), isError: true);
    } on DioException catch (e) {
      return ToolResult(nasErrorText(e), isError: true);
    } on McpException catch (e) {
      return ToolResult('MCP server error: ${e.message}', isError: true);
    } catch (e) {
      final msg = e is StateError ? e.message : e.toString();
      return ToolResult('Tool failed: $msg', isError: true);
    }
  }
}

final nurToolRuntimeProvider = Provider<NurToolRuntime>((ref) {
  final rt = NurToolRuntime(ref);
  final sub = ref.watch(dbProvider).watchSetting(IntelKeys.execMode).listen((v) => rt._lastExecMode = v == 'admin' ? 'admin' : 'safe');
  ref.onDispose(sub.cancel);
  return rt;
});
