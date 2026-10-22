# Fish Audio in Nur

The voice in the Nur app (voice calls, voice messages, read-aloud) is Fish Audio: Drama 3 for speech and
transcribe-1-pro for speech to text. The app talks to `api.fish.audio` straight from the phone or PC. Nothing goes
through the NAS or Nur Hub, and the key never leaves your device.

## Your own API key

My key is not in this repo and the app has no key built in, so everyone uses their own:

1. Make an account on [fish.audio](https://fish.audio).
2. Create a key on [fish.audio/app/api-keys](https://fish.audio/app/api-keys). The API is paid from the credit on your
   Fish Audio account ([billing](https://fish.audio/app/billing/)).
3. In Nur open Settings, then Voice, paste the key under "Fish Audio API key" and save. The first voice call also asks
   for it.

The app keeps the key in the system's secure storage on that device. If Fish answers 401 or 403 the key is wrong, and
402 means the account is out of credit; the app tells you which one.

## What the app sends

| What | Endpoint | `model` header |
|---|---|---|
| Voice messages and read-aloud | `POST https://api.fish.audio/v1/tts` | `drama-3` |
| Voice calls | WebSocket `wss://api.fish.audio/v1/tts/live`: msgpack events `start`, `text`, `flush`, `stop`, audio comes back on the same socket | `drama-3` |
| Speech to text | `POST https://api.fish.audio/v1/asr`, multipart form with the audio file | `transcribe-1-pro` |

The model is chosen with that `model` HTTP header, not in the JSON body. A missing or misspelled header gives no error:
Fish quietly falls back to `s2.1-pro`, which reads tags like `[laughing]` out loud or ignores them. If that happens,
check the header first.

Drama 3 came out on 2026-10-13. It speaks 83 languages including Arabic (a 35B mixture-of-experts model with about 3B
active per token) and takes directions in square brackets, like `[excited]`, `[laughing]` or `[short pause]`, plus
`<emphasis>...</emphasis>` and `<whisper>...</whisper>`. The directions can be in any language. During calls Nur lets
the model add them; there is a switch for that in Settings, Voice.

## Try a key with curl

```bash
export FISH_API_KEY=your-key-here
curl -X POST https://api.fish.audio/v1/tts \
  -H "Authorization: Bearer $FISH_API_KEY" \
  -H "Content-Type: application/json" \
  -H "model: drama-3" \
  -d '{"text": "[excited] Hello! [laughing] This is my first Drama 3 voice.", "reference_id": "c70cfb98867a4bfb9ae20d2401257b92", "format": "mp3", "latency": "normal"}' \
  --output hello.mp3
```

`reference_id` picks the voice. This one is Delia, a Drama 3 sample voice from the Fish Audio docs and the default
voice in Nur; any voice from the Fish Audio library works (the id is the last part of its page address).

## Measured on 2026-10-16

The same request with only the `model` header changed. I checked every clip with Fish's speech to text to hear what
was really said.

| `model` header | First byte | Audio length | Laugh performed |
|---|---|---|---|
| `drama-3` | 0.77 s | 6.71 s | yes |
| `drama-3-preview` | 1.08 s | 6.43 s | yes |
| `s2.1-pro` | 1.05 s | 5.36 s | no |

`drama-3-preview` still answers, but it is not in Fish's model list, so use `drama-3`. On the live WebSocket the first
audio came after 0.74 to 0.91 s, and speech to text took 0.56 s for 6 s of audio.

A full voice call with the Pi's local model (speech to text, the model on the Pi, then Drama 3 live) took about 6.8 s
from the end of my sentence to the first sound: 1.2 s for speech to text, 4.5 s to the model's first token, 6.0 s to
the first full phrase, then about 0.8 s for Drama 3. The first version needed 51 s; how it got down to 7 s is in the
[build log](JOURNAL.md#16-october-nur-and-nur-hub) and in [SMALL_MODELS.md](SMALL_MODELS.md).
