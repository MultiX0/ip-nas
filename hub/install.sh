#!/usr/bin/env bash
# Install or update Nur Hub on this NAS. Safe to run again.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=/opt/nur-hub
STATE=/var/lib/nur-hub

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo $0" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Installing python3..."
  apt-get update -qq
  apt-get install -y -qq python3
fi

# psutil is optional; the hub falls back to /proc when it is missing.
if ! python3 -c 'import psutil' >/dev/null 2>&1; then
  echo "Installing python3-psutil (optional)..."
  apt-get install -y -qq python3-psutil >/dev/null 2>&1 \
    || { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq python3-psutil >/dev/null 2>&1; } \
    || echo "psutil could not be installed; continuing without it."
fi

python3 -m py_compile "$SRC/nur_hub.py"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SRC/catalog.json"

install -d -m 755 "$DEST"
install -m 755 "$SRC/nur_hub.py" "$DEST/nur_hub.py"
install -m 644 "$SRC/catalog.json" "$DEST/catalog.json"
install -d -m 700 "$STATE"

install -D -m 644 "$SRC/nur-hub.avahi.xml" /etc/avahi/services/nur-hub.service
if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
  systemctl reload avahi-daemon 2>/dev/null || systemctl restart avahi-daemon || true
else
  echo "avahi-daemon is not running. The app still finds the hub by scanning the network;"
  echo "for mDNS discovery install it: sudo apt install avahi-daemon"
fi

install -m 644 "$SRC/nur-hub.service" /etc/systemd/system/nur-hub.service
systemctl daemon-reload
systemctl enable nur-hub.service >/dev/null
systemctl restart nur-hub.service

sleep 1
if systemctl is-active --quiet nur-hub.service; then
  echo "Nur Hub is running on port 8770."
  echo "Open the Nur app on the same Wi-Fi and tap your NAS. The first device becomes the owner;"
  echo "later devices are approved from the app on a device that is already connected."
else
  echo "Nur Hub did not start. See: journalctl -u nur-hub -n 50" >&2
  exit 1
fi
