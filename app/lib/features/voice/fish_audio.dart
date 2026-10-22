// Fish Audio client: Drama 3 TTS (REST streaming and the live WebSocket), transcribe-1-pro speech to text and the
// voice library. API docs: https://docs.fish.audio
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const fishBaseUrl = 'https://api.fish.audio';
const fishLiveUrl = 'wss://api.fish.audio/v1/tts/live';
const fishSampleRate = 44100;

class FishException implements Exception {
  FishException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;

  static String messageFor(int? status, [String? detail]) => switch (status) {
    401 || 403 => 'Fish Audio rejected the API key. Check it in the voice settings.',
    402 => 'Your Fish Audio account is out of credits. Top up at fish.audio to keep talking.',
    429 => 'Fish Audio is busy (too many requests at once). Try again in a moment.',
    413 => 'That recording is too large for Fish Audio.',
    400 => 'Fish Audio could not use that request${detail == null ? '' : ': $detail'}.',
    int s when s >= 500 => 'Fish Audio is having trouble right now ($s). Try again shortly.',
    _ => detail ?? 'Fish Audio request failed${status == null ? '' : ' ($status)'}.',
  };
}

class FishVoice {
  const FishVoice({
    required this.id,
    required this.title,
    this.languages = const [],
    this.cover,
    this.sampleUrl,
    this.description = '',
    this.own = false,
    this.author,
  });
  final String id;
  final String title;
  final List<String> languages;
  final String? cover;
  final String? sampleUrl;
  final String description;
  final bool own;
  final String? author;

  factory FishVoice.fromJson(Map<String, dynamic> j, {bool own = false}) {
    final samples = (j['samples'] as List?)?.whereType<Map>().toList() ?? const [];
    final cover = '${j['cover_image'] ?? ''}';
    return FishVoice(
      id: '${j['_id'] ?? j['id']}',
      title: '${j['title'] ?? 'Voice'}',
      languages: ((j['languages'] as List?) ?? const []).map((e) => '$e').toList(),
      cover: cover.isEmpty ? null : (cover.startsWith('http') ? cover : 'https://public-platform.r2.fish.audio/$cover'),
      sampleUrl: samples.isEmpty ? null : '${samples.first['audio']}',
      description: '${j['description'] ?? ''}',
      own: own,
      author: (j['author'] is Map) ? '${(j['author'] as Map)['nickname'] ?? ''}' : null,
    );
  }
}

class AsrResult {
  const AsrResult(this.text, {this.languageCode, this.duration});
  final String text;
  final String? languageCode;
  final double? duration;
}

