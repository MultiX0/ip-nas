#!/usr/bin/env bash
# Installs or updates the panel agent as the systemd service ipnas-panel. Run it on the Pi from this folder:
#   sudo bash install.sh
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }

if ! python3 -c 'import serial, psutil' 2>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq python3-serial python3-psutil >/dev/null
fi
install -d /opt/ipnas-panel
install -m 755 ipnas_panel_agent.py /opt/ipnas-panel/ipnas_panel_agent.py
install -m 644 README.md /opt/ipnas-panel/README.md
install -m 644 ipnas-panel.service /etc/systemd/system/ipnas-panel.service
systemctl daemon-reload
systemctl enable ipnas-panel.service
systemctl restart ipnas-panel.service      # restart, not start, so an update takes effect
sleep 3
echo "enabled: $(systemctl is-enabled ipnas-panel.service)   active: $(systemctl is-active ipnas-panel.service)"
journalctl -u ipnas-panel.service -n 5 --no-pager

# what the screen will show, read the same way the agent reads it
python3 - <<'EOF'
import sys
sys.path.insert(0, "/opt/ipnas-panel")
import ipnas_panel_agent as a
for d in a.stat_msg(a.wifi_now())["disks"]:
    print(d["n"], "%.0f of %.0f GB used" % (d["u"] / 1e9, d["t"] / 1e9) if d["ok"] else "not connected")
lst, err = a.containers()
print(len(lst or []), "containers", err)
EOF
