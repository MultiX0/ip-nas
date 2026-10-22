// Built-in tools offered to the model: NAS control, web, memory, skills, agent.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/intelligence.dart';
import '../../core/contracts/nas.dart';
import '../../core/providers.dart';
import '../agent/nas_agent.dart';
import '../memory/memory_repo.dart';
import '../skills/skills_repo.dart';
import 'nas_http.dart';
import 'tool_formatters.dart';
import 'text_utils.dart';

class ToolCtx {
  final Ref ref;
  final String chatId;
  final String execMode; // safe | admin
  const ToolCtx(this.ref, this.chatId, this.execMode);
  NasHubClient get nas {
    final hub = ref.read(nasHubProvider);
    if (hub == null || !hub.isPaired) throw const NasNotConnected();
    return hub;
  }
}

class BuiltinTool {
  final String name;
  final String title; // short UI label
  final String group; // nas | web | memory | skills | agent
  final String description;
  final Map<String, dynamic> parameters;
  final ToolRisk Function(Map<String, dynamic> args, String execMode) risk;
  final Future<ToolResult> Function(Map<String, dynamic> args, ToolCtx ctx) run;
  final Duration timeout;
  final bool defaultEnabled;
  const BuiltinTool({
    required this.name,
    required this.title,
    required this.group,
    required this.description,
    required this.parameters,
    required this.risk,
    required this.run,
    this.timeout = const Duration(seconds: 60),
    this.defaultEnabled = true,
  });
}

ToolRisk _safe(Map<String, dynamic> a, String m) => ToolRisk.safe;
ToolRisk _approve(Map<String, dynamic> a, String m) => ToolRisk.needsApproval;

Map<String, dynamic> _obj(Map<String, dynamic> props, [List<String> required = const []]) =>
    {'type': 'object', 'properties': props, if (required.isNotEmpty) 'required': required};

String _str(Map<String, dynamic> a, String k) => (a[k] ?? '').toString().trim();
int _int(Map<String, dynamic> a, String k, int def, int min, int max) {
  final v = a[k];
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? def;
  return n.clamp(min, max);
}

const _containerActions = ['start', 'stop', 'restart', 'pause', 'unpause', 'remove'];

