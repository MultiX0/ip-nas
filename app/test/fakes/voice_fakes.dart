// Network-free stand-ins for the voice call: microphone, player, Fish Audio and the chat engine.
import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:nur/core/contracts/chat_engine.dart';
import 'package:nur/features/voice/audio_engine.dart';
import 'package:nur/features/voice/fish_audio.dart';

/// 16 kHz PCM16 square wave, [ms] long ([amp] 0 is silence).
Uint8List pcm16(int ms, int amp) {
  final n = 16 * ms;
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    b.setInt16(i * 2, i.isEven ? amp : -amp, Endian.little);
  }
  return b.buffer.asUint8List();
}

/// 44.1 kHz PCM16 of [ms] (what Fish sends back).
Uint8List voicePcm(int ms) => Uint8List(441 * ms ~/ 10 * 2);

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 5), String Function()? state}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('condition not met${state == null ? '' : ': ${state()}'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class FakeMic implements MicStream {
  int starts = 0, stops = 0;
  bool disposed = false;
  bool permission = true;
  StreamController<Uint8List>? _out;

  bool get open => _out != null && !_out!.isClosed && _out!.hasListener;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    final out = _out = StreamController<Uint8List>();
    return out.stream;
  }

  void push(Uint8List chunk) {
    final out = _out;
    if (out != null && !out.isClosed) out.add(chunk);
  }

  void fail(Object e) => _out?.addError(e);

  /// [ms] of audio in 20 ms chunks, one chunk every [every].
  Future<void> say(int ms, int amp, {Duration every = Duration.zero}) async {
    for (var t = 0; t < ms; t += 20) {
      push(pcm16(20, amp));
      await Future<void>.delayed(every);
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    await _out?.close();
    _out = null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}

class FakePlayer implements PcmStreamPlayer {
  FakePlayer({this.onStarted});

  @override
  final VoidCallback? onStarted;
  @override
  int get sampleRate => fishSampleRate;

  final chunks = <Uint8List>[];
  int _bytes = 0;
  bool _ended = false, _stopped = false;
  final _finished = Completer<void>();

  /// Set by the test to move the playback position.
  double played = 0;

  @override
  Future<void> get finished => _finished.future;
  @override
  bool get playing => chunks.isNotEmpty && !_stopped && !_finished.isCompleted;
  @override
  bool get ended => _ended;
  @override
  double get queuedMs => _bytes / 2 / sampleRate * 1000;
  @override
  double get playedMs => played;
  /// Output RMS the test wants the VAD to see.
  double outRms = 0.1;

  @override
  double get rms => playing ? outRms : 0;
  @override
  double get level => playing ? 0.5 : 0;

  @override
  Future<void> start() async {}

  @override
  void add(Uint8List chunk) {
    if (_stopped || chunk.isEmpty) return;
    if (chunks.isEmpty) onStarted?.call();
    chunks.add(chunk);
    _bytes += chunk.length;
  }

  @override
  void end() {
    _ended = true;
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    if (!_finished.isCompleted) _finished.complete();
  }
}

class FakeAudio extends CallAudio {
  FakeAudio(this.fakeMic);
  final FakeMic fakeMic;
  final players = <FakePlayer>[];

  FakePlayer? get last => players.isEmpty ? null : players.last;

  @override
  MicStream mic() => fakeMic;
  @override
  PcmStreamPlayer player({VoidCallback? onStarted}) {
    final p = FakePlayer(onStarted: onStarted);
    players.add(p);
    return p;
  }

  @override
  Future<void> ready() async {}
}

class FakeLiveTts implements FishLiveTts {
  final texts = <String>[];
  int stops = 0;
  bool cancelled = false;
  final _audio = StreamController<Uint8List>();
  final _done = Completer<void>();

  /// Send audio as soon as text arrives (else the test calls [emit]).
  bool autoAudio = true;

  @override
  Stream<Uint8List> get audio => _audio.stream;
  @override
  Future<void> get done => _done.future;
  @override
  bool get isClosed => _done.isCompleted;

  void emit(Uint8List chunk) {
    if (!_audio.isClosed) _audio.add(chunk);
  }

  @override
  void text(String t) {
    texts.add(t);
    if (autoAudio) emit(voicePcm(300));
  }

  @override
  void flush() {}

  @override
  void stop() {
    stops++;
    if (_done.isCompleted) return;
    _done.complete();
    _audio.close();
  }

  @override
  void cancel() {
    cancelled = true;
    if (!_done.isCompleted) _done.complete();
    _audio.close();
  }
}

class FakeFish extends FishAudio {
  FakeFish() : super('test-key');

  /// What the next utterances "said", in order; '' once the list is used up.
  final heard = <String>[];
  final sessions = <FakeLiveTts>[];
  Duration validateDelay = Duration.zero;
  bool autoAudio = true;

  /// PCM for REST requests (the fillers), or null to fail them.
  Uint8List? restPcm;

  /// Size of every audio file sent to speech to text, and how long each transcription takes.
  final asrBytes = <int>[];
  Duration asrDelay = Duration.zero;

  @override
  Future<void> validateKey() => Future<void>.delayed(validateDelay);

  @override
  Future<AsrResult> transcribe(Uint8List audio, {String filename = 'speech.wav', String? language, String model = 'transcribe-1-pro', CancelToken? cancel}) async {
    asrBytes.add(audio.length);
    if (asrDelay > Duration.zero) {
      await Future.any([Future<void>.delayed(asrDelay), if (cancel != null) cancel.whenCancel]);
      if (cancel?.isCancelled ?? false) throw FishException('Cancelled.');
    }
    return AsrResult(heard.isEmpty ? '' : heard.removeAt(0));
  }

  @override
  Future<FishLiveTts> openLive({String? voiceId, String model = 'drama-3', String latency = 'balanced', double speed = 1.0}) async {
    final s = FakeLiveTts()..autoAudio = autoAudio;
    sessions.add(s);
    return s;
  }

  @override
  Stream<Uint8List> tts(String text, {String? voiceId, String model = 'drama-3', String format = 'pcm', String latency = 'balanced', double speed = 1.0, CancelToken? cancel}) async* {
    final pcm = restPcm;
    if (pcm == null) throw FishException('no network in tests');
    yield pcm;
  }
}

/// One scripted reply: [events] are sent in order with [gap] between them.
class FakeReply {
  FakeReply(this.events, {this.gap = const Duration(milliseconds: 20), this.closeAfterStop = Duration.zero});
  final List<ReplyEvent> events;
  final Duration gap;

  /// How long the engine takes to wrap up a reply that was stopped.
  final Duration closeAfterStop;
}

/// Chat engine stand-in with the real engine's rule: one reply at a time per chat.
class FakeEngine implements ChatEngine {
  final replies = <FakeReply>[];
  final sent = <String>[];
  int stops = 0;
  bool _busy = false;
  Completer<void>? _stop;

  @override
  Stream<ReplyEvent> send(String? chatId, UserInput input, {void Function(String chatId)? onChatId}) {
    final out = StreamController<ReplyEvent>.broadcast();
    Future<void>(() async {
      onChatId?.call(chatId ?? 'chat1');
      if (_busy) {
        out.add(const ReplyError('A reply is still being written. Stop it first.'));
        await out.close();
        return;
      }
      sent.add(input.text);
      _busy = true;
      final stop = _stop = Completer<void>();
      final r = replies.isEmpty ? FakeReply([const ReplyDone('')]) : replies.removeAt(0);
      for (final e in r.events) {
        await Future.any([Future<void>.delayed(r.gap), stop.future]);
        if (stop.isCompleted) {
          await Future<void>.delayed(r.closeAfterStop);
          break;
        }
        out.add(e);
      }
      _busy = false;
      await out.close();
    });
    return out.stream;
  }

  @override
  void stop(String chatId) {
    stops++;
    final s = _stop;
    if (s != null && !s.isCompleted) s.complete();
  }

  int prewarms = 0;

  @override
  Future<void> prewarm(String? chatId, {bool fromVoiceCall = false}) async => prewarms++;
}
