// Client for the Nur Hub REST API (the endpoints are listed in hub/README.md).
import 'package:dio/dio.dart';

import '../../core/contracts/nas.dart';

/// Plain-words error from the hub (or the network).
class NasException implements Exception {
  NasException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class NasHubClientImpl implements NasHubClient {
  NasHubClientImpl(this._device) : _dio = _makeDio(_device.baseUrl, _device.token);

  final NasDevice _device;
  final Dio _dio;

  static Dio _makeDio(String baseUrl, String? token) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 60),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
        responseType: ResponseType.json,
      ));

  @override
  NasDevice? get device => _device;
  @override
  bool get isPaired => _device.token != null;
  @override
  String? get llmBaseUrl => '${_device.baseUrl}/llm/v1';

  void close() => _dio.close(force: true);

  Future<T> _call<T>(Future<Response<dynamic>> Function() f) async {
    try {
      final r = await f();
      return r.data as T;
    } on DioException catch (e) {
      throw NasException(describeDioError(e), statusCode: e.response?.statusCode);
    } on TypeError {
      throw NasException('The NAS sent an unexpected answer. Update Nur Hub on the NAS.');
    }
  }

  static String describeDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    final code = e.response?.statusCode;
    if (code == 401) return 'This device is no longer paired with the NAS. Pair it again.';
    if (code == 404) return 'The NAS does not support this yet. Update Nur Hub on the NAS.';
    if (code != null) return 'The NAS answered with an error ($code).';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The NAS is taking too long to answer. Is it on and on the same network?';
      case DioExceptionType.connectionError:
        return 'Cannot reach the NAS. Check that it is on and that you are on the same network.';
      case DioExceptionType.cancel:
        return 'Cancelled.';
      default:
        return 'Cannot talk to the NAS: ${e.message ?? e.type.name}';
    }
  }

  static List<Map<String, dynamic>> _list(dynamic d) =>
      (d as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  static Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  /// GET /api/v1/info, the only call that works without a token (used for discovery).
  static Future<Map<String, dynamic>> fetchInfo(String baseUrl, {Duration timeout = const Duration(seconds: 4)}) async {
    final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: timeout, receiveTimeout: timeout));
    try {
      final r = await dio.get('/api/v1/info');
      return _map(r.data);
    } on DioException catch (e) {
      throw NasException(describeDioError(e), statusCode: e.response?.statusCode);
    } finally {
      dio.close();
    }
  }

  /// Asks to pair. The first device ever is approved at once (owner); later devices wait for approval
  /// from an app that is already paired. Returns the hub's answer: {status, token?, device_id?, request_id?}.
  static Future<Map<String, dynamic>> requestPairing(String baseUrl, String deviceName) async {
    final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 6)));
    try {
      final r = await dio.post('/api/v1/pair/request', data: {'device_name': deviceName});
      return _map(r.data);
    } on DioException catch (e) {
      throw NasException(describeDioError(e), statusCode: e.response?.statusCode);
    } finally {
      dio.close();
    }
  }

  /// {status: pending|approved|denied|expired, token?, device_id?}
  static Future<Map<String, dynamic>> pairingStatus(String baseUrl, String requestId) async {
    final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 6)));
    try {
      final r = await dio.get('/api/v1/pair/status/$requestId');
      return _map(r.data);
    } on DioException catch (e) {
      throw NasException(describeDioError(e), statusCode: e.response?.statusCode);
    } finally {
      dio.close();
    }
  }

  Future<Map<String, dynamic>> info() async => _map(await _call<dynamic>(() => _dio.get('/api/v1/info')));

  /// Devices waiting for this owner's approval: [{id, device_name, created}].
  Future<List<Map<String, dynamic>>> pendingPairs() async => _list(await _call<dynamic>(() => _dio.get('/api/v1/pair/pending')));

  Future<void> decidePair(String requestId, {required bool approve}) async =>
      _call<dynamic>(() => _dio.post('/api/v1/pair/${approve ? 'approve' : 'deny'}/$requestId'));

  @override
  Future<Map<String, dynamic>> system() async => _map(await _call<dynamic>(() => _dio.get('/api/v1/system')));

  @override
  Future<List<Map<String, dynamic>>> containers() async => _list(await _call<dynamic>(() => _dio.get('/api/v1/docker/containers')));

  @override
  Future<Map<String, dynamic>> containerAction(String name, String action) async =>
      _map(await _call<dynamic>(() => _dio.post('/api/v1/docker/containers/${Uri.encodeComponent(name)}/$action')));

  Future<String> containerLogs(String name, {int tail = 200}) async {
    final m = _map(await _call<dynamic>(() => _dio.get('/api/v1/docker/containers/${Uri.encodeComponent(name)}/logs', queryParameters: {'tail': tail})));
    return '${m['logs'] ?? ''}';
  }

  @override
  Future<List<Map<String, dynamic>>> search(String query, {int limit = 5}) async =>
      _list(await _call<dynamic>(() => _dio.get('/api/v1/search', queryParameters: {'q': query, 'limit': limit})));

  @override
  Future<Map<String, dynamic>> exec(String command, {String mode = 'safe', int? timeout}) async => _map(await _call<dynamic>(() => _dio.post(
        '/api/v1/exec',
        data: {'command': command, 'mode': mode, 'timeout': ?timeout},
        options: Options(receiveTimeout: const Duration(seconds: 130)),
      )));

  Future<List<Map<String, dynamic>>> runtimes() async => _list(await _call<dynamic>(() => _dio.get('/api/v1/runtimes')));

  Future<Map<String, dynamic>> runtimeAction(String id, String action) async =>
      _map(await _call<dynamic>(() => _dio.post('/api/v1/runtimes/$id/$action', options: Options(receiveTimeout: const Duration(seconds: 120)))));

  Future<List<Map<String, dynamic>>> localModels() async => _list(await _call<dynamic>(() => _dio.get('/api/v1/models/local')));

  Future<Map<String, dynamic>> deleteLocalModel(String runtime, String id) async =>
      _map(await _call<dynamic>(() => _dio.delete('/api/v1/models/local/$runtime/${Uri.encodeComponent(id)}')));

  Future<List<Map<String, dynamic>>> catalog() async => _list(await _call<dynamic>(() => _dio.get('/api/v1/models/catalog')));

  Future<List<Map<String, dynamic>>> hfSearch(String q) async =>
      _list(await _call<dynamic>(() => _dio.get('/api/v1/models/hf/search', queryParameters: {'q': q, 'limit': 20})));

  Future<List<Map<String, dynamic>>> hfFiles(String repo) async =>
      _list(await _call<dynamic>(() => _dio.get('/api/v1/models/hf/files', queryParameters: {'repo': repo})));

  Future<String> download({required String runtime, String? repo, String? file, String? name}) async {
    final m = _map(await _call<dynamic>(() => _dio.post('/api/v1/models/download', data: {
          'runtime': runtime,
          'repo': ?repo,
          'file': ?file,
          'name': ?name,
        })));
    return '${m['job_id']}';
  }

  Future<Map<String, dynamic>> job(String id) async => _map(await _call<dynamic>(() => _dio.get('/api/v1/jobs/$id')));
  Future<List<Map<String, dynamic>>> jobs() async => _list(await _call<dynamic>(() => _dio.get('/api/v1/jobs')));
  Future<void> cancelJob(String id) async => _call<dynamic>(() => _dio.post('/api/v1/jobs/$id/cancel'));

  /// Model ids served by the OpenAI-compatible proxy (llama.cpp router).
  Future<List<String>> llmModelIds() async {
    final m = _map(await _call<dynamic>(() => _dio.get('/llm/v1/models')));
    return _list(m['data']).map((e) => '${e['id']}').toList();
  }
}
