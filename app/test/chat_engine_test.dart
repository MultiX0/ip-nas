// Chat engine regressions found in live runs with Qwen3.5 2B on llama.cpp behind a test Nur Hub.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/features/chat/engine/chat_engine_impl.dart' show cutOffNote;
import 'package:nur/features/chat/engine/live_store.dart' show toolApprovalBrokerProvider;
import 'package:nur/features/context/context_assembler_impl.dart';
import 'package:nur/features/context/prompts.dart';
import 'package:nur/features/memory/memory_extractor.dart' show mentionsSelf;
import 'package:nur/features/nas/nas_hub_client.dart';
import 'package:nur/features/providers/capabilities.dart' show ModelOverrides;
import 'package:nur/features/providers/llm_registry.dart';

import 'helpers/chat_fakes.dart';

void main() {
  late ChatRig rig;
  tearDown(() async => rig.dispose());

  group('planned tool fails', () {
    test('NAS status: plain reply with the hub error, no model call', () async {
      rig = await ChatRig.create(hub: FakeNasHub(failWith: NasException('Cannot reach the NAS. Check that it is on.')));
      final t = await rig.send(null, 'How is my NAS doing?');
      expect(t.done, "I couldn't check the NAS: Cannot reach the NAS. Check that it is on.");
      expect(t.errors, isEmpty);
      expect(rig.llm.chatRequests, isEmpty, reason: 'a small model asked to explain the failure made up NAS values');
      final tool = (await rig.path(t.chatId!)).singleWhere((m) => m.role == 'tool');
      expect(tool.status, 'error');
    });

    test('Arabic question gets the Arabic sentence', () async {
      rig = await ChatRig.create(hub: FakeNasHub(failWith: NasException('This device is not paired.')));
      final t = await rig.send(null, 'كم حرارة الجهاز الآن؟');
      expect(t.done, 'لم أتمكن من فحص الجهاز: This device is not paired.');
      expect(rig.llm.chatRequests, isEmpty);
    });

    test('web search with SearXNG refusing JSON', () async {
      rig = await ChatRig.create(hub: FakeNasHub(failWith: NasException("SearXNG refused JSON output. Add 'json' to search.formats in its settings.yml")));
      final t = await rig.send(null, 'Search the web for the latest Raspberry Pi OS release');
      expect(t.tools, ['web_search']);
      expect(t.done, "I couldn't search the web: SearXNG refused JSON output. Add 'json' to search.formats in its settings.yml.");
      expect(rig.llm.chatRequests, isEmpty);
    });

    test('in a voice call the reply leaves the technical detail to the chat', () async {
      rig = await ChatRig.create(hub: FakeNasHub(failWith: NasException("SearXNG refused JSON output. Add 'json' to search.formats in its settings.yml")));
      final t = await rig.send(null, 'ابحث في الإنترنت عن أخبار راسبيري باي', voice: true);
      expect(t.done, 'لم أتمكن من البحث في الإنترنت. التفاصيل مكتوبة في المحادثة.');
      final tool = (await rig.path(t.chatId!)).singleWhere((m) => m.role == 'tool');
      expect(tool.content, contains('search.formats'));
    });
  });

  group('tools the model calls', () {
    test('a small model whose NAS cannot be reached gets the plain failure reply at once', () async {
      var n = 0;
      rig = await ChatRig.create(
        hub: FakeNasHub(failWith: NasException('Nur Hub has no access to Docker. It has to run as root.', statusCode: 503)),
        llm: ScriptedLlm((req) => switch (n++) {
              0 => callTool('docker_list'),
              _ => say('The logs indicate the following issue with searxng: HTTP 503 (Service Unavailable).'),
            }),
      );
      final t = await rig.send(null, 'Look at the logs of the searxng app and tell me if something is wrong.');
      expect(rig.llm.chatRequests, hasLength(1), reason: 'asked again, the model presented the hub error as the app logs');
      expect(t.done, "I couldn't get the list of apps from the NAS: Nur Hub has no access to Docker. It has to run as root.");
    });

    test('a small model whose tools fail twice gets the plain failure reply, not a made-up answer', () async {
      var n = 0;
      rig = await ChatRig.create(
        hub: FakeNasHub(failWith: NasException('The NAS does not support this yet.', statusCode: 404)),
        llm: ScriptedLlm((req) => switch (n++) {
              0 => callTool('docker_list'),
              1 => callTool('nas_system_status'),
              _ => say('Here are the latest logs:\n```\nHTTP 503 Service Unavailable\n```'),
            }),
      );
      final t = await rig.send(null, 'Look at the logs of the searxng app and tell me if something is wrong.');
      expect(rig.llm.chatRequests, hasLength(2), reason: 'asked a third time, the model made up log lines from the error text');
      expect(t.done, "I couldn't check the NAS: The NAS does not support this yet.");
      final path = await rig.path(t.chatId!);
      expect(path.where((m) => m.role == 'tool' && m.status == 'error'), hasLength(2));
      expect(path.last.content, t.done);
    });

    test('a small model asked for advice answers without calling tools, with the same tool list', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((req) => mustAnswer(req) ? say('استخدم مروحة ومشتتاً حرارياً.') : callTool('nas_system_status')));
      final t = await rig.send(null, 'ما هي أفضل طريقة لتبريد الراسبيري باي؟');
      expect(t.tools, isEmpty, reason: 'it read the NAS values instead of answering');
      expect(t.done, 'استخدم مروحة ومشتتاً حرارياً.');
      final req = rig.llm.chatRequests.single;
      expect(req.toolChoice, 'none');
      expect(req.tools, isNotEmpty);
    });

    test('a call that comes back from a round that must answer is not run', () async {
      // A server that ignores tool_choice none.
      rig = await ChatRig.create(llm: ScriptedLlm((req) => callTool('nas_system_status')));
      final t = await rig.send(null, 'What is the best way to cool my Raspberry Pi?');
      expect(rig.hub.calls, 0);
      expect(t.done, 'I could not finish this with my tools. Please try again or ask in a different way.');
      expect((await rig.path(t.chatId!)).last.toolCallsJson, isNull);
    });

    group('a small model that already answered and then calls a tool', () {
      const results = [
        {'title': 'Moon facts', 'url': 'https://example.org/moon', 'content': 'The Moon has moonquakes.'},
      ];
      const search = ToolCallEvent(LlmToolCall(id: 'c1', name: 'web_search', argumentsJson: '{"query": "moon facts"}'));

      test('ends the turn: the answer is not written (or spoken) twice', () async {
        var n = 0;
        rig = await ChatRig.create(
          hub: FakeNasHub(searchResults: results),
          llm: ScriptedLlm((req) => n++ == 0
              ? const [
                  TextDelta('The Moon is about 384,400 km from Earth. It has no air, so its sky is always black. '
                      'Its surface is covered in fine dust.'),
                  search,
                  DoneEvent('tool_calls'),
                ]
              : say('The Moon is about 384,400 km from Earth.')),
        );
        final t = await rig.send(null, 'Tell me a fun fact about the moon.', voice: true);
        expect(rig.llm.chatRequests, hasLength(1), reason: 'a voice call said the answer twice');
        expect(rig.hub.searches, isEmpty);
        expect(t.done, startsWith('The Moon is about 384,400 km from Earth. It has no air'));
        expect((await rig.path(t.chatId!)).last.toolCallsJson, isNull);
      });

      test('a short "let me look" before the call still runs the tool', () async {
        var n = 0;
        rig = await ChatRig.create(
          hub: FakeNasHub(searchResults: results),
          llm: ScriptedLlm((req) => n++ == 0 ? const [TextDelta('Let me look that up.'), search, DoneEvent('tool_calls')] : say('The Moon has moonquakes.')),
        );
        final t = await rig.send(null, 'Tell me a fun fact about the moon.');
        expect(rig.hub.searches, ['moon facts']);
        expect(t.done, endsWith('The Moon has moonquakes.'));
      });
    });

    test('a declined tool does not count as a failure', () async {
      var n = 0;
      rig = await ChatRig.create(
        hub: FakeNasHub(failWith: NasException('The NAS does not support this yet.', statusCode: 404)),
        llm: ScriptedLlm((req) => switch (n++) {
              0 => callTool('docker_action', {'name': 'jellyfin', 'action': 'restart'}),
              1 => callTool('docker_list'),
              _ => say('OK, I left Jellyfin alone.'),
            }),
      );
      rig.approve = false;
      final t = await rig.send(null, 'I want to tell you about my Jellyfin app and its settings.');
      expect(rig.llm.chatRequests, hasLength(3));
      expect(t.done, 'OK, I left Jellyfin alone.');
    });

    test('a large model whose tool fails twice is asked to answer without tools', () async {
      var n = 0;
      rig = await ChatRig.create(
        hub: FakeNasHub(failWith: NasException('SearXNG is down.')),
        llm: ScriptedLlm((req) => mustAnswer(req) ? say('Sorry, the search does not work right now.') : callTool('web_search', {'query': 'raspberry pi ${n++}'})),
      );
      final reg = rig.container.read(llmRegistryProvider);
      await reg.updateModel(ChatRig.modelRef, overrides: const ModelOverrides(smallModel: false));
      for (var i = 0; i < 100 && reg.isSmallModel(_model(rig)); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(reg.isSmallModel(_model(rig)), isFalse);
      final t = await rig.send(null, 'I want to tell you about the history of the Raspberry Pi.');
      final reqs = rig.llm.chatRequests;
      expect(reqs.length, 3);
      expect(mustAnswer(reqs[0]), isFalse);
      expect(mustAnswer(reqs[1]), isFalse);
      expect(reqs[2].toolChoice, 'none', reason: 'the second failure forces the answer');
      expect(reqs[2].tools, isNotEmpty, reason: 'same tool list, so the prompt cache stays valid');
      expect(t.done, 'Sorry, the search does not work right now.');
    });

    test('a failed tool result reaches a small model with the error note', () async {
      var n = 0;
      rig = await ChatRig.create(
        // An empty query is the model's mistake: it gets the error and one more round.
        llm: ScriptedLlm((req) => mustAnswer(req) || n++ > 0 ? say('It did not work.') : callTool('web_search', {'query': ''})),
      );
      await rig.send(null, 'I want to tell you about the Raspberry Pi.');
      final second = rig.llm.chatRequests[1];
      final tool = second.messages.lastWhere((m) => m.role == LlmRole.tool);
      expect(tool.isError, isTrue);
      expect(tool.content, endsWith(smallModelErrorNote));
      expect(tool.content, isNot(contains(smallModelAnswerNote)));
    });

    test('a forced answer that is only call markup says which tool failed', () async {
      var n = 0;
      rig = await ChatRig.create(
        hub: FakeNasHub(failWith: NasException('The NAS does not support this yet.', statusCode: 404)),
        // docker_list fails once, then the same call again (a repeat forces the answer), then only markup.
        llm: ScriptedLlm((req) => mustAnswer(req)
            ? say('<tool_call>{"name": "docker_list", "arguments": {}}</tool_call>')
            : n++ < 2
                ? [ToolCallEvent(LlmToolCall(id: 'c$n', name: 'docker_list', argumentsJson: '{}')), const DoneEvent('tool_calls')]
                : say('unused')),
      );
      final t = await rig.send(null, 'I want to tell you about my apps and what they do.');
      expect(t.done, "I couldn't get the list of apps from the NAS: The NAS does not support this yet.");
    });

    test('call markup on the last round becomes an Arabic sentence for an Arabic chat', () async {
      rig = await ChatRig.create(
        hub: FakeNasHub(searchResults: const [
          {'title': 'Raspberry Pi', 'url': 'https://www.raspberrypi.com/about/', 'content': 'Founded in 2009.'},
        ]),
        // The same call twice: the repeat makes the next round answer without tools.
        llm: ScriptedLlm((req) => mustAnswer(req)
            ? say('<tool_call>{"name": "web_search", "arguments": {"query": "x"}}</tool_call>')
            : callTool('web_search', {'query': 'x'})),
      );
      final t = await rig.send(null, 'أريد أن أحدثك عن تاريخ راسبيري باي');
      expect(t.done, endsWith('لم أتمكن من إنهاء ذلك بأدواتي. حاول مرة أخرى أو اسأل بطريقة أخرى.'));
      expect(t.done, isNot(contains('tool_call')));
    });
  });

  test('an explicit language request is not forced back into the language of the message', () async {
    rig = await ChatRig.create(llm: ScriptedLlm((_) => say('مرحبا! كيف حالك اليوم يا صديقي العزيز؟')));
    final t = await rig.send(null, 'Say hello to me in Arabic.');
    expect(rig.llm.chatRequests, hasLength(1), reason: 'no language retry');
    expect(lastUserText(rig.llm.chatRequests.single), isNot(contains('(Reply in English only.)')));
    expect(t.done, 'مرحبا! كيف حالك اليوم يا صديقي العزيز؟');
  });

  test('a chat whose first reply was stopped still gets a title', () async {
    rig = await ChatRig.create(
      llm: ScriptedLlm((req) => lastUserText(req).contains('story') ? [for (var i = 0; i < 40; i++) TextDelta('word$i '), const DoneEvent('stop')] : say('A joke.'),
          delay: const Duration(milliseconds: 20)),
    );
    var stopped = false;
    final first = await rig.send(null, 'Write a long story about a robot.', onText: (t) {
      if (!stopped && t.text.length > 20) {
        stopped = true;
        rig.engine.stop(t.chatId!);
      }
    });
    expect((await rig.path(first.chatId!)).last.status, 'cancelled');
    await rig.send(first.chatId, 'Tell me a joke.');
    var title = '';
    for (var i = 0; i < 100 && title != 'Test title'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      title = (await rig.repo.getChat(first.chatId!))!.title;
    }
    expect(title, 'Test title');
  });

  group('remember that', () {
    test('is saved by the app and confirmed', () async {
      rig = await ChatRig.create();
      final t = await rig.send(null, 'Remember that my cat is called Luna.');
      expect(t.done, "Got it, I'll remember that your cat is called Luna.");
      expect((await rig.db.select(rig.db.memories).get()).single.content, 'my cat is called Luna');
      expect(rig.llm.chatRequests, isEmpty);
    });

    test('"tell me ..." is a request, not something about the user (no extraction call on a Pi)', () {
      expect(mentionsSelf('Tell me a fun fact about the moon.'), isFalse);
      expect(mentionsSelf('Give me one more, please.'), isFalse);
      expect(mentionsSelf('Call me Sam.'), isTrue);
      expect(mentionsSelf('I have two cats.'), isTrue);
      expect(mentionsSelf('اسمي سامي'), isTrue);
    });

    test('with memory switched off nothing is saved and the reply says so', () async {
      rig = await ChatRig.create();
      await rig.db.setSetting('memory_enabled', 'false');
      final t = await rig.send(null, 'Remember that my cat is called Luna.');
      expect(t.done, "Memory is turned off, so I can't save that. You can turn it on in Settings > Memory.");
      expect(await rig.db.select(rig.db.memories).get(), isEmpty);
    });
  });

  group('compaction', () {
    test('too little conversation is not reported as a failure and does not block the next try', () async {
      rig = await ChatRig.create(
        contextWindow: 2048,
        llm: ScriptedLlm((_) => [const TextDelta('ok'), const UsageEvent(promptTokens: 1500, completionTokens: 1), const DoneEvent('stop')]),
      );
      await rig.db.setSetting('auto_compact_threshold', '0.5');
      final first = await rig.send(null, 'Tell me about llamas, please, in one short line.');
      final id = first.chatId!;
      final assembler = rig.container.read(nurContextAssemblerProvider);
      final model = _model(rig);
      await expectLater(assembler.compact(chatId: id, model: model), throwsA(isA<StateError>()));
      expect((await assembler.watchInfo(id).first).lastError, isNull);

      await rig.send(id, 'And about alpacas, also in one short line.');
      var summary = false;
      for (var i = 0; i < 150 && !summary; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        summary = (await rig.repo.messages(id)).any((m) => m.kind == 'summary');
      }
      expect(summary, isTrue, reason: 'auto compaction runs on the second turn');
    });

    test('each summary request fits a small window', () async {
      rig = await ChatRig.create(contextWindow: 2048, llm: ScriptedLlm((_) => say('ok')));
      await rig.db.setSetting('auto_compact_enabled', 'false');
      String? id;
      // About 490 tokens per message: with the old fixed 1500-token chunks three of them plus the prompt and the
      // summary budget overflow a 2048-token window.
      final long = List.filled(45, 'words about the garden and the weather').join(' ');
      for (var i = 0; i < 6; i++) {
        id = (await rig.send(id, '$i $long')).chatId;
      }
      await rig.container.read(nurContextAssemblerProvider).compact(chatId: id!, model: _model(rig));
      final summaries = rig.llm.requests.where((r) => r.messages.first.content.startsWith('You compress a conversation')).toList();
      expect(summaries, isNotEmpty);
      for (final r in summaries) {
        final prompt = r.messages.fold<int>(0, (a, m) => a + (m.content.length / 3.6).ceil() + 4);
        expect(prompt + (r.maxTokens ?? 0), lessThanOrEqualTo(2048));
      }
    });
  });

  group('stop while a tool runs', () {
    test('a planned NAS check that hangs ends at once', () async {
      final hang = Completer<void>();
      rig = await ChatRig.create(hub: FakeNasHub(wait: hang.future));
      final sw = Stopwatch()..start();
      final t = await rig.send(null, 'How is my NAS doing?', onTool: (t) => rig.engine.stop(t.chatId!));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)), reason: 'the reply stayed busy until the NAS answered');
      expect(t.errors, isEmpty);
      expect(rig.engine.isBusy(t.chatId!), isFalse);
      final last = (await rig.path(t.chatId!)).last;
      expect(last.role, 'tool');
      expect(last.content, 'Cancelled by the user.');
      expect(rig.llm.chatRequests, isEmpty);
      hang.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await rig.path(t.chatId!)).last.content, 'Cancelled by the user.', reason: 'a late result is dropped');
    });

    test('a tool the model called ends at once and the model is not asked again', () async {
      final hang = Completer<void>();
      rig = await ChatRig.create(hub: FakeNasHub(wait: hang.future), llm: ScriptedLlm((req) => callTool('docker_list')));
      final sw = Stopwatch()..start();
      final t = await rig.send(null, 'I want to tell you about my apps and what they do.', onTool: (t) => rig.engine.stop(t.chatId!));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(rig.llm.chatRequests, hasLength(1));
      expect(rig.engine.isBusy(t.chatId!), isFalse);
      hang.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('an approval given after the stop does not run the action', () async {
      final decide = Completer<bool>();
      rig = await ChatRig.create(llm: ScriptedLlm((req) => callTool('docker_action', {'name': 'jellyfin', 'action': 'restart'})));
      rig.container.read(toolApprovalBrokerProvider).register((_) => decide.future);
      await rig.send(null, 'I want to tell you about my Jellyfin app and its settings.', onTool: (t) => rig.engine.stop(t.chatId!));
      decide.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.hub.actions, isEmpty);
    });
  });

  test('a reply cut off by the length limit is kept and marked', () async {
    rig = await ChatRig.create(llm: ScriptedLlm((_) => const [TextDelta('The Raspberry Pi 5 has a quad-core'), DoneEvent('length')]));
    final t = await rig.send(null, 'Write a very long essay about the Raspberry Pi.');
    expect(t.errors, isEmpty);
    final last = (await rig.path(t.chatId!)).last;
    expect(last.status, 'done');
    expect(last.content, 'The Raspberry Pi 5 has a quad-core');
    expect(last.errorText, cutOffNote);
  });

  test('the local time is not added just because a message says "now"', () {
    expect(wantsTime('Now say hello in Arabic.'), isFalse);
    expect(wantsTime('What time is it now?'), isTrue);
    expect(wantsTime('What day is it today?'), isTrue);
  });
}

LlmModel _model(ChatRig rig) => rig.container.read(llmRegistryProvider).modelByRef(ChatRig.modelRef)!;