class FishAudio {
  /// [baseUrl] and [liveUrl] only change in tests, which point them at a local server.
  FishAudio(this.apiKey, {String baseUrl = fishBaseUrl, this.liveUrl = fishLiveUrl, this.asrTimeout = const Duration(seconds: 30)})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 90),
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );

  final String apiKey;
  final String liveUrl;
  final Duration asrTimeout;
  final Dio _dio;

  void close() => _dio.close(force: true);

  FishException _wrap(Object e) {
    if (e is FishException) return e;
    if (e is DioException) {
      final status = e.response?.statusCode;
      String? detail;
      final d = e.response?.data;
      if (d is Map && d['message'] != null) detail = '${d['message']}';
      if (status == null) {
        return FishException(switch (e.type) {
          DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => 'Fish Audio is not answering. Check your internet connection.',
          DioExceptionType.cancel => 'Cancelled.',
          _ => 'Cannot reach Fish Audio. Check your internet connection.',
        });
      }
      return FishException(FishException.messageFor(status, detail), statusCode: status);
    }
    return FishException('Voice error: $e');
  }

  /// Throws [FishException] when the key is wrong (401) or the account has no credit (402).
  Future<void> validateKey() async {
    try {
      await _dio.get('/model', queryParameters: {'page_size': 1, 'self': true});
    } catch (e) {
      throw _wrap(e);
    }
  }

  Future<List<FishVoice>> listVoices({
    String? query,
    String? language,
    bool self = false,
    int pageSize = 20,
    int page = 1,
    String sortBy = 'score',
  }) async {
    try {
      final r = await _dio.get(
        '/model',
        queryParameters: {
          'page_size': pageSize,
          'page_number': page,
          'title': ?(query == null || query.isEmpty ? null : query),
          'language': ?language,
          'self': self,
          'sort_by': sortBy,
        },
      );
      final items = (r.data is Map ? (r.data as Map)['items'] as List? : null) ?? const [];
      return items.whereType<Map>().map((m) => FishVoice.fromJson(Map<String, dynamic>.from(m), own: self)).toList();
    } catch (e) {
      throw _wrap(e);
    }
  }

  Future<FishVoice?> getVoice(String id) async {
    try {
      final r = await _dio.get('/model/$id');
      return r.data is Map ? FishVoice.fromJson(Map<String, dynamic>.from(r.data as Map)) : null;
    } catch (e) {
      final w = _wrap(e);
      if (w.statusCode == 404) return null;
      throw w;
    }
  }

  Map<String, dynamic> _ttsRequest(String text, {String? voiceId, String format = 'pcm', String latency = 'balanced', double speed = 1.0}) => {
    'text': text,
    'reference_id': ?voiceId,
    'format': format,
    if (format == 'pcm' || format == 'wav') 'sample_rate': fishSampleRate,
    'latency': latency,
    'chunk_length': 200,
    'normalize': true,
    'condition_on_previous_chunks': true,
    'prosody': {'speed': speed.clamp(0.5, 2.0), 'volume': 0},
  };

  /// REST TTS, streamed (raw PCM s16le mono 44.1 kHz by default). Cancel with [cancel].
  Stream<Uint8List> tts(
    String text, {
    String? voiceId,
    String model = 'drama-3',
    String format = 'pcm',
    String latency = 'balanced',
    double speed = 1.0,
    CancelToken? cancel,
  }) async* {
    Response<ResponseBody> r;
    try {
      r = await _dio.post<ResponseBody>(
        '/v1/tts',
        data: _ttsRequest(text, voiceId: voiceId, format: format, latency: latency, speed: speed),
        options: Options(headers: {'model': model}, responseType: ResponseType.stream, contentType: 'application/json'),
        cancelToken: cancel,
      );
    } catch (e) {
      throw _wrap(e);
    }
    try {
      await for (final chunk in r.data!.stream) {
        yield chunk;
      }
    } on DioException catch (e) {
      throw _wrap(e);
    } catch (_) {
      // The socket closed in the middle of the audio (dart:io reports it as a raw HttpException).
      throw FishException('The connection to Fish Audio dropped. Check your internet connection.');
    }
  }

  /// transcribe-1-pro speech to text. [audio] is a complete file (WAV, MP3, M4A, ...).
  Future<AsrResult> transcribe(
    Uint8List audio, {
    String filename = 'speech.wav',
    String? language,
    String model = 'transcribe-1-pro',
    CancelToken? cancel,
  }) async {
    try {
      final form = FormData.fromMap({
        'audio': MultipartFile.fromBytes(audio, filename: filename),
        if (language != null && language.isNotEmpty && language != 'auto') 'language': language,
        'ignore_timestamps': 'true',
        if (model == 'transcribe-1-pro') 'tag_audio_events': 'false',
      });
      // A transcript comes back in a second or two; on a stalled network, give up after [asrTimeout] instead of the
      // client's 90 s so a call does not sit in "thinking".
      final r = await _dio.post(
        '/v1/asr',
        data: form,
        options: Options(headers: {'model': model}, sendTimeout: asrTimeout, receiveTimeout: asrTimeout),
        cancelToken: cancel,
      );
      final m = r.data is Map ? r.data as Map : const {};
      return AsrResult('${m['text'] ?? ''}', languageCode: m['language_code'] as String?, duration: (m['duration'] as num?)?.toDouble());
    } catch (e) {
      throw _wrap(e);
    }
  }

  /// Opens a live (WebSocket) Drama 3 TTS session that turns streamed text into streamed PCM audio.
  Future<FishLiveTts> openLive({String? voiceId, String model = 'drama-3', String latency = 'balanced', double speed = 1.0}) => FishLiveTts.connect(
    url: liveUrl,
    apiKey: apiKey,
    model: model,
    request: _ttsRequest('', voiceId: voiceId, latency: latency, speed: speed),
  );
}

/// One live TTS session: send text / flush / stop; listen to [audio] (PCM s16le 44.1 kHz mono).
class FishLiveTts {
  FishLiveTts._(this._ch) {
    _done.future.ignore(); // errors are delivered to whoever awaits [done]; never unhandled
  }
  final WebSocketChannel _ch;
  final _audio = StreamController<Uint8List>();
  final _done = Completer<void>();
  bool _closed = false;
  bool _stopSent = false;
  StreamSubscription<dynamic>? _sub;

