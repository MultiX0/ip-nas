// NAS state: discovery (mDNS with a LAN scan as fallback), pairing, the saved hub and its LLM provider entry.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../../core/contracts/nas.dart';
import '../../core/providers.dart';
import '../../data/db/app_db.dart' as db;
import 'nas_hub_client.dart';

const hubPort = 8770;
const _serviceType = '_nurhub._tcp.local';

class DiscoveredHub {
  const DiscoveredHub({required this.name, required this.baseUrl, this.info = const {}});
  final String name;
  final String baseUrl;
  final Map<String, dynamic> info;
}

/// Finds Nur Hubs on the local network. Emits each hub once. mDNS first, then a quick probe of the local /24.
Stream<DiscoveredHub> discoverHubs({Duration timeout = const Duration(seconds: 8)}) {
  final out = StreamController<DiscoveredHub>();
  final seen = <String>{};
  var closed = false;

  Future<void> report(String host, int port, {String? name}) async {
    final base = 'http://${host.contains(':') ? '[$host]' : host}:$port';
    if (closed || !seen.add(base)) return;
    try {
      final info = await NasHubClientImpl.fetchInfo(base, timeout: const Duration(seconds: 3));
      if (!closed) out.add(DiscoveredHub(name: '${info['name'] ?? name ?? host}', baseUrl: base, info: info));
    } catch (_) {
      seen.remove(base); // not a hub (or not reachable yet)
    }
  }

  Future<void> mdns() async {
    MDnsClient? client;
    try {
      client = MDnsClient(rawDatagramSocketFactory: (dynamic host, int port, {bool reuseAddress = true, bool reusePort = false, int ttl = 1}) =>
          RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: !Platform.isWindows && !Platform.isAndroid ? reusePort : false, ttl: ttl));
      await client.start();
      final ptrs = client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_serviceType), timeout: timeout);
      await for (final ptr in ptrs) {
        if (closed) break;
        await for (final srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName), timeout: const Duration(seconds: 3))) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target), timeout: const Duration(seconds: 3))) {
            await report(ip.address.address, srv.port, name: ptr.domainName.split('.').first);
          }
        }
      }
    } catch (_) {
      // mDNS is unavailable on some networks/platforms; the LAN probe below covers it.
    } finally {
      client?.stop();
    }
  }

  Future<void> probeLan() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      final prefixes = <String>{};
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final p = a.address.split('.');
          if (p.length != 4) continue;
          final first = int.tryParse(p[0]) ?? 0, second = int.tryParse(p[1]) ?? 0;
          final private = first == 10 || (first == 192 && second == 168) || (first == 172 && second >= 16 && second <= 31);
          if (private) prefixes.add('${p[0]}.${p[1]}.${p[2]}');
        }
      }
      for (final prefix in prefixes.take(3)) {
        // 32 parallel connects of 350 ms each, so a /24 takes about 3 s.
        for (var start = 1; start < 255 && !closed; start += 32) {
          await Future.wait([
            for (var h = start; h < start + 32 && h < 255; h++)
              Socket.connect('$prefix.$h', hubPort, timeout: const Duration(milliseconds: 350)).then((s) {
                s.destroy();
                return report('$prefix.$h', hubPort);
              }).catchError((_) {}),
          ]);
        }
      }
    } catch (_) {}
  }

  () async {
    await Future.wait([mdns(), Future.delayed(const Duration(milliseconds: 1500), probeLan)]);
    closed = true;
    await out.close();
  }();
  out.onCancel = () => closed = true;
  return out.stream;
}

String normalizeHubUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  final u = Uri.parse(s);
  final withPort = u.hasPort ? u : u.replace(port: hubPort);
  return withPort.replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
}

String _idFor(String name) {
  final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  return 'hub_${s.isEmpty ? 'nas' : s}';
}

