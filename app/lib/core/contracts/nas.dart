// Contract for the Nur Hub service running on the NAS (hub/ in this repo). Implemented by features/nas.
class NasDevice {
  final String id;
  final String name;
  final String baseUrl; // http://host:port
  final String? token;
  const NasDevice({required this.id, required this.name, required this.baseUrl, this.token});
}

abstract class NasHubClient {
  NasDevice? get device;
  bool get isPaired;
  /// GET /api/v1/system: cpu, ram, temp, disks, uptime.
  Future<Map<String, dynamic>> system();
  /// GET /api/v1/docker/containers
  Future<List<Map<String, dynamic>>> containers();
  /// POST /api/v1/docker/containers/{name}/{action}  action: start|stop|restart|pause|unpause|remove
  Future<Map<String, dynamic>> containerAction(String name, String action);
  /// GET /api/v1/search?q=  (SearXNG on the NAS)
  Future<List<Map<String, dynamic>>> search(String query, {int limit = 5});
  /// POST /api/v1/exec {command}, returns {exit_code, stdout, stderr}. The hub enforces its own allow-list.
  Future<Map<String, dynamic>> exec(String command);
  /// Base URL of the OpenAI-compatible endpoint the hub proxies (llama.cpp on the NAS).
  String? get llmBaseUrl;
}
