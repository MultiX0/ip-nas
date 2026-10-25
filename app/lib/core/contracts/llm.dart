// Shared LLM contract, implemented by the adapters in features/providers.
// Every adapter turns a provider's wire format into this single event stream.
import 'dart:typed_data';

enum LlmRole { system, user, assistant, tool }

/// How hard the model should think (same scale as the llama.cpp web UI / `reasoning_effort`).
/// `off` disables reasoning when the model allows it; `extra` = llama.cpp `xhigh`.
enum ReasoningLevel { off, minimal, low, medium, high, extra }

/// Thinking-token budget per level. llama.cpp enforces it live (`reasoning_control` + `reasoning_end`), so the
/// level works even on models whose template ignores `reasoning_effort`. null = unlimited.
const reasoningBudgets = <ReasoningLevel, int?>{
  ReasoningLevel.minimal: 256,
  ReasoningLevel.low: 1024,
  ReasoningLevel.medium: 4096,
  ReasoningLevel.high: 8192,
  ReasoningLevel.extra: null,
};

/// Name used by OpenAI-style APIs: minimal | low | medium | high | xhigh.
String effortName(ReasoningLevel l, {bool hasXHigh = false, bool hasMinimal = true}) => switch (l) {
      ReasoningLevel.off || ReasoningLevel.minimal => hasMinimal ? 'minimal' : 'low',
      ReasoningLevel.low => 'low',
      ReasoningLevel.medium => 'medium',
      ReasoningLevel.high => 'high',
      ReasoningLevel.extra => hasXHigh ? 'xhigh' : 'high',
    };

class LlmImage {
  final Uint8List bytes;
  final String mimeType; // image/png, image/jpeg, image/webp
  const LlmImage(this.bytes, this.mimeType);
}

class LlmToolCall {
  final String id;
  final String name;
  final String argumentsJson; // complete JSON object text
  const LlmToolCall({required this.id, required this.name, required this.argumentsJson});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'arguments': argumentsJson};
  factory LlmToolCall.fromJson(Map<String, dynamic> j) =>
      LlmToolCall(id: j['id'] as String, name: j['name'] as String, argumentsJson: j['arguments'] as String? ?? '{}');
}

class LlmMessage {
  final LlmRole role;
  final String content;
  final List<LlmImage> images;
  final List<LlmToolCall> toolCalls; // assistant messages that called tools
  final String? toolCallId; // tool results
  final String? toolName;
  final bool isError; // tool results: the tool failed
  final String? reasoning; // previous reasoning, only replayed if the provider wants it
  const LlmMessage(this.role, this.content,
      {this.images = const [], this.toolCalls = const [], this.toolCallId, this.toolName, this.isError = false, this.reasoning});
}

/// JSON-schema tool definition sent to the model (OpenAI "function" shape).
class LlmToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  const LlmToolSpec({required this.name, required this.description, required this.parameters});
}

class LlmRequest {
  final String modelId;
  final List<LlmMessage> messages;
  final List<LlmToolSpec> tools;
  final ReasoningLevel reasoning;
  final double? temperature;
  final int? maxTokens;
  final bool stream;

  /// 'none': answer without calling a tool. [tools] are still sent where the backend allows it, so the prompt starts
  /// the same as in the other rounds and llama.cpp reuses its cache (the tool list comes first in the prompt).
  final String? toolChoice;
  const LlmRequest({
    required this.modelId,
    required this.messages,
    this.tools = const [],
    this.reasoning = ReasoningLevel.medium,
    this.temperature,
    this.maxTokens,
    this.stream = true,
    this.toolChoice,
  });
}

/// Streaming events. Adapters must emit TextDelta/ReasoningDelta as soon as bytes arrive.
sealed class LlmEvent {
  const LlmEvent();
}

class TextDelta extends LlmEvent {
  final String text;
  const TextDelta(this.text);
}

class ReasoningDelta extends LlmEvent {
  final String text;
  const ReasoningDelta(this.text);
}

/// Emitted once per tool call when its arguments are complete.
class ToolCallEvent extends LlmEvent {
  final LlmToolCall call;
  const ToolCallEvent(this.call);
}

class UsageEvent extends LlmEvent {
  final int promptTokens;
  final int completionTokens;
  final double? tokensPerSecond;
  const UsageEvent({required this.promptTokens, required this.completionTokens, this.tokensPerSecond});
}

class DoneEvent extends LlmEvent {
  final String finishReason; // stop, length, tool_calls, cancelled
  const DoneEvent(this.finishReason);
}

class ErrorEvent extends LlmEvent {
  final String message;
  final int? statusCode;
  const ErrorEvent(this.message, {this.statusCode});
}

/// What a model can do. Filled from provider metadata (llama.cpp /props, provider model lists, ...) or user overrides.
class ModelCapabilities {
  final bool vision;
  final bool tools;
  final bool reasoning;
  final bool reasoningCanDisable;
  final List<ReasoningLevel> reasoningLevels;
  final int? contextWindow;
  const ModelCapabilities({
    this.vision = false,
    this.tools = false,
    this.reasoning = false,
    this.reasoningCanDisable = false,
    this.reasoningLevels = const [],
    this.contextWindow,
  });
  Map<String, dynamic> toJson() => {
        'vision': vision,
        'tools': tools,
        'reasoning': reasoning,
        'reasoningCanDisable': reasoningCanDisable,
        'reasoningLevels': reasoningLevels.map((e) => e.name).toList(),
        'contextWindow': contextWindow,
      };
  factory ModelCapabilities.fromJson(Map<String, dynamic> j) => ModelCapabilities(
        vision: j['vision'] == true,
        tools: j['tools'] == true,
        reasoning: j['reasoning'] == true,
        reasoningCanDisable: j['reasoningCanDisable'] == true,
        reasoningLevels: ((j['reasoningLevels'] as List?) ?? [])
            .map((e) => ReasoningLevel.values.firstWhere((l) => l.name == e, orElse: () => ReasoningLevel.medium))
            .toList(),
        contextWindow: j['contextWindow'] as int?,
      );
}

class LlmModel {
  final String providerId;
  final String modelId;
  final String displayName;
  final ModelCapabilities caps;
  const LlmModel({required this.providerId, required this.modelId, required this.displayName, this.caps = const ModelCapabilities()});
  String get ref => '$providerId::$modelId';
}

/// One configured provider (llama.cpp, OpenAI, Anthropic, OpenRouter, NAS hub, ...).
abstract class LlmClient {
  String get providerId;
  Future<List<LlmModel>> listModels();
  Stream<LlmEvent> chat(LlmRequest request, {LlmCancelToken? cancel});
  /// Exact token count if the backend can tokenize (llama.cpp /tokenize), else null.
  Future<int?> countTokens(String modelId, String text) async => null;
}

class LlmCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }

  void onCancel(void Function() f) => _cancelled ? f() : _listeners.add(f);
}
