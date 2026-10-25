// Optional embeddings for memory retrieval (setting `memory_embedding_model` = providerId::modelId).
// Talks to the provider's embeddings endpoint directly: OpenAI-compatible `/v1/embeddings`.
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import '../context/intel_settings.dart';

class Embedder {
  Embedder(this._db, this._secure);
  final AppDb _db;
  final FlutterSecureStorage _secure;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 60)));

  Future<bool> get configured async => ((await _db.getSetting(IntelKeys.memoryEmbeddingModel)) ?? '').contains('::');

  /// Returns one vector per text, or null when no embedding model is configured or the call fails.
  Future<List<Float32List>?> embed(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final ref = (await _db.getSetting(IntelKeys.memoryEmbeddingModel)) ?? '';
    final sep = ref.indexOf('::');
    if (sep <= 0) return null;
    final providerId = ref.substring(0, sep), modelId = ref.substring(sep + 2);
    final p = await (_db.select(_db.llmProviders)..where((t) => t.id.equals(providerId))).getSingleOrNull();
    if (p == null) return null;
    final key = await _secure.read(key: 'provider_key_$providerId');
    final headers = <String, String>{if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key'};
    var base = p.baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      if (p.kind == 'nas_hub' && !base.endsWith('/v1')) base = '$base/llm/v1';
      if (!base.endsWith('/v1')) base = '$base/v1';
      final r = await _dio.post<Map<String, dynamic>>('$base/embeddings',
          data: {'model': modelId, 'input': texts}, options: Options(headers: headers));
      final data = (r.data?['data'] as List?) ?? const [];
      final sorted = [...data]..sort((a, b) => ((a['index'] ?? 0) as int).compareTo((b['index'] ?? 0) as int));
      return [for (final d in sorted) _vec(d['embedding'] as List)];
    } catch (_) {
      return null;
    }
  }

  static Float32List _vec(List v) => Float32List.fromList([for (final x in v) (x as num).toDouble()]);
}

Uint8List vectorToBlob(Float32List v) => v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes);

Float32List? blobToVector(Uint8List? b) {
  if (b == null || b.isEmpty || b.lengthInBytes % 4 != 0) return null;
  final copy = Uint8List.fromList(b);
  return copy.buffer.asFloat32List();
}

double cosine(Float32List a, Float32List b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Ranks (id, blob) pairs by cosine to [query]; runs in an isolate for large sets.
Future<List<(String, double)>> rankByCosine(Float32List query, List<(String, Uint8List)> items, {int top = 8}) async {
  List<(String, double)> run() {
    final scored = <(String, double)>[];
    for (final (id, blob) in items) {
      final v = blobToVector(blob);
      if (v == null) continue;
      scored.add((id, cosine(query, v)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(top).toList();
  }

  if (items.length < 300) return run();
  try {
    return await Isolate.run(run);
  } catch (_) {
    return run();
  }
}
