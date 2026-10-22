#!/usr/bin/env python3
"""Pi side of the IP NAS touch screen: finds the screen on USB, streams the Pi's stats and Docker containers to it as
JSON lines and runs the commands it sends back. Runs as root (systemd service ipnas-panel). Protocol: docs/PANEL.md."""
import glob, json, os, queue, re, socket, subprocess, threading, time
import psutil
import serial                                     # apt: python3-serial

VERSION = "1.0.3"
ESP_VID = "303a"                                  # Espressif USB vendor ID
MAX_CTRS = 24                                     # the screen keeps 24 containers (MAX_CTR in main.cpp)
MAX_NETS = 20                                     # and 20 Wi-Fi networks (MAX_NET)
CTR_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}")
ACTIONS = {"start", "stop", "restart", "pause", "unpause", "rm"}
DISK_RE = re.compile(r"^(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|hd[a-z]+|xvd[a-z]+)")
SYSTEM_MOUNTS = ("/", "/boot", "/boot/firmware")
# nmcli translates its output (even "yes"), so parse it in English; C.UTF-8 keeps non-ASCII Wi-Fi names intact
CMD_ENV = dict(os.environ, LC_ALL="C.UTF-8")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def sh(cmd, timeout=20):
    """Run a command. A missing program or a timeout comes back as an error code with a short message: the exception
    text would contain the whole command line, and for Wi-Fi that includes the password."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=CMD_ENV)
    except FileNotFoundError:
        return 127, "", f"{cmd[0]} not found"
    except subprocess.TimeoutExpired:
        return 124, "", f"{cmd[0]} timed out"
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()


def read_text(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def nm_fields(line):
    """Split a line of `nmcli -t` output. nmcli puts a backslash before ':' and '\\' inside values."""
    fields, cur, esc = [], "", False
    for ch in line:
        if esc:
            cur += ch; esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            fields.append(cur); cur = ""
        else:
            cur += ch
    fields.append(cur)
    return fields


def cpu_temp():
    try:
        return round(int(read_text("/sys/class/thermal/thermal_zone0/temp")) / 1000.0, 1)
    except ValueError:
        return None


def wifi_now():
    rc, out, _ = sh(["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi"], 8)
    for f in map(nm_fields, out.splitlines()):
        if len(f) == 3 and f[0] == "yes":
            return {"ssid": f[1], "signal": int(f[2]) if f[2].isdigit() else 0}
    return {"ssid": "", "signal": 0}


def primary_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("1.1.1.1", 53))                # UDP: nothing is sent, it only picks the outgoing interface
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return ""


def data_drives():
    """(mount point, usage) of each mounted data drive, whatever its name or mount point: one per physical disk (its
    largest mounted partition), in disk order (sda, sdb, ...). The SD card (mmcblk) is left out."""
    best = {}
    for p in psutil.disk_partitions(all=False):
        m = DISK_RE.match(os.path.basename(os.path.realpath(p.device)))
        if not m or p.mountpoint in SYSTEM_MOUNTS:
            continue
        try:
            du = psutil.disk_usage(p.mountpoint)
        except OSError:
            continue
        disk = m.group(1)
        if disk not in best or du.total > best[disk][1].total:
            best[disk] = (p.mountpoint, du)
    return [best[k] for k in sorted(best)]


_net_prev = [None, 0.0]


def stat_msg(wifi):
    """The screen shows its three storage rows by position: the first two data drives, then the SD card (/)."""
    vm = psutil.virtual_memory()
    drives = data_drives()
    disks = []
    for i in range(2):
        if i < len(drives):
            du = drives[i][1]
            disks.append({"n": "HDD%d" % (i + 1), "ok": True, "u": du.used, "t": du.total})
        else:
            disks.append({"n": "HDD%d" % (i + 1), "ok": False})
    du = psutil.disk_usage("/")
    disks.append({"n": "SD", "ok": True, "u": du.used, "t": du.total})
    io = psutil.net_io_counters()
    now = time.time()
    rx = tx = 0
    if _net_prev[0] is not None:
        dt = max(0.1, now - _net_prev[1])
        rx = int((io.bytes_recv - _net_prev[0].bytes_recv) / dt)
        tx = int((io.bytes_sent - _net_prev[0].bytes_sent) / dt)
    _net_prev[0], _net_prev[1] = io, now
    return {"t": "stat", "cpu": round(psutil.cpu_percent(), 1), "ram_u": vm.total - vm.available, "ram_t": vm.total,
            "temp": cpu_temp(), "up": int(now - psutil.boot_time()), "disks": disks,
            "ssid": wifi["ssid"], "rssi": wifi["signal"],     # rssi is the nmcli signal in %, not dBm
            "ip": primary_ip(), "rx": rx, "tx": tx, "clock": time.strftime("%H:%M")}


def size_to_bytes(s):
    m = re.match(r"([\d.]+)\s*([kKMGT]?i?B)", s.strip())
    if not m:
        return 0
    mult = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4,
            "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
    return int(float(m.group(1)) * mult.get(m.group(2), 1))


def containers():
    """All containers, running first, at most MAX_CTRS. Returns (list, "") or (None, error)."""
    rc, out, err = sh(["docker", "ps", "-a", "--format", "{{json .}}"], 15)
    if rc != 0:
        return None, err or "docker ps failed"
    lst = {}
    for line in out.splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        name = d.get("Names", "")
        lst[name] = {"name": name, "image": d.get("Image", "")[:48], "state": d.get("State", ""),
                     "status": d.get("Status", "")[:40], "cpu": 0.0, "mu": 0, "ml": 0}
    rc, out, _ = sh(["docker", "stats", "--no-stream", "--format", "{{json .}}"], 25)
    for line in out.splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        c = lst.get(d.get("Name"))
        if not c:
            continue
        try:
            c["cpu"] = round(float(d.get("CPUPerc", "0").rstrip("%") or 0), 1)
        except ValueError:
            pass
        used, _, limit = d.get("MemUsage", "").partition("/")
        c["mu"], c["ml"] = size_to_bytes(used), size_to_bytes(limit)
    order = {"running": 0, "paused": 1, "restarting": 2}
    return sorted(lst.values(), key=lambda c: (order.get(c["state"], 3), c["name"].lower()))[:MAX_CTRS], ""


def wifi_scan():
    cmd = ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
    rc, out, err = sh(cmd, 30)
    if rc != 0:
        raise RuntimeError(err or "Wi-Fi scan failed")
    nets = {}
    for f in map(nm_fields, out.splitlines()):
        if len(f) < 4 or not f[1]:                # hidden networks have no name
            continue
        ssid, sig, cur = f[1], int(f[2]) if f[2].isdigit() else 0, f[0] == "*"
        if ssid not in nets or sig > nets[ssid]["sig"] or cur:
            nets[ssid] = {"ssid": ssid[:32], "sig": sig, "sec": (f[3] or "open")[:16],
                          "cur": cur or nets.get(ssid, {}).get("cur", False)}
    return sorted(nets.values(), key=lambda n: (not n["cur"], -n["sig"]))[:MAX_NETS]


def wifi_profiles():
    """UUIDs of the saved Wi-Fi profiles, or None if nmcli fails."""
    rc, out, _ = sh(["nmcli", "-t", "-f", "UUID,TYPE", "con", "show"], 8)
    if rc != 0:
        return None
    return {f[0] for f in map(nm_fields, out.splitlines()) if len(f) == 2 and f[1] == "802-11-wireless"}


def wifi_connect(ssid, psk):
    """Join a network. If it does not come up, delete the profile this attempt saved (nmcli keeps it, wrong password
    and all) and bring the previous Wi-Fi connection back, so a typo never leaves the NAS offline."""
    rc, out, _ = sh(["nmcli", "-t", "-f", "NAME,UUID,TYPE", "con", "show", "--active"], 8)
    prev = next((f for f in map(nm_fields, out.splitlines()) if len(f) == 3 and f[2] == "802-11-wireless"), None)
    before = wifi_profiles()
    cmd = ["nmcli", "--wait", "45", "dev", "wifi", "connect", ssid] + (["password", psk] if psk else [])
    rc, out, err = sh(cmd, 60)
    if rc == 0 and wifi_now()["ssid"] == ssid:
        return True, f"Connected to {ssid}"
    after = wifi_profiles()
    if before is not None and after is not None:
        for uuid in sorted(after - before):
            sh(["nmcli", "con", "delete", "uuid", uuid], 15)
    reason = (err or out or "Could not connect").splitlines()[-1]
    reason = reason.removeprefix("Error: ").rstrip(".")[:90]
    if not prev:
        return False, reason
    rc, _, _ = sh(["nmcli", "--wait", "30", "con", "up", "uuid", prev[1]], 45)
    return False, f"{reason}. " + (f"Back on {prev[0]}" if rc == 0 else f"Could not go back to {prev[0]}")


def run_command(msg, state):
    """Run one command from the screen and return the message to send back."""
    op, cid = msg.get("op"), msg.get("id", 0)
    try:
        if op == "ctr":
            act, name = msg.get("act"), msg.get("name")
            if not (isinstance(act, str) and act in ACTIONS and isinstance(name, str) and CTR_NAME_RE.fullmatch(name)):
                raise ValueError("bad request")
            cmd = ["docker", "rm", "-f", name] if act == "rm" else ["docker", act, name]
            log("cmd", " ".join(cmd))
            rc, out, err = sh(cmd, 90)
            state["ctr_due"] = 0                  # refresh the list now, not in 3 s
            if rc != 0:
                log("cmd failed:", err or out)
            return {"t": "res", "id": cid, "ok": rc == 0,
                    "msg": f"{name}: {act} done" if rc == 0 else (err or out or f"{act} failed")[:120]}
        if op == "wifi_scan":
            return {"t": "wifi", "list": wifi_scan()}
        if op == "wifi_connect":
            ssid, psk = msg.get("ssid"), msg.get("psk") or ""
            if not isinstance(ssid, str) or not ssid or not isinstance(psk, str):
                raise ValueError("no network name")
            log("wifi connect", ssid)
            ok, text = wifi_connect(ssid[:32], psk[:63])
            log("wifi", text)
            state["wifi_due"] = 0
            return {"t": "res", "id": cid, "ok": ok, "msg": text}
        raise ValueError(f"unknown op {op}")
    except Exception as e:                        # the screen waits for an answer, so every failure gets one
        log("cmd failed:", op, e)
        return {"t": "res", "id": cid, "ok": False, "msg": str(e)[:120]}


def hello_msg():
    os_name = re.search(r'^PRETTY_NAME="?(.*?)"?$', read_text("/etc/os-release"), re.M)
    return {"t": "hello", "host": socket.gethostname(), "ip": primary_ip(), "agent": VERSION,
            "model": read_text("/proc/device-tree/model").strip("\x00 \n"), "os": os_name.group(1) if os_name else ""}


def find_panel():
    for path in sorted(glob.glob("/dev/serial/by-id/*")) + sorted(glob.glob("/dev/ttyACM*")):
        dev = os.path.realpath(path)
        if read_text(f"/sys/class/tty/{os.path.basename(dev)}/device/../idVendor").strip() == ESP_VID:
            return dev
    return None


class Link:
    def __init__(self, dev):
        self.s = serial.Serial(dev, 115200, timeout=0.2, write_timeout=2)
        self.s.dtr = True
        self.lock = threading.Lock()
        self.buf = b""

    def send(self, obj):
        data = (json.dumps(obj, separators=(",", ":")) + "\n").encode()
        with self.lock:
            self.s.write(data)

    def lines(self):
        self.buf += self.s.read(4096)
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            line = line.strip()
            if line.startswith(b"{"):
                yield line
        if len(self.buf) > 8192:                  # no newline in 8 KB: not the screen talking
            self.buf = b""


def worker(link, cmdq, state):
    """Commands run one at a time here, so a slow docker or nmcli call never holds up the stats."""
    while state["alive"]:
        try:
            msg = cmdq.get(timeout=0.5)
        except queue.Empty:
            continue
        reply = run_command(msg, state)
        try:
            link.send(reply)
        except (serial.SerialException, OSError):
            pass                                  # the main loop sees the closed port and ends the session


def collector(state):
    """docker stats takes about 2 s and nmcli can hang, so both run here, off the 1 s stat loop."""
    while state["alive"]:
        now = time.time()
        try:
            if now - state["wifi_due"] >= 10:
                state["wifi_due"] = now
                state["wifi"] = wifi_now()
            if now - state["ctr_due"] >= 3:
                state["ctr_due"] = now
                lst, err = containers()
                state["ctrs"] = {"t": "ctrs", "list": lst or [], "err": err[:80] if lst is None else ""}
                state["ctrs_ver"] += 1
        except Exception as e:                    # keep the thread alive; the next round tries again
            log("collector:", e)
        time.sleep(0.2)


def session(dev):
    log("panel found on", dev)
    link = Link(dev)
    hello = hello_msg()
    cmdq = queue.Queue()
    state = {"alive": True, "ctr_due": 0, "wifi_due": 0, "wifi": {"ssid": "", "signal": 0}, "ctrs": None,
             "ctrs_ver": 0}
    try:
        threading.Thread(target=worker, args=(link, cmdq, state), daemon=True).start()
        threading.Thread(target=collector, args=(state,), daemon=True).start()
        sent_ver, last_stat, last_hello, panel_fw = 0, 0, 0, None
        while True:
            now = time.time()
            for raw in link.lines():
                try:
                    msg = json.loads(raw)
                except ValueError:
                    continue
                if not isinstance(msg, dict):
                    continue
                if msg.get("t") == "hi":          # every 2 s; answering at once greets a screen that just restarted
                    last_hello = 0
                    if msg.get("fw") != panel_fw:
                        panel_fw = msg.get("fw")
                        log("panel firmware", panel_fw)
                elif msg.get("t") == "cmd":
                    cmdq.put(msg)
            if now - last_hello > 10:
                link.send(hello)
                last_hello = now
            if now - last_stat >= 1.0:
                link.send(stat_msg(state["wifi"]))
                last_stat = now
            if state["ctrs_ver"] != sent_ver:
                link.send(state["ctrs"])
                sent_ver = state["ctrs_ver"]
            time.sleep(0.05)
    except (serial.SerialException, OSError) as e:
        log("panel disconnected:", e)
    finally:
        state["alive"] = False
        link.s.close()


def main():
    log("ipnas-panel agent", VERSION, "waiting for the panel on USB")
    while True:
        dev = find_panel()
        if dev:
            try:
                session(dev)
            except Exception as e:
                log("session error:", e)
        time.sleep(2)


if __name__ == "__main__":
    main()
