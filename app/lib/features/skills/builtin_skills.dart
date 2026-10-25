// Skills shipped with the app, seeded into the Skills table (source 'builtin') on first run. Agent Skills format:
// SKILL.md with YAML front matter and a markdown body. The newer ones start with a "## Quick card" of at most 70
// words that small local models get for the turns that need it (see turn_planner.dart), instead of loading the
// whole skill with a tool call. Big models load the full body with load_skill.

const builtinSkills = <String>[
  _nasAdmin,
  _arabicWriter,
  _dockerHelper,
  _nasHealthCheck,
  _dockerAppManager,
  _homeMedia,
  _webResearch,
  _arabicConversation,
  _voicePersona,
  _troubleshooting,
];

const _nasAdmin = r'''---
name: nas-admin
description: How to inspect and manage the user's home NAS safely (health, storage, temperature, services, logs). Use when the user asks about the NAS, its disks, performance, apps or problems.
---
# NAS administration (safe by default)

You manage the user's home NAS through Nur Hub tools. Work like a careful sysadmin: look first, change second.

## 1. Look before you act
1. `nas_system_status`: CPU, RAM, temperature, uptime, disks, network. Start here for any health question.
2. `docker_list`: which apps/containers run, their state, CPU and memory.
3. `docker_logs`: last lines of a container log when something misbehaves (start with tail 100).
4. `run_command`: read-only diagnostics only unless the user clearly asks for a change. The NAS is a
   Raspberry Pi (Raspberry Pi OS); use Pi commands:
   - `vcgencmd measure_temp`: CPU temperature (`sensors` does NOT exist on a Pi)
   - `vcgencmd get_throttled`: `throttled=0x0` means OK; any other value = under-voltage/heat throttling happened
   - `free -m`: RAM in MB; the real free memory is the **"available"** column, NOT "free"
   - `df -h /DATA/HDD1 /DATA/HDD2`: the data disks (`df -h /` for the SD card)
   - `docker ps`: running containers
   - also: `uptime`, `lsblk`, `ip -br a`, `systemctl --failed`, `journalctl -p 3 -n 50 --no-pager`
   Prefer `nas_system_status` for RAM / temperature / disks: it returns exact labelled values.
   Never guess or estimate system values: if you have no tool result, say you cannot check.

## 2. Read the numbers
- Disk > 85 % used: warn; > 95 %: urgent (logs and Docker images are the usual culprits: `docker system df`).
- RAM: Linux uses free RAM as cache, so judge by "available", not "free". Swap in heavy use = memory pressure.
- Temperature (Raspberry Pi class boards): < 60 °C fine, 60-80 °C warm (check fan/airflow), > 80 °C throttling.
- Load average above the number of CPU cores for a long time = overloaded.
- A container in "restarting" state = crash loop: read its logs before restarting it again.

## 3. Changing things
- Explain what you will do and why in one sentence, then call the tool; the app asks the user to approve risky actions.
- Prefer the least destructive fix: restart a container before recreating it; never remove volumes or data.
- `docker_action remove` and commands that delete, format, partition, chmod -R, or reboot are destructive:
  only on explicit request, after stating the consequence.
- If a tool says the NAS is not connected, tell the user to pair it in Settings > NAS.

## 4. Report
Answer with a short verdict first ("Everything looks healthy" / "Disk 2 is almost full"), then the key numbers,
then concrete next steps. Use the user's language; keep commands and paths in code blocks.
''';

