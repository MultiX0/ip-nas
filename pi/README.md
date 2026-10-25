# Raspberry Pi setup

How I set up the Pi for the NAS, in the order of the video: the SD card, the first boot, SSH, CasaOS, the two drives,
then the apps. It is for a Raspberry Pi 5 (4 GB) with Raspberry Pi OS Lite (64-bit), which is Debian 13 (trixie).
In the examples the Pi is `raspberrypi.local` (or `192.168.1.50`) and the user is `pi`; use your own.

`casaos_apps/` has a compose file for each app, and `snapshot/` shows what my Pi looked like on 2026-10-22.

## 1. Flash Raspberry Pi OS

The microSD card (64 GB or more) goes into a USB card reader on the PC.

1. Install Raspberry Pi Imager from https://www.raspberrypi.com/software/ (the video uses 2.0.x).
2. Device: Raspberry Pi 5.
3. OS: Raspberry Pi OS (other) > Raspberry Pi OS Lite (64-bit). Lite has no desktop. A NAS doesn't need one, and the
   apps get the RAM instead.
4. Storage: the card. Check the size, so you don't pick another drive.
5. Imager then offers to set the hostname, time zone and keyboard, a user, Wi-Fi and SSH. I left it empty and did all
   of it on the Pi (sections 2 and 3). If you fill it in, keep the hostname `raspberrypi` and turn SSH on, and most of
   sections 2 and 3 is done.
6. Write, and wait until Imager has verified the card.

When it's done, Windows may say the disk has to be formatted before you can use it. Click **Cancel**: that's the Linux
partition, which Windows can't read.

## 2. First boot with a monitor and a keyboard

Card into the Pi, the monitor on the micro-HDMI port next to the USB-C power port (HDMI0), a USB keyboard, Ethernet if
you have it. Then plug in the official 27 W supply. The first boot takes a minute or two.

Without a user from Imager, the first boot ends in a small text wizard: the keyboard layout (if it asks), a new user
name (I use `pi` in this guide) and a password, twice. Then log in with them.

The layout matters for the password: Raspberry Pi OS starts with the UK layout, and on a US keyboard Shift+2 then types
`"` and Shift+3 `£`. Fix the layout first (next section) or use a password without symbols until then.

## 3. Keyboard, Wi-Fi, SSH, time zone, hostname

What I typed on the Pi in the video:

```bash
sudo raspi-config nonint do_configure_keyboard us   # US keyboard layout
sudo raspi-config                                    # 1 System Options > S1 Wireless LAN: country, Wi-Fi name, password
hostname -I                                          # prints the Pi's IP address once the Wi-Fi is up
sudo systemctl enable --now ssh                      # SSH on, now and after every boot
```

The rest is in the same menu, `sudo raspi-config`:

- 5 Localisation Options > L2 Timezone. Set yours: CasaOS hands it to the apps.
- 5 Localisation Options > L3 Keyboard, the menu version of the first line, for any other layout.
- 5 Localisation Options > L1 Locale, only if you want another language or date format.
- 1 System Options > S4 Hostname. I kept `raspberrypi`, so the Pi is `raspberrypi.local` on the network. If you change
  it, use your name everywhere this guide says `raspberrypi`.
- 3 Interface Options > I1 SSH, the menu version of the last line.

Wi-Fi without the menu: `sudo nmcli dev wifi connect "MyWiFi" password "your-wifi-password"`. Ethernet needs nothing.

## 4. SSH from the PC

In PowerShell on Windows, or a terminal on macOS or Linux:

```bash
ssh pi@raspberrypi.local
```

Answer `yes` to the fingerprint question the first time. If `.local` names don't work on your network, use the address
from `hostname -I`: `ssh pi@192.168.1.50`. From here on everything happens over SSH, and the monitor and the keyboard
can go back in the drawer. `cat /etc/os-release` should say `Debian GNU/Linux 13 (trixie)`.

Logging in with a key instead of the password is optional. In PowerShell:

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\*.pub | ssh pi@raspberrypi.local "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

On macOS and Linux, `ssh-copy-id pi@raspberrypi.local` does the second line.

Then update everything once:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

## 5. CasaOS

```bash
curl -fsSL https://get.casaos.io | sudo bash
```

That's the official install command from the CasaOS README. It takes a few minutes and installs Docker and what CasaOS
uses next to it: Samba for Windows shares, smartmontools for drive health, udevil (its devmon mounts USB drives),
mergerfs and rclone. At the end it prints the address CasaOS runs at.

Open `http://raspberrypi.local` on the PC and create your CasaOS account.

