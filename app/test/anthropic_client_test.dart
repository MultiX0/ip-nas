// Request bodies of the Anthropic adapter against the Messages API: Claude 4.6 and newer think adaptively
// (thinking.type adaptive + output_config.effort), budget_tokens is only for older models, and Opus 4.7+,
// Sonnet 5+ and Fable reject temperature.
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/features/providers/adapters/anthropic_client.dart';

Map<String, dynamic> body(String model, {ReasoningLevel reasoning = ReasoningLevel.medium, double? temperature, int? maxTokens}) =>
    AnthropicClient(providerId: 'anthropic', apiKey: 'test-key').buildBody(LlmRequest(
      modelId: model,
      messages: const [LlmMessage(LlmRole.system, 'Be brief.'), LlmMessage(LlmRole.user, 'Hello')],
      reasoning: reasoning,
      temperature: temperature,
      maxTokens: maxTokens,
    ));

void main() {
  test('Opus 4.7: adaptive thinking with a summarized display and an effort level, no temperature', () {
    final b = body('claude-opus-4-7', temperature: 0.2);
    expect(b['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    expect(b['output_config'], {'effort': 'medium'});
    expect(b.containsKey('temperature'), isFalse);
    expect(b['max_tokens'], greaterThanOrEqualTo(8192));
    expect(b['system'], 'Be brief.');
  });

  test('Opus 4.8 with reasoning off: no thinking and no temperature (sampling is rejected)', () {
    final b = body('claude-opus-4-8', reasoning: ReasoningLevel.off, temperature: 0.2);
    expect(b.containsKey('thinking'), isFalse);
    expect(b.containsKey('output_config'), isFalse);
    expect(b.containsKey('temperature'), isFalse);
  });

  test('Sonnet 4.6: adaptive thinking without display; temperature only when thinking is off', () {
    final on = body('claude-sonnet-4-6', reasoning: ReasoningLevel.high, temperature: 0.2);
    expect(on['thinking'], {'type': 'adaptive'});
    expect(on['output_config'], {'effort': 'high'});
    expect(on.containsKey('temperature'), isFalse);
    final off = body('claude-sonnet-4-6', reasoning: ReasoningLevel.off, temperature: 0.2);
    expect(off.containsKey('thinking'), isFalse);
    expect(off['temperature'], 0.2);
  });

  test('Haiku 4.5 keeps the thinking budget and room for the answer', () {
    final b = body('claude-haiku-4-5-20251001', temperature: 0.7);
    expect(b['thinking'], {'type': 'enabled', 'budget_tokens': 4096});
    expect(b.containsKey('output_config'), isFalse);
    expect(b.containsKey('temperature'), isFalse);
    expect(b['max_tokens'] as int, greaterThan(4096));
    final small = body('claude-haiku-4-5', maxTokens: 700);
    expect(small['max_tokens'] as int, greaterThan(4096), reason: 'max_tokens must exceed budget_tokens');
  });

  test('Opus 5.5 always thinks: "off" becomes the lowest effort, never a thinking budget', () {
    final b = body('claude-opus-5-5', reasoning: ReasoningLevel.off, temperature: 0, maxTokens: 16);
    expect(b.containsKey('thinking'), isFalse);
    expect(b['output_config'], {'effort': 'low'});
    expect(b.containsKey('temperature'), isFalse);
    expect(b['max_tokens'], greaterThanOrEqualTo(8192));
  });

  test('Fable 5.1: the extra level is xhigh', () {
    final b = body('claude-fable-5-1', reasoning: ReasoningLevel.extra);
    expect(b['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    expect(b['output_config'], {'effort': 'xhigh'});
    expect(body('claude-opus-4-6', reasoning: ReasoningLevel.extra)['output_config'], {'effort': 'max'});
  });

  test('capabilities by model generation', () {
    final opus55 = AnthropicClient.capsFor('claude-opus-5-5', contextWindow: 1000000);
    expect(opus55.reasoning, isTrue);
    expect(opus55.reasoningCanDisable, isFalse);
    expect(opus55.reasoningLevels, [ReasoningLevel.low, ReasoningLevel.medium, ReasoningLevel.high, ReasoningLevel.extra]);
    expect(opus55.contextWindow, 1000000);
    final opus47 = AnthropicClient.capsFor('claude-opus-4-7');
    expect(opus47.reasoningCanDisable, isTrue);
    expect(opus47.contextWindow, 200000);
    final haiku = AnthropicClient.capsFor('claude-haiku-4-5');
    expect(haiku.reasoningLevels.first, ReasoningLevel.minimal);
  });

  test('a failed tool result is sent with is_error', () {
    final b = AnthropicClient(providerId: 'anthropic', apiKey: 'test-key').buildBody(const LlmRequest(
      modelId: 'claude-sonnet-4-6',
      reasoning: ReasoningLevel.off,
      messages: [
        LlmMessage(LlmRole.user, 'How is my NAS?'),
        LlmMessage(LlmRole.assistant, '', toolCalls: [LlmToolCall(id: 'toolu_1', name: 'nas_system_status', argumentsJson: '{}')]),
        LlmMessage(LlmRole.tool, 'Cannot reach the NAS.', toolCallId: 'toolu_1', toolName: 'nas_system_status', isError: true),
      ],
    ));
    final msgs = b['messages'] as List;
    final result = ((msgs.last as Map)['content'] as List).single as Map;
    expect(result, {'type': 'tool_result', 'tool_use_id': 'toolu_1', 'content': 'Cannot reach the NAS.', 'is_error': true});
    expect(((msgs[1] as Map)['content'] as List).single, {'type': 'tool_use', 'id': 'toolu_1', 'name': 'nas_system_status', 'input': {}});
  });
}
