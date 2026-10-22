// What the model gets to see: context resets, branches, interrupted tool calls, and the llama.cpp request body.
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/core/providers.dart';
import 'package:nur/features/context/history.dart';
import 'package:nur/features/providers/adapters/openai_compat_client.dart';
import 'package:nur/features/providers/sampling_presets.dart';

import 'helpers/chat_fakes.dart';

void main() {
  group('history sent to the model', () {
    late ChatRig rig;
    tearDown(() async => rig.dispose());

    List<String> userTexts(LlmRequest r) => [for (final m in r.messages) if (m.role == LlmRole.user) m.content];

    test('after "clear context" only the new turn is sent', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((_) => say('Noted.')));
      const a = 'I want to tell you about my garden in the city.';
      final id = (await rig.send(null, a)).chatId!;
      await rig.send(id, 'I want to tell you about my old bicycle.');
      await rig.container.read(contextAssemblerProvider).clearContext(chatId: id);
      await rig.send(id, 'I want to tell you about a new book I read.');
      final users = userTexts(rig.llm.chatRequests.last);
      expect(users, hasLength(1));
      expect(users.single, contains('new book'));
      expect(rig.llm.chatRequests.last.messages.any((m) => m.content.contains('garden')), isFalse);
    });

    test('an edited message starts a branch: the old reply is not sent, switching back restores it', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((req) => say('Reply to: ${userTexts(req).last.split('\n').first}')));
      final id = (await rig.send(null, 'I want to tell you about my garden in the city.')).chatId!;
      final original = (await rig.path(id)).firstWhere((m) => m.role == 'user');
      await rig.engine.editAndResend(id, original, 'I want to tell you about my garden in the village.');
      final path = await rig.path(id);
      expect(path.where((m) => m.role == 'user').single.content, contains('village'));
      expect(path.last.content, contains('village'));
      expect(rig.llm.chatRequests.last.messages.any((m) => m.content.contains('city')), isFalse);
      final siblings = (await rig.repo.thread(id)).children[original.parentId]!;
      expect(siblings, hasLength(2));
      await rig.engine.switchBranch(id, original);
      expect((await rig.path(id)).last.content, contains('city'));
    });
  });

  test('a tool call that never got its result gets a placeholder, and stray results are dropped', () {
    final out = pairToolMessages(const [
      LlmMessage(LlmRole.user, 'How is my NAS?'),
      LlmMessage(LlmRole.tool, 'orphan', toolCallId: 'x'),
      LlmMessage(LlmRole.assistant, '', toolCalls: [
        LlmToolCall(id: 'a', name: 'nas_system_status', argumentsJson: '{}'),
        LlmToolCall(id: 'b', name: 'docker_list', argumentsJson: '{}'),
      ]),
      LlmMessage(LlmRole.tool, 'RAM 1.5 GB free', toolCallId: 'a', toolName: 'nas_system_status'),
      LlmMessage(LlmRole.user, 'thanks'),
    ]);
    expect(out.map((m) => m.role).toList(), [LlmRole.user, LlmRole.assistant, LlmRole.tool, LlmRole.tool, LlmRole.user]);
    expect(out[3].toolCallId, 'b');
    expect(out[3].content, startsWith('No result'));
  });

  group('llama.cpp request body', () {
    const qwen = ModelCapabilities(tools: true, reasoning: true, reasoningCanDisable: true, reasoningLevels: [ReasoningLevel.medium]);
    OpenAiCompatClient client() => OpenAiCompatClient(
          providerId: 'nas',
          baseUrl: 'http://192.168.1.50:8770/llm/v1/',
          apiKey: 'token',
          preset: 'nas',
          capsOf: (_) => qwen,
          samplingOf: (id, thinking) => recommendedSampling(id, thinking: thinking),
        );

    test('thinking off: template switch off, Qwen3.5 sampling, prompt cache on', () {
      final b = client().buildBody(const LlmRequest(
        modelId: 'Qwen3.5-2B-Q4_0',
        reasoning: ReasoningLevel.off,
        maxTokens: 1536,
        messages: [LlmMessage(LlmRole.system, 'a'), LlmMessage(LlmRole.user, 'hi'), LlmMessage(LlmRole.system, 'b')],
      ));
      expect(b['chat_template_kwargs'], {'enable_thinking': false});
      expect(b['reasoning_effort'], 'none');
      expect(b['cache_prompt'], isTrue);
      expect(b['temperature'], 0.7);
      expect(b['top_k'], 20);
      expect(b['max_tokens'], 1536);
      final msgs = b['messages'] as List;
      expect(msgs.first, {'role': 'system', 'content': 'a\n\nb'}, reason: 'one leading system message for strict templates');
      expect(msgs, hasLength(2));
    });

    test('thinking on: effort, live budget and the thinking sampling; a request temperature wins', () {
      final b = client().buildBody(const LlmRequest(
        modelId: 'Qwen3.5-2B-Q4_0',
        reasoning: ReasoningLevel.low,
        temperature: 0.2,
        messages: [LlmMessage(LlmRole.user, 'hi')],
      ));
      expect(b['reasoning_effort'], 'low');
      expect(b['chat_template_kwargs'], {'reasoning_effort': 'low', 'enable_thinking': true});
      expect(b['reasoning_control'], isTrue);
      expect(b['temperature'], 0.2);
      expect(b['top_p'], 0.95);
    });

    const spec = LlmToolSpec(name: 'nas_system_status', description: 'NAS status', parameters: {'type': 'object', 'properties': {}});

    test('a round that must answer keeps the tool list and sends tool_choice none', () {
      // The tool list opens the prompt; without it llama.cpp re-reads the whole chat (30 s or more on a Pi).
      final b = client().buildBody(const LlmRequest(
          modelId: 'Qwen3.5-2B-Q4_0', messages: [LlmMessage(LlmRole.user, 'hi')], tools: [spec], toolChoice: 'none'));
      expect(b['tools'], hasLength(1));
      expect(b['tool_choice'], 'none');
      final normal = client().buildBody(const LlmRequest(modelId: 'Qwen3.5-2B-Q4_0', messages: [LlmMessage(LlmRole.user, 'hi')], tools: [spec]));
      expect(normal.containsKey('tool_choice'), isFalse);
    });

    test('other servers get no tools in a round that must answer', () {
      final c = OpenAiCompatClient(providerId: 'or', baseUrl: 'https://openrouter.ai/api/v1', apiKey: 'your-key-here', preset: 'openrouter');
      final b = c.buildBody(const LlmRequest(modelId: 'qwen/qwen3.5-27b', messages: [LlmMessage(LlmRole.user, 'hi')], tools: [spec], toolChoice: 'none'));
      expect(b.containsKey('tools'), isFalse);
      expect(b.containsKey('tool_choice'), isFalse);
    });
  });
}
