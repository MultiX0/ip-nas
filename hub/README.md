# Nur Hub

Nur Hub is the small service on my NAS that the Nur app talks to. It is one Python file, [`nur_hub.py`](nur_hub.py),
standard library only, and on my Pi it runs as a Docker container next to the other CasaOS apps.

The app uses it to pair with the NAS, to show the Pi's CPU, RAM, temperature, disks and Wi-Fi, to start, stop and
restart Docker apps and read their logs, to search the web through my own SearXNG, to run commands, and to chat with a
local model. For the local model the hub installs llama.cpp as a container, downloads GGUF models from
Hugging Face and passes the app's chat requests on to them.

Voice is not part of the hub. The app sends speech straight to Fish Audio with your own API key, see
[docs/FISH_AUDIO.md](../docs/FISH_AUDIO.md).

## How the pieces talk

| From | To | Address |
|---|---|---|
| Nur app | Nur Hub | `http://<nas>:8770`, found on the Wi-Fi with mDNS (`_nurhub._tcp`) or by scanning the local network for port 8770 |
| Nur Hub | llama.cpp | `http://127.0.0.1:8088` |
| Nur Hub | SearXNG | `http://127.0.0.1:8888`, set up as in [pi/README.md](../pi/README.md#8-searxng) |
| Nur Hub | Docker, `vcgencmd`, `smartctl`, `nmcli` | the host itself (through `nsenter` when the hub runs in a container) |
| Nur app | Fish Audio | `api.fish.audio`, straight from the phone |

The app never talks to llama.cpp directly. It goes through the hub (`/llm/...`), so it
can stay on 127.0.0.1 and every request needs the token of a paired device.

## Install with Docker / CasaOS (recommended)

The image is [`multix00/nur-hub`](https://hub.docker.com/r/multix00/nur-hub) on Docker Hub, for linux/arm64
(Raspberry Pi 4 and 5) and linux/amd64. It is built from the [`Dockerfile`](Dockerfile) in this folder.

On CasaOS:

1. Click **+** next to Apps and pick **Install a customized app** (in the App Store it is called **Custom Install**).
2. Click **Import** at the top right, paste all of [`docker-compose.yml`](docker-compose.yml), press **Submit**, then
   **Install**.
3. Open the Nur app on a phone or PC on the same Wi-Fi and tap the NAS (see [Pairing](#pairing)).

On any other Docker host, from this folder (the bind-mounted folder has to exist first):

```bash
sudo mkdir -p /DATA/AppData/nur-hub
sudo docker compose up -d
sudo docker logs -f nur-hub
```

The compose file asks for a lot of access, on purpose: the hub manages the NAS it runs on. `network_mode: host` lets it
announce itself over mDNS and reach llama.cpp and SearXNG on 127.0.0.1. `pid: host` and `privileged: true` let
it run the host's own `docker`, `vcgencmd`, `nmcli` and `smartctl` through `nsenter` (the image sets
`NUR_HUB_CONTAINER=1` for this). `/DATA` is mounted so model downloads land in the folder the llama.cpp
containers read, and `/DATA/AppData/nur-hub` keeps the paired devices.

To build the image yourself, run `sudo docker build -t nur-hub:local .` here and put `image: nur-hub:local` in the
compose file. I build mine for both architectures with
`docker buildx build --platform linux/arm64,linux/amd64 -t multix00/nur-hub:1.2.0 -t multix00/nur-hub:latest --push .`

## Install as a systemd service

This is how the hub ran before I moved it into a container, and it still works. It needs root and the Python 3 that
comes with Raspberry Pi OS.

```bash
sudo ./install.sh
journalctl -u nur-hub -f
```

`install.sh` copies `nur_hub.py` and `catalog.json` to `/opt/nur-hub`, creates `/var/lib/nur-hub`, installs
[`nur-hub.service`](nur-hub.service) and the avahi file [`nur-hub.avahi.xml`](nur-hub.avahi.xml) (that is how the app
finds `_nurhub._tcp`) and starts the service. It also installs `python3-psutil` when it can; without it the hub reads
`/proc`. Run it again to update.

Don't run both installs at once, they both want port 8770. To move from the service to the container without pairing
again:

```bash
sudo systemctl disable --now nur-hub
sudo mkdir -p /DATA/AppData/nur-hub
sudo cp /var/lib/nur-hub/devices.json /DATA/AppData/nur-hub/
```

Then install the container as above.

## Settings

Everything is an environment variable: in the compose file for the container, or in `/etc/default/nur-hub` for the
systemd service. Restart the hub after a change. Each variable has a command-line flag too, and the flag wins.

| Variable | Flag | Default | |
|---|---|---|---|
| `NUR_HUB_PORT` | `--port` | `8770` | keep it, the app's network scan only tries 8770 |
| `NUR_HUB_HOST` | `--host` | `0.0.0.0` | address to listen on |
| `NUR_HUB_NAME` | `--name` | hostname | the NAS name in the app. In the container this is the container's hostname (`nur-hub` on CasaOS). The app remembers the NAS by this name, so change it before pairing |
| `NUR_HUB_STATE_DIR` | `--state-dir` | `/var/lib/nur-hub` | holds `devices.json` (the compose file maps it to `/DATA/AppData/nur-hub`) |
| `NUR_HUB_MODELS_DIR` | `--models-dir` | `/DATA/AppData/llamacpp/models` | GGUF files for llama.cpp |
| `NUR_HUB_LLAMA_URL` | `--llama-url` | `http://127.0.0.1:8088` | llama.cpp server |
| `NUR_HUB_SEARX_URL` | `--searx-url` | `http://127.0.0.1:8888` | SearXNG |
| `NUR_HUB_ALLOW_ADMIN` | `--allow-admin 0/1`, `--no-allow-admin` | on | admin mode for `/exec` (any command, as root) |
| `NUR_HUB_AGENT_URL` | | not set | the agent behind `POST /api/v1/agent`, see [Agent mode](#agent-mode) |
| `NUR_HUB_LOG_LEVEL` | `--log-level` | `INFO` | `DEBUG` adds the raw access log |

In the container, keep the model folders under `/DATA`. The hub writes model files itself, and `/DATA` is the only host
folder mounted into its container.

Apart from the model files (`.part` while a download runs), the hub keeps one file: `devices.json`, the paired devices
with a SHA-256 hash of each token (never the token itself), mode 600.

## Pairing

There is no code to type.

1. The app sends `POST /api/v1/pair/request` with its device name. If the hub has no paired device yet, this device
   becomes the owner and gets its token at once.
2. A later device has to wait, for up to 5 minutes. Every paired app shows "New device wants to connect" and you tap
   Approve or Deny. The new device then picks up its token.
3. From then on the app sends `Authorization: Bearer <token>` with every request.

Pair your own phone right after installing: until then, the first device on the network that asks becomes the owner.
`GET /api/v1/info` shows how many devices are paired.

To remove one device, stop the hub, delete its entry from `devices.json` (the names are in there) and start the hub
again, or call `DELETE /api/v1/devices/{id}` from a paired device. To start over, delete the file, and the next device
that connects becomes the owner:

```bash
sudo rm /DATA/AppData/nur-hub/devices.json && sudo docker restart nur-hub    # container
sudo rm /var/lib/nur-hub/devices.json && sudo systemctl restart nur-hub       # systemd service
```

If `devices.json` exists but can't be read, the hub refuses all pairing until you fix or delete it, so a broken file
never gives the owner slot to whoever asks first.

## Local models

The app does all of this (its first-run setup, then the NAS screen), so normally there is nothing to type. The app
opens a chat only when `/api/v1/info` says `setup.ready`: llama.cpp installed and running and at least one model.

Install puts llama.cpp (`ghcr.io/ggml-org/llama.cpp:server`, container `nur-llamacpp`) on the NAS, published on
127.0.0.1 only. llama.cpp runs in router mode on the models folder with 2 threads, `--jinja` for tool calls and a
2048-token context on a NAS with up to 2.5 GB of RAM, 4096 up to 4.5 GB and 8192 above that.
If a llama.cpp container is already there, for example the llama.cpp app from
[`pi/casaos_apps/`](../pi/casaos_apps/), the hub uses it instead of installing another one.

Models come from Hugging Face as GGUF files into the models folder. A stopped download resumes from its `.part` file.
The catalog marks a model as fitting when the RAM it needs stays within 75% of the NAS's RAM (on boards under 2.5 GB:
the RAM minus 0.3 GB), and recommends the biggest fitting model with tools that stays within 60% (on a 1-2 GB board the
smallest one). The hub refuses a download when the file plus 0.9 GB is more than the RAM, or when the disk would end up
with less than 0.5 GB free. After a download it restarts the llama.cpp container, because llama.cpp only looks at the
models folder when it starts.

SearXNG: every 30 seconds the hub checks that SearXNG answers `format=json`. When it refuses (403), the hub adds
`json` to `search.formats` in the container's `settings.yml`, turns the limiter off and restarts the container; when
SearXNG is not installed yet it keeps checking. `searxng_state` in `/api/v1/info` says where it is (`waiting`, `fixing`,
`ready`, `failed`).

llama.cpp's router (seen with build b11819) can lose a model process and then answer every request with "Could not
establish connection" until it is restarted. The hub notices that answer, restarts the llama.cpp container and tells
the app to try again in a minute. It waits 1, 2, 4 and 8 minutes between restarts and stops after 5 in a row without a
working answer, and its log says each time.

The Get models list in the app is [`catalog.json`](catalog.json): the models I tried on the Pi 5 with 4 GB.

| Model | Download | Tool calls | On the Pi 5 (4 GB) |
|---|---|---|---|
| Qwen3.5 2B (Huihui), Q4_0 | 1.2 GB | yes | the one I use, and the one in the video. On the Pi, Q4_0 writes about 10% and reads prompts about 45% faster than Q4_K_M |
| Qwen3.5 2B (Huihui), Q4_K_M | 1.3 GB | yes | same model, a bit slower |
| Qwen3 4B Instruct 2507 | 2.4 GB | yes | good answers, but ran out of memory with an 8k context; better on 8 GB |
| Granite 4.2 3B | 2.2 GB | yes | picks the right commands, but takes 3 to 7 minutes per answer |
| Gemma 3 4B | 2.5 GB | no | nice prose, never calls a tool and makes up NAS numbers |
| LFM2.5 1.2B | 0.7 GB | no | fast (5 to 33 s), weak Arabic |
| Spark-X2.5 4B, IQ4_XS | 2.4 GB | yes | IQ quants are heavy on the CPU, the Pi reached 81 C |

Each entry has `id` (the file name without `.gguf`, the app matches downloaded files by it), `title`, `repo`, `file`,
`size` (bytes, as Hugging Face lists the file), `ram_needed` (bytes, shown in the app, about the file size plus 0.9 GB),
`langs`, `tools`, `vision`, `note` and `recommended`. To use your own list with the container, mount it over the
built-in one:

```yaml
    volumes:
      - /DATA/AppData/nur-hub-catalog.json:/app/catalog.json:ro
```

How I tested these models, and why nothing bigger is worth it on a 4 GB Pi: [docs/SMALL_MODELS.md](../docs/SMALL_MODELS.md).

## Agent mode

`POST /api/v1/agent` passes `{"message": "..."}` on to the URL in `NUR_HUB_AGENT_URL` and returns `{"reply": "..."}`.
The app's "NAS agent" tool uses it. It is off unless you set the variable, and I don't use it in the video. The agent
has to accept a JSON POST without auth (keep it on 127.0.0.1) and answer with JSON that has a `reply`, `response`,
`message`, `text`, `output` or `content` string.

## API

Everything is JSON and errors look like `{"error": "..."}`. All endpoints except the first three need
`Authorization: Bearer <token>`.

| Method | Path | Body or query | Answer |
|---|---|---|---|
| GET | `/api/v1/info` | | `{name, version, model, os, ram, paired_devices, llm: {llamacpp}, searxng, searxng_state, setup: {llamacpp_installed, llamacpp_running, models, ready}}` |
| POST | `/api/v1/pair/request` | `{device_name}` | `{status: "approved", token, device_id}` or `{status: "pending", request_id, expires_in}` |
| GET | `/api/v1/pair/status/{request_id}` | | `{status}`: `pending` (with `expires_in`), `approved` (with `token` and `device_id`, given out once), `denied` or `expired` |
| GET | `/api/v1/pair/pending` | | `[{id, device_name, created}]` |
| POST | `/api/v1/pair/approve/{id}`, `/api/v1/pair/deny/{id}` | | `{ok}` |
| GET | `/api/v1/devices` | | `[{id, name, created, last_seen}]` |
| DELETE | `/api/v1/devices/{id}` | | `{ok}` |
| GET | `/api/v1/system` | | `{cpu, ram_used, ram_total, temp, uptime, disks: [{name, mount, used, total}], net: {rx, tx}, wifi: {ssid, signal, quality}}` |
| GET | `/api/v1/docker/containers` | | `[{name, image, state, status, cpu, mem_used, mem_limit, ports}]` |
| POST | `/api/v1/docker/containers/{name}/{action}` | action `start`, `stop`, `restart`, `pause`, `unpause` or `remove` | `{ok, message}` |
| GET | `/api/v1/docker/containers/{name}/logs` | `tail` (1 to 2000, default 100) | `{logs}` |
| GET | `/api/v1/search` | `q`, `limit` (1 to 50, default 5) | `[{title, url, content}]` from SearXNG |
| POST | `/api/v1/exec` | `{command, mode, timeout}`, mode `safe` (default) or `admin`, timeout 1 to 120 s (default 15) | `{exit_code, stdout, stderr}`, exit code 124 on timeout, at most 64 KB per stream |
| GET | `/api/v1/runtimes` | | `[{id, installed, running, url, container}]` for `llamacpp` |
| POST | `/api/v1/runtimes/{id}/{action}` | action `install` (runs as a job), `start` or `stop` | `{ok, message}`, plus `job_id` for install |
| GET | `/api/v1/models/local` | | `[{runtime, id, file, size, loaded}]` |
| DELETE | `/api/v1/models/local/{runtime}/{id}` | | `{ok, message}` |
| GET | `/api/v1/models/catalog` | | the `catalog.json` entries plus `installed` and `fits` |
| GET | `/api/v1/models/hf/search` | `q`, `limit` (1 to 100, default 20) | `[{repo, downloads, likes, updated}]`, GGUF repos only |
| GET | `/api/v1/models/hf/files` | `repo=owner/name` | `[{file, size, fits}]` |
| POST | `/api/v1/models/download` | `{runtime: "llamacpp", repo, file}` | `{job_id}` |
| GET | `/api/v1/jobs`, `/api/v1/jobs/{id}` | | `{id, kind, state, progress, bytes, total, error, title}`, state `queued`, `running`, `done`, `error` or `cancelled` |
| POST | `/api/v1/jobs/{id}/cancel` | | `{ok}` |
| POST | `/api/v1/agent` | `{message}` | `{reply}`, or 501 when agent mode is off |
| any | `/llm/...` | | passed to llama.cpp, for example `/llm/v1/chat/completions` and `/llm/v1/models`; streams pass through |

In `info`, `searxng` is true only when SearXNG answers and allows JSON output. `pair/request` answers 403 to a web browser, 429 when 5 devices are already waiting and 503 when `devices.json` is broken.

## Updating

For the container:

```bash
sudo docker pull multix00/nur-hub:latest
cd /var/lib/casaos/apps/nur-hub && sudo docker compose up -d
```

CasaOS keeps its copy of the compose file in that folder. With your own compose file, run
`sudo docker compose pull && sudo docker compose up -d` next to it. The paired devices stay, they live in
`/DATA/AppData/nur-hub`. For the systemd service, get the new files and run `sudo ./install.sh` again.

## Troubleshooting

| Problem | What to do |
|---|---|
| The app does not find the NAS | Phone and NAS have to be on the same network. Try `curl http://raspberrypi.local:8770/api/v1/info` from a PC. Without `avahi-daemon` on the host there is no mDNS, but the app still scans the local network for port 8770, and you can type the address (`192.168.1.50`) in the app. |
| "This device is not paired" | The device was removed or `devices.json` was reset. Pair again. |
| "Pairing is locked" | `devices.json` is broken. Fix or delete it, then restart the hub. |
| "Too many devices are waiting for approval" | 5 requests are open. Answer them in the app or wait 5 minutes. |
| Web search says "SearXNG refused JSON output" | Add `json` under `search: formats:` in `/DATA/AppData/searxng/settings.yml` and run `sudo docker restart searxng` ([pi/README.md](../pi/README.md#8-searxng)). |
| "llama.cpp lost its model process" | The hub restarts llama.cpp by itself; try again after a minute. If it keeps happening, `sudo docker logs nur-llamacpp` usually shows a model that does not fit in the RAM. |
| "The local AI runtime is not running" | Start llama.cpp in the app (NAS, Runtimes) and look at `sudo docker logs nur-llamacpp`. |
| A model download is refused | Not enough RAM (file size plus 0.9 GB) or disk space (file size plus 0.5 GB). |
| "Nur Hub has no access to Docker" | The hub is not running as root. |
| Anything else | `sudo docker logs -f nur-hub` or `journalctl -u nur-hub -f`. `NUR_HUB_LOG_LEVEL=DEBUG` logs more. |

## Security

The hub is meant for the home network. Don't forward port 8770 on your router; from outside, reach the NAS through
Tailscale.

A paired device can do a lot. In admin mode (on by default) it can run any command as root; the app asks you before
every command it runs. With `NUR_HUB_ALLOW_ADMIN=0` only the safe list is left: `free`, `df`, `uptime`, `vcgencmd`,
`lsblk`, `ps`, `top -bn1`, `docker ps`, `docker stats`, `docker logs`, `cat` of a few `/proc` files, `ip` show
commands, `hostname`, `uname`, `systemctl status` and `smartctl -H`. Each argument is checked and nothing goes through
a shell. `ps e` is blocked because it prints the environment of every process, and that is where other containers keep
their passwords.

Tokens are random 256-bit strings. The hub keeps only their SHA-256 hashes and never logs them; admin commands are only
logged by length. The traffic is plain HTTP, so someone who can read your network traffic could copy a token. On your
own Wi-Fi or through Tailscale that is fine.

Pairing requests from a web browser are refused (browsers send an `Origin` header, the app does not), so a web page
can't pair itself with a fresh hub. The llama.cpp container the hub installs listens on 127.0.0.1 only.

## Tests

From the repo root:

```bash
python3 -m unittest discover -s hub/tests -v
```

Standard library only, no Docker or Pi needed. The tests start the hub on 127.0.0.1 with temporary folders and a fake
llama.cpp, SearXNG and Hugging Face, and cover pairing, the safe command list, path checks, resumed downloads, the
proxy and the catalog.
