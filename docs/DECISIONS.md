# Why these parts and tools

Short notes on why the build looks the way it does. For the build itself, start at the [README](../README.md).

## Raspberry Pi 5, 4 GB

A NAS with CasaOS, a few Docker apps and a 2B local model fits in 4 GB. The 8 GB board has the same size and the same
holes, so the case takes either one, but it costs a lot more.

The Active Cooler is not optional on a Pi 5. The CPU gets throttled between 80 and 85 °C; with the cooler mine idles at
40-50 °C, and the fan only starts at 50 °C. The official 27 W supply (5.1 V, 5 A) matters too: only with a 5 A supply
does the Pi allow 1.6 A on its USB ports instead of 0.6 A, and a weak supply gives you undervoltage and random problems.

## Raspberry Pi OS Lite (64-bit)

It's Debian with the Pi 5 drivers, and plain Debian images didn't fully support the Pi 5 when I set this up. Lite means
no desktop: the NAS is managed from a browser, over SSH and from its own screen.

## CasaOS

One web page for the drives, the files, network shares and one-click Docker apps, and a one-line install that brings
Docker with it. It has no RAID, which is fine here: my two drives are two separate volumes, and the second one only
holds backups.

## Two old laptop drives on UGREEN 20611 cables

I used drives I already had. 2.5" drives keep the case small, and the UGREEN 20611 (USB 3.0 to SATA, with UASP) plugs
straight onto the drive, no enclosure needed. It comes with a 12 V / 2 A adapter (5.5 x 2.1 mm plug, centre positive).

UGREEN says 2.5" drives don't need that adapter. For one drive on a laptop that's true. For two drives on a Pi 5 it
isn't: both spin up together on every boot and need about 2 A, and the Pi gives all its USB ports 1.6 A in total. In my
test, without 12 V the second drive froze for 30 s on every wake-up. One adapter into a 4-way DC splitter powers both
heads, so only one thin extra cable leaves the case. The measurements are in [HARDWARE.md](HARDWARE.md#power-tests).

## The USB hub

The drives take both blue USB 3 ports and the screen takes one black port. A small hub on the last black port gives
four free ports on top of the case. It runs at USB 2 speed and has no power of its own, so it's for a keyboard or a
flash drive, not for more hard drives.

## llama.cpp for local AI

I started with Ollama and Open WebUI. On a 4 GB Pi, llama.cpp's own server was much faster: no extra hidden requests,
and newer ARM code than the Ollama build in the CasaOS store. Nur Hub can install either one, and Ollama is still the
easier pick if you switch between many models.

Models stay at 4-bit. Below that, small models get much worse and they aren't faster on the Pi's CPU. Q4_0 files read
prompts faster on ARM than Q4_K_M. The default is Qwen3.5 2B (Q4_0, a 1.2 GB download); 4B models only fit with a
4096-token context.

## Nur and Nur Hub

I wanted to talk to my NAS by text and by voice, in Arabic and English, from my phone and my PC, and to control it from
the same place. I didn't find an app that does both, so I wrote Nur (Flutter: Android, iOS, Windows). The voice is Fish
Audio Drama 3: it speaks Arabic, and it follows emotion tags like `[excited]`. Nur Hub is the small service on the NAS
that the app talks to (status, Docker apps, web search, model downloads). It runs as a container with host networking,
host PID and privileged mode because it manages the NAS itself, and only paired devices can use it.

## SearXNG

Web search for Nur without an API key. Google, Bing, Brave and Tavily all want keys; SearXNG asks several engines at
once and uses about 100-150 MB of RAM.

## Nextcloud, Jellyfin, Immich and Tailscale

These replace the cloud subscriptions most people pay for: Nextcloud for files (like Google Drive), Jellyfin for your
own movies and shows, and Immich for photo backup from the phone (like Google Photos). Tailscale lets me reach the NAS
from anywhere without opening ports on the router, which I can't do on my network anyway, and its personal plan is
free. All four are in the CasaOS App Store.

## The case

I designed it around the real parts, measured with a caliper, so nothing has to be forced or glued. It's a vertical
tower so it takes little space on a desk, with the drives behind a window and the screen at the front.

It's PLA because it's cheap and every print shop has it. PETG handles heat better (PLA starts to soften around
55-60 °C), so for a hot room without AC I'd print it in PETG. The tower is 209 mm tall because of the straight 12 V
plugs under the drives; 90-degree DC adapters would make it shorter, but I couldn't buy them locally. Screws only go
into metal nuts, never into plastic, so the case can be opened as often as you like. Before printing, every part had to
pass two slicers with zero warnings and a collision check in Blender.

## The screen

The Guition JC3248W535 is an ESP32-S3 with a 3.5" 320 x 480 capacitive touch screen for about $20, and it connects to
the Pi with one USB cable: no soldering, no GPIO wires. The screen itself knows nothing about the network. A small
Python service on the Pi sends it live data and runs its commands (Docker and Wi-Fi), so no passwords are stored on the
screen. If you switch Wi-Fi from the screen and the new network doesn't come up within 45 s, the Pi goes back to the
old one, so a typo can't take the NAS offline.
