// In-memory live state of streaming replies. Only the streaming message listens to its notifier,
// so token updates never rebuild the rest of the list.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/intelligence.dart';
import '../../../core/contracts/llm.dart';

@immutable
class LiveMessage {
  final String content;
  final String reasoning;
  final DateTime? reasoningStart;
  final int? reasoningMs; // set once reasoning finished
  const LiveMessage({this.content = '', this.reasoning = '', this.reasoningStart, this.reasoningMs});
  bool get thinking => reasoningStart != null && reasoningMs == null;
}

class LiveStore {
  final _messages = <String, ValueNotifier<LiveMessage>>{};

  /// chatId -> id of the assistant message currently streaming ('' while preparing the request).
  final active = ValueNotifier<Map<String, String>>(const {});

  ValueNotifier<LiveMessage>? of(String messageId) => _messages[messageId];

  ValueNotifier<LiveMessage> start(String chatId, String messageId) {
    final n = _messages[messageId] ??= ValueNotifier(const LiveMessage());
    setActive(chatId, messageId);
    return n;
  }

  /// Forgets the live state once the final text is persisted. The notifier is not disposed: widgets still
  /// holding it simply stop receiving updates and switch to the stored message on their next rebuild.
  void end(String messageId) {
    Future<void>.delayed(const Duration(seconds: 1), () => _messages.remove(messageId));
  }

  void setActive(String chatId, String? messageId) {
    final m = Map<String, String>.of(active.value);
    if (messageId == null) {
      m.remove(chatId);
    } else {
      m[chatId] = messageId;
    }
    active.value = m;
  }

  bool isActive(String? chatId) => chatId != null && active.value.containsKey(chatId);
}

final liveStoreProvider = Provider<LiveStore>((ref) => LiveStore());

/// A pending tool approval shown by the chat UI.
class ApprovalRequest {
  final String chatId;
  final LlmToolCall call;
  final ToolRisk risk;
  const ApprovalRequest(this.chatId, this.call, this.risk);
}

typedef ApprovalHandler = Future<bool> Function(ApprovalRequest request);

/// UI layers register a handler that shows the approval sheet (the chat screen does; a voice call screen may too).
/// The most recently registered handler wins. Without any handler risky tools are denied.
class ToolApprovalBroker {
  final _handlers = <ApprovalHandler>[];
  void register(ApprovalHandler h) => _handlers.add(h);
  void unregister(ApprovalHandler h) => _handlers.remove(h);
  Future<bool> request(ApprovalRequest r) async {
    if (_handlers.isEmpty) return false;
    return _handlers.last(r);
  }
}

final toolApprovalBrokerProvider = Provider<ToolApprovalBroker>((ref) => ToolApprovalBroker());
