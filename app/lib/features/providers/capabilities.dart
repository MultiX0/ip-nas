// Model capability heuristics (by model name) and user override merging.
import '../../core/contracts/llm.dart';
import 'sampling_presets.dart';

const _lmh = [ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high];
const _onOnly = [ReasoningLevel.medium];

bool _has(String id, List<String> keys) => keys.any(id.contains);

/// Best-effort guess from the model id when the provider exposes no metadata.
ModelCapabilities guessCaps(String modelId, {String? preset}) {
  final id = modelId.toLowerCase();
  final vision = _has(id, [
        'gpt-4o', 'gpt-4.1', 'gpt-5', 'gpt-4-turbo', 'o3', 'o4', 'gemini', 'claude', 'llava', 'vision', '-vl', 'vl-',
        'pixtral', 'gemma-3', 'gemma3', 'llama-4', 'llama4', 'grok-4', 'mistral-medium', 'mistral-small-3', 'minicpm-v',
        'internvl', 'moondream', 'qwen-vl', 'qvq', 'kimi-vl', 'glm-4.5v', 'glm-4v', 'mistral-large-3', 'magistral-medium',
      ]) &&
      !_has(id, ['gemma-3-1b', 'gemma3:1b', 'o3-mini']);
  final tools = _has(id, [
        'gpt', 'o1', 'o3', 'o4', 'gemini', 'claude', 'mistral', 'mixtral', 'magistral', 'ministral', 'codestral', 'llama-3.1',
        'llama-3.2', 'llama-3.3', 'llama3.1', 'llama3.2', 'llama3.3', 'llama-4', 'llama4', 'qwen', 'qwq', 'deepseek', 'grok',
        'command', 'hermes', 'glm', 'kimi', 'granite', 'phi-4', 'firefunction', 'functionary', 'devstral', 'smollm3', 'nemotron',
      ]) ||
      const {'openai', 'openrouter', 'groq', 'gemini', 'deepseek', 'mistral', 'xai', 'together', 'anthropic'}.contains(preset);

  var reasoning = false;
  var canDisable = false;
  var levels = const <ReasoningLevel>[];
  if (_has(id, ['gpt-oss'])) {
    reasoning = true;
    levels = _lmh;
  } else if (RegExp(r'(^|[/:\-])o[134](-|$)').hasMatch(id) || id.startsWith('o1') || id.startsWith('o3') || id.startsWith('o4') || _has(id, ['gpt-5'])) {
    reasoning = !_has(id, ['gpt-5-chat']);
    levels = _lmh;
  } else if (_has(id, ['grok-3-mini'])) {
    reasoning = true;
    levels = const [ReasoningLevel.low, ReasoningLevel.high];
  } else if (_has(id, ['grok-4'])) {
    reasoning = !_has(id, ['non-reasoning']);
    levels = _onOnly;
  } else if (_has(id, ['deepseek-reasoner', 'deepseek-r1', 'qwq', 'magistral', 'phi-4-reasoning', 'thinking', 'r1-distill'])) {
    reasoning = true;
    levels = _onOnly;
  } else if (_has(id, ['qwen3']) && !_has(id, ['instruct-2507', 'coder', '-vl-instruct'])) {
    reasoning = true;
    canDisable = true;
    levels = _onOnly;
  } else if (_has(id, ['gemini-2.5', 'gemini-3', 'gemini-flash-latest', 'gemini-pro-latest'])) {
    reasoning = true;
    canDisable = _has(id, ['flash']);
    levels = _lmh;
  } else if (_has(id, ['claude-3-7', 'claude-3.7', 'sonnet-4', 'opus-4', 'haiku-4', 'claude-sonnet-4', 'claude-opus-4', 'claude-haiku-4', 'claude-4'])) {
    reasoning = true;
    canDisable = true;
    levels = _lmh;
  } else if (_has(id, ['glm-4.5', 'glm-4.6', 'glm-4.7', 'glm-5', 'deepseek-v3.1', 'deepseek-v3.2', 'hunyuan-a13b', 'smollm3', 'seed-oss'])) {
    reasoning = true;
    canDisable = true;
    levels = _onOnly;
  }
  return ModelCapabilities(
    vision: vision,
    tools: tools,
    reasoning: reasoning,
    reasoningCanDisable: canDisable,
    reasoningLevels: reasoning ? levels : const [],
    contextWindow: guessContext(id),
  );
}

int? guessContext(String id) {
  if (_has(id, ['gpt-4.1', 'gemini'])) return 1048576;
  if (_has(id, ['gpt-5'])) return 400000;
  if (_has(id, ['claude', 'o1', 'o3', 'o4'])) return 200000;
  if (_has(id, ['gpt-4o', 'gpt-4-turbo', 'gpt-oss', 'mistral', 'llama-3.1', 'llama-3.3', 'llama3.1', 'llama3.3', 'deepseek', 'grok', 'kimi'])) {
    return 131072;
  }
  if (_has(id, ['qwen3', 'qwq', 'qwen2.5'])) return 32768;
  return null;
}