/// The paired, default NAS (null when none). Overrides [nasHubProvider] in the wiring.
class ActiveNasNotifier extends AsyncNotifier<NasHubClientImpl?> {
  @override
  Future<NasHubClientImpl?> build() async {
    final d = ref.watch(dbProvider);
    final rows = await (d.select(d.nasDevices)..orderBy([(t) => OrderingTerm.desc(t.isDefault)])).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    final token = await ref.read(secureStoreProvider).read(key: 'nas_token_${row.id}');
    if (token == null) return null;
    final device = NasDevice(id: row.id, name: row.name, baseUrl: row.baseUrl, token: token);
    final client = NasHubClientImpl(device);
    ref.onDispose(client.close);
    unawaited(_refreshAddress(row, token));
    return client;
  }

  /// If the NAS moved to a new IP, find it again via discovery and update the stored URL.
  Future<void> _refreshAddress(db.NasDevice row, String token) async {
    try {
      await NasHubClientImpl.fetchInfo(row.baseUrl);
      final d = ref.read(dbProvider);
      await (d.update(d.nasDevices)..where((t) => t.id.equals(row.id))).write(db.NasDevicesCompanion(lastSeen: Value(DateTime.now())));
    } catch (_) {
      await for (final hub in discoverHubs(timeout: const Duration(seconds: 5))) {
        if (_idFor(hub.name) == row.id && hub.baseUrl != row.baseUrl) {
          final d = ref.read(dbProvider);
          await (d.update(d.nasDevices)..where((t) => t.id.equals(row.id))).write(db.NasDevicesCompanion(baseUrl: Value(hub.baseUrl), lastSeen: Value(DateTime.now())));
          await _registerProvider(row.id, hub.name, hub.baseUrl, token);
          ref.invalidateSelf();
          break;
        }
      }
    }
  }

  /// Starts pairing with the hub at [baseUrl]. No code: the first device ever becomes the owner at once;
  /// later devices get `pending` with a request id until an already-paired app approves them.
  Future<({bool approved, String? requestId})> requestPair(String baseUrl, {Map<String, dynamic>? info}) async {
    final r = await NasHubClientImpl.requestPairing(baseUrl, _deviceName());
    if (r['status'] == 'approved') {
      await _savePair(baseUrl, '${r['token']}', '${r['device_id']}', info: info);
      return (approved: true, requestId: null);
    }
    return (approved: false, requestId: '${r['request_id']}');
  }

  /// Polls a pending request once. Returns 'approved' (and saves the pairing), 'pending', 'denied' or 'expired'.
  Future<String> checkPair(String baseUrl, String requestId, {Map<String, dynamic>? info}) async {
    final r = await NasHubClientImpl.pairingStatus(baseUrl, requestId);
    final status = '${r['status']}';
    if (status == 'approved') await _savePair(baseUrl, '${r['token']}', '${r['device_id']}', info: info);
    return status;
  }

  Future<NasHubClientImpl> _savePair(String baseUrl, String token, String myDeviceId, {Map<String, dynamic>? info}) async {
    final hubInfo = info ?? await NasHubClientImpl.fetchInfo(baseUrl);
    final name = '${hubInfo['name'] ?? 'NAS'}';
    final id = _idFor(name);
    final d = ref.read(dbProvider);
    final store = ref.read(secureStoreProvider);
    await store.write(key: 'nas_token_$id', value: token);
    await d.transaction(() async {
      await d.update(d.nasDevices).write(const db.NasDevicesCompanion(isDefault: Value(false)));
      await d.into(d.nasDevices).insertOnConflictUpdate(db.NasDevicesCompanion.insert(
            id: id,
            name: name,
            baseUrl: baseUrl,
            infoJson: Value(jsonEncode({...hubInfo, 'my_device_id': myDeviceId})),
            isDefault: const Value(true),
            lastSeen: Value(DateTime.now()),
          ));
    });
    await _registerProvider(id, name, baseUrl, token);
    ref.invalidateSelf();
    final client = await future;
    if (client == null) throw NasException('Pairing worked but the NAS could not be saved.');
    return client;
  }