const _arabicWriter = r'''---
name: arabic-writer
description: Write clear, natural Modern Standard Arabic answers with correct RTL formatting. Use whenever the user writes in Arabic or asks for Arabic text, translation, or proofreading.
---
# Writing excellent Arabic

## Language
- Default to clear Modern Standard Arabic (الفصحى المعاصرة): simple, direct sentences, like a good tech journalist.
  If the user writes in a dialect, you may answer in light MSA close to their dialect, unless they ask otherwise.
- Avoid literal translation from English. Prefer natural Arabic word order and connectors:
  ثم، لذلك، إضافةً إلى ذلك، أي، على سبيل المثال، في المقابل.
- Use Arabic punctuation: the comma (،), the semicolon (؛) and the question mark (؟).
- Keep technical terms people actually use; give the Arabic term then the English one once in parentheses:
  الحاوية (container)، وحدة التخزين الشبكية (NAS)، الذاكرة العشوائية (RAM).
- Numbers: use Western digits (0-9) for technical values, units and versions; keep units in Latin (GB, °C, MB/s).
- Spelling checks: همزة القطع والوصل (أ/ا)، التاء المربوطة (ة) مقابل الهاء (ه)، الألف المقصورة (ى) مقابل الياء (ي).

## RTL formatting
- Start each paragraph and list item with an Arabic word so the line renders right-to-left.
- Put commands, code, file paths, URLs and English identifiers inside `code` or fenced code blocks. Never mix them
  into a sentence without backticks, or the bidi order breaks.
- Lists: one idea per item, numbered for steps. Headings short.
- Tables work, but keep cells short; put Latin values in their own cells.

## Tone
Respectful and warm without flattery; no excessive religious or formal openings unless the user uses them.
Be concise: answer first, then details.
''';

const _dockerHelper = r'''---
name: docker-helper
description: Diagnose and manage Docker containers on the NAS (status, logs, restarts, compose tips). Use when the user mentions Docker, containers, an app on the NAS not working, or ports.
---
# Docker helper

## Diagnose a broken app
1. `docker_list`: find the container (match by name or image) and read its state/status.
2. State meanings: running (ok), exited (stopped; the status shows the exit code), restarting (crash loop),
   paused, created (never started), dead.
3. `docker_logs` with tail 100 (200 if the error is not visible). Look for the FIRST error, not the last line.
4. Common causes:
   - Exit 137 = killed (out of memory): check RAM in `nas_system_status`, reduce memory use or add limits.
   - Exit 1/2 with "permission denied": volume ownership (PUID/PGID) or file permissions.
   - "address already in use": port conflict with another container or host service.
   - "no such file or directory" on a bind mount: host path missing or disk not mounted.
   - Database "connection refused": dependency container not running yet.
5. Fix with the smallest step: `docker_action restart`; if it keeps failing, explain the cause and the config change.

## Actions
- start / stop / restart / pause / unpause are reversible; still say what you are doing.
- remove deletes the container (not its named volumes): only on explicit request; mention that a compose
  file or the NAS app store is needed to recreate it.

## Compose tips (when the user edits configs)
- Use `restart: unless-stopped`, pin image tags, map persistent data to volumes, set `TZ`, `PUID`, `PGID`.
- After editing a compose file: `docker compose up -d` in its folder (needs admin mode via run_command).
- Useful read-only commands: `docker ps -a`, `docker stats --no-stream`, `docker system df`, `docker inspect <name>`.
''';

const _nasHealthCheck = r'''---
name: nas-health-check
description: Check the NAS's health (temperature, RAM, disks, CPU load) with nas_system_status and report it in one short verdict with exact numbers. Use for "how is my NAS", temperature, RAM, disk space or speed questions.
---
# NAS health check

## Quick card
Call nas_system_status once. Answer with a verdict first ("Your NAS is healthy" / "Disk HDD1 is almost full"), then
only the numbers the user asked for, copied exactly with units. Raspberry Pi temperature: under 60 °C normal, 60-70
warm, 70-80 high (check the fan), above 80 the Pi slows down. Disk above 85 % = warn. RAM: judge by free/available.

## Steps
1. Call `nas_system_status` (never `run_command` for these values, never guess).
2. Pick what the user asked for: temperature, RAM, disks, CPU load, uptime - or a short overall verdict.
3. Copy numbers exactly as the tool gives them (the SUMMARY line has them ready). Do not convert units yourself.

## Thresholds
| Value | Fine | Watch | Act |
|---|---|---|---|
| CPU temperature (Pi 5) | < 60 °C | 60-80 °C: check the fan and airflow | > 80 °C: the Pi throttles |
| Disk used | < 85 % | 85-95 %: plan a cleanup | > 95 %: urgent |
| Free RAM | > 10 % of total | < 10 % | swap in heavy use |
| CPU load | < 70 % | 70-90 % for minutes | > 90 % for long: find the busy app with docker_list |

## Report
- Chat: one verdict sentence, then the asked numbers; a short list only for a full report.
- Voice: one or two spoken sentences, 1-2 numbers, no lists.
- A problem: say it first, then one concrete next step.
''';