/// User overrides stored in LlmModels.overridesJson.
class ModelOverrides {
  final bool? vision;
  final bool? tools;
  final bool? reasoning;
  final bool? reasoningCanDisable;
  final int? contextWindow;
  final double? temperature;
  final ReasoningLevel? defaultReasoning;

  /// `sampling`: auto ("Recommended (auto)", the default) | server | custom. See sampling_presets.dart.
  final SamplingMode? samplingMode;

  /// `samplingCustom`: {temperature, topP, topK, minP, presencePenalty, repeatPenalty} used when mode = custom.
  final SamplingParams? samplingCustom;

  /// `smallModel`: force small-model mode on/off (null = automatic from the model size).
  final bool? smallModel;
  const ModelOverrides({
    this.vision,
    this.tools,
    this.reasoning,
    this.reasoningCanDisable,
    this.contextWindow,
    this.temperature,
    this.defaultReasoning,
    this.samplingMode,
    this.samplingCustom,
    this.smallModel,
  });

  factory ModelOverrides.fromJson(Map<String, dynamic> j) => ModelOverrides(
        vision: j['vision'] as bool?,
        tools: j['tools'] as bool?,
        reasoning: j['reasoning'] as bool?,
        reasoningCanDisable: j['reasoningCanDisable'] as bool?,
        contextWindow: (j['contextWindow'] as num?)?.toInt(),
        temperature: (j['temperature'] as num?)?.toDouble(),
        defaultReasoning: ReasoningLevel.values.where((l) => l.name == j['defaultReasoning']).firstOrNull,
        samplingMode: SamplingMode.values.where((m) => m.name == j['sampling']).firstOrNull,
        samplingCustom: j['samplingCustom'] is Map ? SamplingParams.fromJson((j['samplingCustom'] as Map).cast<String, dynamic>()) : null,
        smallModel: j['smallModel'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        if (vision != null) 'vision': vision,
        if (tools != null) 'tools': tools,
        if (reasoning != null) 'reasoning': reasoning,
        if (reasoningCanDisable != null) 'reasoningCanDisable': reasoningCanDisable,
        if (contextWindow != null) 'contextWindow': contextWindow,
        if (temperature != null) 'temperature': temperature,
        if (defaultReasoning != null) 'defaultReasoning': defaultReasoning!.name,
        if (samplingMode != null) 'sampling': samplingMode!.name,
        if (samplingCustom != null && !samplingCustom!.isEmpty) 'samplingCustom': samplingCustom!.toJson(),
        if (smallModel != null) 'smallModel': smallModel,
      };

  /// Same overrides with another default reasoning level (used for the small-model default).
  ModelOverrides withDefaultReasoning(ReasoningLevel? level) => ModelOverrides(
        vision: vision,
        tools: tools,
        reasoning: reasoning,
        reasoningCanDisable: reasoningCanDisable,
        contextWindow: contextWindow,
        temperature: temperature,
        defaultReasoning: level,
        samplingMode: samplingMode,
        samplingCustom: samplingCustom,
        smallModel: smallModel,
      );

  ModelCapabilities apply(ModelCapabilities c) {
    final r = reasoning ?? c.reasoning;
    var levels = c.reasoningLevels;
    if (r && levels.isEmpty) levels = _lmh;
    return ModelCapabilities(
      vision: vision ?? c.vision,
      tools: tools ?? c.tools,
      reasoning: r,
      reasoningCanDisable: r && (reasoningCanDisable ?? c.reasoningCanDisable),
      reasoningLevels: r ? levels : const [],
      contextWindow: contextWindow ?? c.contextWindow,
    );
  }
}

/// Levels offered in the reasoning pill for a model.
List<ReasoningLevel> pillLevels(ModelCapabilities c) {
  if (!c.reasoning) return const [];
  final lv = c.reasoningLevels.isEmpty ? _onOnly : c.reasoningLevels;
  return [if (c.reasoningCanDisable) ReasoningLevel.off, ...lv];
}

/// Clamp a wanted level to what the model supports.
ReasoningLevel effectiveLevel(ModelCapabilities c, ReasoningLevel want) {
  final lv = pillLevels(c);
  if (lv.isEmpty) return ReasoningLevel.off;
  if (lv.contains(want)) return want;
  if (want == ReasoningLevel.off) return lv.first;
  return lv.lastWhere((l) => l != ReasoningLevel.off && l.index <= want.index, orElse: () => lv.firstWhere((l) => l != ReasoningLevel.off, orElse: () => lv.first));
}

String formatCtx(int? n) {
  if (n == null || n <= 0) return '';
  if (n >= 1000000) return '${(n / 1048576).toStringAsFixed(n % 1048576 == 0 ? 0 : 1)}M';
  return '${(n / 1024).round()}K';
}
