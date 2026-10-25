// Odd output from small models: almost-JSON arguments, calls written as text, unknown tools, thinking tags,
// a stream that breaks off.
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/features/providers/adapters/stream_utils.dart';
import 'package:nur/features/tools/tool_call_repair.dart';

import 'helpers/chat_fakes.dart';

const _results = [
  {'title': 'Raspberry Pi', 'url': 'https://www.raspberrypi.com/about/', 'content': 'The Raspberry Pi Foundation was founded in 2009.'},
];

void main() {
  late ChatRig rig;
  tearDown(() async => rig.dispose());

  const question = 'I want to tell you about the Raspberry Pi.';

  test('almost-JSON arguments are repaired before the tool runs', () async {
    var n = 0;
    rig = await ChatRig.create(
      hub: FakeNasHub(searchResults: _results),
      llm: ScriptedLlm((req) => n++ == 0
          ? [
              const ToolCallEvent(LlmToolCall(id: 'c1', name: 'web_search', argumentsJson: "{'query': 'raspberry pi history',}")),
              const DoneEvent('tool_calls'),
            ]
          : say('It started in 2009.')),
    );
    final t = await rig.send(null, question);
    expect(rig.hub.searches, ['raspberry pi history']);
    expect(t.done, 'It started in 2009.');
    final call = (await rig.path(t.chatId!)).firstWhere((m) => m.toolCallsJson != null);
    expect(call.toolCallsJson, contains(r'"arguments":"{\"query\":\"raspberry pi history\"}"'));
  });

  test('a call written as text becomes a real call and leaves no markup in the reply', () async {
    var n = 0;
    rig = await ChatRig.create(
      hub: FakeNasHub(searchResults: _results),
      llm: ScriptedLlm((req) => n++ == 0
          ? say('Let me look.\n<tool_call>{"name": "web_search", "arguments": {"query": "pi history"}}</tool_call>')
          : say('It started in 2009.')),
    );
    final t = await rig.send(null, question);
    expect(rig.hub.searches, ['pi history']);
    expect(t.done, isNot(contains('tool_call')));
    expect(t.done, endsWith('It started in 2009.'));
  });

  test('an unknown tool gets an error result and the model still answers', () async {
    var n = 0;
    rig = await ChatRig.create(
      llm: ScriptedLlm((req) => n++ == 0
          ? [const ToolCallEvent(LlmToolCall(id: 'c1', name: 'launch_rocket', argumentsJson: '{}')), const DoneEvent('tool_calls')]
          : say('I cannot do that.')),
    );
    final t = await rig.send(null, question);
    expect(t.errors, isEmpty);
    expect(t.done, 'I cannot do that.');
  });

  test('a stream that breaks off is stored as a failed reply with what arrived', () async {
    rig = await ChatRig.create(llm: ScriptedLlm((_) => const [TextDelta('The Raspberry Pi was'), ErrorEvent('Connection closed')]));
    final t = await rig.send(null, question);
    expect(t.errors, ['Connection closed']);
    final last = (await rig.path(t.chatId!)).last;
    expect(last.status, 'error');
    expect(last.content, 'The Raspberry Pi was');
    expect(rig.engine.isBusy(t.chatId!), isFalse);
  });

  group('adapter helpers', () {
    test('think tags split across chunks', () {
      final s = ThinkTagSplitter();
      final events = [...s.feed('<thi'), ...s.feed('nk>let me count</th'), ...s.feed('ink>\nThe answer is 7.'), ...s.flush()];
      expect(events.whereType<ReasoningDelta>().map((e) => e.text).join(), 'let me count');
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'The answer is 7.');
    });

    test('a later <think> in the visible answer stays text', () {
      final s = ThinkTagSplitter();
      final events = [...s.feed('Use the tag <think> in your prompt.'), ...s.flush()];
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'Use the tag <think> in your prompt.');
    });

    test('tool calls streamed in fragments, and calls without a name are dropped', () {
      final a = ToolCallAssembler()
        ..add({'index': 0, 'id': 'call_1', 'function': {'name': 'web_search', 'arguments': '{"que'}})
        ..add({'index': 0, 'function': {'arguments': 'ry": "nas"}'}})
        ..add({'index': 1, 'function': {'name': '', 'arguments': '{}'}});
      final calls = a.build();
      expect(calls, hasLength(1));
      expect(calls.single.name, 'web_search');
      expect(calls.single.argumentsJson, '{"query": "nas"}');
    });

    test('argument repair', () {
      expect(repairArguments('```json\n{"name": "jellyfin",}\n```'), {'name': 'jellyfin'});
      expect(repairArguments("{name: 'jellyfin', action: 'restart'}"), {'name': 'jellyfin', 'action': 'restart'});
      expect(repairArguments('"{\\"tail\\": 50}"'), {'tail': 50});
      expect(repairArguments('name="jellyfin", tail=50'), {'name': 'jellyfin', 'tail': 50});
      expect(repairArguments(''), <String, dynamic>{});
      expect(repairArguments('not json at all'), isNull);
      expect(toolCallKey('docker_logs', '{"name": "Jellyfin", "tail": 50}'), toolCallKey('docker_logs', '{"tail":50,"name":"jellyfin"}'));
    });
  });
}
