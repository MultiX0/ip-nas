# Pi agent for the touch screen

`ipnas_panel_agent.py` is the small service on the Pi that the screen talks to over USB. It sends the Pi's stats every
second and the Docker containers every 3 s, and it runs what you tap on the screen: start, stop, restart, pause or
remove a container, scan for Wi-Fi and switch the Pi to another network (it goes back to the old one if that fails).

Install or update it on the Pi, from this folder:

    sudo bash install.sh

Check it with `systemctl status ipnas-panel` and `journalctl -u ipnas-panel -f`. The tests need neither the screen nor
root: `python3 -m unittest -v`.

Flashing the screen, uninstalling and the USB protocol are in [docs/PANEL.md](../../docs/PANEL.md).
