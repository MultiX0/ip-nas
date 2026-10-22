// Small-model tool router: picks at most [maxTools] tools for one turn from the user's words (English + Arabic),
// and shortens tool descriptions. Small models choose the right tool far more often from a short list
// ("Less is More", arXiv 2411.15399; TinyAgent tool retrieval, arXiv 2409.00608).
//
// The KV cache matters as much as accuracy on a Pi (prompt processing ~40 tokens/s): the tool list is part of
// the cached prompt prefix, so the router keeps a fixed CORE set in a fixed order and only adds extras when the
// message clearly needs them. Most turns therefore send the exact same tool block and reuse the cache.
// Pure Dart (no Flutter imports).
import '../../core/contracts/llm.dart';

/// Always offered in small-model mode (when enabled), in this order. Fixed so the tool block (part of the cached
/// prompt prefix) is byte-identical across turns, chats, the voice call and the prewarm request.
const kCoreTools = ['nas_system_status', 'docker_list', 'docker_action', 'web_search'];

/// Built-in order; the routed list keeps it so equal choices give byte-identical prompts.
const _order = [
  'nas_system_status', 'docker_list', 'docker_action', 'docker_logs', 'web_search', 'fetch_url', 'run_command',
  'memory_save', 'memory_search', 'memory_forget', 'load_skill', 'nas_agent',
];

RegExp _en(List<String> words) => RegExp('(?<![a-z])(${words.join('|')})(?![a-z])', caseSensitive: false);

final _enWords = <String, RegExp>{
  'nas_system_status': _en([
    'ram', 'memory usage', 'free memory', r'temp(erature)?s?', 'hot', 'heat', 'cpu', 'load', r'disks?', 'storage', 'space',
    r'drives?', r'hdd\d?', 'ssd', 'full', 'uptime', 'health', 'status', 'performance', 'slow', 'nas', 'pi', 'raspberry', 'fan',
    r'thrott\w*',
  ]),
  'docker_list': _en([
    r'apps?', r'applications?', r'containers?', 'docker', r'services?', 'running', 'installed', 'jellyfin', 'searxng',
    'llamacpp', 'immich', 'nextcloud', 'plex',
  ]),
  'docker_action': _en(['restart', 'reboot', 'start', 'stop', 'pause', 'unpause', 'remove', 'kill', 'turn (on|off)']),
  'docker_logs': _en([r'logs?', r'crash\w*', 'not working', 'unhealthy']),
  'web_search': _en([
    'search', 'google', 'look ?up', 'latest', 'newest', 'news', r'current(ly)?', 'today', 'price', r'versions?', r'release[sd]?',
    'weather', 'who (is|won)', r'20[2-3]\d', 'internet', 'online', 'web',
  ]),
  'fetch_url': RegExp(r'https?://|www\.|\b[a-z0-9-]+\.(com|org|net|io|dev|ai|sa)\b', caseSensitive: false),
  'run_command': _en(['command', 'shell', 'terminal', 'execute', 'bash', 'vcgencmd', 'df', 'journalctl', 'systemctl']),
  'memory_save': _en(['remember', "don'?t forget", 'note that', 'keep in mind', 'my name is', 'call me', 'i (like|love|prefer|hate)']),
  'memory_search': _en(['what do you (know|remember)', 'do you remember', 'recall', 'about me']),
  'memory_forget': _en(['forget']),
  'load_skill': _en(['skill', r'skills']),
  'nas_agent': _en(['agent', 'zeroclaw']),
};

// Arabic: substring match (handles the attached prefixes ال / و / ب / ف).
const _arWords = <String, List<String>>{
  'nas_system_status': [
    'رام', 'الذاكرة', 'ذاكرة', 'حرارة', 'حرار', 'ساخن', 'سخون', 'معالج', 'قرص', 'أقراص', 'اقراص', 'مساحة', 'تخزين', 'ممتلئ',
    'حالة', 'أداء', 'بطيء', 'الجهاز', 'الناس', 'السيرفر', 'الخادم', 'المروحة',
  ],
  'docker_list': ['تطبيق', 'تطبيقات', 'حاوية', 'حاويات', 'دوكر', 'خدمة', 'خدمات', 'شغال', 'تعمل', 'يعمل', 'مثبت'],
  'docker_action': [
    'أعد تشغيل', 'اعد تشغيل', 'إعادة تشغيل', 'اعادة تشغيل', 'أعِد', 'شغّل', 'شغل ', 'أوقف', 'اوقف', 'إيقاف', 'ايقاف', 'احذف', 'أزل', 'ازل',
  ],
  'docker_logs': ['سجل', 'سجلات', 'لا يعمل', 'تعطل', 'معطل'],
  'web_search': [
    'ابحث', 'بحث', 'أخبار', 'اخبار', 'آخر', 'أحدث', 'احدث', 'سعر', 'أسعار', 'إصدار', 'اصدار', 'نسخة', 'اليوم', 'الطقس', 'من هو',
    'من فاز', 'الإنترنت', 'الانترنت',
  ],
  'fetch_url': ['رابط', 'الرابط'],
  'run_command': ['أمر', 'الأمر', 'نفذ', 'نفّذ', 'الطرفية'],
  'memory_save': ['تذكر', 'تذكّر', 'احفظ', 'لا تنس', 'اسمي', 'أنا أحب', 'أفضل'],
  'memory_search': ['هل تتذكر', 'ماذا تعرف عني', 'ماذا تتذكر', 'عني'],
  'memory_forget': ['انس', 'انسَ', 'إنس', 'امسح من الذاكرة'],
  'load_skill': ['مهارة'],
};