Good to know:

- Each app keeps its settings and data in `/DATA/AppData/<app>`, and the Files app in CasaOS starts at `/DATA`.
- To install one of the compose files from this repo: **+** next to the apps, **Install a customized app**, the import
  button at the top right, paste the file, **Submit**, check the ports and folders, **Install**.
- The App Store shows two sources from the start, CasaOS's own apps and BigBear's, so a search often finds the same
  app twice. Below I say which one I used.
- A big image can sit at 75% for minutes while it downloads. Just wait.
- Your user isn't in the `docker` group, so Docker commands need `sudo` (`sudo docker ps`).
- To update CasaOS later: `curl -fsSL https://get.casaos.io/update | sudo bash`.

## 6. The drives

### Power

Two 2.5" drives, each on a UGREEN 20611 USB 3.0 to SATA cable, in the two blue USB 3 ports. The UGREEN cable has a
12 V input: one of the 12 V adapters goes into the DC splitter (1 female to 4 male, 5.5 x 2.1 mm), and the splitter
feeds both cables, so one adapter powers both drives.

Don't skip the 12 V. The Pi 5 gives its four USB ports 1.6 A together (0.6 A with a weaker supply than the official
27 W one), and two laptop drives spinning up want more. In my test the second drive froze for 30 s every time both
started on USB power alone; with the 12 V adapter both were up in about 2 s, every time. The numbers are in
[../docs/HARDWARE.md](../docs/HARDWARE.md).

The drives have their own power, so they don't go off with the Pi. To switch everything off: `sudo poweroff`, wait
until the Pi's LED is red and the drives are quiet, then switch off the power strip. Shut down before you plug or
unplug a drive.

### Check them

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL,MOUNTPOINTS   # the drives are sda and sdb, the SD card is mmcblk0
lsusb -t                                           # each drive: Driver=uas, 5000M (USB 3)
sudo smartctl -d sat -H /dev/sda                   # must say PASSED (then the same for /dev/sdb)
sudo smartctl -d sat -A /dev/sda                   # Reallocated_Sector_Ct and Current_Pending_Sector should be 0
```

`-d sat` is needed because the drive sits behind a USB bridge. A drive at `480M` in a blue port usually has a plug that
isn't all the way in. A long surface test runs inside the drive and takes an hour or more:
`sudo smartctl -d sat -t long /dev/sda`, later `sudo smartctl -d sat -l selftest /dev/sda` shows the result. My 160 GB
drive has 255 reallocated sectors, which is why it only gets copies (below).

If a drive hangs or disappears, `dmesg | grep -iE 'uas|reset|disconnect'` shows the USB resets, and
`vcgencmd pmic_read_adc EXT5V_V` the Pi's 5 V input, which should stay above 5 V. Both point at power first: is the
12 V adapter in?

### Format them (this erases them)

One GPT partition per drive, ext4, labelled HDD1 and HDD2. Do one drive at a time, and look at `lsblk` first: `sdX`
below is `sda` or `sdb`, never `mmcblk0`.

```bash
sudo umount /dev/sdX?*                                   # only if an old partition got mounted
sudo wipefs -a /dev/sdX                                  # removes the old partition table
sudo parted -s -a optimal /dev/sdX mklabel gpt mkpart data ext4 1MiB 100%
sudo mkfs.ext4 -L HDD1 -m 0 /dev/sdX1                    # -L HDD2 for the second drive
```

`-m 0` drops the 5% that ext4 keeps free for root, which a data drive doesn't need. On a drive that had a filesystem
before, mkfs asks whether to proceed: answer `y`. If parted warns that the partition is not aligned for best
performance, ignore it: some USB bridges report odd values, and a start at 1 MiB is fine.

### Mount them at /DATA/HDD1 and /DATA/HDD2

CasaOS's devmon mounts every USB drive by itself, at `/media/devmon/HDD1` and `/media/devmon/HDD2`. That's how my Pi
ran in the video, but for a NAS it isn't enough. devmon starts at the same time as Docker, so after a reboot an app can
start before its drive is mounted and write into an empty folder on the SD card. devmon also unmounts the drives
whenever it stops or restarts, and `/media/devmon` is closed to your user.

So I tell devmon to leave these two drives alone and mount them from `/etc/fstab`, by UUID, before Docker starts. Under
`/DATA` they also show up in the CasaOS Files app, where you can upload files and share folders.

```bash
# devmon ignores the labels HDD1 and HDD2 from now on (when it restarts it lets go of them)
sudo sed -i 's/--ignore-label EFI/& --ignore-label HDD1 --ignore-label HDD2/' /etc/conf.d/devmon
sudo systemctl restart devmon@devmon

