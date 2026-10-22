// Heavy string work for tool results, meant to run off the UI isolate.
import 'dart:convert';
import 'dart:isolate';

/// Keeps the head and the tail of a long text with a marker in between.
String truncateMiddle(String s, int max) {
  if (s.length <= max) return s;
  final head = (max * 0.75).floor();
  final tail = max - head;
  final omitted = s.length - head - tail;
  return '${s.substring(0, head)}\n\n[$omitted characters omitted]\n\n${s.substring(s.length - tail)}';
}

/// Converts any JSON-able value to readable text and truncates it; isolate for large inputs.
Future<String> formatAndTruncate(Object? value, int max) async {
  String run() {
    final s = value is String ? value : const JsonEncoder.withIndent(' ').convert(value);
    return truncateMiddle(s, max);
  }

  final big = value is String ? value.length > 40000 : (value is List && value.length > 200) || (value is Map && value.length > 200);
  if (!big) return run();
  try {
    return await Isolate.run(run);
  } catch (_) {
    return run();
  }
}

class ReadablePage {
  final String title;
  final String text;
  const ReadablePage(this.title, this.text);
}

const _entities = {'&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'", '&mdash;': '—', '&ndash;': '–', '&hellip;': '…'};

ReadablePage htmlToReadable(String html) {
  var title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim() ?? '';
  _entities.forEach((k, v) => title = title.replaceAll(k, v));
  var s = html.replaceAll(RegExp(r'<head(\s[^>]*)?>[\s\S]*?</head>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<title[^>]*>[\s\S]*?</title>', caseSensitive: false), ' ');
  // Prefer <article> or <main> when present.
  final main = RegExp(r'<(article|main)[^>]*>([\s\S]*?)</\1>', caseSensitive: false).firstMatch(s);
  if (main != null && (main.group(2)?.length ?? 0) > 500) s = main.group(2)!;
  s = s.replaceAll(RegExp(r'<(script|style|noscript|svg|nav|footer|header|form|iframe|template)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  s = s.replaceAllMapped(RegExp(r'<h([1-6])[^>]*>', caseSensitive: false), (m) => '\n\n${'#' * int.parse(m[1]!)} ');
  s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n- ');
  s = s.replaceAll(RegExp(r'<(br|/p|/div|/h[1-6]|/li|/tr|p|div|tr|section|/section)[^>]*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = s.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (m) {
    final v = m[1]!;
    final code = v.startsWith('x') || v.startsWith('X') ? int.tryParse(v.substring(1), radix: 16) : int.tryParse(v);
    return code == null || code > 0x10FFFF ? ' ' : String.fromCharCode(code);
  });
  _entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAll(RegExp(r'[ \t\f\r]+'), ' ');
  s = s.split('\n').map((l) => l.trim()).join('\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return ReadablePage(title, s);
}

Future<ReadablePage> htmlToReadableAsync(String html) async {
  if (html.length < 20000) return htmlToReadable(html);
  try {
    return await Isolate.run(() => htmlToReadable(html));
  } catch (_) {
    return htmlToReadable(html);
  }
}