/// Names of the tools the user's message asks for (no core defaults).
Set<String> intentTools(String text) {
  final hits = <String>{};
  _enWords.forEach((name, re) {
    if (re.hasMatch(text)) hits.add(name);
  });
  _arWords.forEach((name, words) {
    if (words.any(text.contains)) hits.add(name);
  });
  return hits;
}

/// Picks the small-model tool set for a chat: the fixed core plus extras that any user message of the visible history
/// clearly asks for (or that were already called). The set only grows during a chat, so the prompt cache is broken at
/// most once per extra tool, never turn-to-turn.
List<LlmToolSpec> routeTools(Iterable<String> userTexts, List<LlmToolSpec> available,
    {Iterable<String> called = const [], int maxTools = 7}) {
  if (available.length <= 1) return available;
  final byName = {for (final t in available) t.name: t};
  final hits = <String>{...called.where(byName.containsKey)};
  for (final text in userTexts) {
    hits.addAll(intentTools(text));
    // MCP / unknown tools: offered when a word of their name appears in a message.
    final lower = text.toLowerCase();
    for (final t in available) {
      if (_order.contains(t.name)) continue;
      final words = t.name.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 4 && w != 'mcp');
      if (words.any(lower.contains)) hits.add(t.name);
    }
  }
  final chosen = <String>{for (final n in kCoreTools) if (byName.containsKey(n)) n};
  final extras = [
    for (final n in _order) if (hits.contains(n) && !chosen.contains(n)) n,
    for (final t in available) if (!_order.contains(t.name) && hits.contains(t.name)) t.name,
  ];
  for (final n in extras) {
    if (chosen.length >= maxTools) break;
    chosen.add(n);
  }
  return [for (final t in available) if (chosen.contains(t.name)) t]..sort((a, b) => _rank(a.name).compareTo(_rank(b.name)));
}

int _rank(String name) {
  final i = _order.indexOf(name);
  return i < 0 ? 1000 : i;
}

/// One-line descriptions for small models (the long ones cost ~1,000 prompt tokens).
const _shortDescriptions = {
  'nas_system_status': 'Live NAS health: free RAM, CPU temperature, CPU load, disk usage, uptime. Use for any question about the NAS RAM, temperature, disks or speed.',
  'docker_list': 'List the apps (Docker containers) on the NAS and whether they run.',
  'docker_action': 'Start, stop, restart, pause, unpause or remove one app (Docker container) on the NAS. The user approves it.',
  'docker_logs': 'Read the last log lines of one app (Docker container).',
  'web_search': 'Search the web for current information (news, versions, prices, facts). Returns the top results.',
  'fetch_url': 'Read the text of a web page (http or https URL).',
  'run_command': 'Run a read-only shell command on the NAS (a Raspberry Pi). Use only when no other tool fits.',
  'memory_save': 'Save one short fact about the user to long-term memory, when the user asks you to remember something.',
  'memory_search': 'Search the facts saved about the user.',
  'memory_forget': 'Delete saved facts the user asks you to forget.',
  'load_skill': 'Load the instructions of one of your skills by name.',
  'nas_agent': 'Give a multi-step NAS task to the agent on the NAS.',
};

/// Short description + parameters without property descriptions (names, types, enums and required stay).
LlmToolSpec compactTool(LlmToolSpec t) {
  var desc = _shortDescriptions[t.name];
  if (desc == null) {
    final first = t.description.split(RegExp(r'(?<=[.!?])\s')).first.trim();
    desc = first.length > 160 ? '${first.substring(0, 157)}...' : first;
  }
  var params = _stripDescriptions(t.parameters);
  if (t.name == 'memory_save') {
    // The category enum confuses tiny models; the repo files the fact under 'general' when it is missing.
    final props = Map<String, dynamic>.from((params['properties'] as Map?) ?? const {})..remove('category');
    params = {...params, 'properties': props};
  }
  return LlmToolSpec(name: t.name, description: desc, parameters: params);
}

Map<String, dynamic> _stripDescriptions(Map<String, dynamic> schema) {
  final props = schema['properties'];
  if (props is! Map) return schema;
  return {
    ...schema,
    'properties': {
      for (final e in props.entries)
        '${e.key}': e.value is Map ? {for (final f in (e.value as Map).entries) if (f.key != 'description') '${f.key}': f.value} : e.value,
    },
  };
}
