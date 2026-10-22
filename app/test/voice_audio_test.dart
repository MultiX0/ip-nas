import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nur/features/voice/audio_engine.dart';
import 'package:nur/features/voice/voice_fillers.dart';

/// 16 kHz PCM16: [ms] of a square wave with amplitude [amp] (0 is silence).
Uint8List _pcm(int ms, int amp) {
  final n = 16 * ms;
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    b.setInt16(i * 2, i.isEven ? amp : -amp, Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Feeds 20 ms chunks and returns the chunk index of every VAD event.
List<(int, VadEvent)> _run(EnergyVad vad, List<(int, int)> parts) {
  final events = <(int, VadEvent)>[];
  var chunk = 0;
  for (final (count, amp) in parts) {
    for (var i = 0; i < count; i++, chunk++) {
      for (final e in vad.add(_pcm(20, amp))) {
        events.add((chunk, e));
      }
    }
  }
  return events;
}

void main() {
  test('pcm16Rms and levelFromRms', () {
    expect(pcm16Rms(_pcm(20, 16384)), closeTo(0.5, 1e-6));
    expect(pcm16Rms(_pcm(20, 0)), 0);
    expect(levelFromRms(0), 0);
    expect(levelFromRms(1), 1);
    expect(levelFromRms(0.01), closeTo(15 / 45, 1e-6));
  });

  group('EnergyVad', () {
    test('finds an utterance after 120 ms of speech and ends it after 550 ms of silence', () {
      final vad = EnergyVad();
      final events = _run(vad, [(10, 0), (30, 6000), (30, 0)]);
      expect(events, [(15, VadEvent.speechStart), (67, VadEvent.speechEnd)]);
      // 300 ms of pre-roll, the rest of the speech and the silence until the end: 1340 ms.
      expect(vad.takeUtterance()!.length, 1340 * 32);
    });

    test('ignores a short click', () {
      expect(_run(EnergyVad(), [(10, 0), (3, 8000), (40, 0)]), isEmpty);
    });

    test('drops an utterance with less than 250 ms of speech', () {
      final vad = EnergyVad();
      final events = _run(vad, [(10, 0), (7, 6000), (30, 0)]);
      expect(events.map((e) => e.$2).toList(), [VadEvent.speechStart, VadEvent.speechEnd]);
      expect(vad.takeUtterance(), isNull);
    });
  });

  test('trimSilence keeps the sound plus the padding', () {
    final b = ByteData(2500 * 2);
    for (var i = 1000; i < 1500; i++) {
      b.setInt16(i * 2, 1000, Endian.little);
    }
    final pcm = b.buffer.asUint8List();
    expect(trimSilence(pcm, padSamples: 100).length, (1599 - 900) * 2);
    expect(trimSilence(Uint8List(4000)).length, 4000);
  });

  test('encodeWav writes a 16-bit mono PCM header', () async {
    final wav = await encodeWav(_pcm(10, 100), 16000);
    final h = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(h.getUint16(20, Endian.little), 1);
    expect(h.getUint16(22, Endian.little), 1);
    expect(h.getUint32(24, Endian.little), 16000);
    expect(h.getUint16(34, Endian.little), 16);
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(h.getUint32(40, Endian.little), 320);
    expect(wav.length, 44 + 320);
  });
}
