// Token accounting: exact counts through the backend tokenizer (llama.cpp /tokenize via LlmClient.countTokens)
// with a per-message cache, otherwise a script-aware estimate. Long batches are estimated off the UI isolate.
import 'dart:async';
import 'dart:isolate';

import '../../core/contracts/llm.dart';

/// Tokens a chat template adds around each message (role markers, separators).
const kPerMessageOverhead = 4;

/// Rough cost of one image for vision models (typical 512-1024 px tile budget).
const kImageTokens = 768;

/// Script-aware estimate: ~3.6 chars/token for Latin text and code, ~2.2 for Arabic, ~1 per CJK character.
int estimateTokens(String s) {
  if (s.isEmpty) return 0;
  var arabic = 0, cjk = 0, other = 0;
  for (final c in s.codeUnits) {
    if ((c >= 0x0600 && c <= 0x06FF) ||
        (c >= 0x0750 && c <= 0x077F) ||
        (c >= 0x08A0 && c <= 0x08FF) ||
        (c >= 0xFB50 && c <= 0xFDFF) ||
        (c >= 0xFE70 && c <= 0xFEFF)) {
      arabic++;
    } else if ((c >= 0x3040 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7AF)) {
      cjk++;
    } else {
      other++;
    }
  }
  return (arabic / 2.2 + other / 3.6 + cjk).ceil();
}

List<int> _estimateAll(List<String> texts) => [for (final t in texts) estimateTokens(t)];

Future<List<int>> _estimateInIsolate(List<String> texts) => Isolate.run(() => _estimateAll(texts));

/// One piece of text to count. [key] identifies it for caching (message id, or a hash for prompt parts).
class TokenItem {
  final String key;
  final String text;
  const TokenItem(this.key, this.text);
}

class TokenCounts {
  final List<int> counts;
  final bool exact;
  const TokenCounts(this.counts, this.exact);
}

class TokenCounter {
  TokenCounter(this._clientFor);
  final LlmClient? Function(String providerId) _clientFor;

  final _cache = <String, int>{};
  static const _cacheMax = 6000;
  // Per provider: until when exact counting is treated as unavailable.
  final _unavailableUntil = <String, DateTime>{};

  String _cacheKey(LlmModel m, TokenItem it) => '${m.ref}|${it.key}|${it.text.length}|${it.text.hashCode}';

  /// Estimates all items (in an isolate for long inputs).
  Future<List<int>> estimate(List<String> texts) async {
    var total = 0;
    for (final t in texts) {
      total += t.length;
    }
    if (total < 60000) return _estimateAll(texts);
    try {
      return await _estimateInIsolate(texts);
    } catch (_) {
      return _estimateAll(texts);
    }
  }

  bool _exactPossible(LlmModel model) {
    if (model.providerId.isEmpty) return false;
    final until = _unavailableUntil[model.providerId];
    return until == null || DateTime.now().isAfter(until);
  }

  /// Counts [items]. Uses the backend tokenizer when it answers; at most [maxUncached] network calls are made
  /// (the rest are estimated and warmed in the background) so a request is never held up by a long history.
  Future<TokenCounts> count(LlmModel model, List<TokenItem> items, {int maxUncached = 1 << 30}) async {
    final out = List<int>.filled(items.length, 0);
    final client = _exactPossible(model) ? _clientFor(model.providerId) : null;
    if (client == null) {
      final est = await estimate([for (final i in items) i.text]);
      return TokenCounts(est, false);
    }
    final missing = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (items[i].text.isEmpty) continue;
      final hit = _cache[_cacheKey(model, items[i])];
      if (hit != null) {
        out[i] = hit;
      } else {
        missing.add(i);
      }
    }
    var exact = true;
    final now = missing.take(maxUncached).toList();
    final later = missing.skip(maxUncached).toList();
    if (later.isNotEmpty) {
      exact = false;
      unawaited(_warm(client, model, [for (final i in later) items[i]]));
    }
    final failed = <int>[];
    for (var start = 0; start < now.length; start += 8) {
      final batch = now.sublist(start, (start + 8).clamp(0, now.length));
      final results = await Future.wait(batch.map((i) => _exact(client, model, items[i])));
      for (var j = 0; j < batch.length; j++) {
        final r = results[j];
        if (r == null) {
          failed.add(batch[j]);
        } else {
          out[batch[j]] = r;
        }
      }
      if (failed.isNotEmpty && !_exactPossible(model)) {
        failed.addAll(now.skip(start + 8));
        break;
      }
    }
    final rest = [...failed, ...later];
    if (rest.isNotEmpty) {
      exact = false;
      final est = await estimate([for (final i in rest) items[i].text]);
      for (var j = 0; j < rest.length; j++) {
        out[rest[j]] = est[j];
      }
    }
    return TokenCounts(out, exact);
  }

  Future<int?> _exact(LlmClient client, LlmModel model, TokenItem it) async {
    try {
      final n = await client.countTokens(model.modelId, it.text).timeout(const Duration(seconds: 6));
      if (n == null) {
        _unavailableUntil[model.providerId] = DateTime.now().add(const Duration(minutes: 3));
        return null;
      }
      _put(_cacheKey(model, it), n);
      return n;
    } catch (_) {
      _unavailableUntil[model.providerId] = DateTime.now().add(const Duration(minutes: 1));
      return null;
    }
  }

  Future<void> _warm(LlmClient client, LlmModel model, List<TokenItem> items) async {
    for (final it in items) {
      if (!_exactPossible(model)) return;
      if (_cache.containsKey(_cacheKey(model, it))) continue;
      await _exact(client, model, it);
    }
  }

  void _put(String k, int v) {
    _cache.remove(k);
    _cache[k] = v;
    while (_cache.length > _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
  }
}
