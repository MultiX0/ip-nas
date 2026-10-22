// Fish Audio client against a local server: error mapping and the live session protocol.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:nur/features/voice/fish_audio.dart';

Future<HttpServer> _http(Future<void> Function(HttpRequest r) handle) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen(handle);
  return s;
}

/// A live TTS endpoint: records the client's events and answers a stop with [onStop].
Future<(HttpServer, List<Map<dynamic, dynamic>>)> _live(void Function(WebSocket ws) onStop) async {
  final events = <Map<dynamic, dynamic>>[];
  final s = await _http((r) async {
    final ws = await WebSocketTransformer.upgrade(r);
    ws.listen((data) {
      final m = msgpack.deserialize(Uint8List.fromList((data as List).cast<int>())) as Map;
      events.add(m);
      if (m['event'] == 'stop') onStop(ws);
    });
  });
  return (s, events);
}

void main() {
  group('REST errors in plain words', () {
    for (final (code, words) in [(401, 'rejected the API key'), (402, 'out of credits'), (429, 'busy'), (503, 'having trouble')]) {
      test('$code', () async {
        final s = await _http((r) async {
          r.response.statusCode = code;
          r.response.write('{"message": "nope"}');
          await r.response.close();
        });
        final f = FishAudio('k', baseUrl: 'http://127.0.0.1:${s.port}');
        await expectLater(f.validateKey(), throwsA(isA<FishException>().having((e) => e.message, 'message', contains(words))));
        await expectLater(f.tts('Hi.').drain<void>(), throwsA(isA<FishException>().having((e) => e.statusCode, 'status', code)));
        f.close();
        await s.close(force: true);
      });
    }

    test('a stalled transcription gives up instead of holding the call', () async {
      final s = await _http((r) async {
        await r.drain<void>(); // takes the audio, never answers
      });
      final f = FishAudio('k', baseUrl: 'http://127.0.0.1:${s.port}', asrTimeout: const Duration(milliseconds: 300));
      final sw = Stopwatch()..start();
      await expectLater(f.transcribe(Uint8List(100)), throwsA(isA<FishException>().having((e) => e.message, 'message', contains('not answering'))));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      f.close();
      await s.close(force: true);
    });

    test('no server at all', () async {
      final f = FishAudio('k', baseUrl: 'http://127.0.0.1:9');
      await expectLater(f.validateKey(), throwsA(isA<FishException>().having((e) => e.message, 'message', contains('Cannot reach Fish Audio'))));
      f.close();
    });

    test('the connection drops in the middle of the audio', () async {
      // A raw socket: headers promise 100 kB, 2 kB arrive, then the line goes dead.
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((sock) async {
        sock.listen((_) {}, onError: (_) {});
        sock.add('HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: 100000\r\n\r\n'.codeUnits);
        sock.add(Uint8List(2000));
        await sock.flush();
        sock.destroy();
      });
      final f = FishAudio('k', baseUrl: 'http://127.0.0.1:${s.port}');
      await expectLater(
        f.tts('Hi.').drain<void>(),
        throwsA(isA<FishException>().having((e) => e.message, 'message', 'The connection to Fish Audio dropped. Check your internet connection.')),
      );
      f.close();
      await s.close();
    });
  });

  group('live session', () {
    test('sends start, text, flush and stop, and ends after finish', () async {
      final (s, events) = await _live((ws) {
        ws.add(msgpack.serialize({'event': 'audio', 'audio': Uint8List(10)}));
        ws.add(msgpack.serialize({'event': 'finish', 'reason': 'stop'}));
        ws.close();
      });
      final t = await FishLiveTts.connect(url: 'ws://127.0.0.1:${s.port}', apiKey: 'k', model: 'drama-3', request: const {});
      final audio = <int>[];
      t.audio.listen(audio.addAll);
      t.text('Hello there. ');
      t.flush();
      t.stop();
      await t.done.timeout(const Duration(seconds: 5));
      expect(events.map((e) => e['event']).toList(), ['start', 'text', 'flush', 'stop']);
      expect(audio.length, 10);
      expect(t.isClosed, isTrue);
      await s.close(force: true);
    });

    test('a refused key closes with a plain message', () async {
      // Fish answers the start event of a bad key with close code 4001.
      final s = await _http((r) async {
        final ws = await WebSocketTransformer.upgrade(r);
        ws.listen((_) => ws.close(4001, 'invalid api key'));
      });
      final t = await FishLiveTts.connect(url: 'ws://127.0.0.1:${s.port}', apiKey: 'k', model: 'drama-3', request: const {});
      await expectLater(t.done, throwsA(isA<FishException>().having((e) => e.message, 'message', contains('rejected the API key'))));
      await s.close(force: true);
    });

    test('a session closed before stop is a dropped connection, not a finished answer', () async {
      final s = await _http((r) async {
        final ws = await WebSocketTransformer.upgrade(r);
        ws.listen((data) {
          final m = msgpack.deserialize(Uint8List.fromList((data as List).cast<int>())) as Map;
          if (m['event'] == 'text') ws.close();
        });
      });
      final t = await FishLiveTts.connect(url: 'ws://127.0.0.1:${s.port}', apiKey: 'k', model: 'drama-3', request: const {});
      t.text('Hello. ');
      await expectLater(t.done, throwsA(isA<FishException>().having((e) => e.message, 'message', contains('dropped'))));
      await s.close(force: true);
    });

    test('a dead network shows up through unanswered pings', () async {
      final (s, _) = await _live((ws) {});
      // A TCP relay that goes silent in both directions, like a Wi-Fi link that died.
      var frozen = false;
      final relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      relay.listen((client) async {
        final up = await Socket.connect(InternetAddress.loopbackIPv4, s.port);
        client.listen((d) => frozen ? null : up.add(d), onDone: up.destroy, onError: (_) {});
        up.listen((d) => frozen ? null : client.add(d), onDone: client.destroy, onError: (_) {});
      });
      final t = await FishLiveTts.connect(
        url: 'ws://127.0.0.1:${relay.port}',
        apiKey: 'k',
        model: 'drama-3',
        request: const {},
        pingInterval: const Duration(milliseconds: 200),
      );
      t.text('Hello. ');
      frozen = true;
      await expectLater(
        t.done.timeout(const Duration(seconds: 5)),
        throwsA(isA<FishException>().having((e) => e.message, 'message', contains('dropped'))),
      );
      await relay.close();
      await s.close(force: true);
    });

    test('a failed synthesis ends the session with an error', () async {
      final (s, _) = await _live((ws) {
        ws.add(msgpack.serialize({'event': 'finish', 'reason': 'error'}));
      });
      final t = await FishLiveTts.connect(url: 'ws://127.0.0.1:${s.port}', apiKey: 'k', model: 'drama-3', request: const {});
      t.text('Hello. ');
      t.stop();
      await expectLater(t.done, throwsA(isA<FishException>()));
      await s.close(force: true);
    });
  });
}