final List<BuiltinTool> builtinTools = [
  BuiltinTool(
    name: 'nas_system_status',
    title: 'NAS status',
    group: 'nas',
    description: "Get the live health of the user's home NAS as pre-computed, labelled values: CPU load, RAM "
        '(ram_available_mb is what is really free), CPU temperature in °C, uptime, and every disk with used/total/percent. '
        'ALWAYS prefer this tool over run_command for RAM, temperature, disk space or performance questions, and quote '
        'its numbers exactly. Never guess system values.',
    parameters: _obj({}),
    risk: _safe,
    run: (a, c) async {
      final s = await c.nas.system();
      final values = systemValues(s);
      return ToolResult(formatSystemStatus(values), display: {'type': 'system', 'data': values});
    },
  ),
  BuiltinTool(
    name: 'docker_list',
    title: 'Docker containers',
    group: 'nas',
    description: 'List the Docker containers (apps) on the NAS with name, image, state, status, CPU, memory and ports.',
    parameters: _obj({}),
    risk: _safe,
    run: (a, c) async {
      final list = await c.nas.containers();
      if (list.isEmpty) return const ToolResult('No containers on the NAS.');
      return ToolResult(formatContainers(list), display: {'type': 'containers', 'items': list});
    },
  ),
  BuiltinTool(
    name: 'docker_action',
    title: 'Docker action',
    group: 'nas',
    description: 'Start, stop, restart, pause, unpause or remove a Docker container on the NAS. The user is asked to '
        'approve. "remove" deletes the container (use only when explicitly requested).',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Container name, exactly as listed by docker_list'},
      'action': {'type': 'string', 'enum': _containerActions},
    }, ['name', 'action']),
    risk: (a, m) => _str(a, 'action') == 'remove' ? ToolRisk.dangerous : ToolRisk.needsApproval,
    run: (a, c) async {
      final name = _str(a, 'name'), action = _str(a, 'action');
      if (name.isEmpty) return const ToolResult('Missing container name.', isError: true);
      if (!_containerActions.contains(action)) {
        return ToolResult('Unknown action "$action". Use one of ${_containerActions.join(', ')}.', isError: true);
      }
      final r = await c.nas.containerAction(name, action);
      final ok = r['ok'] != false;
      return ToolResult('${ok ? 'Done' : 'Failed'}: $action $name. ${r['message'] ?? ''}'.trim(), isError: !ok);
    },
  ),
  BuiltinTool(
    name: 'docker_logs',
    title: 'Container logs',
    group: 'nas',
    description: 'Read the last lines of a Docker container log on the NAS (to diagnose errors).',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Container name'},
      'tail': {'type': 'integer', 'description': 'Number of lines from the end (default 100, max 1000)'},
    }, ['name']),
    risk: _safe,
    run: (a, c) async {
      final name = _str(a, 'name');
      if (name.isEmpty) return const ToolResult('Missing container name.', isError: true);
      final dio = await nasDio(c.ref);
      try {
        final r = await dio.get<dynamic>('/api/v1/docker/containers/${Uri.encodeComponent(name)}/logs',
            queryParameters: {'tail': _int(a, 'tail', 100, 1, 1000)});
        final d = r.data;
        final logs = d is Map ? (d['logs'] ?? '').toString() : '$d';
        return ToolResult(logs.trim().isEmpty ? '(no log output)' : logs);
      } finally {
        dio.close();
      }
    },
  ),
  BuiltinTool(
    name: 'web_search',
    title: 'Web search',
    group: 'web',
    description: "Search the web privately through the SearXNG instance on the user's NAS. Returns titles, URLs and "
        'snippets. Use for current events, facts you are unsure about, or anything after your training data. '
        'Write the query in the most useful language for the topic (Arabic or English).',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Search query'},
      'limit': {'type': 'integer', 'description': 'Number of results (1-10, default 5)'},
    }, ['query']),
    risk: _safe,
    run: (a, c) async {
      final q = _str(a, 'query');
      if (q.isEmpty) return const ToolResult('Missing query.', isError: true);
      final res = await c.nas.search(q, limit: _int(a, 'limit', 5, 1, 10));
      if (res.isEmpty) return ToolResult('No results for "$q".');
      return ToolResult(formatSearch(q, res), display: {'type': 'search', 'items': res});
    },
  ),
  BuiltinTool(
    name: 'fetch_url',
    title: 'Read web page',
    group: 'web',
    description: 'Download a web page or text file (HTTP GET) and return its readable text. Use after web_search or '
        'when the user gives a link.',
    parameters: _obj({
      'url': {'type': 'string', 'description': 'http(s) URL'},
    }, ['url']),
    risk: _safe,
    timeout: const Duration(seconds: 45),
    run: (a, c) => fetchUrl(_str(a, 'url')),
  ),
  BuiltinTool(
    name: 'run_command',
    title: 'Run command',
    group: 'nas',
    description: "Run a shell command on the NAS through Nur Hub and return exit code, stdout and stderr. In safe mode "
        'the hub only allows read-only diagnostics (df, free, uptime, docker ps, journalctl ...). Always needs the '
        "user's approval. Prefer the dedicated tools when one fits (nas_system_status for RAM/temperature/disks, "
        'docker_list/docker_logs for containers). The NAS is a Raspberry Pi: use vcgencmd measure_temp (not sensors), '
        'free -m (read the "available" column), df -h, docker ps.',
    parameters: _obj({
      'command': {'type': 'string', 'description': 'The shell command'},
    }, ['command']),
    risk: (a, mode) => mode == 'admin' ? ToolRisk.dangerous : ToolRisk.needsApproval,
    timeout: const Duration(minutes: 3),
    run: (a, c) async {
      final cmd = _str(a, 'command');
      if (cmd.isEmpty) return const ToolResult('Missing command.', isError: true);
      final r = await c.nas.exec(cmd);
      final code = r['exit_code'];
      final out = (r['stdout'] ?? '').toString(), err = (r['stderr'] ?? '').toString();
      final b = StringBuffer('exit code: $code\n');
      if (out.trim().isNotEmpty) b.write('stdout:\n$out\n');
      if (err.trim().isNotEmpty) b.write('stderr:\n$err\n');
      if (code != 0 && err.contains('not allowed')) {
        b.write('(The hub is in safe mode: only read-only commands are allowed. The user can switch to admin mode in Settings > Tools.)');
      }
      return ToolResult(b.toString().trim(), isError: code is num && code != 0);
    },
  ),
  BuiltinTool(
    name: 'memory_save',
    title: 'Save memory',
    group: 'memory',
    description: 'Save a durable fact about the user to long-term memory (when the user asks you to remember something, '
        'or shares a lasting preference or personal detail). One short sentence, in the user\'s language.',
    parameters: _obj({
      'content': {'type': 'string', 'description': 'The fact, e.g. "Prefers short answers."'},
      'category': {'type': 'string', 'enum': kMemoryCategories},
    }, ['content']),
    risk: _safe,
    run: (a, c) async {
      final text = _str(a, 'content');
      if (text.isEmpty) return const ToolResult('Nothing to save.', isError: true);
      final (_, what) = await c.ref.read(memoryRepoProvider).remember(text, category: _str(a, 'category'), source: 'model');
      return ToolResult(switch (what) {
        'duplicate' => 'Already remembered.',
        'updated' => 'Updated an existing memory.',
        _ => 'Saved to memory.',
      });
    },
  ),
  BuiltinTool(
    name: 'memory_search',
    title: 'Search memory',
    group: 'memory',
    description: 'Search long-term memory about the user (facts and preferences saved earlier).',
    parameters: _obj({
      'query': {'type': 'string'},
    }, ['query']),
    risk: _safe,
    run: (a, c) async {
      final rows = await c.ref.read(memoryRepoProvider).search(_str(a, 'query'), limit: 10);
      final enabled = rows.where((m) => m.enabled).toList();
      if (enabled.isEmpty) return const ToolResult('No matching memories.');
      return ToolResult([for (final m in enabled) '- [${m.category}] ${m.content}'].join('\n'));
    },
  ),
  BuiltinTool(
    name: 'memory_forget',
    title: 'Forget memory',
    group: 'memory',
    description: 'Delete memories matching a description, when the user asks you to forget something.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What to forget'},
    }, ['query']),
    risk: _safe,
    run: (a, c) async {
      final gone = await c.ref.read(memoryRepoProvider).forget(_str(a, 'query'));
      if (gone.isEmpty) return const ToolResult('No matching memory found.');
      return ToolResult('Forgot ${gone.length} memor${gone.length == 1 ? 'y' : 'ies'}:\n${gone.map((m) => '- ${m.content}').join('\n')}');
    },
  ),
  BuiltinTool(
    name: 'load_skill',
    title: 'Load skill',
    group: 'skills',
    description: 'Load the full instructions of one of your skills (listed in the system prompt) before doing a task it '
        'covers. Optionally load one of its extra files.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Skill name'},
      'file': {'type': 'string', 'description': 'Optional relative path of an extra file in the skill'},
    }, ['name']),
    risk: _safe,
    run: (a, c) async {
      final file = _str(a, 'file');
      return ToolResult(await c.ref.read(skillsRepoProvider).load(_str(a, 'name'), file: file.isEmpty ? null : file));
    },
  ),
  BuiltinTool(
    name: 'nas_agent',
    title: 'NAS agent',
    group: 'agent',
    description: 'Delegate a multi-step task to the agent running on the NAS (it can plan and use NAS tools on '
        'its own). Describe the task and the expected result clearly. Needs approval.',
    parameters: _obj({
      'task': {'type': 'string', 'description': 'What the agent should do'},
    }, ['task']),
    risk: _approve,
    timeout: const Duration(minutes: 10),
    defaultEnabled: false,
    run: (a, c) async {
      final task = _str(a, 'task');
      if (task.isEmpty) return const ToolResult('Missing task.', isError: true);
      final reply = await c.ref.read(nasAgentProvider).run(task);
      return ToolResult(reply.trim().isEmpty ? '(the agent returned no reply)' : reply);
    },
  ),
];

