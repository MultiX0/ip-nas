// Recommended sampling per model family (from the official model cards, see docs/SMALL_MODELS.md) and
// small-model detection. Applied automatically to local backends (llama.cpp, Ollama, LM Studio, vLLM) unless the
// user picks "server defaults" or custom values in the model's overrides.
import '../../core/contracts/llm.dart';

/// Sampling values sent with a request. null = leave the server default.
class SamplingParams {
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? minP;
  final double? presencePenalty;
  final double? repeatPenalty;
  const SamplingParams({this.temperature, this.topP, this.topK, this.minP, this.presencePenalty, this.repeatPenalty});

  static const none = SamplingParams();
  bool get isEmpty => temperature == null && topP == null && topK == null && minP == null && presencePenalty == null && repeatPenalty == null;

  factory SamplingParams.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return SamplingParams(
      temperature: d('temperature'),
      topP: d('topP'),
      topK: (j['topK'] as num?)?.toInt(),
      minP: d('minP'),
      presencePenalty: d('presencePenalty'),
      repeatPenalty: d('repeatPenalty'),
    );
  }

  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'topP': topP,
        if (topK != null) 'topK': topK,
        if (minP != null) 'minP': minP,
        if (presencePenalty != null) 'presencePenalty': presencePenalty,
        if (repeatPenalty != null) 'repeatPenalty': repeatPenalty,
      };

  /// OpenAI-compatible body fields understood by llama.cpp / LM Studio / vLLM.
  Map<String, dynamic> toOpenAiBody() => {
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (topK != null) 'top_k': topK,
        if (minP != null) 'min_p': minP,
        if (presencePenalty != null) 'presence_penalty': presencePenalty,
        if (repeatPenalty != null) 'repeat_penalty': repeatPenalty,
      };

  /// Ollama `options`.
  Map<String, dynamic> toOllamaOptions() => {
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (topK != null) 'top_k': topK,
        if (minP != null) 'min_p': minP,
        if (presencePenalty != null) 'presence_penalty': presencePenalty,
        if (repeatPenalty != null) 'repeat_penalty': repeatPenalty,
      };
}

/// How a model's sampling is chosen (stored in the model overrides JSON as `sampling`).
enum SamplingMode {
  /// "Recommended (auto)": the family preset below (default).
  auto,

  /// Send nothing; the server's own defaults apply.
  server,

  /// The user's own values (`samplingCustom`), missing ones fall back to the preset.
  custom,
}

/// Sampling recommended by the model makers. [thinking] = reasoning is on for this request.
/// Returns [SamplingParams.none] for families without a published recommendation.
SamplingParams recommendedSampling(String modelId, {required bool thinking}) {
  final id = modelId.toLowerCase();
  bool has(String s) => id.contains(s);
  // Qwen3.5 (model card): thinking 1.0/0.95/20/0 + presence 1.5. For non-thinking the card lists 1.0/1.0/20/0 +
  // presence 2.0 (text) and 0.7/0.8/20/0 + presence 1.5 (general/VL); the lower temperature copied tool numbers
  // more reliably in our Pi tests, so it is used for both chat and tools.
  if (RegExp(r'qwen3[._\-]?5').hasMatch(id)) {
    return thinking
        ? const SamplingParams(temperature: 1.0, topP: 0.95, topK: 20, minP: 0.0, presencePenalty: 1.5, repeatPenalty: 1.0)
        : const SamplingParams(temperature: 0.7, topP: 0.8, topK: 20, minP: 0.0, presencePenalty: 1.5, repeatPenalty: 1.0);
  }
  // Qwen3 / Qwen3-2507 (model card): thinking 0.6/0.95/20/0, non-thinking 0.7/0.8/20/0. Never greedy.
  if (has('qwen3') || has('qwq')) {
    return thinking
        ? const SamplingParams(temperature: 0.6, topP: 0.95, topK: 20, minP: 0.0)
        : const SamplingParams(temperature: 0.7, topP: 0.8, topK: 20, minP: 0.0);
  }
  // Qwen2.5 generation_config: 0.7/0.8/20, repetition 1.05.
  if (has('qwen2.5') || has('qwen2_5')) return const SamplingParams(temperature: 0.7, topP: 0.8, topK: 20, repeatPenalty: 1.05);
  // Gemma 3 (Gemma team via Unsloth docs): 1.0/0.95/64, min_p 0, no repetition penalty.
  if (has('gemma-3') || has('gemma3')) return const SamplingParams(temperature: 1.0, topP: 0.95, topK: 64, minP: 0.0, repeatPenalty: 1.0);
  // LFM2 / LFM2.5 (Liquid AI model card): temperature 0.1, top_k 50, repetition 1.05.
  if (has('lfm2')) return const SamplingParams(temperature: 0.1, topK: 50, topP: 1.0, minP: 0.0, repeatPenalty: 1.05);
  // Granite 4.2 (IBM model card): temperature 1.0, top_p 0.95 for all tasks including tool calling.
  if (RegExp(r'granite[\-_]?4\.[1-9]').hasMatch(id)) return const SamplingParams(temperature: 1.0, topP: 0.95, topK: 0, minP: 0.0);
  // Granite 4.0 (IBM): temperature 0, top_p 1.0, top_k 0.
  if (has('granite')) return const SamplingParams(temperature: 0.0, topP: 1.0, topK: 0);
  // Llama 3.x generation_config: 0.6/0.9.
  if (RegExp(r'llama[\-_ .]?3').hasMatch(id)) return const SamplingParams(temperature: 0.6, topP: 0.9);
  return SamplingParams.none;
}

/// Parameter count in billions guessed from the model name ("Qwen3.5-2B", "LFM2.5-1.2B", "qwen3:4b", "gemma-3-270m"),
/// largest number wins (so "30B-A3B" is 30). null when the name has no size.
double? paramsFromName(String modelId) {
  final id = modelId.toLowerCase();
  double? best;
  for (final m in RegExp(r'(?<![\d.])(\d+(?:\.\d+)?)\s*([bm])(?![a-z])').allMatches(id)) {
    final v = double.tryParse(m[1]!);
    if (v == null) continue;
    final b = m[2] == 'm' ? v / 1000 : v;
    if (best == null || b > best) best = b;
  }
  if (best == null && RegExp(r'smollm|tinyllama|phi-?\d?-?mini|functiongemma').hasMatch(id)) best = 3.8;
  return best;
}

/// Up to about 4.5 B parameters counts as "small" (1-4 B models on a Pi or phone).
bool isSmallByName(String modelId) {
  final b = paramsFromName(modelId);
  return b != null && b <= 4.5;
}

/// Thinking is on for this request?
bool thinkingOn(ModelCapabilities caps, ReasoningLevel level) => caps.reasoning && level != ReasoningLevel.off;
