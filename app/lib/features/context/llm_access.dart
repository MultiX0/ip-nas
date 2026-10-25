// Model access for the context and memory code (see providers/llm_registry.dart), used for background model calls:
// compaction summaries and memory extraction.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/llm.dart';
import '../providers/foreground_gate.dart';
import '../providers/llm_registry.dart';

class IntelLlm {
  IntelLlm(this._ref);
  final Ref _ref;

  LlmRegistry get _reg => _ref.read(llmRegistryProvider);

  LlmClient? clientFor(String providerId) => _reg.clientFor(providerId);

  LlmModel? modelByRef(String? ref) => ref == null || ref.isEmpty ? null : _reg.modelByRef(ref);

  /// Completes when the registry has loaded providers and models (at most 10 s).
  Future<void> ready() => _reg.ready;

  /// Small-model mode for [m] (1-4 B local model, or forced in the model overrides).
  bool isSmallModel(LlmModel m) => m.modelId.isNotEmpty && _reg.isSmallModel(m);

  /// Fires when providers or models change.
  Stream<void> get changes => _reg.changes;

  Future<List<LlmModel>> allModels() => _reg.allModels();

  Stream<LlmModel?> watchDefaultModel() => _reg.watchDefaultModel();

  Future<LlmModel?> defaultModel() async {
    try {
      return await watchDefaultModel().first.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return null;
    }
  }

  /// Runs one non-interactive completion and returns the whole text. A [background] call waits while a reply or a
  /// voice call holds the model and throws [BackgroundCancelled] when one starts (see foreground_gate.dart).
  /// Throws [StateError] with a user-readable message on other failures.
  Future<String> complete(
    LlmModel model,
    List<LlmMessage> messages, {
    double temperature = 0.2,
    int? maxTokens,
    Duration timeout = const Duration(minutes: 4),
    LlmCancelToken? cancel,
    bool background = true,
  }) {
    if (!background) return _complete(model, messages, temperature, maxTokens, timeout, cancel);
    return _ref.read(foregroundGateProvider).background((stop) {
      cancel?.onCancel(stop.cancel);
      return _complete(model, messages, temperature, maxTokens, timeout, stop);
    });
  }

  Future<String> _complete(LlmModel model, List<LlmMessage> messages, double temperature, int? maxTokens, Duration timeout,
      LlmCancelToken? stop) async {
    final client = clientFor(model.providerId);
    if (client == null) throw StateError('The model provider "${model.providerId}" is not available.');
    // Background calls need no thinking; a model that cannot turn it off thinks as little as it can.
    final reasoning = model.caps.reasoning && !model.caps.reasoningCanDisable ? ReasoningLevel.low : ReasoningLevel.off;
    final req = LlmRequest(
      modelId: model.modelId,
      messages: messages,
      reasoning: reasoning,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: true,
    );
    final buf = StringBuffer();
    final token = LlmCancelToken();
    stop?.onCancel(token.cancel);
    try {
      await for (final e in client.chat(req, cancel: token).timeout(timeout)) {
        if (e is TextDelta) buf.write(e.text);
        if (e is ErrorEvent) throw StateError(e.message);
      }
    } on TimeoutException {
      token.cancel();
      throw StateError('The model took too long to answer.');
    }
    if (token.isCancelled) throw StateError('Cancelled.');
    return stripThinking(buf.toString()).trim();
  }
}

/// Removes inline `<think>...</think>` blocks some local reasoning models emit in the content.
String stripThinking(String s) {
  var out = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
  final open = out.toLowerCase().indexOf('<think>');
  if (open >= 0) out = out.substring(0, open);
  return out;
}

final intelLlmProvider = Provider<IntelLlm>((ref) => IntelLlm(ref));