# the mount points; +i on the empty folders means nothing can write into them while a drive is missing
sudo mkdir -p /DATA/HDD1 /DATA/HDD2
sudo chattr +i /DATA/HDD1 /DATA/HDD2

# one line per drive in /etc/fstab
for d in HDD1 HDD2; do
  echo "UUID=$(sudo blkid -s UUID -o value /dev/disk/by-label/$d)  /DATA/$d  ext4  defaults,noatime,nofail,x-systemd.device-timeout=30s,x-systemd.before=docker.service  0  2" | sudo tee -a /etc/fstab
done
sudo systemctl daemon-reload
sudo mount -a
findmnt /DATA/HDD1; findmnt /DATA/HDD2
```

`cat /etc/conf.d/devmon` should now end in `--ignore-label HDD1 --ignore-label HDD2"`, and both `findmnt` lines should
show `/dev/sdX1` and `ext4`. Reboot once and check again. What the fstab options do:

- `UUID=`: the drive is found by its filesystem's ID, not by `sda`/`sdb`, which can swap between boots.
- `nofail` and `x-systemd.device-timeout=30s`: the Pi still boots without the drive, after waiting 30 s at most.
- `x-systemd.before=docker.service`: Docker, and so every app, starts only after the drives are mounted (or given up
  on).
- `noatime`: no write to the drive every time a file is read.

The apps' folders on the drives:

```bash
sudo mkdir -p /DATA/HDD1/media/movies /DATA/HDD1/media/tvshows /DATA/HDD1/immich /DATA/HDD1/nextcloud /DATA/HDD2/backup
sudo chown -R "$USER:$USER" /DATA/HDD1/media      # your user (1000), the same one Jellyfin runs as
sudo chown 33:33 /DATA/HDD1/nextcloud && sudo chmod 770 /DATA/HDD1/nextcloud   # www-data in the Nextcloud container
```

| App | On the drive | Inside the container | Compose file |
|---|---|---|---|
| Jellyfin | `/DATA/HDD1/media/movies`, `/DATA/HDD1/media/tvshows` | `/data/movies`, `/data/tvshows` | [jellyfin](casaos_apps/jellyfin.docker-compose.yml) |
| Nextcloud | `/DATA/HDD1/nextcloud` | `/var/www/html/data` | [nextcloud](casaos_apps/nextcloud.docker-compose.yml) |
| Immich | `/DATA/HDD1/immich` | `/data` | [immich](casaos_apps/immich.docker-compose.yml) |
| copies | `/DATA/HDD2/backup` | | the cron line below |

Settings, databases and caches stay in `/DATA/AppData` on the SD card. They are small, and an SD card handles lots of
small reads better than a laptop drive.

### Copies on HDD2

HDD2 is my old 160 GB drive with reallocated sectors, so it only holds copies, never the only copy of anything. Every
night at 3:30 it copies the photos and the Nextcloud files. Add this line with `sudo crontab -e`:

```
30 3 * * * mountpoint -q /DATA/HDD1 && mountpoint -q /DATA/HDD2 && { rsync -a /DATA/HDD1/immich/ /DATA/HDD2/backup/immich/; rsync -a /DATA/HDD1/nextcloud/ /DATA/HDD2/backup/nextcloud/; }
```

`mountpoint -q` skips the copy when a drive is missing. Without `--delete`, a file you delete stays in the copy, so keep
an eye on the space with `df -h /DATA/HDD2`.

## 7. Nur Hub and the Nur app

Nur Hub is the small service I wrote for the Nur app: NAS status, starting and stopping Docker apps, web search and local
AI. It goes in like the compose files here: paste [../hub/docker-compose.yml](../hub/docker-compose.yml) into
**Install a customized app**. Then open the Nur app on the same Wi-Fi and tap your NAS; the first device becomes the
owner. llama.cpp and the first model come from the app's setup screen; the hub runs llama.cpp as the
container `nur-llamacpp` on 127.0.0.1:8088. The rest is in [../hub/README.md](../hub/README.md) and
[../app/README.md](../app/README.md).

## 8. SearXNG

SearXNG asks Google, Bing, DuckDuckGo and others at once and gives you the results, with no API key and no account. Nur
Hub uses it for web search. Neither CasaOS store has it, so it goes in as a custom app.