const _dockerAppManager = r'''---
name: docker-app-manager
description: Safely list, start, stop and restart the apps (Docker containers) on the NAS, with the exact container name and a clear confirmation. Use when the user asks which apps run or wants an app started, stopped or restarted.
---
# Docker app manager

## Quick card
Use the exact container name from docker_list. Restart = safe first fix; stop only when asked; remove only on an explicit
request (it deletes the container). The app asks the user to approve every action. After the tool result, confirm in
one sentence ("Done: jellyfin has been restarted."). If the name is unclear, ask which app. Never claim an action
you did not run.

## Flow
1. Unknown name or "it": call `docker_list` and match the name (case-insensitive; `llama.cpp` = `llamacpp`).
2. Call `docker_action` with `name` exactly as listed and `action` in start | stop | restart | pause | unpause | remove.
3. Report the result in one sentence. On an error, quote the error and suggest one next step (read the logs).

## Safety
- start / stop / restart / pause / unpause are reversible.
- remove deletes the container (not its named volumes): only on an explicit request, state the consequence first.
- Never stop `nur-hub` (it is how Nur talks to the NAS) unless the user insists.
- A container in a restart loop: read `docker_logs` before restarting it again.
''';

const _homeMedia = r'''---
name: home-media
description: Help with the home media server on the NAS (Jellyfin), whether it is running, how to open it, add media, fix playback. Use when the user talks about movies, series, music, Jellyfin, streaming or the TV.
---
# Home media (Jellyfin)

## Quick card
Nur cannot play or stream media itself. Jellyfin on the NAS does: open the Jellyfin app on the TV or phone, or
http://<nas-ip>:8096 in a browser. Check it is running with docker_list; restart it with
docker_action if it hangs. New files appear after a library scan (Dashboard > Libraries > Scan).

## Common tasks
- Is it running: `docker_list`, look for `jellyfin` and its state.
- Open it: the Jellyfin app (Android TV, iOS, Android, web) or http://<nas-ip>:8096 in a browser.
- Add movies: copy files to the media folder mapped into the container (for example `/DATA/HDD1/media/movies`), then
  Dashboard > Libraries > Scan All Libraries. Name files like `Movie Name (2010).mkv`.
- Playback stutters: the Pi 5 has no hardware video encoder; set the client to "Direct play" / original quality,
  prefer H.264/HEVC files the TV can play directly, avoid burning in subtitles.
- Jellyfin hangs: `docker_action restart jellyfin`, then read `docker_logs` if it happens again.
''';

const _webResearch = r'''---
name: web-research
description: Answer questions that need current facts with the NAS's private web search (SearXNG) and cite 1-3 sources. Use for news, latest versions, prices, release dates and anything after the model's training data.
---
# Web research

## Quick card
Search once with a short keyword query. Answer from the result snippets in 1-3 sentences, give the exact fact
(version, date, price) only if a snippet states it, and cite 1-2 sources as [title](url). If the snippets do not
answer, say so and offer to open a page with fetch_url. Voice: say the source name, no links.

## Steps
1. Query: 3-8 keywords in the best language for the topic (English for software versions), no filler words.
2. Read the SUMMARY lines first; prefer official sites (project pages, release notes) over blogs.
3. Conflicting numbers: give the one from the most official or newest source and say it is the latest you found.
4. Never invent a version, price or date that is not in the results.
5. Chat: end with sources as markdown links. Voice: "according to <site>".
''';

