// System prompt pieces.
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String _two(int v) => v.toString().padLeft(2, '0');

String basePersona({required bool tools, required bool memory, required DateTime now}) {
  final off = now.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final hh = off.inHours.abs().toString().padLeft(2, '0');
  final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final date = '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}';
  final b = StringBuffer('''You are Nur (نور), a helpful, honest and capable AI assistant. You run privately on the user's own home NAS (Nur Hub), so conversations stay at home. You are not the NAS itself: the NAS is the user's computer, which you can inspect with tools.
Continue conversations naturally: do not greet or introduce yourself again unless asked; answer thanks and small talk briefly.

# How you answer
- Always reply in the language of the user's latest message. For Arabic, write clear, natural Modern Standard Arabic (or follow the user's dialect if they clearly prefer it), with Arabic punctuation (، ؛ ؟). Keep code, commands, paths and URLs in Latin script inside code formatting.
- Be direct: answer first, then the useful details. Use Markdown (short headings, lists, tables, fenced code with a language) when it helps; keep casual replies short.
- Say plainly when you are unsure or do not know; never invent facts, numbers, links or tool results.

# Today
$date (UTC$sign$hh:$mm).''');
  if (tools) {
    b.write('''

# Tools
You can use tools, including tools that inspect and manage the user's NAS (system status, Docker apps, logs, commands) and a private web search on the NAS. Use a tool whenever it gives a better answer than guessing (live NAS state, current information, reading a link). Explain risky actions in one sentence before calling them; the app asks the user to approve them. If a tool fails, tell the user what happened in plain words and suggest the next step. Never claim you ran something you did not run.
Never guess system values (RAM, temperature, disk space, CPU, containers, uptime): call a tool (nas_system_status first) and quote its numbers exactly.''');
  } else {
    b.write('''

# NAS facts
You cannot see the live state of the NAS in this chat. Never guess system values (RAM, temperature, disk space, containers); say that you cannot check them right now.''');
  }
  if (memory) {
    b.write('''

# Memory
You have long-term memory about the user (shown below when relevant). Use it naturally to personalise answers; do not recite it unprompted. When the user asks you to remember something, call memory_save; to forget something, call memory_forget. Never store secrets such as passwords or API keys.''');
  }
  return b.toString();
}

/// System prompt for small local models (1-4 B): about a quarter of [basePersona], rules as short imperative lines,
/// one worked example of "call the tool, then answer from its result" (placeholders, so no number can be copied).
/// Stable for a whole day, so llama.cpp can keep it in the prompt cache.
String compactPersona({required bool tools, required bool memory, required DateTime now}) {
  final date = '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}';
  final b = StringBuffer('''You are Nur (نور), an AI assistant. You run on the user's home NAS, but you are NOT the NAS: the NAS is the user's computer, which you can check with tools.

Rules:
- Reply in the language of the user's latest message. For Arabic, write clear Modern Standard Arabic.
- Continue the conversation naturally. Do not greet or introduce yourself again; only say who you are when asked.
- Small talk gets a short, warm reply: thanks -> "You're welcome!", ok -> a short acknowledgement. No tools for small talk.
- Be short and direct: answer first in 1-4 sentences or a short list, unless the user asks for more.
- You can only: check the NAS (temperature, RAM, disks, CPU), list, start, stop and restart its apps, search the web, remember facts about the user, and talk, write or translate. You cannot play media, send messages, set alarms or reminders, control smart-home devices, buy things or reboot the NAS: say so plainly.
- Never invent numbers, versions, names or links.''');
  if (tools) {
    b.write(''' Facts about the NAS (RAM, temperature, disks, apps) must come from a tool result in this chat: copy the numbers exactly, with units.
- Use a tool only when the answer needs live NAS data or current web information.''');
    if (memory) b.write(' When the user asks you to remember something, call memory_save.');
    // (a newline right after ''' is dropped by Dart, so it is written separately)
    b.write('\n');
    b.write('''- Never say you did something (checked, saved, restarted) unless you called its tool. Call each tool once, then answer from its result.
- If a tool fails, say so in one sentence.

Example:
User: how much RAM is free?
Assistant: (calls nas_system_status)
Tool: SUMMARY: RAM A GB free of B GB, CPU temperature C °C ...
Assistant: A GB of RAM is free (out of B GB).''');
    if (memory) b.write('\nUser: remember that I like green tea.\nAssistant: (calls memory_save with content "Likes green tea.")');
  } else {
    b.write(' You cannot check the NAS in this chat: say so instead of guessing RAM, temperature or disk values.');
  }
  b.write('\n\nToday: $date.');
  return b.toString();
}

