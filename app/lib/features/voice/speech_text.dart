// Text helpers for speech: markdown to speakable text, sentence splitting for streaming TTS and removing
// Drama 3 direction tags from captions.

final _directionBracket = RegExp(r'\[[^\]\n]{1,80}\]');
final _pairedTags = RegExp(r'</?(whisper|emphasis|soft|fast|slow|stress|forceful|[a-z]{3,12})>', caseSensitive: false);
final _phoneme = RegExp(r'<\|phoneme_start\|>.*?<\|phoneme_end\|>');
final _hasWords = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _speakerMarker = RegExp(r'<\|speaker:\d+\|>');

/// Emoji (with skin tones, flags, joiners and variation selectors) and the space in front of them.
final _emoji = RegExp(r'\s*[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}‍️⃣]+', unicode: true);

/// Removes Drama 3 performance directions (`[warmly]`, `<whisper>..</whisper>`) for on-screen captions.
String stripDirections(String s) => s
    .replaceAll(_phoneme, '')
    .replaceAll(_speakerMarker, '')
    .replaceAll(_directionBracket, '')
    .replaceAll(_pairedTags, '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();

/// Cleans an ASR transcript (speaker markers, audio-event cues).
String cleanTranscript(String s) => s.replaceAll(_speakerMarker, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Turns a markdown answer into plain speakable text: drops code blocks, tables, links' URLs, emphasis markers,
/// headings, list bullets, images, raw URLs and emoji (small models add them to spoken answers anyway).
String markdownToSpeech(String md, {bool keepDirections = true}) {
  var s = md;
  s = s.replaceAll(RegExp(r'```[\s\S]*?(```|$)'), ' ');
  s = s.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' ');
  s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\((?:[^)]+)\)'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'https?://\S+'), ' ');
  s = s.replaceAll(RegExp(r'^\s*\|.*\|\s*$', multiLine: true), ' ');
  s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*([-*+]|\d+[.)])\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*([-*_]\s*){3,}$', multiLine: true), ' ');
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'(\*\*|__|\*|~~)'), '');
  s = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), ' ');
  s = s.replaceAll(_emoji, '');
  if (!keepDirections) s = stripDirections(s);
  // A paragraph break ends a sentence, without a second mark after one that is already there ("Ready?. Yes").
  s = s
      .replaceAllMapped(RegExp(r'([.!?…؟۔:;،])?[ \t]*\n{2,}'), (m) => m.start == 0 ? '' : (m[1] == null ? '. ' : '${m[1]} '))
      .replaceAll('\n', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'(\.\s*){2,}'), '. ');
  return s.trim();
}

/// Incremental splitter: feed streamed deltas, get back complete sentences (English + Arabic punctuation).
/// Text inside ``` code fences is skipped entirely.
class SentenceSplitter {
  final _buf = StringBuffer();
  bool _inFence = false;
  bool _started = false;
  String _pendingTicks = '';

  // A sentence ends at . ! ? (also the ellipsis character, Arabic ؟ and ۔) followed by whitespace, at a newline, or
  // at an Arabic comma, Arabic semicolon or colon when at least 40 more characters follow.
  static final _end = RegExp(r'([.!?…؟۔]+["”’)]*\s)|([،؛:]\s(?=.{40,}))|(\n+)');

  /// Returns sentences completed by this delta.
  List<String> add(String delta) {
    var text = _pendingTicks + delta;
    _pendingTicks = '';
    // Hold back trailing backticks until we know whether they form a fence.
    final trailing = RegExp(r'`{1,2}$').firstMatch(text);
    if (trailing != null) {
      _pendingTicks = trailing[0]!;
      text = text.substring(0, trailing.start);
    }
    while (text.isNotEmpty) {
      final i = text.indexOf('```');
      if (i < 0) {
        if (!_inFence) _buf.write(text);
        break;
      }
      if (!_inFence) _buf.write(text.substring(0, i));
      _inFence = !_inFence;
      if (!_inFence) _buf.write(' ');
      text = text.substring(i + 3);
    }
    return _drain(force: false);
  }

  /// Flush whatever is left (end of the reply).
  List<String> close() {
    if (!_inFence && _pendingTicks.isNotEmpty) _buf.write(_pendingTicks);
    _pendingTicks = '';
    return _drain(force: true);
  }

  /// Directions that came on their own, waiting for the next sentence.
  String _lead = '';

  /// A piece that is only directions ("[cheerfully]" on a line by itself) waits for the next sentence: sent alone,
  /// Drama 3 performs it as a sound of its own (a laugh).
  void _emit(List<String> out, String speak) {
    if (!_hasWords.hasMatch(speak)) return;
    if (!_hasWords.hasMatch(stripDirections(speak))) {
      _lead = _lead.isEmpty ? speak : '$_lead $speak';
      return;
    }
    out.add(_lead.isEmpty ? speak : '$_lead $speak');
    _lead = '';
  }

  List<String> _drain({required bool force}) {
    final out = <String>[];
    var s = _buf.toString();
    while (true) {
      final m = _end.firstMatch(s);
      if (m == null) break;
      final piece = s.substring(0, m.end);
      s = s.substring(m.end);
      _emit(out, markdownToSpeech(piece));
    }
    // First audio as early as possible: the first clause goes out at a comma once it has a few words.
    if (!force && !_started && out.isEmpty) {
      final m = RegExp(r'[,،]\s').allMatches(s).where((m) => m.start >= 24).firstOrNull;
      if (m != null) {
        _emit(out, markdownToSpeech(s.substring(0, m.end)));
        s = s.substring(m.end);
      }
    }
    // Very long run-on text without punctuation: cut at a space so speech can start.
    if (!force && s.length > 140) {
      final cut = s.lastIndexOf(' ', 120);
      if (cut > 40) {
        _emit(out, markdownToSpeech(s.substring(0, cut)));
        s = s.substring(cut + 1);
      }
    }
    if (force) {
      _emit(out, markdownToSpeech(s));
      if (_lead.isNotEmpty) out.add(_lead); // a closing [small laugh] is meant to be heard
      _lead = '';
      s = '';
    }
    _buf
      ..clear()
      ..write(s);
    if (out.isNotEmpty) _started = true;
    return out;
  }
}