final _fetchDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 30),
  followRedirects: true,
  maxRedirects: 5,
  headers: {'User-Agent': 'Mozilla/5.0 (compatible; NurAssistant/0.1)', 'Accept': 'text/html,text/plain,application/json;q=0.9,*/*;q=0.5'},
));

Future<ToolResult> fetchUrl(String url) async {
  final u = Uri.tryParse(url);
  if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) {
    return const ToolResult('Give a full http(s) URL.', isError: true);
  }
  const cap = 2 * 1024 * 1024;
  final res = await _fetchDio.getUri<ResponseBody>(u,
      options: Options(responseType: ResponseType.stream, validateStatus: (_) => true));
  final status = res.statusCode ?? 0;
  final bytes = <int>[];
  final stream = res.data?.stream;
  if (stream != null) {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length > cap) break;
    }
  }
  if (status >= 400) return ToolResult('The page answered HTTP $status.', isError: true);
  final ct = (res.headers.value('content-type') ?? '').toLowerCase();
  if (!(ct.isEmpty || ct.contains('text') || ct.contains('json') || ct.contains('xml') || ct.contains('javascript'))) {
    return ToolResult('This URL is not a text page ($ct, ${bytes.length} bytes).', isError: true);
  }
  final body = utf8.decode(bytes, allowMalformed: true);
  if (ct.contains('html') || body.trimLeft().startsWith('<')) {
    final page = await htmlToReadableAsync(body);
    return ToolResult('${page.title.isEmpty ? '' : '# ${page.title}\n'}Source: $u\n\n${page.text}');
  }
  return ToolResult('Source: $u\n\n$body');
}
