// Low-latency audio: streaming PCM playback with SoLoud, mic capture, an energy VAD and WAV encoding.
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

import 'fish_audio.dart' show fishSampleRate;

class AudioEngine {
  static Future<void>? _init;

  /// Starts SoLoud once for the whole app.
  static Future<void> ensure() {
    if (SoLoud.instance.isInitialized) return Future.value();
    return _init ??= SoLoud.instance.init(sampleRate: 44100, bufferSize: 1024, channels: Channels.stereo).catchError((Object e) {
      _init = null;
      throw Exception('Could not start audio playback: $e');
    });
  }
}

/// The audio side of a call: microphone, playback and audio start-up. Tests swap it for fakes.
class CallAudio {
  const CallAudio();
  MicStream mic() => MicStream();
  PcmStreamPlayer player({VoidCallback? onStarted}) => PcmStreamPlayer(onStarted: onStarted);
  Future<void> ready() => AudioEngine.ensure();
}

/// RMS of little-endian PCM16 bytes, 0..1.
double pcm16Rms(Uint8List bytes, [int start = 0, int? end]) {
  final bd = ByteData.sublistView(bytes);
  final e = (end ?? bytes.length) & ~1;
  var sum = 0.0;
  var n = 0;
  for (var i = start & ~1; i + 1 < e; i += 2) {
    final v = bd.getInt16(i, Endian.little) / 32768.0;
    sum += v * v;
    n++;
  }
  return n == 0 ? 0 : math.sqrt(sum / n);
}

/// Maps RMS to a 0..1 level that looks good on the orb.
double levelFromRms(double rms) {
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10; // -inf..0
  return ((db + 55) / 45).clamp(0.0, 1.0);
}

/// Plays streamed PCM s16le mono chunks as they arrive. Playback starts on the first chunk.
class PcmStreamPlayer {
  PcmStreamPlayer({this.sampleRate = fishSampleRate, this.onStarted});
  final int sampleRate;

  /// Called once, the moment playback of the first chunk starts (time-to-first-audio).
  final VoidCallback? onStarted;

  AudioSource? _src;
  SoundHandle? _handle;
  int _carry = -1; // odd leftover byte
  final List<double> _rms = []; // one per 20 ms of queued audio
  int _bytesQueued = 0;
  bool _ended = false;
  bool _stopped = false;
  final _finished = Completer<void>();
  Timer? _watch;
  Stopwatch? _clock;

  Future<void> get finished => _finished.future;

  /// True from the first queued chunk until the audio has drained or was stopped.
  bool get playing => _handle != null && !_stopped && !_finished.isCompleted;

  Future<void> start() async {
    await AudioEngine.ensure();
    if (_stopped) return;
    _src = SoLoud.instance.setBufferStream(
      sampleRate: sampleRate,
      channels: Channels.mono,
      format: BufferType.s16le,
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.12, // start almost immediately; Fish streams faster than real time
    );
  }

