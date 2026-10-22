# Build log

The short story of this build, in order. All dates are October 2026. How to build each part is in the guides linked
from the [README](../README.md).

## 6 October: a 3D model before any parts

The plan: a Raspberry Pi 5 NAS with a small touch screen on the front and a case I design and print myself. Before
buying anything I modelled every part in Blender from its datasheet: the Pi 5 (85 x 56 mm), the Active Cooler, a 2.5"
drive (100 x 69.85 mm) and the Guition JC3248W535 screen from its official drawing. From then on that model was the
reference for every drawing and every fit check.

The first designs were a 120 mm wide box with the Pi lying flat. On paper they had real problems: the Pi couldn't drop
in past its own Ethernet jack, the USB-C plug had zero clearance, and the M2.5 standoffs in my screw kit were 11 mm tall,
not the 6 mm I had drawn. One rule from that review stayed until the end: screws never go into plastic, only into metal
nuts sitting in printed slots.

## 7 October: the "SSDs" are hard drives

I took photos of the two old drives I wanted to use, and they turned out to be laptop hard drives, not SSDs: a WD Blue
WD3200LPVX (320 GB, 7 mm thick) and a WD Scorpio Blue WD1600BEVT (160 GB, 9.5 mm).

Spinning drives change the power math. Each one pulls about 1 A for a second or two while it spins up (1.00 A and
0.95 A in the WD datasheets), and the Pi 5 gives its four USB ports 1.6 A in total, even with the official 27 W supply.
Two drives starting together don't fit in that. The UGREEN 20611 cable comes with a 12 V / 2 A adapter, so the plan
became one of those adapters into a 4-way DC splitter that feeds both drive heads: one extra cable out of the case
instead of one per drive.

## 12 and 13 October: parts ordered

