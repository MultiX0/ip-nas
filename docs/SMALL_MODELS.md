# Small models on the Pi

The NAS in the video is a Raspberry Pi 5 with 4 GB of RAM, so the local model has to be small: 1 to 4 billion
parameters at 4 bits. Used as it is, such a model picks the wrong tool, copies numbers wrong, sometimes loops, and the
Pi needs a long time before the first word. This page has what I measured on the Pi and what the Nur app does about
it. All tests ran in October 2026 on the Pi 5 (4 GB, Active Cooler) with the llama.cpp server image
(`ghcr.io/ggml-org/llama.cpp:server`), one request at a time.

The models you can download from the app are in [hub/catalog.json](../hub/catalog.json), with a short summary in the
[Nur Hub README](../hub/README.md#local-models).

## Why nothing bigger

Writing one token means reading every weight the token needs, once. From RAM the Pi does that at roughly 10 GB/s, so a
1.2 GB model writes about 7 tokens per second. A model that does not fit in RAM has to come from storage instead. I
measured the Pi's storage with direct reads (no cache):

| Storage | Sequential 1 MiB | Random 4 KiB | Random 128 KiB | Random 2 MiB |
|---|---|---|---|---|
| microSD (system card) | 92.8 MB/s | 9.5 MB/s (2,317 IOPS) | 66.9 MB/s | 94.0 MB/s |
| USB hard drive (WD 320 GB) | 88.6 MB/s | 0.5 MB/s (127 IOPS) | 14.5 MB/s | 65.5 MB/s |

That is more than 100 times slower than RAM. A model bigger than the RAM could only work if each token needed a small
part of the weights, which is how mixture-of-experts (MoE) models work, and never for a normal dense model, which uses
every weight for every token. So on a 4 GB Pi it is 1 to 4 B models at 4 bits, and Nur Hub refuses a download when the
file plus 0.9 GB does not fit in the RAM.

## First round: which models call tools

Before I wrote Nur I tested the models as an agent on the Pi, with ZeroClaw (v0.8.5) on top of llama.cpp (4096 context,
2 threads for writing, 4 for reading the prompt). The agent had three tools: a shell limited to read-only commands, web
search through SearXNG, and reading files. There were six questions: free RAM (in English and in Arabic), disk usage of
the two drives, the current Debian version through a web search, the CPU temperature (Arabic), and three Arabic
sentences about what a home NAS is (no tool). Before each run the Pi had to cool down to 65 C, and a watchdog would stop
the test at 80 C, below 150 MB of free RAM, or on any throttling.

| Model (file) | Tool calls | Answers | Arabic | Time per answer | Verdict |
|---|---|---|---|---|---|
| Qwen3 4B Instruct 2507 (2.38 GB) | yes, the right command in all 5 tool tasks | web search and Arabic free RAM exact (404 MB, real 407 MB); English free RAM read the "free" column instead of "available"; the disk question was blocked by an agent setting (fixed after the test); used `sensors` for the temperature, which a Pi does not have | good, natural | 33 to 55 s (153 s on first load) | best for commands and Arabic |
| Huihui Qwen3.5 2B (1.27 GB) | yes | web search and Arabic free RAM right; also read "free"; gave disk sizes instead of usage; the temperature question hit the 5-step limit | good | 51 to 141 s | good small fallback with half the RAM |
| Granite 4.2 3B (2.14 GB) | yes, the best command choice (`vcgencmd`, 62.6 C exact) | temperature and web search right; also read "free" | failed the Arabic text | 181 to 420 s, 2 timeouts | too slow on the Pi |
| Gemma 3 4B (2.37 GB) | never | made up "4096 MB free", "35 C", "85% full" and "Debian 12" | very good prose | 16 to 83 s | chat only, never for NAS control |
| LFM2.5 1.2B (0.70 GB) | no, says it cannot run commands | none | weak, refused the Arabic text | 5 to 33 s | not for an agent |
| Spark-X2.5 4B IQ4_XS (2.38 GB) | yes, the best free RAM answer ("61 MiB free, 2.0 GiB available") | one run only | | 192 s | stopped: the Pi reached 81.2 C |

The Pi peaked at 81.2 C (that was the watchdog stop, with no throttling), the lowest free RAM was 388 MB with a 4 B
model loaded, and the 5 V rail stayed at 5.03 to 5.10 V.

What I took from it for Nur:

- The agent's default prompt was 17,190 tokens, which alone takes minutes on the Pi. With 3 tools it was about 1,150 to
  1,500 tokens. Short prompts became the first rule.
- Small models mix up "free" and "available" RAM and do not know Pi commands, so Nur's NAS tools hand the model ready
  numbers (`nas_system_status`) instead of making it read `free -h`.
- On a 4 GB Pi a 4 B model needs the 4096 context. With 8192 the Pi ran out of memory and the kernel stopped
  llama-server.

## What the model makers recommend

Sampling values from the model cards:

| Model family | Thinking on | Thinking off or instruct | Source |
|---|---|---|---|
| Qwen3.5 (2B, 4B) | temp 1.0, top_p 0.95, top_k 20, min_p 0, presence 1.5 | text: temp 1.0, top_p 1.0, top_k 20, min_p 0, presence 2.0; general and VL: temp 0.7, top_p 0.8, top_k 20, presence 1.5 | [Qwen3.5-2B card](https://huggingface.co/Qwen/Qwen3.5-2B) |
| Qwen3 (and 2507) | temp 0.6, top_p 0.95, top_k 20, min_p 0, never greedy (it loops) | temp 0.7, top_p 0.8, top_k 20, min_p 0; presence 0 to 2 helps against repeats | [Qwen3-4B card](https://huggingface.co/Qwen/Qwen3-4B) |
| Gemma 3 | | temp 1.0, top_k 64, top_p 0.95, min_p 0 (0.01 is fine), repetition penalty off | [Unsloth Gemma 3 guide](https://unsloth.ai/docs/basics/gemma-3-how-to-run-and-fine-tune) (the Gemma team's values) |
| LFM2.5 | | temp 0.1, top_k 50, repetition penalty 1.05 | [LFM2.5-1.2B-Instruct card](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct) |
| Granite 4.2 | temp 1.0, top_p 0.95 for everything, tool calls included | the same | [granite-4.2-3b card](https://huggingface.co/ibm-granite/granite-4.2-3b) |
| Granite 4.0 | | temp 0, top_p 1.0, top_k 0 | [Unsloth Granite 4.0 guide](https://unsloth.ai/docs/models/tutorials/ibm-granite-4.0) |

More from the cards: the Qwen3.5 2B card says the model is "more prone to entering thinking loops" with thinking on,
and thinking is off by default for Qwen3.5. LFM2.5 is made for "agentic tasks, data extraction and RAG", not for
knowledge questions or code, and writes its tool calls as Python-style calls between `<|tool_call_start|>` and
`<|tool_call_end|>`. Gemma 3 has no tool tokens at all; Google's own examples make it call tools through the prompt
([Phil Schmid](https://www.philschmid.de/gemma-function-calling),
[Simon Willison](https://simonwillison.net/2025/Mar/26/function-calling-with-gemma)), which fits the first round where
it never called one. Granite 4.x writes `<tool_call>{"name": ..., "arguments": ...}</tool_call>` in the Hermes style
([granite-4.0-micro card](https://huggingface.co/ibm-granite/granite-4.0-micro)).

When a request sends no sampling values, llama-server uses its own defaults (temp 0.8, top_k 40, top_p 0.95, min_p
0.05, repeat penalty 1.0, presence 0), so every model runs with the same generic values instead of the ones it was
tuned for.

## What helps small models with tools

- Fewer tools per request. "Less is More" ([arXiv 2411.15399](https://arxiv.org/html/2411.15399v1)) cut the tool list
  per request and got more tasks right while using up to 70% less time and 40% less power on edge hardware. TinyAgent
  ([arXiv 2409.00608](https://arxiv.org/abs/2409.00608)) picks about 4 tools per query with a small classifier, and its
  1.1 B and 7 B models match GPT-4-Turbo at function calling. DTDR
  ([arXiv 2512.17052](https://arxiv.org/pdf/2512.17052)) adds 23 to 104% success by picking tools again as the plan
  goes on. Going from 48 to 25 tools improved every model in
  [Paragon's tests](https://www.useparagon.com/blog/how-to-optimize-tool-calling).
- Short tool descriptions in JSON. The BFCL v4 prompt study
  ([Gorilla blog](https://gorilla.cs.berkeley.edu/blogs/17_bfcl_v4_prompt_variation.html)) found JSON tool docs work
  best, JSON or Python answers beat XML, and small models lose the most when the format is unusual. Plain text against
  Markdown made no steady difference.
- Native tool calls beat parsing text, but small models still print a call as text now and then (code fences,
  `<tool_call>` tags, `<function=...>` XML). Real parsers try each known wrapper and then fall back to a forgiving JSON
  scan ([NVIDIA Dynamo](https://docs.nvidia.com/dynamo/parsing/tool-call-parsing.md),
  [LocalAI](https://localai.io/docs/features/openai-functions/)). llama.cpp has parsers per family (Qwen3-Coder XML,
  Hermes, LFM2, Granite) and lazy grammars that hold the call to the format once it starts.
- Grammars: llama.cpp takes `grammar`, `json_schema` and `response_format`, and with `--jinja` it already forces valid
  tool-call JSON for templates it knows. Another grammar on top could break the model's own tool format, so Nur relies
  on the server's tool grammar plus repair.
- Best-of-n or reward-model reranking of tool calls (ToolRM, [arXiv 2509.11963](https://arxiv.org/abs/2509.11963))
  helps tiny models a lot, but it multiplies the generation time, and at about 7 tokens/s on the Pi that is not
  practical.
- Answer from the tool result. Small models paraphrase numbers or convert them wrong (the "free" against "available"
  RAM above). What works: tools that return a ready SUMMARY line with exact values and units, and a short note right
  after the tool result ("answer now, copy the numbers exactly"), because small models follow the most recent text
  best.
- Keep the prompt prefix the same. The Pi reads prompts at about 40 tokens/s, so a 2,000-token prompt costs about 50 s
  before the first word. llama.cpp reuses the KV cache for the unchanged start of the previous request (`cache_prompt`,
  on by default), so the system prompt and the tool list must stay byte for byte the same between turns, and anything
  that changes (the time, retrieved memories) goes at the end, in the newest user message
  ([llama.cpp discussion](https://github.com/ggml-org/llama.cpp/discussions/13606)).

On the BFCL v4 tool-calling benchmark granite-4.2-3B scores 52.4 against 43.6 for Qwen3.5-2B (thinking), but on the
Pi it was far too slow in both test rounds. Small Arabic-focused models I have not tried yet: Falcon-H1-Arabic 3B
(TII, January 2026), Tiny Aya Global (Cohere) and Fanar.

## What Nur does with a small model

| Part | What the app does | Code (in `app/lib/features/`) |
|---|---|---|
| Detection | A local model (llama.cpp, Ollama, LM Studio, vLLM, the NAS) whose name says 4.5 B parameters or less counts as small (`Qwen3.5-2B`, `qwen3:4b`; "30B-A3B" counts as 30 B). `"smallModel": true` or `false` in the model's overrides JSON forces it. | `providers/sampling_presets.dart`, `providers/capabilities.dart` |
| Sampling | The family values from the table above go with every local request, different for thinking on and off. An explicit temperature still wins. In the overrides JSON, `"sampling"` is `"auto"` (default), `"server"` (send nothing) or `"custom"` with `"samplingCustom": {temperature, topP, topK, minP, presencePenalty, repeatPenalty}`. Cloud providers are not touched. For Qwen3.5 with thinking off it uses the card's general values (temp 0.7, top_p 0.8, top_k 20, presence 1.5), not the text values: exact numbers matter more here than variety. | `providers/sampling_presets.dart`, `providers/llm_registry.dart`, `providers/adapters/` |
| Thinking | Off by default for small models (still selectable per chat). The Qwen3.5 2B card warns about thinking loops, and on the Pi every thinking token costs about 0.15 s. | `providers/llm_registry.dart` |
| Prompt | A compact persona of about 250 tokens instead of about 850 (persona plus skills index): short rules, numbers only from tool results, never claim an action without calling its tool, and one worked example with placeholders so there is no number to copy. | `context/prompts.dart`, `context/context_assembler_impl.dart` |
| Tools | A fixed core of 4 tools in a fixed order (`nas_system_status`, `docker_list`, `docker_action`, `web_search`), the same bytes in every turn so the prompt cache holds. The others (`docker_logs`, `fetch_url`, `run_command`, the memory tools, `load_skill`, MCP tools) are added only when a message in the chat asks for them, 7 tools at most, with one-line descriptions. | `tools/tool_router.dart` |
| Tool-call repair | Calls written as text become real calls (Hermes and Qwen `<tool_call>`, Qwen3-Coder `<function=...>`, LFM `<\|tool_call_start\|>`, Gemma `tool_code`, a bare JSON object), only for tools offered in that request, and broken arguments are repaired. Raw tool markup is never shown or spoken. | `tools/tool_call_repair.dart`, `chat/engine/chat_engine_impl.dart` |
| Loops | The same tool with the same arguments twice in one reply is not run again. A small model gets at most 3 tool rounds and 1,536 output tokens with thinking off. | `chat/engine/chat_engine_impl.dart` |
| Grounding | For small models every tool result ends with "(Answer the user now from this result, in their language. Copy numbers exactly. Do not call the same tool again.)", and the NAS and search tools start with a SUMMARY line that has the numbers ready. | `context/prompts.dart`, `tools/tool_formatters.dart` |
| Prompt cache | `cache_prompt: true` for llama.cpp, a fixed system prompt and tool block, the time on each user message instead of only on the newest one, retrieved memories at the end of the newest message. | `providers/adapters/openai_compat_client.dart`, `context/` |
| Prewarm | When you focus the message box or open the call screen, the app sends the exact start of the next request with `max_tokens: 1`, so the model is loaded and the prefix is cached before you send. Local models only, the same prefix at most once per 60 s. | `chat/engine/chat_engine_impl.dart` |
| Turn planner | Added after the tests below. A rule-based intent check (English, Arabic and common dialects) runs before the model. Thanks, greetings, "remember X" and requests Nur cannot do get a fixed reply with no model call (the app saves the memory itself). NAS questions call the right tool directly, and short ones are answered from a template, so the numbers are always exact. "Restart jellyfin" is matched against the real container list and goes straight to `docker_action`, which you still approve. The idea follows Home Assistant's "prefer local intents", NeMo Guardrails' canonical forms and Rasa CALM. | `context/turn_planner.dart` |
| Reply guard | Also added after the tests. Cheap rule checks on the reply, with no second model, because small models cannot check themselves ([arXiv 2310.01798](https://arxiv.org/abs/2310.01798)). It removes a self-introduction in the middle of a chat, repeated questions, greetings nobody asked for and stray Chinese text, and asks for one retry when the reply is in the wrong language or claims an action no tool ran. | `chat/engine/reply_guard.dart` |
| Background calls | Memory extraction after a turn is skipped for small models unless the message is about the user (I, my, remember, أنا, اسمي). One extraction costs the Pi 30 to 60 s and blocks llama.cpp's only slot. | `memory/memory_extractor.dart` |
| Titles | The title request sees only the first user message, has two examples (English and Arabic), thinking off, at most 16 tokens and temperature 0.2. The result is cut to 6 words and dropped if it has numbers the user never wrote (that fixed titles like "1598 MB RAM, 60.6 C"). | `chat/engine/chat_engine_impl.dart` |

## Second round: Qwen3.5 2B before and after

On 2026-10-16 I rebuilt the app's exact requests in a script and ran 8 tasks through Nur Hub on the Pi. The tools got
real NAS data (`/api/v1/system`, `/api/v1/docker/containers`, `/api/v1/search`); `docker_action` and `memory_save` were
faked. One request at a time, with the CPU temperature checked before each one (wait above 70 C; it stayed at 47 to
68 C), and thinking off in both versions (the old default, medium thinking with a 4,096-token budget, adds minutes per
answer). One run per task, so single results are noisy. This was before the turn planner and the reply guard.

- T1: free RAM and CPU temperature (English)
- T2: disk usage (Arabic)
- T3: which apps are running (English)
- T4: restart SearXNG (Arabic, needs `docker_action`)
- T5: the latest Debian version (English, web search; the truth is 13, point release 13.7)
- T6: "remember that my NAS sits in the living room" (English, needs `memory_save`)
- T7: three Arabic sentences about reading (no tool)
- T8: the follow-up "is that temperature too hot for a Pi?" (needs the turn before)

| Task | Before (2,022-token prompt, 11 tools, server sampling) | After (small-model mode) |
|---|---|---|
| T1 | PASS, 77.6 s, a long answer plus a follow-up question | PASS, 33.5 s ("1.0 GB of RAM free (out of 4.0 GB), CPU temperature 66.1 °C"); again PASS, 16.9 s |
| T2 | PASS, 31.4 s | PASS, 17.3 s; again PASS, 23.8 s |
| T3 | PASS, 39.8 s (219-token answer) | PASS, 18.6 s (86 tokens) |
| T4 | FAIL, 49.5 s: memory_search, run_command, docker_list and docker_logs, then the raw `<tool_call><function=run_command>` text as the answer | PASS, 42.3 s (docker_list, then docker_action restart: "تم إعادة تشغيل تطبيق searxng بنجاح"); again FAIL (chose stop instead of restart) |
| T5 | FAIL: runaway text, over 5,400 tokens in over 12 minutes, killed | PASS, 26.2 s ("Debian 13, codenamed Trixie") |
| T6 | PASS, 63.3 s | FAIL 3 of 3: once it called nas_system_status, twice it said "noted" without calling memory_save |
| T7 | PASS, 14.2 s (3 paragraphs) | PASS, 7.2 s and 8.2 s (one tight paragraph) |
| T8 | PASS, 47.1 s (a needless memory_search) | PASS, 78.4 s (a needless web_search, long); again PASS, 23.6 s, no tool |
| Total | 6 of 8 in 323 s, plus the 13-minute runaway | first run 7 of 8 in 256 s; 11 of all 15 runs |

The prompt went from 2,022 tokens to about 760 with 4 tools, or about 920 with 5 tools and the user message. The Pi
reads prompts at about 40 tokens/s with Qwen3.5 2B and writes 6.7 to 7.0 tokens/s, so the first request went from
52.7 s to 20.2 s before the tool call, and the shorter answers save about as much again.

Other models in small-model mode, thinking off:

| Model | Result | Speed on the Pi | Verdict |
|---|---|---|---|
| granite-4.2-3B Heretic Q4_K_S | T1 PASS ("RAM free: 1.0 GB, CPU temperature 68.3 °C"); T4 FAIL (listed the apps, said searxng is "already running", no restart); stopped after 2 tasks | 235 s and 324 s per task: prompt 20 tokens/s, writing 4 tokens/s, and `cache_n = 0` on every request (a hybrid Mamba model, llama.cpp did not reuse its prompt cache), so every step read about 1,000 tokens again | still too slow on a Pi 5 even with the short prompt; the better BFCL score does not help at 4 to 5 minutes per answer |
| LFM2.5-1.2B Instruct Q4_0 | 1 of 5: T1 called the tool but answered the English question in Arabic; T4 and T6 claimed "restarted" and "noted" without a tool call; T5 made up "Debian 5.15.2"; T7 (Arabic) PASS | very fast: prompt 117 tokens/s, writing 15 tokens/s, 5 to 8 s per answer (120 s to load the model) | not for NAS control or facts; fine as a fast Arabic chat model |
| gemma-3-4B | not run again (in the first round it never called a tool and made numbers up) | | chat only |

Prewarm and the prompt cache with Qwen3.5 2B, the compact prompt and 5 tools:

| Request | Prompt tokens read (from cache) | Time to first token |
|---|---|---|
| First turn, nothing cached | 918 (0) | 21.8 s |
| Prewarm (system, tools and an empty user turn, `max_tokens` 1) | 39 (869) | 1.1 s (the prefix came back from llama.cpp's RAM cache; a truly cold prewarm costs the 20 s once, in the background) |
| First turn after the prewarm | 49 (869) | 1.3 to 2.6 s |
| Answer after the tool result | 343 to 362 (914 to 933) | 8.5 to 8.7 s (the tool result itself has to be read) |
| Second turn without a prewarm | 426 to 429 (914) | 10.3 s |
| Second turn after a prewarm with the history | 47 (1,293) | 1.4 s |

Without a prewarm the second turn reads about 430 tokens again because the Qwen chat template writes the previous
assistant turn differently once a new user message follows (it handles the think block), so the cache breaks at the
last tool call. A request cannot avoid that, but a prewarm with the full history (on message box focus and on the call
screen) moves the work into idle time. The voice prompt (now about 418 tokens) is part of the cached prefix, so after a
prewarm it costs nothing per turn. This is also how the first voice call went from 51 s to about 7 s
([FISH_AUDIO.md](FISH_AUDIO.md#measured-on-2026-10-16)).

## Still open

- T6 is solved differently now: the turn planner saves "remember ..." facts itself and never waits for the model to
  call `memory_save`.
- T4 picked `stop` once instead of `restart`. The approval dialog catches that (`docker_action` always needs your
  approval), and the turn planner now sends a clear "restart X" straight to `docker_action`.
- The last allowed tool round goes out without tools, which changes the cached prefix (the old app read 923 tokens again
  there). It is rare with 3 rounds; sending `tool_choice: "none"` and keeping the tools would avoid it.
- Title and memory-extraction calls share llama.cpp's only slot. With `--cache-ram 512` the chat prefix came back from
  RAM in my runs, but on a busy Pi they can still delay the next reply.
- Best-of-n reranking and grammar-forced tool JSON are not worth it at 7 tokens/s. Maybe on faster hardware.
