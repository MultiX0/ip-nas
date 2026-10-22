import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/chat_engine.dart';
import 'package:nur/features/providers/foreground_gate.dart';
import 'package:nur/features/voice/voice_call_controller.dart';
import 'package:nur/features/voice/voice_fillers.dart';
import 'package:nur/features/voice/voice_prefs.dart';

import 'fakes/voice_fakes.dart';

void main() {
  late FakeMic mic;
  late FakeAudio audio;
  late FakeFish fish;
  late FakeEngine engine;
  late Directory cache;
  late VoiceCallController c;

  setUp(() {
    mic = FakeMic();
    audio = FakeAudio(mic);
    fish = FakeFish();
    engine = FakeEngine();
    cache = Directory.systemTemp.createTempSync('nur_fillers');
    c = VoiceCallController(
      engine: engine,
      fish: fish,
      prefs: () => const VoicePrefs(apiKey: 'test-key'),
      audio: audio,
      fillers: VoiceFillers(fish, cacheDir: () async => cache),
    );
  });

  tearDown(() {
    c.dispose();
    try {
      cache.deleteSync(recursive: true);
    } catch (_) {}
  });

  String st() =>
      'phase ${c.phase}, status ${c.status}, sent ${engine.sent}, stops ${engine.stops}, players ${audio.players.length}, '
      'playing ${audio.last?.playing}, caption "${c.assistantCaption}", mic ${mic.starts}/${mic.stops}';

  /// One spoken question: [ms] of speech, then enough silence for the VAD to end it.
  Future<void> ask({int ms = 400}) async {
    await mic.say(ms, 6000);
    await mic.say(600, 0);
  }

  test('a retry after a microphone error does not leave the old stream open', () async {
    await c.start();
    expect(c.phase, CallPhase.listening);
    mic.fail(Exception('device gone'));
    await waitFor(() => c.error != null, state: st);

    await c.start();
    expect(mic.starts, 2);
    expect(mic.stops, 1);
    expect(c.error, isNull);
    expect(c.phase, CallPhase.listening);
  });

  test('closing the call while it connects never opens the microphone', () async {
    fish.validateDelay = const Duration(milliseconds: 150);
    final starting = c.start();
    await c.end();
    await starting;
    expect(mic.starts, 0);
  });

  test('a filler leaking from the speaker into the mic does not interrupt Nur', () async {
    fish.restPcm = voicePcm(800);
    fish.heard.add('How is my NAS?');
    engine.replies.add(FakeReply([const ReplyText('Your NAS is healthy.'), const ReplyDone('Your NAS is healthy.')], gap: const Duration(milliseconds: 1500)));
    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 100)); // fillers cached
    await ask();
    await waitFor(() => audio.last?.playing ?? false, state: st);

    // The filler plays while the model thinks, and the room picks it up.
    for (var i = 0; i < 30; i++) {
      mic.push(pcm16(20, 1500));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await waitFor(() => engine.sent.length == 1 && c.phase == CallPhase.listening && c.assistantCaption.isNotEmpty, state: st);
    expect(engine.stops, 0);
    expect(fish.sessions.first.texts.join(), contains('Your NAS is healthy.'));
    expect(c.status, isNull);
  });

  test('captions follow the answer, not the filler in front of it', () async {
    fish.restPcm = voicePcm(1000);
    fish.autoAudio = false;
    fish.heard.add('How is my NAS?');
    engine.replies.add(FakeReply([const ReplyText('Your NAS is healthy and cool.'), const ReplyDone('Your NAS is healthy and cool.')], gap: const Duration(milliseconds: 900)));
    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await ask();
    await waitFor(() => audio.last?.playing ?? false, state: st);
    final player = audio.last!;

    player.played = 800; // still inside the 1 s filler
    await waitFor(() => c.assistantCaption.isNotEmpty, state: st);
    expect(c.revealedWords, 0);

    fish.sessions.single.emit(voicePcm(600));
    await waitFor(() => c.phase == CallPhase.speaking, state: st);
    player.played = 1000 + 400; // 400 ms into the answer
    expect(c.revealedWords, 2);
  });

  test('a question asked right after a barge-in waits for the cut-off reply', () async {
    fish.heard.addAll(['Tell me a long story.', 'What time is it?']);
    engine.replies.add(FakeReply([
      for (var i = 0; i < 40; i++) ReplyText('Part $i of the story. '),
      const ReplyDone('...'),
    ], gap: const Duration(milliseconds: 100), closeAfterStop: const Duration(milliseconds: 1500)));
    engine.replies.add(FakeReply([const ReplyText('It is noon.'), const ReplyDone('It is noon.')]));
    await c.start();
    await ask();
    await waitFor(() => c.phase == CallPhase.speaking, state: st);

    await mic.say(1200, 0); // the mic keeps running while Nur talks (echo cancelled to silence)
    await ask(); // talks over Nur, then asks something else
    await waitFor(() => engine.sent.length == 2, timeout: const Duration(seconds: 8), state: st);
    await waitFor(() => c.assistantCaption.contains('noon'), state: st);
    expect(engine.stops, greaterThanOrEqualTo(1));
    expect(c.status, isNull);
  });

  test('a short pause in the middle of a question does not lose its first part', () async {
    fish.asrDelay = const Duration(milliseconds: 400);
    fish.heard.add('Can you check how much space is left?');
    engine.replies.add(FakeReply([const ReplyText('Plenty.'), const ReplyDone('Plenty.')]));
    await c.start();
    await mic.say(500, 6000); // "Can you check..."
    await mic.say(600, 0); // long enough for the VAD to end the utterance
    await waitFor(() => c.phase == CallPhase.thinking, state: st);
    await mic.say(700, 6000); // "...how much space is left?"
    await mic.say(600, 0);
    await waitFor(() => engine.sent.length == 1, state: st);

    // The first transcription was cut off; the second one got both parts.
    expect(fish.asrBytes, hasLength(2));
    expect(fish.asrBytes.last, greaterThan(fish.asrBytes.first + 700 * 32));
    expect(engine.sent.single, 'Can you check how much space is left?');
  });

  test('a pause just after the transcript came back still makes one question', () async {
    fish.heard.addAll(['Can you check', 'Can you check how much space is left?']);
    engine.replies.add(FakeReply([const ReplyText('Plenty.'), const ReplyDone('Plenty.')]));
    await c.start();
    await mic.say(500, 6000);
    await mic.say(600, 0);
    await waitFor(() => c.phase == CallPhase.thinking, state: st);
    await Future<void>.delayed(const Duration(milliseconds: 150)); // the first transcript is already back
    await mic.say(700, 6000);
    await mic.say(600, 0);
    await waitFor(() => engine.sent.isNotEmpty && c.phase == CallPhase.listening, state: st);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.sent, ['Can you check how much space is left?']);
  });

  test('a question picked up again after it reached the chat engine goes out whole', () async {
    fish.heard.addAll(['Can you check', 'how much space is left?']);
    engine.replies.add(FakeReply([const ReplyText('Checking.'), const ReplyDone('Checking.')], gap: const Duration(milliseconds: 1500)));
    engine.replies.add(FakeReply([const ReplyText('Plenty.'), const ReplyDone('Plenty.')]));
    await c.start();
    await ask(ms: 500);
    await waitFor(() => engine.sent.length == 1, state: st); // the first part went out
    await ask(ms: 700); // and the user goes on before Nur answers
    await waitFor(() => engine.sent.length == 2, state: st);
    expect(engine.sent.last, 'Can you check how much space is left?');
    expect(engine.stops, greaterThanOrEqualTo(1));
  });

  test('a short noise while Nur thinks does not lose the question', () async {
    fish.heard.add('What time is it?');
    engine.replies.add(FakeReply([const ReplyText('Noon.'), const ReplyDone('Noon.')], gap: const Duration(milliseconds: 1500)));
    engine.replies.add(FakeReply([const ReplyText('It is noon.'), const ReplyDone('It is noon.')]));
    await c.start();
    await ask();
    await waitFor(() => engine.sent.length == 1, state: st);
    await mic.say(160, 6000); // a door slams
    await mic.say(600, 0);
    await waitFor(() => engine.sent.length == 2, state: st);
    expect(engine.sent.last, 'What time is it?');
  });

  test('an answer that breaks off ends with a short apology, not half a sentence', () async {
    fish.heard.add('Tell me a story.');
    engine.replies.add(FakeReply([
      const ReplyText('Here is the story. A robot named Leo loved gadgets but'),
      const ReplyError('The model stopped.'),
      const ReplyDone('Here is the story. A robot named Leo loved gadgets but'),
    ]));
    await c.start();
    await ask();
    await waitFor(() => engine.sent.length == 1 && c.phase == CallPhase.listening && c.status != null, state: st);
    final said = fish.sessions.first.texts.join();
    expect(said, contains('Here is the story.'));
    expect(said, isNot(contains('loved gadgets')));
    expect(said, contains('Sorry, something went wrong on my side.'));
    expect(c.status, 'The model stopped.');
    expect(c.assistantCaption, endsWith('Please ask me again.'));
  });

  test('the model is warmed once per call, not after every answer', () async {
    fish.heard.addAll(['Hi.', 'How are you?']);
    engine.replies.add(FakeReply([const ReplyText('Hello.'), const ReplyDone('Hello.')]));
    engine.replies.add(FakeReply([const ReplyText('Fine.'), const ReplyDone('Fine.')]));
    await c.start();
    await ask();
    await waitFor(() => engine.sent.length == 1 && c.phase == CallPhase.listening, state: st);
    await ask();
    await waitFor(() => engine.sent.length == 2 && c.phase == CallPhase.listening, state: st);
    expect(engine.prewarms, 1);
  });

  test('the call keeps background model work waiting until it ends', () async {
    final gate = ForegroundGate();
    final call = VoiceCallController(engine: engine, fish: fish, prefs: () => const VoicePrefs(apiKey: 'k'), gate: gate, audio: FakeAudio(FakeMic()));
    await call.start();
    expect(gate.isHeld, isTrue);
    var titled = false;
    final title = gate.background((_) async => titled = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(titled, isFalse);
    await call.end();
    await title;
    expect(titled, isTrue);
    expect(gate.isHeld, isFalse);
    call.dispose();
  });

  test('pause turns the mic and the warm socket off, resume brings them back', () async {
    await c.start();
    final warm = fish.sessions.single;
    await c.pause();
    expect(c.paused, isTrue);
    expect(mic.stops, 1);
    expect(warm.cancelled, isTrue);
    expect(c.micLevel, 0);

    await c.resume();
    expect(c.paused, isFalse);
    expect(mic.starts, 2);
    expect(fish.sessions.length, 2);
    expect(c.phase, CallPhase.listening);
  });

  test('backgrounded while connecting: the mic opens only after resume', () async {
    fish.validateDelay = const Duration(milliseconds: 150);
    final starting = c.start();
    await c.pause();
    await starting;
    expect(c.phase, CallPhase.listening);
    expect(mic.starts, 0);
    await c.resume();
    expect(mic.starts, 1);
  });

  test('an empty reply says so, an error keeps its own message', () async {
    fish.heard.addAll(['Hello?', 'Again?']);
    engine.replies.add(FakeReply([const ReplyDone('')]));
    engine.replies.add(FakeReply([const ReplyError('The model stopped.'), const ReplyDone('')]));
    await c.start();

    await ask();
    await waitFor(() => engine.sent.length == 1 && c.phase == CallPhase.listening && c.status != null, state: st);
    expect(c.status, noAnswerMessage);

    await ask();
    await waitFor(() => engine.sent.length == 2 && c.phase == CallPhase.listening && c.status != null, state: st);
    expect(c.status, 'The model stopped.');
  });
}
