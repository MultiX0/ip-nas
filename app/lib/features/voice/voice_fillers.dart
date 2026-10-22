// Short spoken fillers that hide the model's thinking time in voice calls: when the answer is slow to start, Nur
// says "Mm, one sec." in the selected Drama 3 voice and the real answer follows in the same audio stream.
// Generated once per voice and language and cached on disk as raw PCM (44.1 kHz s16le mono).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fish_audio.dart';

enum FillerKind { thinking, tool }

const _phrases = <String, Map<FillerKind, List<String>>>{
  'en': {
    FillerKind.thinking: ['[thoughtful] Mm, one sec.', '[warmly] Okay, let me see.', '[calmly] Hmm, good question.'],
    FillerKind.tool: ['[calmly] Let me check your NAS.', '[warmly] One moment, checking.'],
  },
  'ar': {
    FillerKind.thinking: ['[thoughtful] ممم، لحظة.', '[warmly] طيب، خليني أشوف.'],
    FillerKind.tool: ['[calmly] لحظة، بشيك على الجهاز.', '[warmly] ثانية، بتأكد لك.'],
  },
};

class VoiceFillers {
  VoiceFillers(this.fish);
  final FishAudio fish;
  final _clips = <String, Uint8List>{}; // key = voice|lang|kind|index
  final _rng = math.Random();
  String? _voice;

  /// Generates (or loads from disk) every filler for [voiceId] in the background. Safe to call on every call start.
  Future<void> prepare({required String voiceId, required String model, double speed = 1.0}) async {
    _voice = voiceId;
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'voice_fillers'));
    await dir.create(recursive: true);
    final jobs = <Future<void>>[];
    _phrases.forEach((lang, kinds) {
      kinds.forEach((kind, list) {
        for (var i = 0; i < list.length; i++) {
          jobs.add(_load(dir, voiceId, model, speed, lang, kind, i, list[i]));
        }
      });
    });
    await Future.wait(jobs);
  }

  Future<void> _load(Directory dir, String voice, String model, double speed, String lang, FillerKind kind, int i, String text) async {
    final key = '$voice|$lang|${kind.name}|$i';
    final file = File(p.join(dir.path, '${voice}_${model}_${speed.toStringAsFixed(2)}_${lang}_${kind.name}_$i.pcm'));
    try {
      if (await file.exists() && await file.length() > 4000) {
        _clips[key] = trimSilence(await file.readAsBytes());
        return;
      }
      final b = BytesBuilder(copy: false);
      await for (final c in fish.tts(text, voiceId: voice, model: model, format: 'pcm', speed: speed)) {
        b.add(c);
      }
      final bytes = trimSilence(b.takeBytes());
      if (bytes.length < 4000) return;
      await file.writeAsBytes(bytes, flush: true);
      _clips[key] = bytes;
    } catch (_) {
      /* no filler for this one; the call works without it */
    }
  }

  /// A random cached clip in Arabic or English, or null if none is ready yet.
  Uint8List? pick(FillerKind kind, {required bool arabic}) {
    final v = _voice;
    if (v == null) return null;
    final lang = arabic ? 'ar' : 'en';
    final ready = [for (var i = 0; i < (_phrases[lang]![kind]!.length); i++) ?_clips['$v|$lang|${kind.name}|$i']];
    if (ready.isEmpty) return null;
    return ready[_rng.nextInt(ready.length)];
  }
}

/// Cuts leading/trailing near-silence from s16le mono PCM (keeps 60 ms of padding) so a filler starts and ends crisply.
Uint8List trimSilence(Uint8List pcm, {int threshold = 500, int padSamples = 2646}) {
  final n = pcm.length ~/ 2;
  if (n == 0) return pcm;
  final v = ByteData.sublistView(pcm);
  var first = 0, last = n - 1;
  while (first < n && v.getInt16(first * 2, Endian.little).abs() < threshold) {
    first++;
  }
  while (last > first && v.getInt16(last * 2, Endian.little).abs() < threshold) {
    last--;
  }
  if (first >= last) return pcm;
  final s = math.max(0, first - padSamples), e = math.min(n, last + padSamples);
  return Uint8List.sublistView(pcm, s * 2, e * 2);
}