  Stream<Uint8List> get audio => _audio.stream;

  /// Completes when the server sent `finish` (or the socket closed). Errors complete it with an error.
  Future<void> get done => _done.future;
  bool get isClosed => _closed;

  /// [pingInterval]: Fish answers pings, so a dead network shows up within two intervals instead of never.
  static Future<FishLiveTts> connect({
    String url = fishLiveUrl,
    required String apiKey,
    required String model,
    required Map<String, dynamic> request,
    Duration pingInterval = const Duration(seconds: 10),
  }) async {
    final ch = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $apiKey', 'model': model},
      pingInterval: pingInterval,
      connectTimeout: const Duration(seconds: 10),
    );
    try {
      await ch.ready;
    } catch (e) {
      unawaited(ch.sink.close().catchError((_) {}));
      throw FishException(_wsError(e));
    }
    final s = FishLiveTts._(ch);
    s._listen();
    s._send({'event': 'start', 'request': request});
    return s;
  }

  static String _wsError(Object e) {
    final text = '$e';
    final code = RegExp(r'\b(401|402|403|429|5\d\d)\b').firstMatch(text)?.group(1);
    if (code != null) return FishException.messageFor(int.parse(code));
    if (e is SocketException || text.contains('SocketException') || text.contains('HandshakeException')) {
      return 'Cannot reach Fish Audio. Check your internet connection.';
    }
    if (e is WebSocketChannelException) return 'Fish Audio refused the voice connection. Check your API key and credits.';
    return 'Voice connection failed: $text';
  }

  void _listen() {
    _sub = _ch.stream.listen(
      (data) {
        if (data is! List<int>) return;
        dynamic msg;
        try {
          msg = msgpack.deserialize(data is Uint8List ? data : Uint8List.fromList(data));
        } catch (_) {
          return;
        }
        if (msg is! Map) return;
        switch (msg['event']) {
          case 'audio':
            final a = msg['audio'];
            if (a is Uint8List && a.isNotEmpty) {
              if (!_audio.isClosed) _audio.add(a);
            } else if (a is List && a.isNotEmpty) {
              if (!_audio.isClosed) _audio.add(Uint8List.fromList(a.cast<int>()));
            }
          case 'finish':
            if (msg['reason'] == 'error') {
              _fail(FishException('Fish Audio could not finish speaking this reply.'));
            } else {
              _finish();
            }
          case 'error':
            _fail(FishException('${msg['message'] ?? msg['error'] ?? 'Fish Audio voice error.'}'));
          default:
            break; // ignore unknown events (forward compatible)
        }
      },
      onError: (Object e) => _fail(FishException(_wsError(e))),
      onDone: () {
        final code = _ch.closeCode;
        if (!_done.isCompleted && code != null && code >= 4000) {
          _fail(FishException(FishException.messageFor(code == 4001 ? 401 : (code == 4002 ? 402 : null), _ch.closeReason)));
        } else if (!_done.isCompleted && !_stopSent) {
          // Closed before we said stop: unanswered pings (the network went away) or the server dropped the session.
          _fail(FishException('The connection to Fish Audio dropped. Check your internet connection.'));
        } else {
          _finish();
        }
      },
      cancelOnError: true,
    );
  }

  void _send(Map<String, dynamic> m) {
    if (_closed) return;
    try {
      _ch.sink.add(msgpack.serialize(m));
    } catch (_) {}
  }

  void text(String t) {
    if (t.isNotEmpty) _send({'event': 'text', 'text': t});
  }

  void flush() => _send({'event': 'flush'});

  /// No more text: the server finishes buffered audio, sends `finish` and closes.
  void stop() {
    _stopSent = true;
    _send({'event': 'stop'});
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
    _teardown();
  }

  void _fail(Object e) {
    if (!_audio.isClosed) _audio.addError(e);
    if (!_done.isCompleted) _done.completeError(e);
    _teardown();
  }

  void _teardown() {
    if (_closed) return;
    _closed = true;
    unawaited(_audio.close());
    unawaited(_sub?.cancel());
    unawaited(_ch.sink.close().catchError((_) {}));
  }

  /// Barge-in: drop the session immediately.
  void cancel() {
    if (!_done.isCompleted) _done.complete();
    _teardown();
  }
}
