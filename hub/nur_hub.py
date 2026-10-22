#!/usr/bin/env python3
"""Nur Hub: the small HTTP API on the NAS that the Nur app talks to.

Standard library only (psutil is used when it is installed, otherwise /proc is parsed).
Runs as root, either as the nur-hub Docker container or as a systemd service.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import http.client
import json
import logging
import os
import platform
import posixpath
import re
import secrets
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import psutil  # type: ignore
except ImportError:
    psutil = None

VERSION = "1.1.3"
USER_AGENT = "nur-hub/" + VERSION
MAX_BODY = 1 << 20  # 1 MB for API requests
MAX_PROXY_BODY = 32 << 20  # chat requests with images can be larger
OUT_CAP = 64 * 1024  # per output stream of /exec
RAM_OVERHEAD = 0.9e9  # context, KV cache and llama.cpp itself on top of the model file
DISK_MARGIN = 0.5e9  # left free after a model download
PAIR_TTL = 300
PAIR_MAX_PENDING = 5
HF = "https://huggingface.co"

LLAMA_IMAGE = "ghcr.io/ggml-org/llama.cpp:server"
OLLAMA_IMAGE = "ollama/ollama"
CONTAINER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}/[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$")
OLLAMA_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,199}$")
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "trailers", "transfer-encoding", "upgrade",
}

log = logging.getLogger("nur-hub")
CFG: argparse.Namespace = argparse.Namespace()
POOL = ThreadPoolExecutor(max_workers=8, thread_name_prefix="probe")


class ApiError(Exception):
    def __init__(self, status: int, message: str, **extra):
        super().__init__(message)
        self.status = status
        self.payload = {"error": message, **extra}


class BodyTooLarge(Exception):
    pass


class JobCancelled(Exception):
    pass


# Container mode (Docker / CasaOS): NUR_HUB_CONTAINER=1 with pid: host, network_mode: host and privileged: true.
# Host files are read through /proc/1/root and every command runs in the host's namespaces with nsenter,
# so docker, vcgencmd, nmcli, smartctl and df behave the same as in the systemd install.
HOST_MODE = os.environ.get("NUR_HUB_CONTAINER", "") == "1"
HOST_ROOT = "/proc/1/root"
NSENTER = ["/usr/bin/nsenter", "-t", "1", "-m", "-u", "-i", "-n", "-p", "--"]
_HOST_BINS = ("/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin")
# Paths the hub owns inside the container (its bind mounts): these are never redirected to the host view.
_OWN_PREFIXES = ("/var/lib/nur-hub", "/app", "/DATA", "/tmp")


def host_path(path: str) -> str:
    """Host view of an absolute path in container mode (unchanged otherwise)."""
    if (not HOST_MODE or not path.startswith("/") or path.startswith(("/proc/", "/sys/", "/dev/"))
            or any(path == p or path.startswith(p + "/") for p in _OWN_PREFIXES)):
        return path
    return HOST_ROOT + path


def read_text(path: str, default=None):
    if HOST_MODE:
        if path == "/proc/mounts":
            path = "/proc/1/mounts"  # the host's mount table, not the container's
        else:
            path = host_path(path)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return default


if HOST_MODE:
    _RealPopen = subprocess.Popen

    def _host_which(cmd, mode=os.F_OK | os.X_OK, path=None):
        if os.sep in cmd:
            return cmd if os.access(HOST_ROOT + cmd, mode) else None
        for d in _HOST_BINS:
            if os.access(HOST_ROOT + d + "/" + cmd, mode):
                return d + "/" + cmd
        return None

    class _HostPopen(_RealPopen):
        def __init__(self, args, *a, **k):
            if isinstance(args, (list, tuple)) and args and args[0] != NSENTER[0]:
                args = NSENTER + list(args)
            super().__init__(args, *a, **k)

    shutil.which = _host_which
    subprocess.Popen = _HostPopen  # subprocess.run/check_output use it too


def atomic_write_json(path: str, obj, mode: int = 0o600) -> None:
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    tmp = "%s.tmp.%d.%d" % (path, os.getpid(), threading.get_ident())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def gb(n: float) -> str:
    return "%.1f" % (n / 1e9)


def _error_body(e: urllib.error.HTTPError) -> bytes:
    with e:
        try:
            return e.read()
        except (OSError, http.client.HTTPException):
            return b""


def http_get(url: str, timeout: float = 5.0, headers: dict | None = None):
    """GET a URL. Returns (status, bytes). Raises URLError/OSError when unreachable."""
    h = {"User-Agent": USER_AGENT}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, _error_body(e)


def http_json(url: str, timeout: float = 5.0, method: str = "GET", payload=None):
    """Request JSON. Returns (status, parsed or None). Raises on connection errors."""
    data = None
    h = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            status, body = r.status, r.read()
    except urllib.error.HTTPError as e:
        status, body = e.code, _error_body(e)
    try:
        return status, json.loads(body.decode("utf-8", "replace")) if body else None
    except ValueError:
        return status, None


def searx_json_ok() -> bool:
    """SearXNG answers and allows format=json. Without q no search engine is asked; 403 means json is not enabled."""
    try:
        status, _ = http_get(CFG.searx_url.rstrip("/") + "/search?format=json", timeout=2.0)
    except Exception:
        return False
    return status != 403


def reachable(url: str, timeout: float = 2.0) -> bool:
    """True if anything answers HTTP at this URL (any status code)."""
    try:
        http_get(url, timeout=timeout)
        return True
    except Exception:
        return False


def _win_mem():
    if os.name != "nt":
        return None
    try:
        import ctypes

        class MEMSTAT(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]

        m = MEMSTAT()
        m.dwLength = ctypes.sizeof(MEMSTAT)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
            return int(m.ullTotalPhys), int(m.ullAvailPhys)
    except Exception:
        pass
    return None


def _meminfo() -> dict:
    out = {}
    txt = read_text("/proc/meminfo", "") or ""
    for line in txt.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].endswith(":"):
            try:
                out[parts[0][:-1]] = int(parts[1]) * 1024
            except ValueError:
                pass
    return out


def ram_used_total():
    if psutil is not None:
        try:
            vm = psutil.virtual_memory()
            return int(vm.total - vm.available), int(vm.total)
        except Exception:
            pass
    mi = _meminfo()
    if mi.get("MemTotal"):
        total = mi["MemTotal"]
        avail = mi.get("MemAvailable", mi.get("MemFree", 0) + mi.get("Cached", 0))
        return int(total - avail), int(total)
    w = _win_mem()
    if w:
        return w[0] - w[1], w[0]
    return 0, 0


def total_ram() -> int:
    return ram_used_total()[1]


def _proc_stat_cpu():
    txt = read_text("/proc/stat")
    if not txt:
        return None
    first = txt.splitlines()[0].split()
    if not first or first[0] != "cpu":
        return None
    vals = [int(v) for v in first[1:9]]
    while len(vals) < 8:
        vals.append(0)
    idle = vals[3] + vals[4]
    return sum(vals), idle


def cpu_percent() -> float:
    if psutil is not None:
        try:
            return float(psutil.cpu_percent(interval=0.2))
        except Exception:
            pass
    a = _proc_stat_cpu()
    if not a:
        return 0.0
    time.sleep(0.2)
    b = _proc_stat_cpu()
    if not b:
        return 0.0
    dt = b[0] - a[0]
    if dt <= 0:
        return 0.0
    return round(max(0.0, min(100.0, 100.0 * (1.0 - (b[1] - a[1]) / dt))), 1)


def cpu_temp():
    t = read_text("/sys/class/thermal/thermal_zone0/temp")
    if t:
        try:
            return round(int(t.strip()) / 1000.0, 1)
        except ValueError:
            pass
    vc = shutil.which("vcgencmd")
    if vc:
        try:
            p = subprocess.run([vc, "measure_temp"], capture_output=True, timeout=3,
                               stdin=subprocess.DEVNULL)
            m = re.search(r"temp=([0-9.]+)", p.stdout.decode("utf-8", "replace"))
            if m:
                return float(m.group(1))
        except Exception:
            pass
    return None


def uptime_seconds() -> int:
    t = read_text("/proc/uptime")
    if t:
        try:
            return int(float(t.split()[0]))
        except (ValueError, IndexError):
            pass
    if psutil is not None:
        try:
            return int(time.time() - psutil.boot_time())
        except Exception:
            pass
    if os.name == "nt":
        try:
            import ctypes
            f = ctypes.windll.kernel32.GetTickCount64
            f.restype = ctypes.c_ulonglong
            return int(f() // 1000)
        except Exception:
            pass
    return 0


SKIP_FS = {
    "tmpfs", "devtmpfs", "overlay", "squashfs", "proc", "sysfs", "cgroup", "cgroup2",
    "devpts", "mqueue", "debugfs", "tracefs", "securityfs", "pstore", "bpf", "configfs",
    "fusectl", "hugetlbfs", "autofs", "binfmt_misc", "nsfs", "ramfs", "efivarfs",
    "rpc_pipefs", "nfsd", "zram", "iso9660",
}


def _unescape_mount(s: str) -> str:
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), s)


def disks() -> list:
    entries = []
    mounts = read_text("/proc/mounts")
    if mounts:
        for line in mounts.splitlines():
            parts = line.split()
            if len(parts) >= 3:
                entries.append((_unescape_mount(parts[0]), _unescape_mount(parts[1]), parts[2]))
    elif psutil is not None:
        try:
            for p in psutil.disk_partitions(all=False):
                entries.append((p.device, p.mountpoint, p.fstype))
        except Exception:
            pass
    elif os.name == "nt" and hasattr(os, "listdrives"):
        try:
            for d in os.listdrives():
                entries.append((d, d, "ntfs"))
        except Exception:
            pass

    best: dict[str, str] = {}
    order: list[str] = []
    for dev, mnt, fs in entries:
        if fs in SKIP_FS:
            continue
        if os.name != "nt":
            if not dev.startswith("/dev/"):
                continue
            base = os.path.basename(dev)
            if base.startswith(("loop", "zram", "ram")):
                continue
        if dev not in best:
            best[dev] = mnt
            order.append(dev)
        elif len(mnt) < len(best[dev]):
            best[dev] = mnt
    out = []
    for dev in order:
        mnt = best[dev]
        try:
            u = shutil.disk_usage(host_path(mnt) if HOST_MODE else mnt)
        except OSError:
            continue
        name = os.path.basename(dev.rstrip("/\\")) or dev.rstrip("/\\") or dev
        out.append({"name": name, "mount": mnt, "used": int(u.used), "total": int(u.total)})
    return out


def net_totals() -> dict:
    rx = tx = 0
    if psutil is not None:
        try:
            for nic, c in psutil.net_io_counters(pernic=True).items():
                if nic == "lo" or nic.lower().startswith("loopback"):
                    continue
                rx += int(c.bytes_recv)
                tx += int(c.bytes_sent)
            return {"rx": rx, "tx": tx}
        except Exception:
            rx = tx = 0
    txt = read_text("/proc/net/dev")
    if txt:
        for line in txt.splitlines()[2:]:
            if ":" not in line:
                continue
            name, rest = line.split(":", 1)
            if name.strip() == "lo":
                continue
            f = rest.split()
            if len(f) >= 9:
                try:
                    rx += int(f[0])
                    tx += int(f[8])
                except ValueError:
                    pass
    return {"rx": rx, "tx": tx}


def _run_quiet(argv, timeout=3) -> str:
    try:
        p = subprocess.run(argv, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
        if p.returncode == 0:
            return p.stdout.decode("utf-8", "replace").strip()
    except Exception:
        pass
    return ""


def wifi_info():
    txt = read_text("/proc/net/wireless")
    if not txt:
        return None
    iface = level = quality = None
    for line in txt.splitlines()[2:]:
        parts = line.split()
        if len(parts) >= 4 and parts[0].endswith(":"):
            iface = parts[0][:-1]
            try:
                quality = float(parts[2].rstrip("."))
                level = float(parts[3].rstrip("."))
            except ValueError:
                pass
            break
    if iface is None:
        return None
    if level is not None and level > 0:
        level -= 256  # some drivers report unsigned dBm
    ssid = ""
    iw = shutil.which("iwgetid")
    if iw:
        ssid = _run_quiet([iw, "-r"])
    if not ssid and shutil.which("iw"):
        m = re.search(r"SSID:\s*(.+)", _run_quiet([shutil.which("iw"), "dev", iface, "link"]))
        if m:
            ssid = m.group(1).strip()
    if not ssid and shutil.which("nmcli"):
        for line in _run_quiet([shutil.which("nmcli"), "-t", "-f", "active,ssid", "dev", "wifi"]).splitlines():
            if line.startswith("yes:"):
                ssid = line[4:]
                break
    return {
        "ssid": ssid or None,
        "signal": int(level) if level is not None else None,
        "quality": int(round(min(100.0, quality / 70.0 * 100.0))) if quality is not None else None,
    }


def device_model() -> str:
    raw = None
    try:
        with open("/proc/device-tree/model", "rb") as f:
            raw = f.read()
    except OSError:
        pass
    if raw:
        s = raw.replace(b"\x00", b"").decode("utf-8", "replace").strip()
        if s:
            return s
    return platform.machine() or "unknown"


def os_name() -> str:
    txt = read_text("/etc/os-release")
    if txt:
        for line in txt.splitlines():
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ("%s %s" % (platform.system(), platform.release())).strip() or "unknown"


def stop_process(p, kill: bool = False) -> None:
    # Children are started in their own session so the whole group can be stopped: in container mode the
    # child is nsenter, which forks the real command and does not pass signals on to it.
    try:
        if os.name == "nt":
            if kill:
                p.kill()
            else:
                p.terminate()
        else:
            os.killpg(p.pid, signal.SIGKILL if kill else signal.SIGTERM)
    except OSError:
        pass


def run_capped(argv, timeout: float, cap: int = OUT_CAP, merge: bool = False, env=None):
    """Run a command without a shell. Returns (exit_code, stdout, stderr, timed_out)."""
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=(subprocess.STDOUT if merge else subprocess.PIPE),
                         env=env, start_new_session=(os.name != "nt"))
    bufs = [bytearray(), bytearray()]
    trunc = [False, False]

    def pump(stream, i):
        try:
            with stream:
                while True:
                    chunk = stream.read1(65536)
                    if not chunk:
                        break
                    room = cap - len(bufs[i])
                    if room > 0:
                        bufs[i] += chunk[:room]
                    if len(chunk) > max(room, 0):
                        trunc[i] = True
        except (OSError, ValueError):
            pass

    threads = [threading.Thread(target=pump, args=(p.stdout, 0), daemon=True)]
    if not merge:
        threads.append(threading.Thread(target=pump, args=(p.stderr, 1), daemon=True))
    for t in threads:
        t.start()
    timed_out = False
    try:
        p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        stop_process(p, kill=True)
        p.wait()
    end = time.monotonic() + 2.0
    for t in threads:  # grandchildren may still hold the pipes open; do not wait forever
        t.join(max(0.0, end - time.monotonic()))

    def dec(i):
        s = bytes(bufs[i]).decode("utf-8", "replace")
        if trunc[i]:
            s += "\n[output truncated]"
        return s

    return p.returncode, dec(0), ("" if merge else dec(1)), timed_out


class DeviceStore:
    def __init__(self, path: str):
        self.path = path
        self.lock = threading.Lock()
        self.load_error = None
        self.devices = self._load()

    def _load(self) -> list:
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            return []
        except (OSError, ValueError) as e:
            self.load_error = str(e) or e.__class__.__name__
        else:
            if isinstance(data, list):
                return [d for d in data if isinstance(d, dict) and d.get("token_sha256") and d.get("id")]
            self.load_error = "not a JSON list"
        # Fail closed: with an unreadable file the next device must not become the owner.
        log.error("Could not read %s (%s). Pairing is locked until the file is fixed or deleted and the hub restarted",
                  self.path, self.load_error)
        return []

    def _save(self):
        atomic_write_json(self.path, self.devices, 0o600)

    def add(self, name: str):
        token = secrets.token_urlsafe(32)
        now = int(time.time())
        dev = {
            "id": secrets.token_hex(8),
            "name": name,
            "token_sha256": hashlib.sha256(token.encode()).hexdigest(),
            "created": now,
            "last_seen": now,
        }
        with self.lock:
            self.devices.append(dev)
            self._save()
        return token, dev["id"]

    def verify(self, token: str):
        if not token:
            return None
        h = hashlib.sha256(token.encode()).hexdigest()
        found = None
        with self.lock:
            for d in self.devices:
                if hmac.compare_digest(str(d.get("token_sha256", "")), h):
                    found = d
            if found is not None:
                now = int(time.time())
                if now - int(found.get("last_seen") or 0) >= 60:
                    found["last_seen"] = now
                    try:
                        self._save()
                    except OSError as e:
                        log.warning("Could not update last_seen: %s", e)
        return found

    def public(self) -> list:
        with self.lock:
            return [{"id": d["id"], "name": d.get("name", ""), "created": d.get("created"),
                     "last_seen": d.get("last_seen")} for d in self.devices]

    def remove(self, dev_id: str) -> bool:
        with self.lock:
            before = len(self.devices)
            self.devices = [d for d in self.devices if d.get("id") != dev_id]
            if len(self.devices) == before:
                return False
            self._save()
            return True

    def count(self) -> int:
        with self.lock:
            return len(self.devices)


class Pairing:
    """The first device to ask becomes the owner. Later devices wait until a paired device approves them in the app."""

    def __init__(self, devices: DeviceStore):
        self.devices = devices
        self.lock = threading.Lock()
        self.requests = {}  # request id: {id, name, created, status, token?, device_id?}

    def _gc(self):
        now = time.time()
        for rid in [k for k, r in self.requests.items() if now - r["created"] > PAIR_TTL]:
            del self.requests[rid]

    def request(self, device_name: str) -> dict:
        with self.lock:
            if self.devices.count() == 0:
                if self.devices.load_error:
                    raise ApiError(503, "Pairing is locked: devices.json on the NAS could not be read. "
                                        "Fix or delete it, then restart Nur Hub")
                token, dev_id = self.devices.add(device_name)
                log.warning("First device paired as owner: %s (%s)", dev_id, device_name)
                return {"status": "approved", "token": token, "device_id": dev_id}
            self._gc()
            if sum(1 for r in self.requests.values() if r["status"] == "pending") >= PAIR_MAX_PENDING:
                raise ApiError(429, "Too many devices are waiting for approval. Try again in a few minutes")
            rid = secrets.token_urlsafe(16)
            self.requests[rid] = {"id": rid, "name": device_name, "created": time.time(), "status": "pending"}
        log.warning("Device '%s' asks to connect; approve it in the Nur app on a paired device", device_name)
        return {"status": "pending", "request_id": rid, "expires_in": PAIR_TTL}

    def status(self, rid: str) -> dict:
        with self.lock:
            self._gc()
            r = self.requests.get(rid)
            if r is None:
                return {"status": "expired"}
            if r["status"] == "approved":
                out = {"status": "approved", "token": r.pop("token"), "device_id": r["device_id"]}
                del self.requests[rid]  # the token is handed out exactly once
                return out
            if r["status"] == "denied":
                del self.requests[rid]
                return {"status": "denied"}
            return {"status": "pending", "expires_in": int(PAIR_TTL - (time.time() - r["created"]))}

    def pending(self) -> list:
        with self.lock:
            self._gc()
            return [{"id": r["id"], "device_name": r["name"], "created": int(r["created"])}
                    for r in self.requests.values() if r["status"] == "pending"]

    def decide(self, rid: str, approve: bool, by: str) -> dict:
        with self.lock:
            self._gc()
            r = self.requests.get(rid)
            if r is None or r["status"] != "pending":
                raise ApiError(404, "This request has expired or was already answered")
            if approve:
                token, dev_id = self.devices.add(r["name"])
                # a fresh TTL, so a request approved just before it expires can still collect its token
                r.update(status="approved", token=token, device_id=dev_id, created=time.time())
                log.warning("Device '%s' approved by %s", r["name"], by)
            else:
                r["status"] = "denied"
                log.warning("Device '%s' denied by %s", r["name"], by)
        return {"ok": True}


class Job:
    def __init__(self, kind: str, title: str, key=None):
        self.id = secrets.token_hex(8)
        self.kind = kind
        self.title = title
        self.key = key
        self.state = "queued"
        self.progress = 0.0
        self.bytes = 0
        self.total = 0
        self.error = None
        self.cancel = threading.Event()
        self.proc = None
        self.created = time.time()

    def to_dict(self) -> dict:
        return {
            "id": self.id, "kind": self.kind, "state": self.state,
            "progress": round(max(0.0, min(1.0, self.progress)), 4),
            "bytes": int(self.bytes), "total": int(self.total),
            "error": self.error, "title": self.title,
        }

    def check(self):
        if self.cancel.is_set():
            raise JobCancelled()


class JobManager:
    KEEP = 50

    def __init__(self):
        self.lock = threading.Lock()
        self.jobs: dict[str, Job] = {}
        self.active: dict = {}

    def submit(self, kind: str, title: str, fn, key=None) -> Job:
        with self.lock:
            if key is not None and key in self.active:
                return self.active[key]
            job = Job(kind, title, key)
            self.jobs[job.id] = job
            if key is not None:
                self.active[key] = job
            self._prune()
        threading.Thread(target=self._run, args=(job, fn), daemon=True,
                         name="job-" + job.id).start()
        return job

    def _prune(self):
        if len(self.jobs) <= self.KEEP:
            return
        for jid in list(self.jobs):
            if len(self.jobs) <= self.KEEP:
                break
            if self.jobs[jid].state in ("done", "error", "cancelled"):
                del self.jobs[jid]

    def _run(self, job: Job, fn):
        job.state = "running"
        try:
            fn(job)
            job.check()
            job.progress = 1.0
            job.state = "done"
        except JobCancelled:
            job.state = "cancelled"
        except Exception as e:
            if job.cancel.is_set():
                job.state = "cancelled"
            else:
                job.state = "error"
                job.error = str(e) or e.__class__.__name__
                log.error("Job %s (%s) failed: %s", job.id, job.title, job.error)
        finally:
            job.proc = None
            with self.lock:
                if job.key is not None and self.active.get(job.key) is job:
                    del self.active[job.key]

    def get(self, jid: str):
        with self.lock:
            return self.jobs.get(jid)

    def list(self) -> list:
        with self.lock:
            jobs = list(self.jobs.values())
        jobs.sort(key=lambda j: j.created, reverse=True)
        return [j.to_dict() for j in jobs[: self.KEEP]]

    def cancel(self, jid: str):
        job = self.get(jid)
        if job is None:
            return None
        if job.state not in ("queued", "running"):
            return False
        job.cancel.set()
        p = job.proc
        if p is not None:
            stop_process(p)
        return True


def docker_bin() -> str:
    b = shutil.which("docker")
    if not b:
        raise ApiError(503, "Docker is not installed")
    return b


def docker(args, timeout=30):
    b = docker_bin()
    try:
        p = subprocess.run([b] + list(args), capture_output=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise ApiError(504, "Docker did not answer in time")
    except OSError:
        raise ApiError(503, "Docker is not installed")
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def docker_fail(err: str, fallback: str) -> ApiError:
    e = (err or "").strip()
    low = e.lower()
    if "permission denied" in low and "docker" in low:
        return ApiError(503, "Nur Hub has no access to Docker. It has to run as root")
    if any(k in low for k in ("cannot connect to the docker daemon", "error during connect",
                              "failed to connect to the docker api", "daemon is running",
                              "docker daemon is not running", "docker.sock")):
        return ApiError(503, "Docker is not running")
    if "no such container" in low:
        return ApiError(404, "That container does not exist")
    return ApiError(500, e.splitlines()[-1] if e else fallback)


def docker_ps_all() -> list:
    rc, out, err = docker(["ps", "-a", "--format", "{{json .}}"])
    if rc != 0:
        raise docker_fail(err, "Could not list containers")
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows


_UNITS = {
    "": 1, "b": 1, "k": 1e3, "kb": 1e3, "kib": 1024, "m": 1e6, "mb": 1e6, "mib": 1024 ** 2,
    "g": 1e9, "gb": 1e9, "gib": 1024 ** 3, "t": 1e12, "tb": 1e12, "tib": 1024 ** 4,
}


def parse_size(s: str) -> int:
    m = re.match(r"^\s*([0-9]*\.?[0-9]+)\s*([A-Za-z]*)\s*$", s or "")
    if not m:
        return 0
    return int(float(m.group(1)) * _UNITS.get(m.group(2).lower(), 1))


def parse_percent(s: str) -> float:
    try:
        return float((s or "").strip().rstrip("%"))
    except ValueError:
        return 0.0


def container_name(row: dict) -> str:
    return (row.get("Names") or "").split(",")[0]


# Safe-mode /exec: a fixed list of read-only commands, checked argument by argument and run without a shell.
SAFE_META = set(";|&$`><\n\r")
PROC_FILES = {
    "/proc/cpuinfo", "/proc/meminfo", "/proc/loadavg", "/proc/uptime", "/proc/version",
    "/proc/mounts", "/proc/diskstats", "/proc/net/dev",
}
VCGEN_CMDS = {"measure_temp", "get_throttled", "measure_clock", "measure_volts", "get_mem"}
FREE_FLAGS = {"-b", "-k", "-m", "-g", "-h", "-t", "-w", "-l", "-v", "--bytes", "--kilo", "--mega",
              "--giga", "--tera", "--kibi", "--mebi", "--gibi", "--tebi", "--human", "--si",
              "--total", "--wide", "--lohi", "--committed", "--help", "--version"}
HOSTNAME_FLAGS = {"-I", "-i", "-f", "-s", "-d", "-A", "--all-ip-addresses", "--ip-address",
                  "--fqdn", "--long", "--short", "--domain", "--all-fqdns"}
UNAME_LONG = {"--all", "--kernel-name", "--nodename", "--kernel-release", "--kernel-version",
              "--machine", "--processor", "--hardware-platform", "--operating-system"}
IP_FLAGS = {"-br", "-brief", "-4", "-6", "-c", "-color", "-s", "-d", "-j", "-json", "-p", "-o"}
IP_OBJECTS = {"addr", "a", "address", "route", "r", "ro", "link", "l"}
IP_SHOW = {"show", "list", "ls", "s", "sh"}
# ps options that take the next argument as a value (format list, pid list, user name), not as more options
PS_VALUE_LONG = {"--sort", "--format", "--pid", "--ppid", "--quick-pid", "--sid", "--tty", "--user", "--User",
                 "--group", "--Group", "--cols", "--columns", "--lines", "--rows", "--width"}
PS_VALUE_SHORT = set("CGgoOpqstUu")  # last letter of the cluster: -o pid,user  -eo pid,comm  -u root
PS_VALUE_BSD = set("oOpqtUk")  # ps axo pid,comm
SAFE_WORD = re.compile(r"^[A-Za-z0-9_,=:/.+%-]+$")


class NotAllowed(Exception):
    pass


def safe_argv(command: str) -> list:
    if any(c in SAFE_META for c in command):
        raise NotAllowed("shell characters like ; | & $ ` > < are blocked")
    try:
        argv = shlex.split(command)
    except ValueError:
        raise NotAllowed("the command could not be parsed")
    if not argv:
        raise NotAllowed("the command is empty")
    cmd, args = argv[0], argv[1:]
    if any(".." in a for a in args):
        raise NotAllowed("'..' is not allowed")

    def deny():
        raise NotAllowed(command.strip())

    if cmd == "free":
        if not all(a in FREE_FLAGS or re.fullmatch(r"-[bkmghtwlv]+", a) for a in args):
            deny()
    elif cmd == "df":
        if not all(SAFE_WORD.match(a) for a in args):
            deny()
    elif cmd == "uptime":
        if not all(a in ("-p", "--pretty", "-s", "--since") for a in args):
            deny()
    elif cmd == "vcgencmd":
        if not (1 <= len(args) <= 2 and args[0] in VCGEN_CMDS):
            deny()
        if len(args) == 2 and not re.fullmatch(r"[a-z0-9_]{1,16}", args[1]):
            deny()
    elif cmd == "lsblk":
        if not all(SAFE_WORD.match(a) for a in args):
            deny()
    elif cmd == "ps":
        value_next = False
        for a in args:
            if not SAFE_WORD.match(a):
                deny()
            if value_next:
                value_next = False
            elif a.startswith("--"):
                value_next = a in PS_VALUE_LONG
            elif a.startswith("-"):
                value_next = a[-1] in PS_VALUE_SHORT
            elif "e" in a:
                # BSD "e" (ps auxe, ps eww) prints the environment of every process: other apps' passwords
                deny()
            else:
                value_next = a[-1] in PS_VALUE_BSD
    elif cmd == "top":
        if args != ["-bn1"]:
            deny()
    elif cmd == "docker":
        if not args:
            deny()
        sub, rest = args[0], args[1:]
        if sub == "ps":
            if not all(a in ("-a", "--all", "-q", "--quiet", "-s", "--size", "-l", "--latest",
                             "--no-trunc") for a in rest):
                deny()
        elif sub == "stats":
            if "--no-stream" not in rest:
                deny()
            if not all(a in ("--no-stream", "--no-trunc", "-a", "--all") or CONTAINER_RE.match(a)
                       for a in rest):
                deny()
        elif sub == "logs":
            names = []
            i = 0
            while i < len(rest):
                a = rest[i]
                if a in ("--tail", "-n") and i + 1 < len(rest) and re.fullmatch(r"\d{1,6}", rest[i + 1]):
                    i += 2
                    continue
                if re.fullmatch(r"--tail=\d{1,6}", a) or a in ("-t", "--timestamps"):
                    i += 1
                    continue
                if a.startswith("-") or not CONTAINER_RE.match(a):
                    deny()
                names.append(a)
                i += 1
            if len(names) != 1:
                deny()
        else:
            deny()
    elif cmd == "cat":
        if len(args) != 1 or args[0] not in PROC_FILES:
            deny()
    elif cmd == "ip":
        i = 0
        while i < len(args) and args[i] in IP_FLAGS:
            i += 1
        if i >= len(args) or args[i] not in IP_OBJECTS:
            deny()
        i += 1
        while i < len(args):
            a = args[i]
            if a in IP_SHOW:
                i += 1
            elif a == "dev" and i + 1 < len(args) and re.fullmatch(r"[A-Za-z0-9_.:@-]{1,32}", args[i + 1]):
                i += 2
            else:
                deny()
    elif cmd == "hostname":
        if not all(a in HOSTNAME_FLAGS for a in args):
            deny()
    elif cmd == "uname":
        if not all(a in UNAME_LONG or re.fullmatch(r"-[asnrvmpio]+", a) for a in args):
            deny()
    elif cmd == "systemctl":
        if not args or args[0] != "status":
            deny()
        units = []
        i = 1
        while i < len(args):
            a = args[i]
            if a in ("--no-pager", "-l", "--full"):
                i += 1
            elif a in ("-n", "--lines") and i + 1 < len(args) and args[i + 1].isdigit():
                i += 2
            elif re.fullmatch(r"--lines=\d+", a):
                i += 1
            elif re.fullmatch(r"[A-Za-z0-9@_.:\\-]{1,128}", a) and not a.startswith("-"):
                units.append(a)
                i += 1
            else:
                deny()
        if len(units) != 1:
            deny()
        if "--no-pager" not in argv:
            argv.append("--no-pager")
    elif cmd == "smartctl":
        if len(args) != 2 or args[0] != "-H" or not re.fullmatch(r"/dev/(sd[a-z]{1,2}|nvme\d+n\d+)", args[1]):
            deny()
    else:
        deny()
    return argv


# The local AI runtimes, each one a Docker container the hub can install, start and stop.
RUNTIMES = {
    "llamacpp": {
        "title": "llama.cpp",
        "container": "nur-llamacpp",
        "prefixes": ("ghcr.io/ggml-org/llama.cpp", "ghcr.io/ggerganov/llama.cpp"),
        "url": "/llm/v1",
        "image": LLAMA_IMAGE,
    },
    "ollama": {
        "title": "Ollama",
        "container": "nur-ollama",
        "prefixes": ("ollama/ollama", "docker.io/ollama/ollama"),
        "url": "/ollama",
        "image": OLLAMA_IMAGE,
    },
}


def runtime_health_url(rt: str) -> str:
    if rt == "llamacpp":
        return CFG.llama_url.rstrip("/") + "/health"
    return CFG.ollama_url.rstrip("/") + "/api/version"


def find_runtime_container(rt: str, rows: list):
    spec = RUNTIMES[rt]
    for r in rows:
        if container_name(r) == spec["container"]:
            return r
    for r in rows:
        if (r.get("Image") or "").startswith(spec["prefixes"]):
            return r
    return None


def llama_run_args(ctx: int) -> list:
    return ["run", "-d", "--name", "nur-llamacpp", "--restart", "unless-stopped",
            "-p", "127.0.0.1:8088:8080", "-v", "%s:/models" % CFG.models_dir,
            LLAMA_IMAGE, "--host", "0.0.0.0", "--port", "8080", "--models-dir", "/models",
            "-c", str(ctx), "-t", "2", "--jinja"]


def ollama_run_args() -> list:
    return ["run", "-d", "--name", "nur-ollama", "--restart", "unless-stopped",
            "-p", "127.0.0.1:11434:11434", "-v", "%s:/root/.ollama" % CFG.ollama_dir,
            "-e", "OLLAMA_KEEP_ALIVE=5m", "-e", "OLLAMA_NUM_PARALLEL=1", OLLAMA_IMAGE]


def job_docker(job: Job, args, timeout=3600, progress_from=0.0, progress_to=1.0) -> str:
    """Run a docker command inside a job, cancellable, with rough pull progress."""
    b = docker_bin()
    p = subprocess.Popen([b] + list(args), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, start_new_session=(os.name != "nt"))
    job.proc = p
    layers: dict[str, str] = {}
    tail: list[str] = []
    deadline = time.time() + timeout
    try:
        for raw in iter(p.stdout.readline, b""):
            line = raw.decode("utf-8", "replace").strip()
            if line:
                tail.append(line)
                del tail[:-20]
            m = re.match(r"^([0-9a-f]{12}): (.+)$", line)
            if m:
                layers[m.group(1)] = m.group(2)
                done = sum(1 for v in layers.values()
                           if v.startswith(("Pull complete", "Already exists")))
                job.progress = progress_from + (progress_to - progress_from) * done / max(1, len(layers))
            if job.cancel.is_set() or time.time() > deadline:
                stop_process(p)
                break
        try:
            p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            stop_process(p, kill=True)
            p.wait()
    finally:
        job.proc = None
        p.stdout.close()
    job.check()
    if p.returncode != 0:
        raise RuntimeError(tail[-1] if tail else "docker %s failed" % args[0])
    job.progress = progress_to
    return "\n".join(tail)


def install_runtime(job: Job, rt: str):
    spec = RUNTIMES[rt]
    existing = find_runtime_container(rt, docker_ps_all())
    if existing:
        if existing.get("State") != "running":
            job_docker(job, ["start", container_name(existing)], timeout=120)
        return
    if rt == "llamacpp":
        os.makedirs(CFG.models_dir, exist_ok=True)
    else:
        os.makedirs(CFG.ollama_dir, exist_ok=True)
    job_docker(job, ["pull", spec["image"]], progress_from=0.02, progress_to=0.9)
    if rt == "llamacpp":
        ctx = 4096 if total_ram() <= 4.5e9 else 8192
        args = llama_run_args(ctx)
    else:
        args = ollama_run_args()
    job_docker(job, args, timeout=300, progress_from=0.9, progress_to=1.0)


def load_catalog() -> list:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "catalog.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        log.error("Could not read catalog.json: %s", e)
        return []
    return [e for e in data if isinstance(e, dict)] if isinstance(data, list) else []


def llama_loaded_ids() -> set:
    loaded = set()
    try:
        status, data = http_json(CFG.llama_url.rstrip("/") + "/models", timeout=3)
    except Exception:
        return loaded
    if status != 200 or not isinstance(data, dict):
        return loaded
    for e in data.get("data") or []:
        if not isinstance(e, dict):
            continue
        st = e.get("status")
        val = st.get("value") if isinstance(st, dict) else st
        if val == "loaded":
            mid = str(e.get("id") or "")
            loaded.add(mid)
            loaded.add(os.path.basename(mid))
            if mid.endswith(".gguf"):
                loaded.add(os.path.basename(mid)[:-5])
    return loaded


def local_llama_models() -> list:
    try:
        names = sorted(os.listdir(CFG.models_dir))
    except OSError:
        return []
    loaded = POOL.submit(llama_loaded_ids)
    out = []
    for fn in names:
        low = fn.lower()
        if not low.endswith(".gguf") or low.startswith("mmproj"):
            continue
        p = os.path.join(CFG.models_dir, fn)
        if not os.path.isfile(p):
            continue
        out.append({"runtime": "llamacpp", "id": fn[:-5], "file": fn,
                    "size": os.path.getsize(p), "loaded": False})
    try:
        ids = loaded.result(timeout=5)
    except Exception:
        ids = set()
    for m in out:
        m["loaded"] = m["id"] in ids or m["file"] in ids
    return out


def local_ollama_models() -> list:
    base = CFG.ollama_url.rstrip("/")
    try:
        status, tags = http_json(base + "/api/tags", timeout=3)
    except Exception:
        return []
    if status != 200 or not isinstance(tags, dict):
        return []
    loaded = set()
    try:
        s2, ps = http_json(base + "/api/ps", timeout=3)
        if s2 == 200 and isinstance(ps, dict):
            for m in ps.get("models") or []:
                loaded.add(m.get("name") or m.get("model"))
    except Exception:
        pass
    out = []
    for m in tags.get("models") or []:
        name = m.get("name") or m.get("model") or ""
        out.append({"runtime": "ollama", "id": name, "file": m.get("model") or name,
                    "size": int(m.get("size") or 0), "loaded": name in loaded})
    return out


def hf_json(url: str, timeout: float = 15.0):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        e.close()
        if e.code in (401, 403, 404):
            raise ApiError(404, "Not found on Hugging Face (the repo may be private or gated)")
        raise ApiError(502, "Hugging Face answered with error %d" % e.code)
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise ApiError(502, "Could not reach Hugging Face: %s" % getattr(e, "reason", e))


def hf_gguf_files(repo: str) -> list:
    url = "%s/api/models/%s/tree/main?recursive=true" % (HF, urllib.parse.quote(repo, safe="/"))
    data = hf_json(url)
    out = []
    for e in data if isinstance(data, list) else []:
        if not isinstance(e, dict) or e.get("type") != "file":
            continue
        path = e.get("path") or ""
        if not path.lower().endswith(".gguf"):
            continue
        size = (e.get("lfs") or {}).get("size") or e.get("size") or 0
        out.append({"file": path, "size": int(size)})
    return out


def hf_file_size(repo: str, file: str) -> int:
    for f in hf_gguf_files(repo):
        if f["file"] == file:
            return f["size"]
    # Fall back to a HEAD request on the download URL.
    url = "%s/%s/resolve/main/%s" % (HF, urllib.parse.quote(repo, safe="/"), urllib.parse.quote(file, safe="/"))
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            n = r.headers.get("X-Linked-Size") or r.headers.get("Content-Length")
            if n and n.isdigit():
                return int(n)
    except urllib.error.HTTPError as e:
        e.close()
        if e.code in (401, 403, 404):
            raise ApiError(404, "That file was not found in %s" % repo)
        raise ApiError(502, "Hugging Face answered with error %d" % e.code)
    except (urllib.error.URLError, OSError) as e:
        raise ApiError(502, "Could not reach Hugging Face: %s" % getattr(e, "reason", e))
    raise ApiError(404, "That file was not found in %s" % repo)


def download_llama(job: Job, repo: str, file: str, size: int):
    base = posixpath.basename(file)
    final = os.path.join(CFG.models_dir, base)
    part = final + ".part"
    url = "%s/%s/resolve/main/%s" % (HF, urllib.parse.quote(repo, safe="/"), urllib.parse.quote(file, safe="/"))
    job.total = size
    if os.path.isfile(final) and size and os.path.getsize(final) == size:
        job.bytes = size
        return
    have = os.path.getsize(part) if os.path.isfile(part) else 0
    if size and have > size:
        os.unlink(part)
        have = 0
    if not (size and have == size):
        headers = {"User-Agent": USER_AGENT}
        if have:
            headers["Range"] = "bytes=%d-" % have
        try:
            resp = urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60)
        except urllib.error.HTTPError as e:
            e.close()
            if e.code == 416 and have:
                resp = None
            else:
                raise RuntimeError("Hugging Face answered with error %d" % e.code)
        except (urllib.error.URLError, OSError) as e:
            raise RuntimeError("Could not reach Hugging Face: %s" % getattr(e, "reason", e))
        if resp is not None:
            with resp:
                if have and resp.status == 206:
                    mode = "ab"
                else:
                    mode = "wb"
                    have = 0
                if not size:
                    cl = resp.headers.get("Content-Length")
                    if cl and cl.isdigit():
                        size = have + int(cl)
                        job.total = size
                job.bytes = have
                with open(part, mode) as f:
                    while True:
                        job.check()
                        chunk = resp.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                        job.bytes += len(chunk)
                        if job.total:
                            job.progress = job.bytes / job.total
        job.check()
    got = os.path.getsize(part)
    if size and got != size:
        raise RuntimeError("Download stopped early (%d of %d bytes). Start it again to resume" % (got, size))
    os.replace(part, final)
    job.bytes = got
    reload_llama_models()


def reload_llama_models() -> None:
    """llama.cpp in router mode scans --models-dir only at start: restart its container so a new file is usable at once."""
    try:
        row = find_runtime_container("llamacpp", docker_ps_all())
        if row is None:
            return
        name = container_name(row)
        rc, _, err = docker(["restart", name], timeout=60)
        if rc == 0:
            log.info("Restarted %s so llama.cpp sees the new model", name)
        else:
            log.warning("Could not restart %s: %s", name, err.strip()[:200])
    except Exception as e:  # never fail a finished download because of this
        log.warning("llama.cpp reload after download failed: %s", e)


def download_ollama(job: Job, name: str):
    u = urllib.parse.urlsplit(CFG.ollama_url)
    cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
    conn = cls(u.hostname or "127.0.0.1", u.port, timeout=600)
    body = json.dumps({"name": name, "model": name, "stream": True}).encode()
    try:
        conn.request("POST", (u.path.rstrip("/") or "") + "/api/pull", body=body,
                     headers={"Content-Type": "application/json", "User-Agent": USER_AGENT})
        resp = conn.getresponse()
        if resp.status != 200:
            txt = resp.read().decode("utf-8", "replace")
            try:
                txt = json.loads(txt).get("error") or txt
            except ValueError:
                pass
            raise RuntimeError("Ollama: %s" % txt.strip()[:300])
        layers: dict[str, tuple] = {}
        while True:
            job.check()
            line = resp.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("error"):
                raise RuntimeError("Ollama: %s" % ev["error"])
            if ev.get("digest") and ev.get("total"):
                layers[ev["digest"]] = (int(ev.get("completed") or 0), int(ev["total"]))
                done = sum(c for c, _ in layers.values())
                tot = sum(t for _, t in layers.values())
                job.bytes, job.total = done, tot
                job.progress = done / tot if tot else 0.0
            if ev.get("status") == "success":
                return
        raise RuntimeError("Ollama stopped the download before it finished")
    except (OSError, http.client.HTTPException) as e:
        job.check()
        raise RuntimeError("Lost connection to Ollama: %s" % e)
    finally:
        conn.close()


ROUTES: list = []


def route(methods: str, pattern: str, auth: bool = True):
    rx = re.compile("^" + pattern + "$")

    def deco(fn):
        ROUTES.append((set(methods.split(",")), rx, fn, auth))
        return fn

    return deco


def qparam(q: dict, name: str, default=None):
    v = q.get(name)
    return v[0] if v else default


def int_param(q: dict, name: str, default: int, lo: int, hi: int) -> int:
    try:
        v = int(qparam(q, name, default))
    except (TypeError, ValueError):
        v = default
    return max(lo, min(hi, v))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "NurHub/" + VERSION
    sys_version = ""
    timeout = 300  # idle keep-alive connections are closed after this

    def log_message(self, fmt, *args):  # _dispatch logs one line per request; the stock access log is debug only
        log.debug("%s - %s", self.address_string(), fmt % args)

    def send_response(self, code, message=None):
        self._status = code
        super().send_response(code, message)

    def read_body(self, limit: int = MAX_BODY) -> bytes:
        if self._body is not None:
            return self._body
        te = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in te:
            data = bytearray()
            while True:
                line = self.rfile.readline(65537)
                try:
                    size = int(line.split(b";")[0].strip(), 16)
                except ValueError:
                    self.close_connection = True
                    raise ApiError(400, "Bad chunked request body")
                if size == 0:
                    while True:
                        t = self.rfile.readline(65537)
                        if t in (b"\r\n", b"\n", b""):
                            break
                    break
                if len(data) + size > limit:
                    self.close_connection = True
                    raise BodyTooLarge()
                data += self.rfile.read(size)
                self.rfile.readline(65537)
            self._body = bytes(data)
        else:
            try:
                n = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                self.close_connection = True
                raise ApiError(400, "Bad Content-Length")
            if n < 0:
                self.close_connection = True
                raise ApiError(400, "Bad Content-Length")
            if n > limit:
                self.close_connection = True
                raise BodyTooLarge()
            self._body = self.rfile.read(n) if n else b""
        return self._body

    def json_body(self) -> dict:
        raw = self.read_body()
        if not raw.strip():
            return {}
        try:
            data = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ApiError(400, "The request body is not valid JSON")
        if not isinstance(data, dict):
            raise ApiError(400, "The request body must be a JSON object")
        return data

    def _drain(self):
        if self._body is None:
            try:
                self.read_body()
            except Exception:
                self.close_connection = True

    def send_json(self, status: int, obj):
        self._drain()
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def require_auth(self):
        h = self.headers.get("Authorization") or ""
        if not h[:7].lower() == "bearer ":
            raise ApiError(401, "This device is not paired. Pair it first")
        self.device = DEVICES.verify(h[7:].strip())
        if self.device is None:
            raise ApiError(401, "This device is not paired or was removed. Pair it again")

    def _dispatch(self):
        t0 = time.monotonic()
        self._status = 0
        self._body = None
        split = urllib.parse.urlsplit(self.path)
        path = split.path or "/"
        try:
            if path in ("/llm", "/ollama") or path.startswith(("/llm/", "/ollama/")):
                self.require_auth()
                if path.startswith("/llm"):
                    self.proxy(CFG.llama_url, path[len("/llm"):] or "/", split.query)
                else:
                    self.proxy(CFG.ollama_url, path[len("/ollama"):] or "/", split.query)
                return
            if len(path) > 1:
                path = path.rstrip("/")
            self.q = urllib.parse.parse_qs(split.query)
            path_matched = False
            for methods, rx, fn, auth in ROUTES:
                m = rx.match(path)
                if not m:
                    continue
                path_matched = True
                if self.command not in methods:
                    continue
                if auth:
                    self.require_auth()
                args = [urllib.parse.unquote(g) for g in m.groups()]
                result = fn(self, *args)
                if isinstance(result, tuple):
                    self.send_json(result[0], result[1])
                else:
                    self.send_json(200, result)
                return
            if path_matched:
                raise ApiError(405, "Method not allowed")
            raise ApiError(404, "Not found")
        except ApiError as e:
            self.send_json(e.status, e.payload)
        except BodyTooLarge:
            self.close_connection = True
            self.send_json(413, {"error": "The request body is too large"})
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            self.close_connection = True
        except Exception as e:
            log.exception("Unhandled error on %s %s", self.command, path)
            if not self._status:
                self.close_connection = True
                try:
                    self.send_json(500, {"error": "Internal error: %s" % e})
                except Exception:
                    pass
            else:
                self.close_connection = True
        finally:
            log.info("%s %s %s %dms", self.command, path, self._status or "-",
                     int((time.monotonic() - t0) * 1000))

    do_GET = do_POST = do_DELETE = do_PUT = do_PATCH = do_HEAD = do_OPTIONS = _dispatch

    def proxy(self, base: str, upstream_path: str, query: str):
        u = urllib.parse.urlsplit(base)
        path = (u.path.rstrip("/") + upstream_path) or "/"
        if query:
            path += "?" + query
        body = self.read_body(MAX_PROXY_BODY)
        conn_tokens = {t.strip().lower() for t in (self.headers.get("Connection") or "").split(",")}
        headers = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in HOP_BY_HOP or lk in conn_tokens or lk in ("host", "authorization", "content-length"):
                continue
            headers[k] = v
        headers["Host"] = u.netloc
        send_body = None
        if body or self.command in ("POST", "PUT", "PATCH"):
            send_body = body
            headers["Content-Length"] = str(len(body))
        cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
        conn = cls(u.hostname or "127.0.0.1", u.port, timeout=600)
        try:
            try:
                conn.request(self.command, path, body=send_body, headers=headers)
                resp = conn.getresponse()
            except (OSError, http.client.HTTPException):
                raise ApiError(502, "The local AI runtime is not running")
            ctype = (resp.getheader("Content-Type") or "").lower()
            te = (resp.getheader("Transfer-Encoding") or "").lower()
            clen = resp.getheader("Content-Length")
            no_body = self.command == "HEAD" or resp.status in (204, 304) or resp.status < 200
            stream = "chunked" in te or "text/event-stream" in ctype or clen is None
            self.send_response(resp.status, resp.reason)
            up_conn = {t.strip().lower() for t in (resp.getheader("Connection") or "").split(",")}
            for k, v in resp.getheaders():
                lk = k.lower()
                if lk in HOP_BY_HOP or lk in up_conn or lk in ("content-length", "server", "date"):
                    continue
                self.send_header(k, v)
            if no_body:
                if self.command == "HEAD" and clen is not None:
                    self.send_header("Content-Length", clen)
                elif resp.status not in (204, 304):
                    self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if stream:
                self.send_header("Transfer-Encoding", "chunked")
                self.send_header("X-Accel-Buffering", "no")
                self.end_headers()
                self.wfile.flush()
                while True:
                    chunk = resp.read1(65536)
                    if not chunk:
                        break
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
            else:
                self.send_header("Content-Length", clen)
                self.end_headers()
                remaining = int(clen)
                while remaining > 0:
                    chunk = resp.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
                if remaining > 0:
                    self.close_connection = True
        except ApiError:
            raise
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            self.close_connection = True
        except (OSError, http.client.HTTPException) as e:
            # upstream died mid-response; we cannot send a clean error any more
            log.warning("Proxy stream aborted: %s", e)
            self.close_connection = True
        finally:
            conn.close()

    @route("GET", r"/api/v1/info", auth=False)
    def api_info(self):
        f_llama = POOL.submit(reachable, runtime_health_url("llamacpp"))
        f_ollama = POOL.submit(reachable, runtime_health_url("ollama"))
        f_searx = POOL.submit(searx_json_ok)
        return {
            "name": CFG.name,
            "version": VERSION,
            "model": device_model(),
            "os": os_name(),
            "paired_devices": DEVICES.count(),
            "llm": {"llamacpp": f_llama.result(), "ollama": f_ollama.result()},
            "searxng": f_searx.result(),
        }

    @route("POST", r"/api/v1/pair/request", auth=False)
    def api_pair_request(self):
        # Browsers send Origin with every POST and the app never does. Without this a web page open on the LAN
        # (cross-site POST or DNS rebinding) could take the owner slot of a hub that has no paired device yet.
        if self.headers.get("Origin") is not None:
            raise ApiError(403, "Pair from the Nur app, not from a browser")
        body = self.json_body()
        name = str(body.get("device_name") or "").strip()[:64] or "Phone"
        name = re.sub(r"[\x00-\x1f\x7f]", "", name) or "Phone"
        return PAIRING.request(name)

    @route("GET", r"/api/v1/pair/status/([A-Za-z0-9_-]+)", auth=False)
    def api_pair_status(self, rid):
        return PAIRING.status(rid)

    @route("GET", r"/api/v1/pair/pending")
    def api_pair_pending(self):
        return PAIRING.pending()

    @route("POST", r"/api/v1/pair/(approve|deny)/([A-Za-z0-9_-]+)")
    def api_pair_decide(self, action, rid):
        by = (getattr(self, "device", None) or {}).get("name", "a paired device")
        return PAIRING.decide(rid, action == "approve", by)

    @route("GET", r"/api/v1/devices")
    def api_devices(self):
        return DEVICES.public()

    @route("DELETE", r"/api/v1/devices/([^/]+)")
    def api_device_delete(self, dev_id):
        if not DEVICES.remove(dev_id):
            raise ApiError(404, "No paired device with that id")
        return {"ok": True}

    @route("GET", r"/api/v1/system")
    def api_system(self):
        f_cpu = POOL.submit(cpu_percent)
        f_wifi = POOL.submit(wifi_info)
        f_temp = POOL.submit(cpu_temp)
        used, total = ram_used_total()
        try:
            dl = disks()
        except Exception as e:
            log.warning("disk listing failed: %s", e)
            dl = []

        def safe(f, default):
            try:
                return f.result(timeout=10)
            except Exception:
                return default

        return {
            "cpu": float(safe(f_cpu, 0.0)),
            "ram_used": int(used),
            "ram_total": int(total),
            "temp": safe(f_temp, None),
            "uptime": uptime_seconds(),
            "disks": dl,
            "net": net_totals(),
            "wifi": safe(f_wifi, None),
        }

    @route("GET", r"/api/v1/docker/containers")
    def api_containers(self):
        rows = docker_ps_all()
        stats = {}
        if any(r.get("State") == "running" for r in rows):
            try:
                rc, out, _ = docker(["stats", "--no-stream", "--format", "{{json .}}"], timeout=30)
                if rc == 0:
                    for line in out.splitlines():
                        line = line.strip()
                        if line.startswith("{"):
                            try:
                                s = json.loads(line)
                            except ValueError:
                                continue
                            stats[s.get("Name") or ""] = s
            except ApiError:
                pass
        out = []
        for r in rows:
            name = container_name(r)
            s = stats.get(name) or {}
            mem = (s.get("MemUsage") or "").split("/")
            out.append({
                "name": name,
                "image": r.get("Image") or "",
                "state": r.get("State") or "",
                "status": r.get("Status") or "",
                "cpu": parse_percent(s.get("CPUPerc") or ""),
                "mem_used": parse_size(mem[0]) if mem and mem[0] else 0,
                "mem_limit": parse_size(mem[1]) if len(mem) > 1 else 0,
                "ports": r.get("Ports") or "",
            })
        return out

    @route("POST", r"/api/v1/docker/containers/([^/]+)/(start|stop|restart|pause|unpause|remove)")
    def api_container_action(self, name, action):
        if not CONTAINER_RE.match(name):
            raise ApiError(400, "That is not a valid container name")
        args = ["rm", "-f", name] if action == "remove" else [action, name]
        rc, out, err = docker(args, timeout=120)
        if rc != 0:
            e = docker_fail(err, "Docker could not %s %s" % (action, name))
            raise ApiError(e.status, e.payload["error"], ok=False, message=e.payload["error"])
        past = {"start": "started", "stop": "stopped", "restart": "restarted", "pause": "paused",
                "unpause": "resumed", "remove": "removed"}[action]
        log.info("Container %s %s", name, past)
        return {"ok": True, "message": "Container %s %s" % (name, past)}

    @route("GET", r"/api/v1/docker/containers/([^/]+)/logs")
    def api_container_logs(self, name):
        if not CONTAINER_RE.match(name):
            raise ApiError(400, "That is not a valid container name")
        tail = int_param(self.q, "tail", 100, 1, 2000)
        b = docker_bin()
        try:
            rc, out, _, timed_out = run_capped([b, "logs", "--tail", str(tail), name], timeout=30,
                                               cap=2 << 20, merge=True)
        except OSError:
            raise ApiError(503, "Docker is not installed")
        if rc != 0 and not timed_out:
            raise docker_fail(out, "Could not read the logs")
        return {"logs": out}

    @route("GET", r"/api/v1/search")
    def api_search(self):
        q = (qparam(self.q, "q") or "").strip()
        if not q:
            raise ApiError(400, "Missing search text (q)")
        limit = int_param(self.q, "limit", 5, 1, 50)
        url = "%s/search?%s" % (CFG.searx_url.rstrip("/"),
                                urllib.parse.urlencode({"q": q, "format": "json"}))
        try:
            status, raw = http_get(url, timeout=15, headers={"Accept": "application/json"})
        except Exception:
            raise ApiError(503, "SearXNG is not reachable at %s" % CFG.searx_url)
        if status == 403:
            raise ApiError(503, "SearXNG refused JSON output. Add 'json' to search.formats in its settings.yml")
        if status != 200:
            raise ApiError(503, "SearXNG answered with error %d" % status)
        try:
            data = json.loads(raw.decode("utf-8", "replace"))
        except ValueError:
            raise ApiError(503, "SearXNG did not return JSON. Add 'json' to search.formats in its settings.yml")
        out = []
        for r in (data.get("results") if isinstance(data, dict) else None) or []:
            if not isinstance(r, dict):
                continue
            out.append({"title": r.get("title") or "", "url": r.get("url") or "",
                        "content": r.get("content") or ""})
            if len(out) >= limit:
                break
        return out

    @route("POST", r"/api/v1/exec")
    def api_exec(self):
        body = self.json_body()
        command = body.get("command")
        if not isinstance(command, str) or not command.strip():
            raise ApiError(400, "Missing command")
        if len(command) > 4096:
            raise ApiError(400, "The command is too long")
        try:
            timeout = float(body.get("timeout") or 15)
        except (TypeError, ValueError):
            timeout = 15.0
        timeout = max(1.0, min(120.0, timeout))
        mode = body.get("mode") or "safe"
        env = dict(os.environ)
        env.update({"SYSTEMD_PAGER": "cat", "SYSTEMD_COLORS": "0", "PAGER": "cat", "TERM": "dumb"})
        if mode == "safe":
            try:
                argv = safe_argv(command)
            except NotAllowed as e:
                raise ApiError(403, "Not allowed in safe mode: %s" % e)
            exe = shutil.which(argv[0])
            if not exe:
                return {"exit_code": 127, "stdout": "", "stderr": "Command not found: %s" % argv[0]}
            argv[0] = exe
        elif mode == "admin":
            if not CFG.allow_admin:
                raise ApiError(403, "Admin mode is turned off on this NAS")
            bash = shutil.which("bash")
            if not bash:
                raise ApiError(500, "bash is not available")
            argv = [bash, "-lc", command]
            log.warning("Admin exec (%d chars)", len(command))
        else:
            raise ApiError(400, "mode must be 'safe' or 'admin'")
        try:
            rc, out, err, timed_out = run_capped(argv, timeout=timeout, env=env)
        except OSError as e:
            return {"exit_code": 127, "stdout": "", "stderr": "Could not run the command: %s" % e}
        if timed_out:
            err = (err + "\n" if err else "") + "Timed out after %g s" % timeout
            rc = 124
        return {"exit_code": rc, "stdout": out, "stderr": err}

    @route("GET", r"/api/v1/runtimes")
    def api_runtimes(self):
        try:
            rows = docker_ps_all()
        except ApiError:
            rows = []
        probes = {rt: POOL.submit(reachable, runtime_health_url(rt)) for rt in RUNTIMES}
        out = []
        for rt, spec in RUNTIMES.items():
            c = find_runtime_container(rt, rows)
            alive = probes[rt].result()
            out.append({
                "id": rt,
                "installed": c is not None,
                "running": bool(c is not None and c.get("State") == "running" and alive),
                "url": spec["url"],
                "container": container_name(c) if c else None,
            })
        return out

    @route("POST", r"/api/v1/runtimes/([^/]+)/(install|start|stop)")
    def api_runtime_action(self, rt, action):
        if rt not in RUNTIMES:
            raise ApiError(404, "Unknown runtime. Use 'llamacpp' or 'ollama'")
        spec = RUNTIMES[rt]
        docker_bin()
        if action == "install":
            job = JOBS.submit("install", "Install %s" % spec["title"],
                              lambda j: install_runtime(j, rt), key=("install", rt))
            return {"ok": True, "message": "Installing %s in the background" % spec["title"],
                    "job_id": job.id}
        c = find_runtime_container(rt, docker_ps_all())
        if c is None:
            raise ApiError(404, "%s is not installed yet" % spec["title"])
        name = container_name(c)
        rc, out, err = docker([action, name], timeout=120)
        if rc != 0:
            e = docker_fail(err, "Docker could not %s %s" % (action, name))
            raise ApiError(e.status, e.payload["error"], ok=False, message=e.payload["error"])
        return {"ok": True, "message": "%s %s" % (spec["title"], "started" if action == "start" else "stopped")}

    @route("GET", r"/api/v1/models/local")
    def api_models_local(self):
        f_ollama = POOL.submit(local_ollama_models)
        out = local_llama_models()
        try:
            out += f_ollama.result(timeout=10)
        except Exception:
            pass
        return out

    @route("DELETE", r"/api/v1/models/local/(llamacpp|ollama)/(.+)")
    def api_model_delete(self, rt, mid):
        if rt == "llamacpp":
            if not mid or "/" in mid or "\\" in mid or ".." in mid or "\x00" in mid or mid.startswith("."):
                raise ApiError(400, "That is not a valid model id")
            fn = mid if mid.lower().endswith(".gguf") else mid + ".gguf"
            path = os.path.join(CFG.models_dir, fn)
            if not os.path.isfile(path):
                raise ApiError(404, "No model file named %s" % fn)
            try:
                os.unlink(path)
            except OSError as e:
                raise ApiError(500, "Could not delete %s: %s" % (fn, e))
            log.info("Deleted model file %s", fn)
            threading.Thread(target=reload_llama_models, daemon=True).start()
            return {"ok": True, "message": "Deleted %s" % fn}
        if not OLLAMA_NAME_RE.match(mid):
            raise ApiError(400, "That is not a valid model name")
        try:
            status, data = http_json(CFG.ollama_url.rstrip("/") + "/api/delete", timeout=30,
                                     method="DELETE", payload={"name": mid, "model": mid})
        except Exception:
            raise ApiError(503, "Ollama is not running")
        if status == 404:
            raise ApiError(404, "Ollama has no model named %s" % mid)
        if status != 200:
            msg = data.get("error") if isinstance(data, dict) else None
            raise ApiError(502, "Ollama could not delete it: %s" % (msg or status))
        return {"ok": True, "message": "Deleted %s" % mid}

    @route("GET", r"/api/v1/models/catalog")
    def api_catalog(self):
        ram = total_ram()
        out = []
        for e in load_catalog():
            e = dict(e)
            fn = posixpath.basename(str(e.get("file") or ""))
            e["installed"] = bool(fn) and os.path.isfile(os.path.join(CFG.models_dir, fn))
            e["fits"] = bool(ram) and int(e.get("size") or 0) + RAM_OVERHEAD <= ram
            out.append(e)
        return out

    @route("GET", r"/api/v1/models/hf/search")
    def api_hf_search(self):
        q = (qparam(self.q, "q") or "").strip()
        limit = int_param(self.q, "limit", 20, 1, 100)
        params = [("search", q), ("filter", "gguf"), ("sort", "downloads"), ("limit", str(limit)),
                  ("expand[]", "downloads"), ("expand[]", "likes"), ("expand[]", "lastModified")]
        data = hf_json("%s/api/models?%s" % (HF, urllib.parse.urlencode(params)))
        out = []
        for m in data if isinstance(data, list) else []:
            if not isinstance(m, dict):
                continue
            out.append({"repo": m.get("id") or m.get("modelId") or "",
                        "downloads": int(m.get("downloads") or 0),
                        "likes": int(m.get("likes") or 0),
                        "updated": m.get("lastModified") or m.get("createdAt")})
        return out

    @route("GET", r"/api/v1/models/hf/files")
    def api_hf_files(self):
        repo = (qparam(self.q, "repo") or "").strip()
        if not REPO_RE.match(repo):
            raise ApiError(400, "repo must look like owner/name")
        ram = total_ram()
        files = hf_gguf_files(repo)
        files.sort(key=lambda f: f["file"])
        return [{"file": f["file"], "size": f["size"],
                 "fits": bool(ram) and f["size"] + RAM_OVERHEAD <= ram} for f in files]

    @route("POST", r"/api/v1/models/download")
    def api_download(self):
        body = self.json_body()
        rt = body.get("runtime")
        if rt == "llamacpp":
            repo = str(body.get("repo") or "").strip()
            file = str(body.get("file") or "").strip()
            if not REPO_RE.match(repo):
                raise ApiError(400, "repo must look like owner/name")
            if (not file.lower().endswith(".gguf") or ".." in file or "\\" in file
                    or file.startswith("/") or "\x00" in file):
                raise ApiError(400, "file must be a .gguf file inside the repo")
            base = posixpath.basename(file)
            key = ("llamacpp", base)
            with JOBS.lock:
                running = JOBS.active.get(key)
            if running is not None:
                return {"job_id": running.id}
            size = hf_file_size(repo, file)
            ram = total_ram()
            if ram and size + RAM_OVERHEAD > ram:
                raise ApiError(400, "This model needs %s GB RAM but the NAS has %s GB"
                               % (gb(size + RAM_OVERHEAD), gb(ram)))
            try:
                os.makedirs(CFG.models_dir, exist_ok=True)
                free = shutil.disk_usage(CFG.models_dir).free
            except OSError as e:
                raise ApiError(500, "The models folder is not usable: %s" % e)
            part = os.path.join(CFG.models_dir, base + ".part")
            have = os.path.getsize(part) if os.path.isfile(part) else 0
            if free < size - have + DISK_MARGIN:
                raise ApiError(507, "Not enough free disk space: needs %s GB but only %s GB is free"
                               % (gb(size - have + DISK_MARGIN), gb(free)))
            job = JOBS.submit("download", base, lambda j: download_llama(j, repo, file, size), key=key)
            job.total = job.total or size
            return {"job_id": job.id}
        if rt == "ollama":
            name = str(body.get("name") or "").strip()
            if not OLLAMA_NAME_RE.match(name):
                raise ApiError(400, "name must be an Ollama model name like qwen3:4b")
            if not reachable(runtime_health_url("ollama"), timeout=3):
                raise ApiError(503, "Ollama is not running. Install or start it first")
            job = JOBS.submit("download", name, lambda j: download_ollama(j, name), key=("ollama", name))
            return {"job_id": job.id}
        raise ApiError(400, "runtime must be 'llamacpp' or 'ollama'")

    @route("GET", r"/api/v1/jobs")
    def api_jobs(self):
        return JOBS.list()

    @route("GET", r"/api/v1/jobs/([^/]+)")
    def api_job(self, jid):
        job = JOBS.get(jid)
        if job is None:
            raise ApiError(404, "No job with that id")
        return job.to_dict()

    @route("POST", r"/api/v1/jobs/([^/]+)/cancel")
    def api_job_cancel(self, jid):
        r = JOBS.cancel(jid)
        if r is None:
            raise ApiError(404, "No job with that id")
        return {"ok": bool(r)}

    @route("POST", r"/api/v1/agent")
    def api_agent(self):
        url = os.environ.get("NUR_HUB_AGENT_URL", "").strip()
        body = self.json_body()
        if not url:
            raise ApiError(501, "Agent mode is not set up on this NAS")
        msg = body.get("message")
        if not isinstance(msg, str) or not msg.strip():
            raise ApiError(400, "Missing message")
        try:
            status, data = http_json(url, timeout=300, method="POST", payload={"message": msg})
        except Exception:
            raise ApiError(502, "The agent is not reachable")
        if status != 200:
            err = data.get("error") if isinstance(data, dict) else None
            raise ApiError(502, "The agent answered with an error: %s" % (err or status))
        reply = None
        if isinstance(data, dict):
            for k in ("reply", "response", "message", "text", "output", "content"):
                if isinstance(data.get(k), str):
                    reply = data[k]
                    break
        elif isinstance(data, str):
            reply = data
        if reply is None:
            reply = json.dumps(data) if data is not None else ""
        return {"reply": reply}


class HubServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 64


def _env_bool(v, default: bool) -> bool:
    if v is None or str(v).strip() == "":
        return default
    return str(v).strip().lower() not in ("0", "false", "no", "off")


def parse_args(argv=None) -> argparse.Namespace:
    env = os.environ.get
    p = argparse.ArgumentParser(description="Nur Hub: the local API for the Nur app")
    p.add_argument("--host", default=env("NUR_HUB_HOST", "0.0.0.0"))
    p.add_argument("--port", type=int, default=int(env("NUR_HUB_PORT", "8770")))
    p.add_argument("--state-dir", default=env("NUR_HUB_STATE_DIR", "/var/lib/nur-hub"))
    p.add_argument("--models-dir", default=env("NUR_HUB_MODELS_DIR", "/DATA/AppData/llamacpp/models"))
    p.add_argument("--ollama-dir", default=env("NUR_HUB_OLLAMA_DIR", "/DATA/AppData/ollama"),
                   help="host folder mounted into the Ollama container")
    p.add_argument("--llama-url", default=env("NUR_HUB_LLAMA_URL", "http://127.0.0.1:8088"))
    p.add_argument("--ollama-url", default=env("NUR_HUB_OLLAMA_URL", "http://127.0.0.1:11434"))
    p.add_argument("--searx-url", default=env("NUR_HUB_SEARX_URL", "http://127.0.0.1:8888"))
    p.add_argument("--allow-admin", nargs="?", const="1", default=env("NUR_HUB_ALLOW_ADMIN"),
                   metavar="0|1", help="allow admin exec mode (default on)")
    p.add_argument("--no-allow-admin", dest="allow_admin", action="store_const", const="0")
    p.add_argument("--name", default=env("NUR_HUB_NAME") or socket.gethostname())
    p.add_argument("--log-level", default=env("NUR_HUB_LOG_LEVEL", "INFO"))
    a = p.parse_args(argv)
    a.allow_admin = _env_bool(a.allow_admin, True)
    return a


DEVICES: DeviceStore
PAIRING: Pairing
JOBS = JobManager()


def publish_avahi(port: int) -> None:
    """Container mode: announce _nurhub._tcp through the host's avahi-daemon so the app finds the NAS on Wi-Fi."""
    d = HOST_ROOT + "/etc/avahi/services"
    if not os.path.isdir(d):
        log.warning("avahi-daemon not found on the host: the app will find the NAS by scanning the network instead")
        return
    xml = """<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Nur Hub on %%h</name>
  <service>
    <type>_nurhub._tcp</type>
    <port>%d</port>
    <txt-record>version=1</txt-record>
  </service>
</service-group>
""" % port
    try:
        with open(d + "/nur-hub.service", "w", encoding="utf-8") as f:
            f.write(xml)
        log.info("Announced _nurhub._tcp on port %d through the host's avahi-daemon", port)
    except OSError as e:
        log.warning("Could not write the avahi service file: %s", e)


def main(argv=None):
    global CFG, DEVICES, PAIRING
    CFG = parse_args(argv)
    logging.basicConfig(stream=sys.stderr, level=getattr(logging, str(CFG.log_level).upper(), logging.INFO),
                        format="%(levelname)s %(message)s")
    try:
        os.makedirs(CFG.state_dir, mode=0o700, exist_ok=True)
        os.chmod(CFG.state_dir, 0o700)  # CasaOS creates the bind-mounted folder world-writable
    except OSError as e:
        log.error("Could not prepare %s: %s", CFG.state_dir, e)
    DEVICES = DeviceStore(os.path.join(CFG.state_dir, "devices.json"))
    if HOST_MODE:
        publish_avahi(CFG.port)
    PAIRING = Pairing(DEVICES)
    srv = HubServer((CFG.host, CFG.port), Handler)
    log.info("Nur Hub %s listening on %s:%d as '%s' (psutil: %s, admin exec: %s, paired devices: %d)",
             VERSION, CFG.host, CFG.port, CFG.name, "yes" if psutil else "no",
             "on" if CFG.allow_admin else "off", DEVICES.count())
    try:
        srv.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