  Future<void> forget() async {
    final c = state.value;
    if (c == null) return;
    final id = c.device!.id;
    final d = ref.read(dbProvider);
    await ref.read(secureStoreProvider).delete(key: 'nas_token_$id');
    await ref.read(secureStoreProvider).delete(key: 'provider_key_nas_$id');
    await (d.delete(d.nasDevices)..where((t) => t.id.equals(id))).go();
    await (d.delete(d.llmProviders)..where((t) => t.id.equals('nas_$id'))).go();
    ref.invalidateSelf();
  }

  /// Registers the hub's OpenAI-compatible proxy as an LLM provider so the model picker shows NAS models.
  Future<void> _registerProvider(String id, String name, String baseUrl, String token) async {
    final d = ref.read(dbProvider);
    await ref.read(secureStoreProvider).write(key: 'provider_key_nas_$id', value: token);
    await d.into(d.llmProviders).insertOnConflictUpdate(db.LlmProvidersCompanion.insert(
          id: 'nas_$id',
          kind: 'nas_hub',
          name: name.toLowerCase().contains('nas') ? name : 'NAS ($name)',
          baseUrl: '$baseUrl/llm/v1',
          preset: const Value('llamacpp'),
          enabled: const Value(true),
          extraJson: Value(jsonEncode({'nas_device_id': id, 'ollama_url': '$baseUrl/ollama'})),
        ));
  }

  /// Picks the best installed NAS model that fits in RAM and stores it as `default_model`.
  Future<String?> chooseDefaultModel() async {
    final c = state.value;
    if (c == null) return null;
    try {
      final local = (await c.localModels()).where((m) => m['runtime'] == 'llamacpp').toList();
      if (local.isEmpty) return null;
      int ram = 0;
      try {
        ram = ((await c.system())['ram_total'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      const prefer = ['qwen3.5-2b', 'qwen3-4b', 'gemma-3-4b', 'lfm2', 'granite']; // Pi benchmark order (tools + Arabic first)
      int score(Map<String, dynamic> m) {
        final id = '${m['id']}'.toLowerCase();
        final i = prefer.indexWhere(id.contains);
        // Q4_0 uses llama.cpp's fast ARM paths (Pi 5: ~10% faster writing, ~45% faster reading than Q4_K_M).
        return i < 0 ? 0 : (prefer.length - i) * 10 + (id.contains('q4_0') ? 1 : 0);
      }

      final fitting = local.where((m) => ram == 0 || ((m['size'] as num?) ?? 0) + 0.9e9 <= ram).toList()
        ..sort((a, b) {
          final s = score(b).compareTo(score(a));
          return s != 0 ? s : ((b['size'] as num?) ?? 0).compareTo((a['size'] as num?) ?? 0);
        });
      if (fitting.isEmpty) return null;
      var modelId = '${fitting.first['id']}';
      try {
        final served = await c.llmModelIds();
        final match = served.firstWhere((s) => s == modelId || s.startsWith(modelId) || modelId.startsWith(s), orElse: () => '');
        if (match.isNotEmpty) modelId = match;
      } catch (_) {}
      final ref0 = 'nas_${c.device!.id}::$modelId';
      await ref.read(dbProvider).setSetting('default_model', ref0);
      return ref0;
    } catch (_) {
      return null;
    }
  }
}

String _deviceName() {
  try {
    final host = Platform.localHostname;
    final os = Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iPhone' : Platform.isWindows ? 'Windows' : Platform.operatingSystem;
    return 'Nur on $os ($host)';
  } catch (_) {
    return 'Nur app';
  }
}

final activeNasProvider = AsyncNotifierProvider<ActiveNasNotifier, NasHubClientImpl?>(ActiveNasNotifier.new);
