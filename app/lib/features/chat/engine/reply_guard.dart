// Cheap, rule-based checks on a small model's reply (no second model, no "please double-check" prompt: small models
// cannot verify themselves, arXiv 2310.01798). Removes what should never be shown (a self-introduction in the middle
// of a conversation, a repeated question, a greeting the user did not ask for, stray Chinese text) and asks for ONE
// retry when the reply is in the wrong language or claims an action no tool ran. Pure Dart, no Flutter imports.

class GuardResult {
  /// Cleaned reply (unchanged when nothing had to be removed).
  final String text;
  final List<String> issues;
  /// Non-null: ask the model once more with this request-only hint.
  final String? retryHint;
  const GuardResult(this.text, this.issues, this.retryHint);
  bool get changed => issues.isNotEmpty;
}

final _sentence = RegExp(r'[^.!?؟\n]+[.!?؟]*\s*');
final _reintroEn = RegExp(r"\b(I am|I'm|I’m|this is|my name is) Nur\b|\bI am an AI assistant\b|\bI'm an AI assistant\b", caseSensitive: false);
final _reintroAr = RegExp(r'(أنا|انا|اسمي|معك) نور|أنا مساعد(ك)? (ذكي|الذكي|افتراضي)');
final _greeting = RegExp(r"^\s*(hi|hello|hey|greetings|good (morning|afternoon|evening))( there| again)?[!,.]*\s*|^\s*(مرحباً|مرحبا|أهلاً|أهلا|اهلا|أهلاً بك|السلام عليكم)[!،,.]*\s*",
    caseSensitive: false);
final _userGreets = RegExp(r"\b(hi|hello|hey|morning|evening)\b|مرحب|أهلا|اهلا|السلام|هلا|صباح|مساء", caseSensitive: false);
final _cjk = RegExp(r'[぀-ヿ㐀-䶿一-鿿가-힯]+');
final _claimEn = RegExp(
    r"\b(I(?:'ve| have)? (?:just )?(?:restarted|stopped|started|saved|removed|deleted|set|sent|turned (?:on|off)|ordered|booked|played|backed up)|(?:has|have) been (?:restarted|stopped|started|saved|removed|deleted|set|sent)|is now (?:restarted|stopped|running|playing))\b",
    caseSensitive: false);
final _claimAr = RegExp(r'(تمت? (إعادة تشغيل|إيقاف|تشغيل|حفظ|حذف|إرسال|ضبط)|قمت (بإعادة|بإيقاف|بتشغيل|بحفظ|بحذف|بإرسال|بضبط)|أعدت تشغيل|أوقفت|شغّلت|حفظت|أرسلت)');

double arabicShare(String s) {
  final t = s.replaceAll(RegExp(r'`[^`]*`'), '').replaceAll(
      RegExp(r'\b(nas|ram|cpu|gb|mb|tb|jellyfin|searxng|nur-hub|llamacpp|docker|nextcloud|debian|raspberry|pi|nur|immich|syncthing|wi-?fi|usb|ssd|hdd)\b',
          caseSensitive: false),
      '');
  final a = RegExp(r'[؀-ۿ]').allMatches(t).length, l = RegExp(r'[A-Za-z]').allMatches(t).length;
  return a + l == 0 ? 0 : a / (a + l);
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// [allowIntro]: the user greeted or asked who Nur is. [toolsRan]: a tool ran in this turn (an action claim is backed).
GuardResult guardReply(String reply,
    {required String userText, required String lang, bool allowIntro = false, bool toolsRan = false, bool retried = false}) {
  var text = reply.trim();
  final issues = <String>[];
  if (text.isEmpty) return GuardResult(text, const ['empty'], retried ? null : _retryHint('empty', lang));

  // Stray CJK text (Qwen drifts into Chinese).
  if (_cjk.hasMatch(text)) {
    text = text.replaceAll(_cjk, '').replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    issues.add('cjk');
  }
  // A greeting the user did not ask for, at the start.
  if (!allowIntro && !_userGreets.hasMatch(userText) && _greeting.hasMatch(text)) {
    final t = text.replaceFirst(_greeting, '').trim();
    if (t.isNotEmpty) {
      text = t;
      issues.add('greeting');
    }
  }
  // Self-introduction sentences in the middle of a conversation.
  if (!allowIntro) {
    final kept = <String>[];
    var dropped = false;
    for (final m in _sentence.allMatches(text)) {
      final s = m[0]!;
      if (_reintroEn.hasMatch(s) || _reintroAr.hasMatch(s)) {
        dropped = true;
      } else {
        kept.add(s);
      }
    }
    final t = kept.join().trim();
    if (dropped && t.isNotEmpty) {
      text = t;
      issues.add('reintro');
    }
  }
  // The user's question repeated back as the first sentence.
  final nu = _norm(userText);
  if (nu.length >= 12) {
    final first = _sentence.firstMatch(text)?[0] ?? '';
    if (_norm(first) == nu || (_norm(first).startsWith(nu) && _norm(first).length < nu.length + 4)) {
      final t = text.substring(first.length).trim();
      if (t.isNotEmpty) {
        text = t;
        issues.add('echo');
      }
    }
  }
  if (text.isNotEmpty && text[0].toLowerCase() != text[0].toUpperCase() && text[0] == text[0].toLowerCase() && issues.isNotEmpty) {
    text = text[0].toUpperCase() + text.substring(1);
  }

  // Retry once: wrong language, or an action claimed without a tool.
  String? retry;
  final share = arabicShare(text);
  if (lang == 'ar' && share < 0.4) {
    issues.add('language');
    retry = _retryHint('language', lang);
  } else if (lang == 'en' && share > 0.2) {
    issues.add('language');
    retry = _retryHint('language', lang);
  } else if (!toolsRan && (_claimEn.hasMatch(text) || _claimAr.hasMatch(text))) {
    issues.add('claim');
    retry = _retryHint('claim', lang);
  }
  return GuardResult(text, issues, retried ? null : retry);
}

String _retryHint(String kind, String lang) {
  final ar = lang == 'ar';
  switch (kind) {
    case 'language':
      return ar ? '(مهم: اكتب ردك كاملاً باللغة العربية فقط.)' : '(Important: write your whole reply in English only.)';
    case 'claim':
      return ar
          ? '(لم تستخدم أي أداة في هذا الرد، فلا تقل إنك نفذت شيئاً. أجب بصدق.)'
          : '(You did not run any tool for this reply, so do not say you did something. Answer honestly.)';
    default:
      return ar ? '(أجب عن سؤال المستخدم باختصار.)' : "(Answer the user's message briefly.)";
  }
}
