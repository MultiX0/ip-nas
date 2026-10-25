// Pure history logic: active branch path, context markers (summary / context_reset), tool-call pairing.
//
// Markers are messages with kind 'summary' or 'context_reset'. Their `toolResultJson` holds
// `{"anchor": "<message id>"}` = the last message they cover (for a reset: the last message before the reset).
// A marker applies when its anchor is on the current branch path, so it works whether or not the marker
// itself is on the path (and stops applying when the user edits an older message and branches away).
import 'dart:convert';

import '../../core/contracts/llm.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;

const kSummaryKind = 'summary';
const kResetKind = 'context_reset';

bool isMarker(Message m) => m.kind == kSummaryKind || m.kind == kResetKind;

Map<String, dynamic> markerMeta(Message m) {
  final raw = m.toolResultJson;
  if (raw == null || raw.isEmpty) return const {};
  try {
    final j = jsonDecode(raw);
    return j is Map<String, dynamic> ? j : const {};
  } catch (_) {
    return const {};
  }
}

/// Branch path from the root to [leafId] (oldest first). Falls back to creation order when the chat has no
/// parent links at all, or to the newest message when the leaf is unknown.
List<Message> activePath(List<Message> all, String? leafId) {
  if (all.isEmpty) return const [];
  final byId = {for (final m in all) m.id: m};
  final hasLinks = all.any((m) => m.parentId != null);
  if (!hasLinks) {
    final sorted = [...all]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted;
  }
  var leaf = leafId == null ? null : byId[leafId];
  if (leaf == null) {
    final sorted = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    leaf = sorted.first;
  }
  final path = <Message>[];
  final seen = <String>{};
  Message? cur = leaf;
  while (cur != null && seen.add(cur.id)) {
    path.add(cur);
    cur = cur.parentId == null ? null : byId[cur.parentId];
  }
  return path.reversed.toList();
}

/// What part of the path is in the model's context.
class ContextView {
  /// Path messages that are sent as history (markers removed), oldest first.
  final List<Message> messages;

  /// Active compaction summary (applies to everything up to its anchor), if any.
  final Message? summary;

  /// Ids of path messages that are no longer sent to the model (summarised or before a reset).
  final Set<String> excludedIds;

  /// Ids of path messages covered by the active summary.
  final Set<String> compactedIds;
  const ContextView(this.messages, this.summary, this.excludedIds, this.compactedIds);
}

ContextView resolveContext(List<Message> path, List<Message> allMessages) {
  final index = <String, int>{};
  for (var i = 0; i < path.length; i++) {
    index[path[i].id] = i;
  }
  Message? bestSummary;
  var summaryAt = -1;
  var resetAt = -1;
  for (final m in allMessages) {
    if (!isMarker(m)) continue;
    final anchor = (markerMeta(m)['anchor'] as String?) ?? m.parentId;
    final at = anchor == null ? -1 : (index[anchor] ?? -2);
    if (at == -2) continue; // anchor on another branch
    if (m.kind == kResetKind) {
      if (at > resetAt) resetAt = at;
    } else if (m.content.trim().isNotEmpty) {
      if (at > summaryAt || (at == summaryAt && bestSummary != null && m.createdAt.isAfter(bestSummary.createdAt))) {
        summaryAt = at;
        bestSummary = m;
      }
    }
  }
  // A reset after (or at) the summary anchor wins over the summary.
  if (resetAt >= summaryAt) {
    bestSummary = null;
    summaryAt = -1;
  }
  final start = (resetAt > summaryAt ? resetAt : summaryAt) + 1;
  final excluded = <String>{};
  final compacted = <String>{};
  for (var i = 0; i < start && i < path.length; i++) {
    if (isMarker(path[i])) continue;
    excluded.add(path[i].id);
    if (bestSummary != null && i <= summaryAt) compacted.add(path[i].id);
  }
  final msgs = <Message>[];
  for (var i = start; i < path.length; i++) {
    final m = path[i];
    if (isMarker(m)) continue;
    if (m.role == 'system') continue;
    if (m.role == 'assistant' && m.status == 'streaming' && m.content.isEmpty && (m.toolCallsJson ?? '').isEmpty) {
      continue; // placeholder of the reply being generated
    }
    if (m.role == 'assistant' && m.status == 'error' && m.content.trim().isEmpty && (m.toolCallsJson ?? '').isEmpty) {
      continue;
    }
    msgs.add(m);
  }
  return ContextView(msgs, bestSummary, excluded, compacted);
}

List<LlmToolCall> parseToolCalls(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final list = jsonDecode(json);
    if (list is! List) return const [];
    final out = <LlmToolCall>[];
    for (final e in list) {
      if (e is! Map) continue;
      var args = e['arguments'];
      if (args is! String) args = jsonEncode(args ?? const {});
      final fn = e['function'];
      out.add(LlmToolCall(
        id: (e['id'] ?? '').toString(),
        name: (e['name'] ?? (fn is Map ? fn['name'] : null) ?? '').toString(),
        argumentsJson: args.isEmpty ? '{}' : args,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Text the model sees for a tool result row.
String toolResultText(Message m) {
  if (m.content.isNotEmpty) return m.content;
  final raw = m.toolResultJson;
  if (raw == null || raw.isEmpty) return '';
  try {
    final j = jsonDecode(raw);
    if (j is Map && j['content'] != null) return j['content'].toString();
    return raw;
  } catch (_) {
    return raw;
  }
}

class ImageRef {
  final String path;
  final String mime;
  const ImageRef(this.path, this.mime);
}

List<ImageRef> imageRefs(Message m) {
  final raw = m.attachmentsJson;
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final a in list)
        if (a is Map && (a['type'] ?? 'image') == 'image' && a['path'] is String)
          ImageRef(a['path'] as String, (a['mime'] as String?) ?? 'image/jpeg'),
    ];
  } catch (_) {
    return const [];
  }
}

/// Makes the tool exchange valid for every provider: each assistant tool call gets exactly one result
/// (a placeholder when the call was interrupted) and tool results without their call are dropped.
List<LlmMessage> pairToolMessages(List<LlmMessage> input) {
  final out = <LlmMessage>[];
  var i = 0;
  while (i < input.length) {
    final m = input[i];
    if (m.role == LlmRole.tool) {
      i++; // orphan result
      continue;
    }
    out.add(m);
    i++;
    if (m.role != LlmRole.assistant || m.toolCalls.isEmpty) continue;
    final results = <String, LlmMessage>{};
    while (i < input.length && input[i].role == LlmRole.tool) {
      final t = input[i];
      if (t.toolCallId != null && m.toolCalls.any((c) => c.id == t.toolCallId)) results[t.toolCallId!] = t;
      i++;
    }
    for (final c in m.toolCalls) {
      out.add(results[c.id] ??
          LlmMessage(LlmRole.tool, 'No result: this tool call was interrupted before it finished.',
              toolCallId: c.id, toolName: c.name));
    }
  }
  return out;
}

/// Indexes in [msgs] where a user turn starts.
List<int> turnStarts(List<Message> msgs) => [
      for (var i = 0; i < msgs.length; i++)
        if (msgs[i].role == 'user') i,
    ];
