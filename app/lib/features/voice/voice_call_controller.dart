// Turn-taking of a voice call. An energy VAD cuts the mic stream into utterances, Fish ASR turns each one into
// text, ChatEngine.send (fromVoiceCall) answers, and the reply goes sentence by sentence into live Drama 3 TTS and
// SoLoud playback. When the user talks while Nur is thinking or speaking (barge-in), TTS and playback stop and the
// reply is cancelled.
//
// Latency: a live TTS socket is opened ("warm") as soon as the call starts and again after every turn, so a reply
// never waits for a WebSocket handshake. The first clause goes out early and playback starts on the first PCM
// chunk. Debug builds log the time to first audio of every turn.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/contracts/chat_engine.dart';
import '../../core/utils/text_dir.dart';
import 'audio_engine.dart';
import 'call_view_model.dart';
import 'fish_audio.dart';
import 'voice_fillers.dart';
import 'speech_text.dart';
import 'voice_prefs.dart';

export 'call_view_model.dart' show CallPhase, ToolKind;

enum _Reveal { all, live, frozen }

class VoiceCallController extends ChangeNotifier implements CallViewModel {
  VoiceCallController({required this.engine, required this.fish, required this.prefs, this.chatId});

  final ChatEngine engine;
  final FishAudio fish;
  late final VoiceFillers _fillers = VoiceFillers(fish);

  /// Read at the start of every turn so voice changes during the call apply to the next answer.
  final VoicePrefs Function() prefs;
  String? chatId;

  @override
  CallPhase phase = CallPhase.connecting;
  @override
  String userCaption = '';
  @override
  String assistantCaption = '';
  @override
  String? status;
  @override
  String? tool;
  @override
  ToolKind? toolKind;
  @override
  String? error;
  @override
  bool errorNeedsSettings = false;
  @override
  bool errorNeedsPermission = false;
  @override
  bool muted = false;
  @override
  int? lastTtfaMs;

  final _mic = MicStream();
  final _vad = EnergyVad();
  StreamSubscription<Uint8List>? _micSub;
  double _micLevel = 0;

  int _turn = 0;
  bool _replyRunning = false;
  StreamSubscription<ReplyEvent>? _replySub;
  FishLiveTts? _tts;
  PcmStreamPlayer? _player;
  CancelToken? _asrCancel;
  String _assistantRaw = '';
  Timer? _notifyTimer;
  bool _disposed = false;
  bool _ending = false;

  // Warm TTS socket for the next turn.
  Future<FishLiveTts>? _warm;
  String? _warmKey;
  int _rewarms = 0;

  // Caption reveal.
  _Reveal _reveal = _Reveal.all;
  int _captionWords = 0;
  int _revealMax = 0;
  PcmStreamPlayer? _revealPlayer;
  bool _ttsDone = false;
  double _msPerWordGuess = 360;

  // Turn timing (debug).
  Stopwatch? _turnClock;
  int? _tAsr, _tToken;

  @override
  double get micLevel => muted ? 0 : _micLevel;
  @override
  double get outLevel => _player?.level ?? 0;

  @override
  int get revealedWords {
    switch (_reveal) {
      case _Reveal.all:
        return _captionWords;
      case _Reveal.frozen:
        return math.min(_revealMax, _captionWords);
      case _Reveal.live:
        final pl = _revealPlayer;
        if (pl == null) return math.min(_revealMax, _captionWords);
        final played = pl.playedMs;
        if (played <= 0) return 0;
        // Once the whole reply is synthesised, the real pace is known.
        final perWord = (_ttsDone && pl.ended && _captionWords > 0) ? math.max(120.0, pl.queuedMs / _captionWords) : _msPerWordGuess;
        final n = math.min(_captionWords, (played / perWord).ceil());
        if (n > _revealMax) _revealMax = n;
        return _revealMax;
    }
  }

  void _setCaption(String text) {
    assistantCaption = text;
    _captionWords = captionWordCount(text);
  }

