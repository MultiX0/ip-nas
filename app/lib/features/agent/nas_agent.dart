// Optional agent mode: hands a multi-step task to an agent on the NAS through the hub
// (POST /api/v1/agent with {message}, answered with {reply}; the hub needs NUR_HUB_AGENT_URL set).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tools/nas_http.dart';

class NasAgent {
  NasAgent(this._ref);
  final Ref _ref;

  Future<String> run(String task) async {
    final dio = await nasDio(_ref, receive: const Duration(minutes: 10));
    try {
      final r = await dio.post<dynamic>('/api/v1/agent', data: {'message': task});
      final d = r.data;
      if (d is Map) return (d['reply'] ?? d['message'] ?? '').toString();
      return d?.toString() ?? '';
    } finally {
      dio.close();
    }
  }
}

final nasAgentProvider = Provider<NasAgent>((ref) => NasAgent(ref));
