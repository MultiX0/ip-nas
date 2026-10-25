// Direct Nur Hub calls for endpoints the NasHubClient contract does not cover (logs, agent).
// Uses the paired device from nasHubProvider, or the default NasDevices row + secure token as a fallback.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class NasNotConnected implements Exception {
  const NasNotConnected();
  @override
  String toString() =>
      'The NAS is not connected. Ask the user to pair their NAS in Settings > NAS (Nur Hub must be running on it).';
}

Future<Dio> nasDio(Ref ref, {Duration receive = const Duration(seconds: 60)}) async {
  String? base;
  String? token;
  final hub = ref.read(nasHubProvider);
  if (hub?.device != null) {
    base = hub!.device!.baseUrl;
    token = hub.device!.token;
  }
  if (base == null || token == null) {
    final db = ref.read(dbProvider);
    final rows = await (db.select(db.nasDevices)..orderBy([(d) => OrderingTerm.desc(d.isDefault)])).get();
    if (rows.isNotEmpty) {
      base ??= rows.first.baseUrl;
      token ??= await ref.read(secureStoreProvider).read(key: 'nas_token_${rows.first.id}');
    }
  }
  if (base == null || base.isEmpty || token == null || token.isEmpty) throw const NasNotConnected();
  return Dio(BaseOptions(
    baseUrl: base.replaceAll(RegExp(r'/+$'), ''),
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: receive,
    headers: {'Authorization': 'Bearer $token'},
  ));
}

/// Plain-words message for network errors from the hub.
String nasErrorText(Object e) {
  if (e is NasNotConnected) return e.toString();
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) return 'The NAS rejected the request (not authorised). Re-pair the NAS in Settings > NAS.';
    if (code == 404) return 'This NAS hub does not support that action (update Nur Hub on the NAS).';
    if (code != null) {
      final d = e.response?.data;
      final msg = d is Map ? (d['detail'] ?? d['message'] ?? d['error']) : null;
      return 'The NAS answered with HTTP $code${msg == null ? '' : ': $msg'}.';
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.connectionError =>
        'Cannot reach the NAS. Check that it is on and on the same network (or reachable via VPN).',
      DioExceptionType.receiveTimeout => 'The NAS took too long to answer.',
      _ => 'Network error talking to the NAS: ${e.message ?? e.type.name}',
    };
  }
  return e.toString();
}
