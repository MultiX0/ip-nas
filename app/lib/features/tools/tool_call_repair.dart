// Makes tool calls from small local models usable. Repairs almost-JSON arguments (code fences, trailing commas,
// single quotes, bare keys, missing braces, double-encoded strings, Python keyword arguments), finds tool calls a
// model wrote as plain text (Hermes/Qwen `<tool_call>{...}`, Qwen3-Coder `<function=name><parameter=x>..`, LFM
// `<|tool_call_start|>[f(a="b")]`, Gemma ```tool_code f(a=1)```, or a bare `{"name": .., "arguments": ..}`),
// and gives a stable key for "same tool, same arguments" so the engine can stop repeated calls.
// Pure Dart, no Flutter imports.
import 'dart:convert';

/// A tool call recovered from text.
class TextToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  const TextToolCall(this.name, this.arguments);
  String get argumentsJson => jsonEncode(arguments);
}

/// Result of [extractTextToolCalls]: the calls and the visible text that is left after removing them.
class TextToolCalls {
  final List<TextToolCall> calls;
  final String remainingText;
  const TextToolCalls(this.calls, this.remainingText);
  bool get isEmpty => calls.isEmpty;
}

/// Parses tool-call arguments; returns null when nothing usable can be recovered.
Map<String, dynamic>? repairArguments(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return <String, dynamic>{};
  s = s.replaceFirst(RegExp(r'^```[a-zA-Z_]*\s*'), '').replaceFirst(RegExp(r'\s*```$'), '').trim();
  Object? tryDecode(String t) {
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? asMap(Object? v, [int depth = 0]) {
    if (v is Map) return Map<String, dynamic>.from(v);
    // Double-encoded: "{\"a\": 1}"
    if (v is String && depth < 2) return asMap(tryDecode(v.trim()), depth + 1);
    return null;
  }

  final direct = asMap(tryDecode(s));
  if (direct != null) return direct;
  var t = s.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
  final noTrailing = asMap(tryDecode(t));
  if (noTrailing != null) return noTrailing;
  // Single-quoted strings and bare keys.
  t = t.replaceAllMapped(RegExp(r"'([^'\\]*)'"), (m) => jsonEncode(m[1]));
  t = t.replaceAllMapped(RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'), (m) => '${m[1]}"${m[2]}":');
  t = t.replaceAllMapped(RegExp(r':\s*(True|False|None)\b'), (m) => ': ${m[1] == 'True' ? 'true' : m[1] == 'False' ? 'false' : 'null'}');
  final open = '{'.allMatches(t).length - '}'.allMatches(t).length;
  if (open > 0) t += '}' * open;
  final fixed = asMap(tryDecode(t));
  if (fixed != null) return fixed;
  // Python keyword arguments: name="x", tail=50
  final kw = pythonKwargs(s);
  if (kw.isNotEmpty) return kw;
  return null;
}

/// Parses Python keyword arguments such as `a="x", b=2, c=True`.
Map<String, dynamic> pythonKwargs(String s) {
  final out = <String, dynamic>{};
  final re = RegExp(r'''(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?|True|False|true|false|None|null)''');
  for (final m in re.allMatches(s)) {
    final v = m[2]!;
    Object? val;
    if (v.startsWith('"') || v.startsWith("'")) {
      val = v.substring(1, v.length - 1).replaceAll(r'\"', '"').replaceAll(r"\'", "'");
    } else if (v == 'True' || v == 'true') {
      val = true;
    } else if (v == 'False' || v == 'false') {
      val = false;
    } else if (v == 'None' || v == 'null') {
      val = null;
    } else {
      val = num.tryParse(v);
    }
    out[m[1]!] = val;
  }
  return out;
}

/// Canonical JSON text of repaired arguments ('{}' when empty), or [raw] when it cannot be repaired.
String normalizeArgumentsJson(String raw) {
  final m = repairArguments(raw);
  return m == null ? raw : jsonEncode(m);
}

/// Stable identity of a call: same tool + same arguments (key order and whitespace ignored).
String toolCallKey(String name, String argumentsJson) {
  final m = repairArguments(argumentsJson);
  if (m == null) return '$name|${argumentsJson.trim()}';
  Object? canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: canon(v[k])};
    }
    if (v is List) return v.map(canon).toList();
    if (v is String) return v.trim().toLowerCase();
    return v;
  }

  return '$name|${jsonEncode(canon(m))}';
}

Map<String, dynamic> _xmlParams(String body) => {
      for (final p in RegExp(r'<parameter=([\w.\-]+)>\s*([\s\S]*?)\s*</parameter>').allMatches(body)) p[1]!: _scalar(p[2]!),
    };

Object? _scalar(String v) {
  final t = v.trim();
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t)) return num.parse(t);
  if (t == 'true' || t == 'false') return t == 'true';
  if ((t.startsWith('{') && t.endsWith('}')) || (t.startsWith('[') && t.endsWith(']'))) {
    try {
      return jsonDecode(t);
    } catch (_) {}
  }
  return t;
}