1. Install [casaos_apps/searxng.docker-compose.yml](casaos_apps/searxng.docker-compose.yml) with **Install a
   customized app**. On its first start SearXNG writes a default `settings.yml` into `/DATA/AppData/searxng`.
2. Replace that file. Nur Hub asks for `format=json` and the default only allows HTML, so every search from the hub
   would get `403 Forbidden`:

```bash
sudo tee /DATA/AppData/searxng/settings.yml > /dev/null <<EOF
use_default_settings: true
server:
  secret_key: "$(openssl rand -hex 32)"
  limiter: false
  image_proxy: true
search:
  formats:
    - html
    - json
EOF
sudo docker restart searxng
```

`use_default_settings: true` keeps SearXNG's defaults (engines, languages) and changes only what follows. The secret key
is a new random one. `limiter: false` turns off the bot protection, which is for public servers and would block the
hub. `image_proxy` loads the result images through the Pi.

3. Test it:

```bash
curl -s "http://127.0.0.1:8888/search?q=raspberry+pi&format=json" | head -c 200
```

The answer should start with `{"query": "raspberry pi"`. In a browser it's `http://raspberrypi.local:8888`. Nur Hub
looks for it at `http://127.0.0.1:8888` (`NUR_HUB_SEARX_URL` changes that).

Still `403` on `format=json`: `json` is missing under `search: formats:`, or the container wasn't restarted. If the
container keeps restarting, `settings.yml` has a YAML mistake (2 spaces, no tabs); `sudo docker logs searxng` says where.

## 9. Nextcloud

Your own Google Drive: files, photos, calendar and contacts, with apps for phones and PCs.

In the video I installed it from the App Store: search "Nextcloud", four results, the first one is BigBear's
**Nextcloud** on port 7580. That app keeps the files on the SD card, and its admin is `casaos` with the password
`casaos`. I'd import [casaos_apps/nextcloud.docker-compose.yml](casaos_apps/nextcloud.docker-compose.yml) instead: the
same app with your own passwords, the files on HDD1 and the trusted domains already set. Before you install it, replace
the three `CHANGE_ME` (the two `POSTGRES_PASSWORD` must be the same) and put your Pi's IP into
`NEXTCLOUD_TRUSTED_DOMAINS`. The first start takes a few minutes.

Then open `http://raspberrypi.local:7580` and log in as `casaos`.

With the store app the first visit ends in "Access through untrusted domain": Nextcloud only answers to the addresses
in its `trusted_domains`, and the store app only knows `localhost`. The fix from the video: in CasaOS Files open DATA >
AppData > big-bear-nextcloud > html > config > `config.php` and add your addresses:

```php
  'trusted_domains' =>
  array (
    0 => 'localhost',
    1 => 'raspberrypi.local',
    2 => 'raspberrypi',
    3 => '192.168.1.50',
  ),
```

Save, restart Nextcloud from its menu in CasaOS, reload. From SSH it's one address at a time:
`sudo docker exec -u www-data nextcloud php occ config:system:set trusted_domains 3 --value=192.168.1.50`. Your
Tailscale address (section 12) goes in the same way. And with the store app, change the admin password right after the
first login (your avatar > Personal settings > Security).

Upload through Nextcloud (web page, phone app or desktop client). Files copied straight into `/DATA/HDD1/nextcloud`
only show up after `sudo docker exec -u www-data nextcloud php occ files:scan --all`.

## 10. Jellyfin

Your movies and shows, streamed to the browser, phones and TVs.

App Store: search "jellyfin". The one I installed is BigBear's **Jellyfin** ("A Free Software Media System..."), port
8096.
Or import [casaos_apps/jellyfin.docker-compose.yml](casaos_apps/jellyfin.docker-compose.yml), which is that app with the
library on HDD1. If you already have the store app, change it instead: its menu in CasaOS > Settings, and point the
`/data/movies` and `/data/tvshows` volumes at `/DATA/HDD1/media/movies` and `/DATA/HDD1/media/tvshows`.

Open `http://raspberrypi.local:8096` and go through the first-run wizard: server name and language, your admin user
and password, the libraries (Movies on `/data/movies`, Shows on `/data/tvshows`), the metadata language, remote access,
Finish.

Copy the films into DATA > HDD1 > media > movies with CasaOS Files (Upload), or share that folder in Files and copy over
the network. Jellyfin notices new files by itself; if one doesn't show up, run Scan All Libraries in its dashboard. On
phones and TVs, the Jellyfin app wants the server address `http://192.168.1.50:8096`.

