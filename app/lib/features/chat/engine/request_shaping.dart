// Request-only changes to the assembled messages (nothing here is saved). Deterministic, so the prewarm request and
// the real turn share the exact same prefix. Pure Dart, no Flutter imports.
import '../../../core/contracts/llm.dart';
import '../../context/prompts.dart' show smallModelAnswerNote;
import '../../context/turn_planner.dart' show detectLang;

/// [turnHint]: request-only answer frame / skill card for the LATEST user message (small models follow the most
/// recent text best). [toolsCapable] false: tool exchanges in the history (e.g. NAS data the app fetched itself) are
/// dropped, because chat templates without a tool role reject them; the assistant answers that quote the data stay.
List<LlmMessage> shapeMessages(List<LlmMessage> input,
    {required bool vision,
    required bool small,
    String voiceHint = '',
    String voiceReminder = '',
    String turnHint = '',
    bool toolsCapable = true}) {
  // Language of each user message, from the user's own text (before hints and reminders are added).
  final langs = [
    for (final m in input)
      if (m.role == LlmRole.user) m.content.trim().isEmpty ? null : languageDirective(m.content)
  ];
  var messages = input;
  if (!toolsCapable && messages.any((m) => m.role == LlmRole.tool || m.toolCalls.isNotEmpty)) {
    messages = [
      for (final m in messages)
        if (m.role == LlmRole.tool || (m.role == LlmRole.assistant && m.content.trim().isEmpty))
          ...const <LlmMessage>[]
        else if (m.toolCalls.isNotEmpty)
          LlmMessage(m.role, m.content, reasoning: m.reasoning)
        else
          m,
    ];
  }
  if (turnHint.isNotEmpty) {
    final last = messages.lastIndexWhere((m) => m.role == LlmRole.user);
    if (last >= 0) {
      final m = messages[last];
      messages = [...messages]..[last] = LlmMessage(LlmRole.user, '${m.content}\n\n$turnHint', images: m.images);
    }
  }
  if (!vision) {
    messages = [
      for (final m in messages)
        m.images.isEmpty
            ? m
            : LlmMessage(m.role, m.content.isEmpty ? '[image omitted: this model cannot see images]' : m.content,
                toolCalls: m.toolCalls, toolCallId: m.toolCallId, toolName: m.toolName, reasoning: m.reasoning),
    ];
  }
  if (small) {
    // Small models otherwise call the same tool again or paraphrase numbers. Every tool result gets the note, older
    // ones too, so the history stays byte-identical on the next turn and llama.cpp reuses its cache (measured: the
    // 2nd turn re-processed ~400 tokens when only the newest result had it).
    messages = [
      for (final m in messages)
        m.role == LlmRole.tool
            ? LlmMessage(LlmRole.tool, '${m.content}$smallModelAnswerNote', toolCallId: m.toolCallId, toolName: m.toolName)
            : m,
    ];
  }
  if (voiceHint.isNotEmpty) {
    // System text must stay at the start (many chat templates require it). Small models follow the most recent text
    // best, so user messages also get a one-line reminder. Every user message gets it, older ones too, so the history
    // stays byte-identical between turns and llama.cpp can reuse its prompt cache during the call.
    final sys = messages.takeWhile((m) => m.role == LlmRole.system).length;
    messages = [
      ...messages.take(sys),
      LlmMessage(LlmRole.system, voiceHint),
      for (final m in messages.skip(sys))
        m.role == LlmRole.user && voiceReminder.isNotEmpty
            ? LlmMessage(LlmRole.user, '${m.content}\n\n$voiceReminder', images: m.images)
            : m,
    ];
  }
  if (small || voiceHint.isNotEmpty) {
    // Language lock: small models drift into Arabic after Arabic examples or memories ("How are you?" answered in
    // Arabic). Each user message gets an explicit directive computed from ITS OWN text, so it is deterministic and
    // byte-identical on later turns (prompt cache stays valid).
    var u = 0;
    messages = [
      for (final m in messages)
        if (m.role == LlmRole.user)
          switch (langs[u++]) {
            null => m,
            final d => LlmMessage(LlmRole.user, '${m.content}\n$d', images: m.images),
          }
        else
          m,
    ];
  }
  return messages;
}

/// The language lock for one user message, decided from the user's own words only: the hidden time note, retrieved
/// memories, turn hints and voice reminders are English and used to tip short Arabic messages into
/// "(Reply in English only.)".
String languageDirective(String text) {
  final t = text
      .replaceAll(RegExp(r'<context>[\s\S]*?</context>'), '')
      .replaceAll(RegExp(r'<background>[\s\S]*?</background>'), '')
      .replaceAll(RegExp(r'\n\n\(voice call:[^)]*\)'), '');
  return detectLang(t) == 'ar' ? '(رد باللغة العربية فقط.)' : '(Reply in English only.)';
}
