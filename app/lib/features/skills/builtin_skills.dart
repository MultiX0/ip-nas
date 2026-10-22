// Skills shipped with the app (seeded into the Skills table on first run, source = 'builtin').

import 'builtin_skills_v3.dart';

const builtinSkills = <String>[_nasAdmin, _arabicWriter, _dockerHelper, ...builtinSkillsV3];

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