  void add(Uint8List chunk) {
    final src = _src;
    if (_stopped || src == null || chunk.isEmpty) return;
    var data = chunk;
    if (_carry >= 0) {
      data = Uint8List(chunk.length + 1)
        ..[0] = _carry
        ..setRange(1, chunk.length + 1, chunk);
      _carry = -1;
    }
    if (data.length.isOdd) {
      _carry = data[data.length - 1];
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    if (data.isEmpty) return;
    // Loudness timeline in 20 ms windows, for the orb and for the VAD's echo estimate.
    final win = sampleRate ~/ 50 * 2;
    for (var i = 0; i < data.length; i += win) {
      _rms.add(pcm16Rms(data, i, math.min(i + win, data.length)));
    }
    _bytesQueued += data.length;
    try {
      SoLoud.instance.addAudioDataStream(src, data);
      if (_handle == null) {
        _handle = SoLoud.instance.play(src);
        _clock = Stopwatch()..start();
        onStarted?.call();
      }
    } catch (e) {
      debugPrint('PcmStreamPlayer.add: $e');
    }
  }

  /// No more data: resolves [finished] when the buffered audio has played.
  void end() {
    if (_ended || _stopped) return;
    _ended = true;
    final src = _src;
    if (src == null || _handle == null) {
      _complete();
      return;
    }
    try {
      SoLoud.instance.setDataIsEnded(src);
    } catch (_) {}
    final totalMs = _bytesQueued / 2 / sampleRate * 1000;
    _watch = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final h = _handle;
      final done = h == null || !SoLoud.instance.getIsValidVoiceHandle(h) || (_clock != null && _clock!.elapsedMilliseconds > totalMs + 4000);
      if (done) _complete();
    });
  }

  /// Milliseconds of audio queued so far.
  double get queuedMs => _bytesQueued / 2 / sampleRate * 1000;

  /// True once [end] was called (no more audio will be queued).
  bool get ended => _ended;

  /// Milliseconds of audio played so far (0 before playback starts).
  double get playedMs {
    final src = _src;
    if (_finished.isCompleted) return queuedMs;
    if (src == null || _handle == null) return 0;
    try {
      return SoLoud.instance.getStreamTimeConsumed(src).inMicroseconds / 1000.0;
    } catch (_) {
      return (_clock?.elapsedMilliseconds ?? 0).toDouble();
    }
  }

  /// Output level (0..1) at the current playback position, for the orb.
  double get level => levelFromRms(rms);

  /// RMS of the audio playing right now.
  double get rms {
    final src = _src;
    if (src == null || _handle == null || _rms.isEmpty || _finished.isCompleted) return 0;
    try {
      final i = SoLoud.instance.getStreamTimeConsumed(src).inMilliseconds ~/ 20;
      return i < _rms.length ? _rms[i] : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Barge-in: stop immediately and free the stream.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final h = _handle, src = _src;
    _handle = null;
    _src = null;
    try {
      if (h != null && SoLoud.instance.getIsValidVoiceHandle(h)) await SoLoud.instance.stop(h);
    } catch (_) {}
    try {
      if (src != null) await SoLoud.instance.disposeSource(src);
    } catch (_) {}
    _complete();
  }

  void _complete() {
    _watch?.cancel();
    if (!_finished.isCompleted) _finished.complete();
    if (!_stopped && _ended) {
      final src = _src;
      _src = null;
      _handle = null;
      if (src != null) SoLoud.instance.disposeSource(src).catchError((_) {});
    }
  }
}

Uint8List _wavFromPcm16(({Uint8List pcm, int sampleRate}) a) {
  final pcm = a.pcm;
  final out = Uint8List(44 + pcm.length);
  final b = ByteData.sublistView(out);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      out[o + i] = s.codeUnitAt(i);
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + pcm.length, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, a.sampleRate, Endian.little);
  b.setUint32(28, a.sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, pcm.length, Endian.little);
  out.setRange(44, out.length, pcm);
  return out;
}

/// Wraps PCM16 mono in a WAV container (off the UI isolate).
Future<Uint8List> encodeWav(Uint8List pcm, int sampleRate) => Isolate.run(() => _wavFromPcm16((pcm: pcm, sampleRate: sampleRate)));

enum VadEvent { speechStart, speechEnd }

/// Energy VAD with an adaptive noise floor. Feed 16 kHz PCM16 chunks; collects the utterance with pre-roll.
///
/// While Nur's voice plays, the mic hears it too. The VAD learns how loud that echo is compared to the output
/// ([playbackRms]) and only counts speech that is clearly louder than the echo it expects at that moment.
class EnergyVad {
  EnergyVad({this.sampleRate = 16000, this.silenceMs = 550, this.minSpeechMs = 250, this.preRollMs = 300, this.maxUtteranceMs = 30000});
  final int sampleRate;
  final int silenceMs;
  final int minSpeechMs;
  final int preRollMs;
  final int maxUtteranceMs;

  double noiseFloor = 0.006;
  bool inSpeech = false;
  double lastRms = 0;

  /// True while Nur's voice plays (an answer or a filler): speech has to stand out from its echo.
  bool playbackActive = false;

  /// RMS of the audio playing right now; set with every chunk while [playbackActive].
  double playbackRms = 0;

  double _coupling = 0; // how loud the echo is: mic RMS per unit of output RMS
  double _lastAnswer = -1; // the echo learned over the previous answer (-1 before the first one)
  final _outs = <double>[]; // output RMS of the last 200 ms, so the delay and reverb from speaker to mic are covered
  int _playMs = 0;