The Pi 5 has no hardware video encoder, so when a player can't play a file as it is, Jellyfin converts it on the CPU,
and that is slow for 1080p and up. MP4 and MKV with H.264 or HEVC play directly on most phones and TVs.

## 11. Immich

Immich backs up the photos and videos from your phone, like Google Photos. The phone app does it in the background.

The App Store has a few Immich apps (CasaOS's is still on v2.7.2, BigBear's on v3.1.0) and they keep the photos on the
SD card, so I use Immich's own compose file:
[casaos_apps/immich.docker-compose.yml](casaos_apps/immich.docker-compose.yml) (release v3.3.5, photos in
`/DATA/HDD1/immich`). Replace both `CHANGE_ME` with the same password, letters and digits only, and import it.

1. Open `http://raspberrypi.local:2283`, click Getting Started and create the admin account.
2. Install the Immich app on the phone, server URL `http://192.168.1.50:2283`, log in with that account.
3. Turn on backup in the app and pick the albums.

Memory: with Nur Hub, SearXNG, Nextcloud and Jellyfin running my Pi used about 1 GB, and llama.cpp with Qwen3.5 2B needs
about 2.2 GB more. Immich's machine learning (faces, smart search) wants 1 GB or more while it works, so on a 4 GB Pi
not everything fits at once. When memory gets tight, turn machine learning off (Administration > Settings > Machine
Learning) and stop the `immich_machine_learning` container, or don't keep a local model loaded during a big first
backup. Raspberry Pi OS ignores Docker memory limits (the kernel runs with `cgroup_disable=memory`), so `free -h` is the
number to watch.

## 12. Tailscale

Tailscale puts your phone, your laptop and the Pi on one private network, so you reach the NAS from anywhere without
opening a port on the router. The Personal plan is free.

In the App Store, search "tailscale": there are two. Install the one that says "Connect your devices and users together
in your own secure virtual private network". That's CasaOS's own, the same as
[casaos_apps/tailscale.docker-compose.yml](casaos_apps/tailscale.docker-compose.yml). It runs on the host network, so
the whole Pi joins your tailnet. The other one (BigBear's, "The easiest, most secure way to use WireGuard and 2FA")
runs Tailscale only inside its own container, and the Pi's apps can't be reached through it without more setup.

1. Open `http://raspberrypi.local:5252` (Tailscale's own page), click Log in and sign in with your Tailscale account.
2. The Pi shows up at https://login.tailscale.com/admin/machines with a `100.x.y.z` address. In its menu there, pick
   Disable key expiry, or it gets logged out after 180 days.
3. Install Tailscale on the phone or laptop, same account.

From anywhere, with Tailscale on: `http://100.x.y.z` is CasaOS, `:8096` Jellyfin, `:2283` Immich and `:7580`
Nextcloud (after adding `100.x.y.z` to its trusted domains, section 9).

## 13. The screen

The 3.5" touch screen talks to a small Python service on the Pi over USB. Copy [../panel/pi_agent/](../panel/pi_agent/)
to the Pi and run `sudo bash install.sh` in it. The firmware, the protocol and the details are in
[../docs/PANEL.md](../docs/PANEL.md) and [../panel/pi_agent/README.md](../panel/pi_agent/README.md).

## Ports

| Port | What |
|---|---|
| 22 | SSH |
| 80 | CasaOS |
| 139, 445 | Samba (Windows shares, from CasaOS) |
| 8770 | Nur Hub |
| 8888 | SearXNG |
| 7580 | Nextcloud |
| 8096 | Jellyfin (8920 HTTPS, 7359/udp discovery, 1900/udp DLNA) |
| 2283 | Immich |
| 5252 | Tailscale's login page |
| 8088 | llama.cpp; only on 127.0.0.1, the app reaches it through Nur Hub |

## Quick checks

```bash
findmnt /DATA/HDD1; findmnt /DATA/HDD2                                    # both drives mounted
df -h /DATA/HDD1 /DATA/HDD2                                                # free space
sudo docker ps --format "table {{.Names}}\t{{.Status}}"                   # the apps
curl -s "http://127.0.0.1:8888/search?q=test&format=json" | head -c 80    # SearXNG answers JSON
curl -s http://127.0.0.1:8770/api/v1/info                                  # Nur Hub
vcgencmd measure_temp; vcgencmd get_throttled                              # throttled=0x0 is good
cat /sys/devices/platform/cooling_fan/hwmon/*/fan1_input                   # fan speed in RPM, 0 = off
free -h                                                                    # memory
```

The Active Cooler's fan stays off below 50 °C, that's normal. The Pi starts slowing itself down at 80 °C.
