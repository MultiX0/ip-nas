// Text helpers for memory retrieval and de-duplication (Arabic-aware normalisation, FTS5 query building).

const _stop = {
  // English
  'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be', 'been', 'to', 'of', 'in', 'on', 'at',
  'for', 'with', 'about', 'as', 'by', 'it', 'its', 'this', 'that', 'these', 'those', 'i', 'me', 'my', 'you', 'your',
  'we', 'our', 'he', 'she', 'they', 'them', 'do', 'does', 'did', 'can', 'could', 'would', 'should', 'will', 'what',
  'how', 'why', 'when', 'where', 'who', 'which', 'please', 'hi', 'hello', 'thanks', 'thank', 'yes', 'no', 'not',
  'have', 'has', 'had', 'so', 'if', 'then', 'there', 'here', 'just', 'some', 'any', 'all', 'from', 'up', 'out',
  'user', 'users',
  // Arabic
  'في', 'من', 'على', 'إلى', 'الى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'تلك', 'التي', 'الذي', 'هو', 'هي', 'أنا', 'انا',
  'أنت', 'انت', 'نحن', 'هم', 'ما', 'ماذا', 'لماذا', 'كيف', 'متى', 'أين', 'اين', 'هل', 'لا', 'نعم', 'أو', 'او', 'ثم',
  'كان', 'كانت', 'يكون', 'لي', 'لك', 'له', 'لها', 'كل', 'بعض', 'قد', 'لقد', 'إن', 'ان', 'أن', 'شكرا', 'مرحبا',
  'المستخدم', 'يا', 'و',
};

final _diacritics = RegExp('[ً-ٰٟـ]');
final _splitter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lowercase, strip Arabic diacritics/tatweel, unify alef/yaa/taa marbuta forms.
String normalizeText(String s) => s
    .toLowerCase()
    .replaceAll(_diacritics, '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي');

String _stem(String t) {
  if (t.length > 4 && t.startsWith('ال')) t = t.substring(2);
  if (t.length > 5 && (t.startsWith('وال') || t.startsWith('بال') || t.startsWith('لل') || t.startsWith('كال'))) {
    t = t.substring(t.startsWith('لل') ? 2 : 3);
  }
  if (t.length > 4 && t.endsWith('s') && !t.endsWith('ss')) t = t.substring(0, t.length - 1);
  return t;
}

/// Content words (normalised, light stemming, stop words removed).
List<String> contentTokens(String s) => normalizeText(s)
    .split(_splitter)
    .where((t) => t.length >= 2 && !_stop.contains(t))
    .map(_stem)
    .where((t) => t.length >= 2)
    .toList();

/// Similarity in [0,1]: max of token Dice coefficient and containment of the shorter in the longer.
double textSimilarity(String a, String b) {
  final na = normalizeText(a).trim(), nb = normalizeText(b).trim();
  if (na == nb) return 1;
  final ta = contentTokens(a).toSet(), tb = contentTokens(b).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  final inter = ta.intersection(tb).length;
  final dice = 2 * inter / (ta.length + tb.length);
  final containment = inter / (ta.length < tb.length ? ta.length : tb.length);
  // Containment alone over-matches short texts; weight it down.
  final c = (ta.length < 3 || tb.length < 3) ? containment * 0.7 : containment * 0.9;
  return dice > c ? dice : c;
}

/// FTS5 MATCH expression (OR of quoted prefix terms), or null when the text has no usable words.
/// The index holds the raw text, so each word is searched in its raw, normalised and with/without "ال" forms.
/// Terms are quoted so user text can never inject FTS syntax.
String? ftsQuery(String text, {int maxTerms = 28}) {
  final seen = <String>{};
  final terms = <String>[];
  final arabic = RegExp('[؀-ۿ]');
  void add(String t) {
    t = t.replaceAll('"', '');
    if (t.length < 2 || !seen.add(t) || terms.length >= maxTerms) return;
    terms.add(t.length >= 3 ? '"$t"*' : '"$t"');
  }

  for (final raw in text.toLowerCase().replaceAll(_diacritics, '').split(_splitter)) {
    if (raw.length < 2 || _stop.contains(raw) || _stop.contains(normalizeText(raw))) continue;
    final stem = _stem(raw);
    add(raw);
    add(stem);
    final norm = normalizeText(stem);
    add(norm);
    if (arabic.hasMatch(stem) && !stem.startsWith('ال')) add('ال$stem');
    if (terms.length >= maxTerms) break;
  }
  return terms.isEmpty ? null : terms.join(' OR ');
}
