// Tool result text for the NAS / web tools: labelled values and a SUMMARY line first (small models copy it instead of
// mis-converting raw numbers). Pure Dart, no Flutter imports.
import 'dart:convert';

String formatBytes(num? v) {
  if (v == null) return '?';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var x = v.toDouble();
  var i = 0;
  while (x >= 1024 && i < u.length - 1) {
    x /= 1024;
    i++;
  }
  return '${x.toStringAsFixed(x >= 100 || i == 0 ? 0 : 1)} ${u[i]}';
}

/// Converts a memory/disk amount of unknown unit (bytes, KB or MB) to MB.
double? _toMb(Object? v, {bool disk = false}) {
  if (v is! num) return null;
  final x = v.toDouble();
  if (x > (disk ? 5e7 : 1e8)) return x / 1048576; // bytes
  if (x > 2e5) return x / 1024; // KB
  return x; // already MB
}

double _r1(double v) => (v * 10).roundToDouble() / 10;

/// Labelled, unit-explicit values small local models can quote without interpreting raw output.
Map<String, Object?> systemValues(Map<String, dynamic> s) {
  num? n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  final total = _toMb(n(s['ram_total']));
  final used = _toMb(n(s['ram_used']));
  final avail = _toMb(n(s['ram_available'] ?? s['ram_avail'])) ?? (total != null && used != null ? total - used : null);
  final temp = n(s['temp'] ?? s['cpu_temp'] ?? s['temperature']);
  final disks = <Map<String, Object?>>[];
  for (final d in (s['disks'] as List? ?? const [])) {
    if (d is! Map) continue;
    final t = _toMb(n(d['total']), disk: true), u = _toMb(n(d['used']), disk: true);
    disks.add({
      'mount': d['mount'] ?? d['name'] ?? '?',
      'used_gb': u == null ? null : _r1(u / 1024),
      'total_gb': t == null ? null : _r1(t / 1024),
      'free_gb': t == null || u == null ? null : _r1((t - u) / 1024),
      'percent_used': t == null || u == null || t == 0 ? null : (u / t * 100).round(),
    });
  }
  final net = s['net'];
  return {
    'cpu_load_percent': n(s['cpu']),
    'ram_total_mb': total?.round(),
    'ram_used_mb': used?.round(),
    'ram_available_mb': avail?.round(),
    'ram_percent_used': total == null || used == null || total == 0 ? null : (used / total * 100).round(),
    'cpu_temp_c': temp == null ? null : _r1(temp.toDouble() > 1000 ? temp / 1000 : temp.toDouble()),
    'uptime': _uptime(s['uptime']),
    'net_rx': net is Map ? formatBytes(net['rx'] as num?) : null,
    'net_tx': net is Map ? formatBytes(net['tx'] as num?) : null,
    'wifi': s['wifi'] is Map ? jsonEncode(s['wifi']) : s['wifi'],
    'disks': disks,
  };
}

String _uptime(Object? v) {
  if (v is! num) return '${v ?? '?'}';
  final s = v.toInt();
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  return d > 0 ? '${d}d ${h}h' : '${h}h ${m}m';
}

/// Disks worth reporting: every mount the hub lists except the boot partition (/boot, /boot/firmware).
bool reportedDisk(Object? mount) => !'${mount ?? ''}'.startsWith('/boot');

/// Short disk name: [system] for /, else the last part of the mount point (/DATA/HDD1 is HDD1).
String diskLabel(Object? mount, {String system = 'system disk'}) {
  final m = '${mount ?? '?'}';
  if (m == '/') return system;
  final parts = m.split('/')..removeWhere((p) => p.isEmpty);
  return parts.isEmpty ? m : parts.last;
}

/// `nas_system_status` result text from [systemValues].
String formatSystemStatus(Map<String, Object?> values) {
  // One ready-made sentence first: small models copy it instead of mis-converting numbers.
  String gb(Object? mb) => mb is num ? (mb / 1024).toStringAsFixed(1) : '?';
  final dl = (values['disks'] as List? ?? const [])
      .cast<Map>()
      .where((d) => reportedDisk(d['mount']))
      .map((d) => '${diskLabel(d['mount'])} ${d['percent_used']}% used')
      .join(', ');
  final b = StringBuffer('SUMMARY (copy these numbers exactly): RAM ${gb(values['ram_available_mb'])} GB free of '
      '${gb(values['ram_total_mb'])} GB, CPU temperature ${values['cpu_temp_c']} °C, CPU load ${values['cpu_load_percent']}%'
      '${dl.isEmpty ? '' : ', disks: $dl'}.\n\n');
  b.write('NAS status (exact values, quote them as-is):\n');
  values.forEach((k, v) {
    if (v is List) {
      for (final d in v) {
        b.writeln('- disk ${(d as Map)['mount']}: used_gb=${d['used_gb']}, total_gb=${d['total_gb']}, '
            'free_gb=${d['free_gb']}, percent_used=${d['percent_used']}%');
      }
    } else if (v != null) {
      b.writeln('- $k: $v');
    }
  });
  return b.toString().trim();
}

/// `docker_list` result text.
String formatContainers(List<Map<String, dynamic>> list) {
  if (list.isEmpty) return 'No containers on the NAS.';
  // SUMMARY first: small models copy it instead of re-reading the whole list.
  final running = [for (final x in list) if ('${x['state']}' == 'running') '${x['name']}'];
  final other = [for (final x in list) if ('${x['state']}' != 'running') '${x['name']} (${x['state'] ?? '?'})'];
  final b = StringBuffer('SUMMARY: ${list.length} apps: ${running.length} running${running.isEmpty ? '' : ' (${running.join(', ')})'}'
      '${other.isEmpty ? '' : ', ${other.length} not running (${other.join(', ')})'}.\n\n');
  for (final x in list) {
    b.writeln('- ${x['name']} · ${x['image'] ?? ''} · ${x['state'] ?? ''} (${x['status'] ?? ''})'
        '${x['cpu'] != null ? ' · cpu ${x['cpu']}%' : ''}'
        '${x['mem_used'] != null ? ' · mem ${formatBytes(x['mem_used'] as num?)}${x['mem_limit'] != null ? '/${formatBytes(x['mem_limit'] as num?)}' : ''}' : ''}'
        '${(x['ports'] ?? '').toString().isNotEmpty ? ' · ports ${x['ports'] is String ? x['ports'] : jsonEncode(x['ports'])}' : ''}');
  }
  return b.toString().trim();
}

/// `web_search` result text: SUMMARY with the top 3 snippets first (what a small model needs to answer), then the sources.
String formatSearch(String q, List<Map<String, dynamic>> res) {
  if (res.isEmpty) return 'No results for "$q".';
  String clip(Object? v, int n) {
    final t = '${v ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= n) return t;
    final cut = t.substring(0, n);
    final sp = cut.lastIndexOf(' ');
    return '${sp > n * 0.6 ? cut.substring(0, sp) : cut}...';
  }

  final b = StringBuffer('SUMMARY: top results for "$q":\n');
  for (final (i, r) in res.take(3).indexed) {
    b.writeln('${i + 1}. ${r['title'] ?? ''}: ${clip(r['content'], 220)}');
  }
  b.writeln('\nSources:');
  for (final (i, r) in res.indexed) {
    b.writeln('[${i + 1}] ${r['title'] ?? ''} - ${r['url'] ?? ''}');
    if (i >= 3) b.writeln('    ${clip(r['content'], 300)}');
  }
  b.write('Cite a source as a markdown link when you use it. Use fetch_url to read a page in full when the snippets are not enough.');
  return b.toString();
}
