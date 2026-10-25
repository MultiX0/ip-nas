# Disclaimer

Nur is a free, open-source app for chatting with AI models that run on your own hardware, mostly small models on a
Raspberry Pi. Please read this before you rely on it.

## Small local models make mistakes

- The models Nur runs on a Raspberry Pi have 1 to 4 billion parameters. Frontier models such as ChatGPT, Claude or
  Gemini are hundreds of times larger. Expect much weaker answers.
- They can be wrong while sounding sure: invented facts, wrong numbers, wrong code, misunderstood questions, mixed up
  languages (Arabic replies are weaker than English ones).
- They forget earlier parts of long chats and can repeat themselves.
- Check anything important yourself. Do not use Nur for medical, legal, financial or safety decisions.

## They can be slow

- On a Raspberry Pi a reply can take from a few seconds to more than a minute. The first message after the model
  loads, long chats, attachments and web searches are slower.
- The Pi gets warm under load. Use a case with cooling and a proper power supply.

## Actions on your NAS

- Nur can read your NAS's status and, when you approve it, start, stop or restart Docker apps and run commands.
  A small model can pick the wrong action. Read every approval before you accept it.
- Keep backups of anything you cannot lose. You use these features at your own risk.

## Where your data goes

- Chats, memories and settings stay on your device. Prompts go to your NAS and the model running on it.
- Web search goes through your own SearXNG on the NAS, which asks public search engines for you.
- If you add a cloud provider (OpenAI, Anthropic, OpenRouter...) or Fish Audio voice, what you send to it goes to
  that company under its own terms.

## No warranty

- Nur, Nur Hub and the IP NAS project are provided as is, under the MIT license, without warranty of any kind.
  The authors are not liable for any damage, data loss or costs from using them.
- Nur is a hobby project and is still being developed. Features can change or break between versions.