TextToolCall? _fromJsonObject(Object? j, Set<String> names) {
  if (j is! Map) return null;
  var name = j['name'] ?? j['tool'] ?? j['function'];
  if (name is Map) name = name['name'];
  if (name is! String || !names.contains(name)) return null;
  final a = j['arguments'] ?? j['parameters'] ?? j['args'] ?? const <String, dynamic>{};
  final args = a is Map ? Map<String, dynamic>.from(a) : (a is String ? repairArguments(a) ?? <String, dynamic>{} : <String, dynamic>{});
  return TextToolCall(name, args);
}

/// Finds tool calls written as text. Only tools in [toolNames] are accepted.
/// Tagged formats are always accepted; bare JSON or code blocks only when they are (nearly) the whole reply,
/// so a model that merely *explains* a JSON example is not misread as calling a tool.
TextToolCalls extractTextToolCalls(String text, Set<String> toolNames) {
  if (text.trim().isEmpty || toolNames.isEmpty) return TextToolCalls(const [], text);
  final calls = <TextToolCall>[];
  var rest = text;

  // <tool_call> ... </tool_call> (Hermes / Qwen / Granite JSON, or Qwen3-Coder XML inside).
  final tc = RegExp(r'<tool_call>\s*([\s\S]*?)\s*(?:</tool_call>|$)');
  for (final m in tc.allMatches(text)) {
    final body = m[1]!;
    final f = RegExp(r'<function=([\w.\-]+)>([\s\S]*?)(?:</function>|$)').firstMatch(body);
    if (f != null) {
      if (toolNames.contains(f[1])) calls.add(TextToolCall(f[1]!, _xmlParams(f[2]!)));
    } else {
      final c = _fromJsonObject(repairArguments(body), toolNames);
      if (c != null) calls.add(c);
    }
  }
  if (calls.isNotEmpty) rest = text.replaceAll(tc, '');

  // <function=name> ... </function> without the wrapper.
  if (calls.isEmpty) {
    final fn = RegExp(r'<function=([\w.\-]+)>([\s\S]*?)(?:</function>|$)');
    for (final m in fn.allMatches(text)) {
      if (!toolNames.contains(m[1])) continue;
      var args = _xmlParams(m[2]!);
      if (args.isEmpty) args = repairArguments(m[2]!) ?? <String, dynamic>{};
      calls.add(TextToolCall(m[1]!, args));
    }
    if (calls.isNotEmpty) rest = text.replaceAll(fn, '');
  }

  // LFM2: <|tool_call_start|>[name(a="b")]<|tool_call_end|>
  if (calls.isEmpty) {
    final lfm = RegExp(r'<\|tool_call_start\|>([\s\S]*?)(?:<\|tool_call_end\|>|$)');
    for (final m in lfm.allMatches(text)) {
      final body = m[1]!.trim();
      final asJson = repairArguments(body.startsWith('[') ? body.substring(1, body.length - (body.endsWith(']') ? 1 : 0)) : body);
      final j = _fromJsonObject(asJson, toolNames);
      if (j != null) {
        calls.add(j);
        continue;
      }
      for (final c in RegExp(r'([\w.\-]+)\(([\s\S]*?)\)').allMatches(body)) {
        if (toolNames.contains(c[1])) calls.add(TextToolCall(c[1]!, pythonKwargs(c[2]!)));
      }
    }
    if (calls.isNotEmpty) rest = text.replaceAll(lfm, '');
  }

  // A fenced block (```json / ```tool_code / ```python) holding a call, when it is most of the reply.
  if (calls.isEmpty) {
    final fence = RegExp(r'```(?:json|tool_code|tool_call|python)?\s*([\s\S]*?)```');
    final ms = fence.allMatches(text).toList();
    final outside = text.replaceAll(fence, '').trim();
    if (ms.isNotEmpty && outside.length < 160) {
      for (final m in ms) {
        final j = _fromJsonObject(repairArguments(m[1]!), toolNames);
        if (j != null) {
          calls.add(j);
          continue;
        }
        for (final c in RegExp(r'([\w.\-]+)\(([\s\S]*?)\)').allMatches(m[1]!)) {
          if (toolNames.contains(c[1])) calls.add(TextToolCall(c[1]!, pythonKwargs(c[2]!)));
        }
      }
      if (calls.isNotEmpty) rest = outside;
    }
  }

  // The whole reply is one JSON object {"name": .., "arguments": ..}.
  if (calls.isEmpty) {
    final t = text.trim();
    if (t.startsWith('{') && t.endsWith('}')) {
      final j = _fromJsonObject(repairArguments(t), toolNames);
      if (j != null) {
        calls.add(j);
        rest = '';
      }
    }
  }
  if (calls.isEmpty) return TextToolCalls(const [], text);
  return TextToolCalls(calls, rest.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim());
}