I took the Pi 5 4 GB instead of the 8 GB. It's the same board with the same holes, and a NAS like this doesn't need
more memory. The microSD is 128 GB; 64 GB is plenty, the bigger card just didn't cost much more. The full list is in
the [README](../README.md#parts).

## 15 October: first boot, CasaOS and a lot of AI experiments

Everything arrived and I started measuring it all with a caliper. The big surprise was the screen: its USB-C port is on
the back, not on the side edge like I had assumed, so the layout had to change around it.

I flashed Raspberry Pi OS Lite (64-bit) with Raspberry Pi Imager. Two things got me on the first boot:

- The OS starts with the UK keyboard layout. On a US keyboard that turns `#` into `£` and `@` into `"`, so a password
  with symbols is not what you think you typed. Switch the layout first (`sudo raspi-config`, Localisation Options,
  Keyboard, English (US)), reboot, and only then set the password with `sudo passwd <user>`.
- The Active Cooler's fan wasn't spinning. That's normal: it stays off below 50 °C, and you can see it spin at full
  speed for a moment on every boot.

SMART on the first drive was clean: 0 reallocated sectors after 6913 hours. Then CasaOS, with its one-line installer.

For local AI I started with Ollama and Open WebUI from the CasaOS store, and it was slow. The store's Ollama was an old
version (0.24), and Open WebUI runs extra hidden requests on every message (titles, tags, follow-up questions). I also
tried the PicoClaw agent; even "hi" took forever, because every message carries a huge hidden prompt that the Pi has to
read first. I removed all of it and ran llama.cpp's own server instead, and the difference was huge. For web search I
set up SearXNG: no API key and about 100-150 MB of RAM. It isn't in the CasaOS store, so it's a custom install, and
`json` has to be enabled in its settings or every app gets a 403.

At night I started over on the case. Printing the box design in PETG would have cost far too much, so the next version
was a vertical tower in PLA.

## 16 October: 12 V is not optional

The first tower was too tall and thin. The second one was shorter and wider, all black, with my logo pressed into the
side.

Then I tested the drive power for real over SSH, with a script that puts both drives to sleep and wakes them at the
same moment:

- without 12 V, the second drive froze for about 30 s and only came back after a USB reset, every single time
- with the 12 V adapter in both heads: 5 runs out of 5 clean, about 2 s each, and the 5 V rail never went under 5.01 V

So the 12 V adapter stays. It also sets the height of the case: the UGREEN head sticks out 47.8 mm past the drive and
the 12 V plug is 44 mm long, so the base grew and the tower ended up 209 mm tall. The next version put the 4-port USB
hub back, standing under the top cap with its ports facing up.

I sliced every part in PrusaSlicer and in OrcaSlicer and kept changing the model until both showed zero warnings:

- recesses for rubber feet made long bridges, so the feet became 4 separate legs, each held by an M3 screw and nut
- the tall drive guides were "thin fragile parts", so they became short fins on the side walls
- closed nut slots left floating bridges, so the slots are open at the top now and the nut drops in
- the two tall side slots left a thin strip of wall between them, so they became one slot near the front edge

After that a collision check in Blender slid every part along its real assembly path. It caught two problems: the
screen couldn't slide in, because its corner bosses hit the ribs that held it, and one of the screw blocks for the back
door sat right in the Pi's way. Both fixed. That's the final case: 4 parts, about 156 g of PLA, all on one print plate.

## 16 October: drives and the screen

I wiped and formatted both drives: GPT, one ext4 partition each, labels HDD1 and HDD2, mounted by UUID with `nofail` so
the Pi still boots if a drive is missing. The second drive passes SMART but has 255 reallocated sectors, so it only
holds copies and backups, never the only copy of anything.

Then the screen. I wrote my own firmware for it (PlatformIO, LVGL) and a small Python service on the Pi that talks to
it over USB. Flashing doesn't need the BOOT button: opening the serial port at 1200 baud reboots the board into
download mode. The first test showed one real bug: the "link lost" timer underflowed and dropped the Pi the moment data
arrived. Firmware 1.1.0 cleaned up the layout, and the top bar only says Connected or Not connected; the network name
stays on the Wi-Fi page.

## 16 October: Nur and Nur Hub

I wanted to talk to the NAS, by text and by voice, in Arabic and English. Before writing my own app I tested ZeroClaw as
an agent on the Pi with local models ([results](SMALL_MODELS.md#first-round-which-models-call-tools)): Qwen3 4B picked the right commands, Gemma 3 4B
never called a tool and made numbers up.

Then the Nur app and Nur Hub, the small service on the NAS that the app talks to. Pairing needs no code: the first
phone or PC becomes the owner and approves the next ones. The first voice call took 51 s before the first word, because
the Pi had to read a 1,248-token prompt at about 41 tokens/s. Cutting the voice prompt to 418 tokens and warming
llama.cpp's prompt cache as soon as the call opens brought it down to about 7 s. Nur Hub went to Docker Hub as a ready
image for arm64 and amd64, so it installs from CasaOS like any other app.

## 17 October: smaller fixes

Nur kept introducing itself again and again. The small model had saved a junk memory about itself ("I am Nur") that
went out with every message, together with a hidden time note. Both fixed. On the Pi, the Q4_0 file of Qwen3.5 2B reads
prompts much faster than Q4_K_M (53.6 vs 36.5 tokens/s), so it became the default model. Hub 1.1.2 restarts llama.cpp
after a model download, because llama.cpp only looks at its models folder when it starts.

## 19 October: printed

A print shop printed the four parts in black PLA.

## 20 October: from zero again

I flashed a fresh card and set the Pi up from zero with a monitor and a keyboard, the way the video shows it: Raspberry
Pi OS Lite 64-bit (Debian 13, trixie), keyboard to US, Wi-Fi, SSH, then CasaOS 0.4.15.

## 21 October: the apps

Nur Hub from CasaOS (Install a customized app) failed at first with "conflicting options: hostname and the UTS mode".
CasaOS gives every app container a hostname and Docker refuses that together with `uts: host`, so that line is gone
from the compose file. After that came SearXNG, Nextcloud and Jellyfin. Nextcloud from the CasaOS store answers "Access
through untrusted domain" until you add the Pi's names to `trusted_domains` in its `config.php`.

## 22 October: all together

Everything is in the case now. The screen first showed both drives as "not detected": on the fresh install they get
mounted automatically under `/media/devmon/`, not at `/mnt/hdd1` and `/mnt/hdd2` like on the first one. Pi agent 1.0.2
picks up every mounted drive, whatever its name or mount point, and it runs as a systemd service, so it comes back by
itself after a reboot or a crash.