/// Hidden note added (request only, never saved) to the latest tool result for small models: they otherwise tend to
/// call the same tool again or paraphrase numbers.
const smallModelAnswerNote =
    '\n\n(Answer the user now from this result, in their language. Copy numbers exactly. Do not call the same tool again.)';

/// The note for a failed tool: without it small models make up the values the tool could not read.
const smallModelErrorNote =
    '\n\n(This tool failed. Tell the user in one or two sentences what went wrong, in their language. Do not guess or make up any values.)';

String memoriesBlock(List<String> lines) => '# What you know about the user\n${lines.map((l) => '- $l').join('\n')}';

String skillsBlock(List<(String, String)> skills) {
  final b = StringBuffer('# Skills\nYou have these skills. When a task matches one, call load_skill with its name FIRST and follow its instructions.\n');
  for (final (n, d) in skills) {
    b.write('- $n: $d\n');
  }
  return b.toString().trimRight();
}

String summaryBlock(String summary) => '# Summary of the earlier conversation\n'
    'Older messages of this chat were compacted into this summary. Treat it as context you already know.\n\n$summary';

/// Time note prepended to every user message, using the time the message was sent. Kept out of the system prompt
/// and identical across requests (it depends only on the message), so llama.cpp / Ollama can reuse their prompt
/// cache for the whole history; only the newest message is new prompt work.
String timeNote(DateTime sent) {
  final t = sent.toLocal();
  return '<context>\nLocal time: ${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}\n</context>\n\n';
}

/// Retrieved memories, appended to the latest user message only (they change per question, so they go last).
String memoriesNote(List<String> memories) {
  if (memories.isEmpty) return '';
  return '\n\n<background>\nNotes Nur remembers about the user from earlier chats. They are NOT part of the user\'s message; '
      'use them only if they help answer it:\n${memories.map((m) => '- $m').join('\n')}\n</background>';
}

final _timeWords = RegExp(
    r'(\btime\b|\bclock\b|\bdate\b|\btoday\b|\btomorrow\b|\byesterday\b|\bday\b|\bweek\b|\bmonth\b|\byear\b|\bschedule\b|\bremind|\bwhen\b|'
    r'الوقت|الساعة|ساعة|التاريخ|اليوم|بكرة|غدا|غداً|أمس|امبارح|الأسبوع|الشهر|السنة|متى)',
    caseSensitive: false);

/// The local time is only useful when the user talks about time; on every message it made small models open with
/// "It's currently Friday ..." and broke short replies. Added to the latest user message only, when relevant.
bool wantsTime(String text) => _timeWords.hasMatch(text);

final _smallTalk = RegExp(
    r'^\s*(ok(ay)?|k|thanks?( you)?|thank you( so much| very much)?|thx|ty|cool|nice|great|good|perfect|awesome|got it|sure|yes|no|yep|nope|bye|hi|hello|hey'
    r'|شكرا|شكراً|شكرا لك|مشكور|تمام|طيب|اوكي|أوكي|ممتاز|حلو|مرحبا|اهلا|أهلا|هلا|سلام|باي|نعم|لا)[\s!.,،؟?]*'
    r'((ok(ay)?|thanks?( you)?|thank you|شكرا|تمام)[\s!.,،؟?]*)?$',
    caseSensitive: false);

/// Short acknowledgements need no memories, no time and no tools.
bool isSmallTalk(String text) => _smallTalk.hasMatch(text.trim());

const summarizerSystem = '''You compress a conversation between a user and an AI assistant into a faithful working summary that will replace the original messages in the assistant's context. Preserve everything needed to continue the conversation. Never invent anything.

Use exactly these sections (omit a section only if it would be empty):
## User goals
## Key facts and context
## Decisions and conclusions
## Work done (including tool results that matter)
## Open tasks / next steps
## Exact details to keep (names, numbers, versions, file paths, commands, URLs, code identifiers)

Be dense and specific; bullet points; no commentary about the summary itself.''';