  void _notify({bool now = false}) {
    if (_disposed) return;
    if (now) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      notifyListeners();
      return;
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _setPhase(CallPhase p) {
    if (phase == p) return;
    phase = p;
    _notify(now: true);
  }

  static void _log(String m) {
    if (kDebugMode) debugPrint('[voice] $m');
  }

  Future<void> start() async {
    error = null;
    errorNeedsSettings = false;
    errorNeedsPermission = false;
    _setPhase(CallPhase.connecting);
    final clock = Stopwatch()..start();
    // Open the first TTS socket right away, in parallel with permission + key checks.
    _warmUp();
    // Short spoken fillers for this voice (cached on disk after the first call).
    final fp = prefs();
    unawaited(_fillers.prepare(voiceId: fp.voiceId, model: fp.model, speed: fp.speed).catchError((Object _) {}));
    // Warm the model too: load it and fill llama.cpp's prompt cache with the voice prompt + tools + history while the
    // user is still speaking, so the first reply only has to read the new words (a Pi reads ~40 tokens/s).
    unawaited(engine.prewarm(chatId, fromVoiceCall: true).catchError((Object _) {}));
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final st = await Permission.microphone.request();
        if (!st.isGranted) {
          errorNeedsPermission = true;
          throw FishException(
            st.isPermanentlyDenied
                ? 'Nur needs the microphone for voice calls. Turn it on in the app settings.'
                : 'Nur needs the microphone for voice calls. Allow it and try again.',
          );
        }
      } else if (!await _mic.hasPermission()) {
        errorNeedsPermission = true;
        throw FishException('Nur cannot use the microphone. Allow microphone access in your system settings.');
      }
      await Future.wait([fish.validateKey(), AudioEngine.ensure()]);
      final stream = await _mic.start();
      _micSub = stream.listen(_onMic, onError: (Object e) => _fail('The microphone stopped: $e'));
      if (_disposed) return;
      _log('call ready in ${clock.elapsedMilliseconds} ms');
      _setPhase(CallPhase.listening);
    } on FishException catch (e) {
      errorNeedsSettings = e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 402;
      _dropWarm();
      _fail(e.message);
    } catch (e) {
      _dropWarm();
      _fail('Could not start the call: $e');
    }
  }

  void _fail(String message) {
    error = message;
    _notify(now: true);
  }

  String _ttsKey(VoicePrefs p) => '${p.voiceId}|${p.model}|${p.latency}|${p.speed}';

  void _warmUp() {
    if (_disposed || _ending || phase == CallPhase.ended || _warm != null) return;
    final p = prefs();
    final f = fish.openLive(voiceId: p.voiceId, model: p.model, latency: p.latency, speed: p.speed);
    f.ignore();
    _warm = f;
    _warmKey = _ttsKey(p);
    final age = Stopwatch()..start();
    f.then(
      (s) {
        _log('TTS socket warm in ${age.elapsedMilliseconds} ms');
        // The server may close an idle session; open a fresh one if it lived a while (bounded).
        s.done.whenComplete(() {
          if (!identical(_warm, f)) return;
          _warm = null;
          if (age.elapsed > const Duration(seconds: 8) && _rewarms < 30 && !_disposed) {
            _rewarms++;
            _warmUp();
          }
        }).ignore();
      },
      onError: (Object e) {
        if (identical(_warm, f)) _warm = null;
      },
    );
  }

  void _dropWarm() {
    final w = _warm;
    _warm = null;
    if (w != null) unawaited(w.then((s) => s.cancel(), onError: (_) {}));
  }

  /// The warm socket when it matches the current voice settings and is still open, else a new one.
  Future<FishLiveTts> _takeTts(VoicePrefs p) {
    final w = _warm;
    final key = _warmKey;
    _warm = null;
    if (w == null) return fish.openLive(voiceId: p.voiceId, model: p.model, latency: p.latency, speed: p.speed);
    if (key != _ttsKey(p)) {
      unawaited(w.then((s) => s.cancel(), onError: (_) {}));
      return fish.openLive(voiceId: p.voiceId, model: p.model, latency: p.latency, speed: p.speed);
    }
    return w.then((s) {
      if (!s.isClosed) return s;
      return fish.openLive(voiceId: p.voiceId, model: p.model, latency: p.latency, speed: p.speed);
    }, onError: (Object _) => fish.openLive(voiceId: p.voiceId, model: p.model, latency: p.latency, speed: p.speed));
  }

  /// An unused turn socket goes back to being the warm one.
  void _putBack(Future<FishLiveTts> f, String key) {
    if (_warm == null && !_disposed && !_ending && phase != CallPhase.ended) {
      _warm = f;
      _warmKey = key;
    } else {
      unawaited(f.then((t) => t.cancel(), onError: (_) {}));
    }
  }

  @override
  void setMuted(bool v) {
    muted = v;
    if (v && _vad.inSpeech) _vad.reset();
    _notify(now: true);
  }

  void _onMic(Uint8List chunk) {
    if (_disposed) return;
    if (muted || phase == CallPhase.connecting) {
      _micLevel = 0;
      return;
    }
    _vad.playbackActive = phase == CallPhase.speaking;
    final events = _vad.add(chunk);
    _micLevel = _micLevel * 0.6 + levelFromRms(_vad.lastRms) * 0.4;
    for (final ev in events) {
      if (ev == VadEvent.speechStart) {
        if (phase == CallPhase.speaking || phase == CallPhase.thinking) _bargeIn();
      } else {
        final pcm = _vad.takeUtterance();
        if (pcm != null) {
          _turnClock = Stopwatch()..start();
          _tAsr = null;
          _tToken = null;
          unawaited(_handleUtterance(pcm));
        }
      }
    }
  }

  /// Stops speech and the running reply right away.
  void _bargeIn() {
    _turn++;
    _asrCancel?.cancel();
    _asrCancel = null;
    if (_replyRunning && chatId != null) {
      try {
        engine.stop(chatId!);
      } catch (_) {}
    }
    _replyRunning = false;
    unawaited(_replySub?.cancel());
    _replySub = null;
    _tts?.cancel();
    _tts = null;
    if (_reveal == _Reveal.live) {
      _revealMax = revealedWords; // keep the spoken prefix on screen
      _reveal = _Reveal.frozen;
    }
    _revealPlayer = null;
    unawaited(_player?.stop());
    _player = null;
    status = null;
    tool = null;
    toolKind = null;
    _setPhase(CallPhase.listening);
    _warmUp();
  }

  /// Interrupt from the UI (tap on the orb while it speaks).
  @override
  void interrupt() {
    if (phase == CallPhase.speaking || phase == CallPhase.thinking) _bargeIn();
  }

  Future<void> _handleUtterance(Uint8List pcm) async {
    final turn = ++_turn;
    final p = prefs();
    final key = _ttsKey(p);
    _setPhase(CallPhase.thinking);
    status = null;
    tool = null;
    toolKind = null;
    // The warm socket (or a fresh one opened while ASR runs).
    final ttsFuture = _takeTts(p);
    ttsFuture.ignore();
    String text;
    try {
      final wav = await encodeWav(pcm, MicStream.sampleRate);
      _asrCancel = CancelToken();
      final r = await fish.transcribe(wav, language: p.sttLanguage, model: p.sttModel, cancel: _asrCancel);
      text = cleanTranscript(r.text);
      _tAsr = _turnClock?.elapsedMilliseconds;
    } catch (e) {
      _putBack(ttsFuture, key);
      if (turn != _turn) return;
      if (e is FishException && e.message == 'Cancelled.') return;
      status = '$e';
      _setPhase(CallPhase.listening);
      return;
    }
    if (turn != _turn) {
      _putBack(ttsFuture, key);
      return;
    }
    if (text.isEmpty) {
      _putBack(ttsFuture, key);
      _setPhase(CallPhase.listening);
      return;
    }
    userCaption = text;
    _setCaption('');
    _assistantRaw = '';
    _reveal = _Reveal.live;
    _revealMax = 0;
    _revealPlayer = null;
    _ttsDone = false;
    _notify(now: true);
    await _runReply(text, ttsFuture, turn, p);
  }

  void _logTtfa(int turn) {
    final c = _turnClock;
    if (c == null) return;
    final total = c.elapsedMilliseconds;
    lastTtfaMs = total;
    final asr = _tAsr;
    final tok = _tToken;
    _log('turn $turn time-to-first-audio $total ms (end of speech -> ASR ${asr ?? '?'} ms -> first token ${tok ?? '?'} ms -> audio $total ms)');
    _notify();
  }

  Future<void> _runReply(String text, Future<FishLiveTts> ttsFuture, int turn, VoicePrefs p) async {
    final player = PcmStreamPlayer(
      onStarted: () {
        if (turn == _turn) _logTtfa(turn);
      },
    );
    _player = player;
    FishLiveTts? tts;
    String? ttsError;
    try {
      // SoLoud stream and TTS socket in parallel (the socket is normally already open).
      final r = await Future.wait<Object?>([player.start(), ttsFuture]);
      tts = r[1] as FishLiveTts?;
    } catch (e) {
      ttsError = '$e';
      try {
        tts = await ttsFuture;
      } catch (_) {}
    }
    if (turn != _turn) {
      tts?.cancel();
      unawaited(player.stop());
      return;
    }
    _tts = tts;
    _revealPlayer = player;
    _msPerWordGuess = 360 / p.speed.clamp(0.5, 2.0);
    var gotAudio = false;
    tts?.audio.listen(
      (chunk) {
        if (turn != _turn) return;
        player.add(chunk);
        if (!gotAudio) {
          gotAudio = true;
          tool = null;
          toolKind = null;
          _setPhase(CallPhase.speaking);
        }
      },
      onError: (Object e) {
        if (turn == _turn) {
          status = '$e';
          _reveal = _Reveal.all;
          _notify(now: true);
        }
      },
      onDone: player.end,
    );
    if (tts == null) {
      status = ttsError ?? 'Could not reach the Fish Audio voice.';
      _reveal = _Reveal.all; // no audio: show the text right away
      player.end();
    }

    // Hide the model's thinking time: if Nur has not started speaking 600 ms after the user finished, say a short
    // filler ("Mm, one sec.") in the same voice; the real answer follows in the same audio stream.
    final arabicTurn = isArabic(text);
    var fillerPlayed = false;
    var toolFillerPlayed = false;
    void playFiller(FillerKind kind) {
      if (turn != _turn || gotAudio) return;
      final clip = _fillers.pick(kind, arabic: arabicTurn);
      if (clip == null) return;
      player.add(clip);
      if (kind == FillerKind.thinking) fillerPlayed = true;
      if (kind == FillerKind.tool) toolFillerPlayed = true;
    }

    final fillerTimer = Timer(const Duration(milliseconds: 600), () {
      if (!fillerPlayed && _assistantRaw.isEmpty) playFiller(FillerKind.thinking);
    });

    final splitter = SentenceSplitter();
    final replyDone = Completer<void>();
    _replyRunning = true;
    void speak(List<String> sentences) {
      for (final s in sentences) {
        tts?.text('$s ');
        tts?.flush();
      }
    }

    Stream<ReplyEvent> replies;
    try {
      replies = engine.send(chatId, UserInput(text, fromVoiceCall: true), onChatId: (id) => chatId = id);
    } catch (e) {
      replies = Stream.value(ReplyError('Chat is not available: $e'));
    }
    _replySub = replies.listen(
      (ev) {
        if (turn != _turn) return;
        switch (ev) {
          case ReplyText(:final delta):
            _tToken ??= _turnClock?.elapsedMilliseconds;
            _assistantRaw += delta;
            _setCaption(markdownToSpeech(_assistantRaw, keepDirections: false));
            if (_msPerWordGuess > 0 && isArabic(assistantCaption)) _msPerWordGuess = 470 / p.speed.clamp(0.5, 2.0);
            if (tool != null && assistantCaption.isNotEmpty) {
              tool = null;
              toolKind = null;
            }
            speak(splitter.add(delta));
            _notify();
          case ReplyToolActivity(:final toolName):
            if (!toolFillerPlayed && _assistantRaw.isEmpty) playFiller(FillerKind.tool);
            final k = toolKindFor(toolName);
            toolKind = k;
            tool = toolCaptionFor(k);
            _notify(now: true);
          case ReplyDone(:final fullText):
            if (_assistantRaw.isEmpty && fullText.isNotEmpty) {
              _assistantRaw = fullText;
              _setCaption(markdownToSpeech(fullText, keepDirections: false));
              speak(splitter.add(fullText));
            }
            fillerTimer.cancel();
            speak(splitter.close());
            tts?.stop();
            if (!replyDone.isCompleted) replyDone.complete();
            // Prepare the next turn while Nur speaks and the user answers: the Pi pre-reads the whole history now,
            // so the next reply starts in ~1-3 s instead of re-reading everything.
            unawaited(engine.prewarm(chatId, fromVoiceCall: true).catchError((Object _) {}));
          case ReplyError(:final message):
            status = message;
            speak(splitter.close());
            tts?.stop();
            _notify(now: true);
            if (!replyDone.isCompleted) replyDone.complete();
        }
      },
      onError: (Object e) {
        if (turn == _turn) status = 'The reply failed: $e';
        tts?.stop();
        if (!replyDone.isCompleted) replyDone.complete();
      },
      onDone: () {
        speak(splitter.close());
        tts?.stop();
        if (!replyDone.isCompleted) replyDone.complete();
      },
    );

    await replyDone.future;
    _replyRunning = false;
    if (turn != _turn) return;
    // Wait for the TTS to finish and the audio to drain.
    try {
      await tts?.done.timeout(const Duration(seconds: 60));
    } catch (e) {
      if (turn == _turn && e is! TimeoutException) status = '$e';
    }
    _ttsDone = true;
    player.end();
    await player.finished;
    if (turn != _turn) return;
    _player = null;
    _tts = null;
    _revealPlayer = null;
    _reveal = _Reveal.all;
    tool = null;
    toolKind = null;
    _setPhase(CallPhase.listening);
    _notify(now: true);
    _warmUp();
  }

  Future<void> end() async {
    if (phase == CallPhase.ended) return;
    _ending = true;
    _bargeIn();
    _dropWarm();
    phase = CallPhase.ended;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    unawaited(end());
    super.dispose();
  }
}
