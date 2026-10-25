# How the Nur app is put together

Flutter with Riverpod 3 for state, drift (SQLite) for the database, dio for HTTP and go_router for the routes.
Secrets (API keys, the hub token) are kept in flutter_secure_storage, never in the database.

## Folders

| Folder | What is in it |
|---|---|
| `lib/main.dart`, `lib/app.dart` | start-up, routes, theme and language |
| `lib/core/` | the interfaces between the parts (`contracts/`), shared providers, theme, desktop layout and widgets |
| `lib/data/db/` | the drift database (`app_db.g.dart` is generated) |
| `lib/features/chat/` | the chat screen and the chat engine (model calls, the tool loop, saving messages) |
| `lib/features/providers/`, `models/` | provider adapters (OpenAI-compatible, Anthropic), presets, the model picker |
| `lib/features/context/` | what the model sees: system prompt, memories, skills, history and compaction |
| `lib/features/memory/`, `tools/`, `mcp/`, `skills/`, `agent/` | long-term memory, built-in tools, MCP servers, skills, the optional NAS agent |
| `lib/features/voice/` | the Fish Audio client, voice calls, voice messages, read-aloud and the voice settings |
| `lib/features/nas/` | the Nur Hub client, discovery and pairing, the NAS page |
| `lib/features/shell/` | the desktop sidebar and the settings screen and dialog |
| `shaders/` | fragment shaders for the call orb and its backdrop |
| `assets/` | fonts, provider logos, the source images of the app icon |
| `android/`, `ios/`, `windows/`, `linux/` | the platform runners; the Windows and Linux ones also answer the `nur/desktop` channel (clipboard images and copied files) |
| `test/` | unit and widget tests |

## How the parts talk

`lib/core/contracts/` holds the interfaces: `LlmClient` (one adapter per provider), `ChatEngine`, `ContextAssembler`,
`ToolRuntime` and `NasHubClient`. The feature folders implement them, and the `lib/features/wiring_*.dart` files put
the implementations behind the providers in `lib/core/providers.dart` when the app starts. That way the voice call
only knows `ChatEngine`: it sends the transcript with `fromVoiceCall: true` and speaks the reply as it streams in.

One chat turn: the chat engine asks the context assembler for the messages and tools, streams the reply from the
model's `LlmClient`, runs tool calls through the tool runtime (risky ones ask the user first) and saves everything in
the database. After the turn the assembler pulls out memories and compacts the history when the window gets full.

Pairing saves the hub in the database and its token in secure storage, and adds the hub's `/llm/v1` proxy as a
provider, so NAS models show up in the model picker like any other. The hub's API is listed in
[hub/README.md](../hub/README.md).
