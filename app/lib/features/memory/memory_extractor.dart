// Background extraction of durable user facts after each turn (Mem0-style add / update / delete operations,
// decided by the model against the related memories that already exist, then guarded locally).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/llm.dart';
import '../context/llm_access.dart';
import 'memory_repo.dart';
import 'memory_text.dart';

const _system = '''You maintain the long-term memory of a personal AI assistant called Nur.
From the latest exchange, extract only DURABLE facts about the USER that will still be useful in future conversations:
identity (name, location, languages, job), preferences (style, tools, formats, likes/dislikes), family/pets,
their NAS / home-lab / devices setup, ongoing projects and goals, recurring routines.

Do NOT store: one-off requests or questions, facts about the assistant, general knowledge, temporary states,
anything the assistant said that the user did not confirm, passwords / API keys / tokens / secrets,
health/financial/other sensitive details unless the user explicitly asked to remember them.

Rules:
- Each memory is one short, self-contained sentence about the user, written in the language the user wrote in
  (e.g. "Prefers answers in Modern Standard Arabic." / "يعمل مهندس شبكات في الرياض.").
- Compare with EXISTING memories: if a new fact refines or corrects one, use "update" with its id;
  if it is already known, output nothing for it.
- If the user explicitly asks to forget something, or states that a stored fact is no longer true, use "delete" with its id.
- If the user explicitly says "remember ...", always store it.
- Usually there is nothing worth storing: then return {"operations": []}.

Answer with JSON only, no prose:
{"operations":[{"op":"add","content":"...","category":"profile|preference|nas|project|general"},
{"op":"update","id":"<existing id>","content":"..."},{"op":"delete","id":"<existing id>"}]}''';

class MemoryExtractor {
  MemoryExtractor(this._repo, this._llm);
  final MemoryRepo _repo;
  final IntelLlm _llm;

  /// Runs extraction for one exchange. Returns the number of changes applied.
  Future<int> extract({
    required LlmModel model,
    required String userText,
    required String assistantText,
    String? chatId,
  }) async {
    final user = userText.trim();
    if (user.length < 4) return 0;
    // Small local models: one extraction costs the Pi 30-60 s and blocks the single llama.cpp slot (the next reply
    // waits and loses its prompt cache), so only run it when the message talks about the user.
    if (_llm.isSmallModel(model) && !mentionsSelf(user)) return 0;
    final existing = await _repo.related('$user\n$assistantText', limit: 12);
    final existingJson = jsonEncode([
      for (final m in existing) {'id': m.id, 'content': m.content, 'category': m.category}
    ]);
    String clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}...';
    final prompt = 'EXISTING memories (JSON):\n$existingJson\n\n'
        'LATEST EXCHANGE\nUser: ${clip(user, 4000)}\nAssistant: ${clip(assistantText.trim(), 1500)}\n\n'
        'Return the JSON operations now.';
    final out = await _llm.complete(model, [LlmMessage(LlmRole.system, _system), LlmMessage(LlmRole.user, prompt)],
        temperature: 0, maxTokens: 700, timeout: const Duration(minutes: 3));
    final ops = parseOperations(out);
    final known = {for (final m in existing) m.id: m};
    var applied = 0;
    for (final op in ops.take(8)) {
      final kind = (op['op'] ?? '').toString().toLowerCase();
      final id = op['id']?.toString();
      final content = (op['content'] ?? '').toString().trim();
      if (_looksSecret(content)) continue;
      switch (kind) {
        case 'add':
          if (content.isEmpty || content.length > 500) continue;
          final (_, what) = await _repo.remember(content,
              category: (op['category'] ?? 'general').toString(), source: 'auto');
          if (what != 'duplicate') applied++;
        case 'update':
          if (id == null || !known.containsKey(id) || content.isEmpty || content.length > 500) continue;
          if (textSimilarity(content, known[id]!.content) >= 0.98) continue;
          await _repo.update(id, content: content, category: op['category']?.toString());
          applied++;
        case 'delete':
          if (id == null || !known.containsKey(id)) continue;
          if (known[id]!.pinned) continue; // pinned memories are only removed by the user
          await _repo.delete(id);
          applied++;
      }
    }
    return applied;
  }

  static bool _looksSecret(String s) =>
      RegExp(r'(sk-[A-Za-z0-9]{12,}|ghp_[A-Za-z0-9]{12,}|AKIA[0-9A-Z]{12,}|password\s*[:=]|كلمة\s*(السر|المرور)\s*[:=])',
              caseSensitive: false)
          .hasMatch(s);
}

/// Cheap check that a message says something about the user (English + Arabic first-person cues).
bool mentionsSelf(String text) =>
    RegExp(r"(?<![a-z])(i|i'm|im|i've|my|mine|me|remember|forget|call me)(?![a-z])", caseSensitive: false).hasMatch(text) ||
    RegExp(r'(أنا|انا|اسمي|عندي|لدي|أحب|احب|أفضل|افضل|أعمل|اعمل|أسكن|اسكن|تذكر|تذكّر|انس|بيتي|جهازي|عملي|زوجتي|زوجي|ابني|بنتي|عائلتي)').hasMatch(text);

/// Tolerant parser: accepts code fences, a bare list, or {"operations": [...]} / {"memories": [...]}.
List<Map<String, dynamic>> parseOperations(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'^```(?:json)?', multiLine: true), '').replaceAll('```', '').trim();
  dynamic j;
  final listFirst = s.contains('[') && (!s.contains('{') || s.indexOf('[') < s.indexOf('{'));
  final slices = listFirst ? [_slice(s, '[', ']'), _slice(s, '{', '}')] : [_slice(s, '{', '}'), _slice(s, '[', ']')];
  for (final candidate in [s, ...slices]) {
    if (candidate == null) continue;
    try {
      j = jsonDecode(candidate);
      break;
    } catch (_) {}
  }
  List? list;
  if (j is List) list = j;
  if (j is Map) list = (j['operations'] ?? j['memories'] ?? j['facts']) as List?;
  if (list == null) return const [];
  return [
    for (final e in list)
      if (e is Map) {...e.map((k, v) => MapEntry(k.toString(), v)), if (!e.containsKey('op')) 'op': 'add'}
      else if (e is String) {'op': 'add', 'content': e, 'category': 'general'}
  ];
}

String? _slice(String s, String open, String close) {
  final a = s.indexOf(open), b = s.lastIndexOf(close);
  return a >= 0 && b > a ? s.substring(a, b + 1) : null;
}

final memoryExtractorProvider =
    Provider<MemoryExtractor>((ref) => MemoryExtractor(ref.watch(memoryRepoProvider), ref.watch(intelLlmProvider)));