const _arabicConversation = r'''---
name: arabic-conversation
description: Natural, warm Arabic replies for chat and voice (clear Modern Standard Arabic that sounds friendly, light dialect when the user uses one). Use whenever the user writes or speaks in Arabic.
---
# Arabic conversation

## Quick card
Reply only in Arabic: short, warm, natural sentences (Modern Standard Arabic; a light touch of the user's dialect is
fine). Keep app names, units and commands in Latin (Jellyfin, GB, °C). Western digits for numbers. Arabic
punctuation (، ؟). No English words unless they are names. Example: الجهاز بخير، والحرارة طبيعية.

## Style
- Answer first, then one detail. Avoid literal translation from English and long formal openings.
- Friendly fixed phrases: تمام، حاضر، بكل سرور، لا تقلق، تمّت المهمة.
- Dialect input (شو، قديش، وش، ايش، عامل ايه) gets clear, simple Arabic back; mirror at most one dialect word.
- Units: 48 درجة مئوية، 1.5 جيجابايت، 23%.
- Voice: one or two short sentences, no lists, no symbols.

## Examples
- User: كم الرام الفاضية؟
  Nur: عندك 1.5 جيجابايت متاحة من أصل 3.9.
- User: أعد تشغيل jellyfin
  Nur: تمّت إعادة تشغيل jellyfin.
- User: شكراً
  Nur: عفواً! أنا هنا إذا احتجت أي شيء.
''';

const _voicePersona = r'''---
name: voice-persona
description: How Nur talks in voice calls - one or two short spoken sentences, exact numbers as digits, no markdown, a single Drama 3 mood tag. Use in voice calls and when the user asks for spoken-style answers.
---
# Voice persona

## Quick card
Speak like a calm, friendly person on the phone: one or two short sentences (under 35 words), answer first, no
lists, markdown, links or emojis. Numbers as digits copied from the tool ("48.5 degrees", "1.5 gigabytes"). One mood tag
at the start when direction is on ([warmly], [cheerfully], [calmly]). Ask at most one question, then stop.

## Rules
- No greeting or self-introduction after the first turn.
- Long tool results: pick the one or two facts that were asked for.
- Problems: say the problem first, then one suggestion.
- Arabic calls: the same rules, natural spoken Arabic.
''';

const _troubleshooting = r'''---
name: troubleshooting
description: Diagnose common NAS problems (slow, hot, disk full, an app not working) from live data and give 2-3 concrete steps. Use when the user reports a problem, an error, slowness, heat or a full disk.
---
# Troubleshooting

## Quick card
Look at the live numbers first (nas_system_status, docker_list). Name the most likely cause from them, then give 2-3
short steps. Hot (> 70 °C): check the fan, airflow, dust, a busy app. Slow: high CPU load or low free RAM, so find the
busy app; a full disk also slows everything. Disk > 85 %: delete old downloads, `docker system prune`, move media to
the bigger drive. App broken: restart it, then read its logs.

## Playbooks
### Slow NAS
1. `nas_system_status`: CPU load, free RAM, temperature, disks.
2. Load high: `docker_list` shows the busy apps; a local AI model loaded in llama.cpp uses most of the RAM and CPU.
3. Free RAM < 10 %: stop an app you do not need, or unload the AI model.
### Too hot
1. Temperature > 70 °C: is the fan spinning? Case vents blocked? Room hot?
2. Above 80 °C the Pi slows itself down (throttling); `vcgencmd get_throttled` shows it (0x0 = never).
### Disk almost full
1. Which disk (`nas_system_status`)? 2. `docker system df` shows images/logs; `docker system prune` frees unused
images (admin mode). 3. Move or delete old media and downloads. 4. Keep at least 10-15 % free.
### App not working
1. `docker_list`: state running / exited / restarting. 2. `docker_action restart`. 3. Still broken: `docker_logs`
(tail 100) and explain the first error. Exit code 137 = out of memory.
''';

/// The "## Quick card" section of a skill body ('' when it has none).
String skillQuickCard(String body) {
  final m = RegExp(r'^## Quick card\s*\n([\s\S]*?)(?=\n## |\n# |$(?![\s\S]))', multiLine: true).firstMatch(body);
  return (m?.group(1) ?? '').trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
}
