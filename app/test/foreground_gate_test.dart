// The foreground gate: background model calls (chat titles, memory extraction, automatic summaries) wait while a
// reply or a voice call holds the model, and a running one stops when the gate is taken. On a Pi the llama.cpp
// server has one slot, so a title or a summary in front of a voice turn made it wait 10-45 s.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/features/providers/foreground_gate.dart';

import 'helpers/chat_fakes.dart';

bool _isTitle(LlmRequest r) => r.messages.isNotEmpty && r.messages.first.content.startsWith('You name chats');
bool _isMemory(LlmRequest r) => r.messages.isNotEmpty && r.messages.first.content.startsWith('You maintain the long-term memory');

/// Records background requests that were stopped.
class _RecordingLlm extends ScriptedLlm {
  _RecordingLlm(super.reply, {super.delay, super.prewarm});
  var cancelledTitles = 0;
  var cancelledPrewarms = 0;

  @override
  Stream<LlmEvent> chat(LlmRequest request, {LlmCancelToken? cancel}) async* {
    await for (final e in super.chat(request, cancel: cancel)) {
      if (e is DoneEvent && e.finishReason == 'cancelled' && _isTitle(request)) cancelledTitles++;
      if (e is DoneEvent && e.finishReason == 'cancelled' && request.maxTokens == 1) cancelledPrewarms++;
      yield e;
    }
  }
}

