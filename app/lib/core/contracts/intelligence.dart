// Contracts between the chat engine (features/chat) and the code that builds the model's context and runs tools
// (features/context, memory, tools, mcp, skills).
import 'llm.dart';

/// One slice of the context window, shown in the context ring.
class ContextSlice {
  final String label; // "System prompt", "Memories", "Tools", "Skills", "Messages", "Images", "Summary"
  final int tokens;
  const ContextSlice(this.label, this.tokens);
}

class ContextBreakdown {
  final int contextWindow;
  final List<ContextSlice> slices;
  final bool exact; // true when counted by the backend tokenizer
  const ContextBreakdown({required this.contextWindow, required this.slices, this.exact = false});
  int get used => slices.fold(0, (a, s) => a + s.tokens);
  double get fraction => contextWindow <= 0 ? 0 : (used / contextWindow).clamp(0, 1).toDouble();
  static const empty = ContextBreakdown(contextWindow: 0, slices: []);
}

/// Result of building the request for one assistant turn.
class AssembledContext {
  final List<LlmMessage> messages;
  final List<LlmToolSpec> tools;
  final ContextBreakdown breakdown;
  const AssembledContext({required this.messages, required this.tools, required this.breakdown});
}

/// Builds what the model sees: system prompt + memories + skills + compaction summary + history.
/// Also decides when to auto-compact.
abstract class ContextAssembler {
  Future<AssembledContext> build({required String chatId, required LlmModel model});
  /// Called after each finished assistant turn (memory extraction, auto-compaction check). Must not block the UI.
  Future<void> afterTurn({required String chatId, required LlmModel model});
  Future<void> compact({required String chatId, required LlmModel model});
  Future<void> clearContext({required String chatId});
  Stream<ContextBreakdown> watchBreakdown(String chatId);
}

enum ToolRisk { safe, needsApproval, dangerous }

class ToolResult {
  final String content; // text given back to the model
  final bool isError;
  final Map<String, dynamic>? display; // optional rich data for the tool card UI
  const ToolResult(this.content, {this.isError = false, this.display});
}

/// Asks the user before a risky tool runs. Implemented by the UI layer.
typedef ToolApprover = Future<bool> Function(LlmToolCall call, ToolRisk risk);

abstract class ToolRuntime {
  /// Tools offered for this chat (NAS tools, web search, memory tools, MCP tools, skill loader).
  Future<List<LlmToolSpec>> toolsFor(String chatId);
  ToolRisk riskOf(LlmToolCall call);
  Future<ToolResult> execute(LlmToolCall call, {required String chatId, required ToolApprover approve});
}