  final _preRoll = <Uint8List>[];
  int _preRollBytes = 0;
  final _utterance = BytesBuilder(copy: false);
  int _speechMs = 0;
  int _silenceRunMs = 0;
  int _candidateMs = 0;

  void reset() {
    inSpeech = false;
    _utterance.clear();
    _speechMs = 0;
    _silenceRunMs = 0;
    _candidateMs = 0;
  }

  /// Returns events triggered by this chunk.
  List<VadEvent> add(Uint8List chunk) {
    final ms = chunk.length / 2 / sampleRate * 1000;
    final rms = pcm16Rms(chunk);
    lastRms = rms;
    final events = <VadEvent>[];

    var echoGate = 0.0;
    if (playbackActive) {
      _outs.add(playbackRms);
      if (_outs.length > 10) _outs.removeAt(0);
      final peak = _outs.reduce(math.max);
      echoGate = _coupling * peak * 2.0;
      if (!inSpeech && peak > 0.01) {
        // An upper envelope of the echo, learned mostly in the first second of each answer. A level far above what
        // the earlier answers taught is most likely the user talking over Nur, so it only moves the estimate slowly.
        final r = rms / peak;
        final plausible = _lastAnswer < 0 || r < math.max(_lastAnswer * 3, 0.05);
        final rate = _playMs < 1000 ? (r > _coupling ? (plausible ? 0.3 : 0.01) : 0.05) : (r > _coupling ? 0.01 : 0.002);
        _coupling += (r - _coupling) * rate;
      }
      _playMs += ms.round();
    } else {
      if (_playMs > 0) _lastAnswer = _coupling;
      _outs.clear();
      _playMs = 0;
    }
    final startThreshold = math.max(noiseFloor * 3.0, 0.012) * (playbackActive ? 1.6 : 1.0);
    final threshold = math.max(startThreshold, echoGate);
    final keepThreshold = math.max(noiseFloor * 2.0, 0.008);

    if (!inSpeech) {
      // Adapt the noise floor only on quiet-ish frames, and not to Nur's echo (the echo gate handles that).
      if (rms < threshold && !playbackActive) {
        noiseFloor = (noiseFloor * 0.95 + rms * 0.05).clamp(0.001, 0.05);
      }
      _preRoll.add(chunk);
      _preRollBytes += chunk.length;
      while (_preRollBytes > preRollMs * sampleRate * 2 ~/ 1000 && _preRoll.length > 1) {
        _preRollBytes -= _preRoll.removeAt(0).length;
      }
      if (rms > threshold) {
        _candidateMs += ms.round();
        final need = playbackActive ? math.max(minSpeechMs, 350) : 120;
        if (_candidateMs >= need) {
          inSpeech = true;
          _speechMs = _candidateMs;
          _silenceRunMs = 0;
          _utterance.clear();
          for (final c in _preRoll) {
            _utterance.add(c);
          }
          _preRoll.clear();
          _preRollBytes = 0;
          events.add(VadEvent.speechStart);
        }
      } else {
        _candidateMs = math.max(0, _candidateMs - ms.round());
      }
    } else {
      _utterance.add(chunk);
      if (rms > keepThreshold) {
        _speechMs += ms.round();
        _silenceRunMs = 0;
      } else {
        _silenceRunMs += ms.round();
      }
      final total = _utterance.length / 2 / sampleRate * 1000;
      if (_silenceRunMs >= silenceMs || total >= maxUtteranceMs) {
        inSpeech = false;
        _candidateMs = 0;
        events.add(VadEvent.speechEnd);
      }
    }
    return events;
  }

  /// PCM of the last utterance (valid after [VadEvent.speechEnd]); null if it was too short.
  Uint8List? takeUtterance() {
    final bytes = _utterance.takeBytes();
    final ok = _speechMs >= minSpeechMs;
    _speechMs = 0;
    return ok ? bytes : null;
  }
}

/// Microphone PCM16 mono stream (16 kHz) with echo cancellation where the platform offers it.
class MicStream {
  final AudioRecorder _rec = AudioRecorder();
  static const sampleRate = 16000;

  Future<bool> hasPermission() => _rec.hasPermission();

  Future<Stream<Uint8List>> start() => _rec.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
      audioInterruption: AudioInterruptionMode.none,
    ),
  );

  Future<void> stop() async {
    try {
      await _rec.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _rec.dispose();
    } catch (_) {}
  }
}