Future<void> _until(bool Function() done, {int tries = 150}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('gate', () {
    test('background work waits while a lease is held and runs after the release', () async {
      final gate = ForegroundGate();
      final lease = gate.hold();
      var ran = false;
      final f = gate.background((_) async => ran = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ran, isFalse);
      lease.release();
      expect(await f, isTrue);
    });

    test('taking the gate stops a running background call', () async {
      final gate = ForegroundGate();
      final started = Completer<void>();
      final f = gate.background((cancel) async {
        started.complete();
        while (!cancel.isCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        return 'half a title';
      });
      await started.future;
      expect(gate.runningBackground, 1);
      final lease = gate.hold();
      await expectLater(f, throwsA(isA<BackgroundCancelled>()));
      expect(gate.runningBackground, 0);
      lease.release();
    });

    test('leases are counted and releasing twice does nothing', () async {
      final gate = ForegroundGate();
      final a = gate.hold(), b = gate.hold();
      a.release();
      a.release();
      expect(gate.isHeld, isTrue);
      b.release();
      expect(gate.isHeld, isFalse);
      await gate.whenFree().timeout(const Duration(seconds: 1));
    });
  });

  group('with the chat engine', () {
    late ChatRig rig;
    tearDown(() async => rig.dispose());

    test('a chat title waits for the end of a voice call', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((_) => say('Llamas are camelids from South America.')));
      final call = rig.container.read(foregroundGateProvider).hold();
      final t = await rig.send(null, 'Tell me about llamas.');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(rig.llm.requests.where(_isTitle), isEmpty, reason: 'no title request while the call holds the model');
      expect((await rig.repo.getChat(t.chatId!))!.title, 'New chat');
      call.release();
      var title = '';
      for (var i = 0; i < 150 && title != 'Test title'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        title = (await rig.repo.getChat(t.chatId!))!.title;
      }
      expect(title, 'Test title');
    });

    test('a running title request stops when the next reply starts, and the chat is named after it', () async {
      final llm = _RecordingLlm((_) => say('Noted.'), delay: const Duration(milliseconds: 120));
      rig = await ChatRig.create(llm: llm);
      final a = await rig.send(null, 'Tell me about llamas.');
      // The title request starts right after the first reply.
      await _until(() => rig.llm.requests.any(_isTitle));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await rig.send(a.chatId, 'And alpacas?');
      expect(llm.cancelledTitles, 1);
      var name = (await rig.repo.getChat(a.chatId!))!.title;
      for (var i = 0; i < 150 && name != 'Test title'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        name = (await rig.repo.getChat(a.chatId!))!.title;
      }
      expect(name, 'Test title');
      expect(rig.llm.requests.where(_isTitle), hasLength(2));
    });

    test('a prewarm still running stops when a reply starts', () async {
      final llm = _RecordingLlm(
        (req) => say('Llamas hum to talk.'),
        prewarm: (req) => [for (var i = 0; i < 200; i++) const TextDelta('.'), const DoneEvent('stop')],
        delay: const Duration(milliseconds: 10),
      );
      rig = await ChatRig.create(llm: llm);
      unawaited(rig.engine.prewarm(null, fromVoiceCall: true));
      await _until(() => rig.llm.requests.any(ScriptedLlm.isPrewarm));
      final t = await rig.send(null, 'Tell me a short fact about llamas.');
      expect(t.done, 'Llamas hum to talk.');
      expect(llm.cancelledPrewarms, greaterThanOrEqualTo(1), reason: 'the first question of a call queued behind a 30-40 s prewarm');
    });

    test('after the title call the chat prompt is read in again, once', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((_) => say('Llamas hum to talk.')));
      final t = await rig.send(null, 'Tell me a short fact about llamas.');
      await _until(() => rig.llm.requests.any(ScriptedLlm.isPrewarm));
      final title = rig.llm.requests.indexWhere(_isTitle);
      final warm = rig.llm.requests.indexWhere(ScriptedLlm.isPrewarm);
      expect(title, greaterThanOrEqualTo(0));
      expect(warm, greaterThan(title), reason: 'the title replaced the cached chat prompt on a one-slot server');
      expect(lastUserText(rig.llm.requests[warm]), isNot(contains('llamas')), reason: 'the prefix of the next turn');
      expect(rig.llm.requests.where(ScriptedLlm.isPrewarm), hasLength(1));
      expect(rig.engine.isBusy(t.chatId!), isFalse);
    });

    test('a voice turn is not read in again after the call', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((_) => say('Llamas hum to talk.')));
      await rig.send(null, 'Tell me a short fact about llamas.', voice: true);
      await _until(() => rig.llm.requests.any(_isTitle));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(rig.llm.requests.where(ScriptedLlm.isPrewarm), isEmpty);
    });

    test('memory extraction waits for the end of the call and then reads every message of it', () async {
      rig = await ChatRig.create(llm: ScriptedLlm((_) => say('Nice.')));
      final call = rig.container.read(foregroundGateProvider).hold();
      final a = await rig.send(null, 'I have two cats called Luna and Milo.');
      await rig.send(a.chatId, 'My brother lives in Amman.');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(rig.llm.requests.where(_isMemory), isEmpty);
      call.release();
      await _until(() => rig.llm.requests.any(_isMemory));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final memory = rig.llm.requests.where(_isMemory).toList();
      expect(memory, hasLength(1));
      final prompt = memory.single.messages.last.content;
      expect(prompt, contains('Luna and Milo'));
      expect(prompt, contains('Amman'));
    });

    test('an automatic summary waiting for the model does not hold up the next reply', () async {
      rig = await ChatRig.create(
        contextWindow: 2048,
        llm: ScriptedLlm((_) => [const TextDelta('ok'), const UsageEvent(promptTokens: 1800, completionTokens: 1), const DoneEvent('stop')]),
      );
      await rig.db.setSetting('auto_compact_threshold', '0.5');
      final call = rig.container.read(foregroundGateProvider).hold();
      final first = await rig.send(null, 'Tell me about llamas, please, in one short line.');
      await rig.send(first.chatId, 'And about alpacas, also in one short line.');
      // The third reply would have waited up to 3 minutes for the summary, which waits for the call to end.
      final third = await rig.send(first.chatId, 'And about camels?').timeout(const Duration(seconds: 5));
      expect(third.done, 'ok');
      call.release();
      var summary = false;
      for (var i = 0; i < 150 && !summary; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        summary = (await rig.repo.messages(first.chatId!)).any((m) => m.kind == 'summary');
      }
      expect(summary, isTrue, reason: 'the summary runs once the call is over');
    });
  });
}
