"""Tests for nur_hub.py, standard library only. From the repo root: python -m unittest discover -s hub/tests -v"""

import http.client
import json
import logging
import os
import re
import shutil
import socket
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

HUB_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HUB_DIR)

import nur_hub as hub  # noqa: E402

hub.log.setLevel(logging.CRITICAL)  # keep the test output readable; assertLogs still sees everything


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class SafeArgvTest(unittest.TestCase):
    ALLOWED = [
        "free -h", "free -m -w", "df -h", "df -h /DATA", "df --output=source,pcent", "uptime -p",
        "vcgencmd measure_temp", "vcgencmd measure_clock arm", "vcgencmd get_throttled", "lsblk -o NAME,SIZE",
        "ps aux", "ps -ef", "ps -e", "ps -eo pid,user,pmem,comm --sort=-pmem", "ps -o user,etime -p 1",
        "ps axo pid,comm", "ps --sort -rss -eo pid,rss", "top -bn1", "docker ps -a", "docker stats --no-stream",
        "docker stats --no-stream jellyfin", "docker logs --tail 50 jellyfin", "docker logs -n 20 -t searxng",
        "cat /proc/meminfo", "ip -br addr", "ip addr show dev eth0", "ip route", "hostname -I", "uname -a",
        "systemctl status ssh", "systemctl status --no-pager -n 20 ipnas-panel.service", "smartctl -H /dev/sda",
        "smartctl -H /dev/nvme0n1",
    ]
    BLOCKED = [
        "rm -rf /", "reboot", "free; reboot", "free && reboot", "free | sh", "df $(reboot)", "df `reboot`",
        "df > /etc/passwd", "free\nreboot", "cat /etc/shadow", "cat /proc/1/environ", "cat ../../etc/shadow",
        "df ../..", "docker run alpine", "docker rm -f jellyfin", "docker exec jellyfin sh", "docker",
        "docker logs a b", "docker logs --follow jellyfin", "docker stats jellyfin", "systemctl restart ssh",
        "systemctl status", "systemctl status a b", "smartctl -t long /dev/sda", "smartctl -H /etc/passwd",
        "ip link set eth0 down", "ip addr add 192.168.1.50/24 dev eth0", "ip", "hostname newname", "top",
        "uname --help-me", "vcgencmd set_config", "vcgencmd measure_clock ARM!", "ps auxe", "ps e", "ps eww",
        "ps -e e", "ps -o user e", "uptime --pretty now", "free --wrong", "lsblk 'a b'", "",
        "nc -l 4444", "bash -c id", "python3 -c 1", "sudo free",
    ]

    def test_allowed(self):
        for cmd in self.ALLOWED:
            with self.subTest(cmd=cmd):
                argv = hub.safe_argv(cmd)
                self.assertEqual(argv[0], cmd.split()[0])

    def test_blocked(self):
        for cmd in self.BLOCKED:
            with self.subTest(cmd=cmd):
                with self.assertRaises(hub.NotAllowed):
                    hub.safe_argv(cmd)

    def test_systemctl_gets_no_pager(self):
        self.assertEqual(hub.safe_argv("systemctl status ssh"), ["systemctl", "status", "ssh", "--no-pager"])
        self.assertEqual(hub.safe_argv("systemctl status --no-pager ssh").count("--no-pager"), 1)


class HelpersTest(unittest.TestCase):
    def test_parse_size(self):
        self.assertEqual(hub.parse_size("1.5GiB"), int(1.5 * 1024 ** 3))
        self.assertEqual(hub.parse_size("512MiB"), 512 * 1024 ** 2)
        self.assertEqual(hub.parse_size("2GB"), 2 * 10 ** 9)
        self.assertEqual(hub.parse_size("100kB"), 100000)
        self.assertEqual(hub.parse_size(" 7B "), 7)
        self.assertEqual(hub.parse_size(""), 0)
        self.assertEqual(hub.parse_size("n/a"), 0)

    def test_parse_percent_and_names(self):
        self.assertEqual(hub.parse_percent("12.5%"), 12.5)
        self.assertEqual(hub.parse_percent(""), 0.0)
        self.assertEqual(hub.parse_percent("--"), 0.0)
        self.assertEqual(hub.container_name({"Names": "jellyfin,alias"}), "jellyfin")
        self.assertEqual(hub.container_name({}), "")
        self.assertEqual(hub._unescape_mount("/mnt/my\\040disk"), "/mnt/my disk")

    def test_docker_errors(self):
        cases = [
            ("permission denied while trying to connect to the docker API at unix:///var/run/docker.sock", 503, "root"),
            ("Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?",
             503, "not running"),
            ("Error response from daemon: No such container: nope", 404, "does not exist"),
            ("line one\nError response from daemon: conflict", 500, "conflict"),
            ("", 500, "fallback"),
        ]
        for err, status, text in cases:
            with self.subTest(err=err[:30]):
                e = hub.docker_fail(err, "fallback")
                self.assertEqual(e.status, status)
                self.assertIn(text, e.payload["error"])

    def test_searx_needs_json(self):
        with mock.patch.object(hub, "CFG", hub.parse_args([])):
            for answer, want in (((403, b""), False), ((400, b"No query"), True), ((200, b"{}"), True)):
                with mock.patch.object(hub, "http_get", return_value=answer):
                    self.assertIs(hub.searx_json_ok(), want)
            with mock.patch.object(hub, "http_get", side_effect=OSError("refused")):
                self.assertFalse(hub.searx_json_ok())

    def test_int_param(self):
        q = {"tail": ["50"], "bad": ["x"], "big": ["99999"]}
        self.assertEqual(hub.int_param(q, "tail", 100, 1, 2000), 50)
        self.assertEqual(hub.int_param(q, "bad", 100, 1, 2000), 100)
        self.assertEqual(hub.int_param(q, "big", 100, 1, 2000), 2000)
        self.assertEqual(hub.int_param(q, "missing", 100, 1, 2000), 100)

    def test_name_patterns(self):
        self.assertTrue(hub.CONTAINER_RE.match("big-bear-nextcloud"))
        self.assertFalse(hub.CONTAINER_RE.match("-rf"))
        self.assertFalse(hub.CONTAINER_RE.match("a/b"))
        self.assertTrue(hub.REPO_RE.match("unsloth/gemma-3-4b-it-GGUF"))
        self.assertFalse(hub.REPO_RE.match("../etc"))
        self.assertFalse(hub.REPO_RE.match("a/b/c"))
        self.assertTrue(hub.OLLAMA_NAME_RE.match("qwen3:4b"))
        self.assertFalse(hub.OLLAMA_NAME_RE.match("qwen3 4b"))

    def test_host_path(self):
        with mock.patch.object(hub, "HOST_MODE", False):
            self.assertEqual(hub.host_path("/etc/os-release"), "/etc/os-release")
        with mock.patch.object(hub, "HOST_MODE", True):
            self.assertEqual(hub.host_path("/etc/os-release"), "/proc/1/root/etc/os-release")
            self.assertEqual(hub.host_path("/"), "/proc/1/root/")
            self.assertEqual(hub.host_path("/mnt/hdd1"), "/proc/1/root/mnt/hdd1")
            self.assertEqual(hub.host_path("/DATA"), "/DATA")
            self.assertEqual(hub.host_path("/DATA/AppData/x"), "/DATA/AppData/x")
            self.assertEqual(hub.host_path("/var/lib/nur-hub/devices.json"), "/var/lib/nur-hub/devices.json")
            self.assertEqual(hub.host_path("/proc/meminfo"), "/proc/meminfo")
            self.assertEqual(hub.host_path("relative"), "relative")
            # only whole path parts count as the hub's own folders
            self.assertEqual(hub.host_path("/DATA2"), "/proc/1/root/DATA2")
            self.assertEqual(hub.host_path("/tmpfs"), "/proc/1/root/tmpfs")
            self.assertEqual(hub.host_path("/apps/x"), "/proc/1/root/apps/x")

    def test_parse_args(self):
        with mock.patch.dict(os.environ, {"NUR_HUB_PORT": "9000", "NUR_HUB_ALLOW_ADMIN": "0",
                                          "NUR_HUB_NAME": "nas"}):
            a = hub.parse_args([])
            self.assertEqual((a.port, a.allow_admin, a.name), (9000, False, "nas"))
            a = hub.parse_args(["--port", "9100", "--allow-admin"])
            self.assertEqual((a.port, a.allow_admin), (9100, True))
        with mock.patch.dict(os.environ, {"NUR_HUB_ALLOW_ADMIN": ""}):
            self.assertTrue(hub.parse_args([]).allow_admin)
            self.assertFalse(hub.parse_args(["--no-allow-admin"]).allow_admin)
            self.assertFalse(hub.parse_args(["--allow-admin", "off"]).allow_admin)


class DeviceStoreTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "devices.json")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_tokens_are_stored_hashed(self):
        store = hub.DeviceStore(self.path)
        token, dev_id = store.add("Phone")
        with open(self.path, encoding="utf-8") as f:
            raw = f.read()
        self.assertNotIn(token, raw)
        self.assertIn(dev_id, raw)
        self.assertEqual(store.verify(token)["id"], dev_id)
        self.assertIsNone(store.verify(token + "x"))
        self.assertIsNone(store.verify(""))
        self.assertNotIn("token_sha256", json.dumps(store.public()))
        if os.name != "nt":
            self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)
        again = hub.DeviceStore(self.path)
        self.assertEqual(again.verify(token)["id"], dev_id)
        self.assertTrue(again.remove(dev_id))
        self.assertFalse(again.remove(dev_id))
        self.assertIsNone(hub.DeviceStore(self.path).verify(token))

    def test_missing_file_is_a_fresh_hub(self):
        store = hub.DeviceStore(self.path)
        self.assertIsNone(store.load_error)
        self.assertEqual(store.count(), 0)

    def test_broken_file_locks_pairing(self):
        for content in ("{not json", '{"a": 1}'):
            with self.subTest(content=content):
                with open(self.path, "w", encoding="utf-8") as f:
                    f.write(content)
                store = hub.DeviceStore(self.path)
                self.assertTrue(store.load_error)
                with self.assertRaises(hub.ApiError) as cm:
                    hub.Pairing(store).request("Attacker")
                self.assertEqual(cm.exception.status, 503)
                self.assertEqual(store.count(), 0)


class PairingTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.store = hub.DeviceStore(os.path.join(self.dir, "devices.json"))
        self.pairing = hub.Pairing(self.store)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_first_device_is_owner_then_approval(self):
        first = self.pairing.request("Owner")
        self.assertEqual(first["status"], "approved")
        self.assertTrue(self.store.verify(first["token"]))

        second = self.pairing.request("Second")
        self.assertEqual(second["status"], "pending")
        rid = second["request_id"]
        self.assertEqual(self.pairing.status(rid)["status"], "pending")
        self.assertEqual([p["device_name"] for p in self.pairing.pending()], ["Second"])
        self.assertEqual(self.pairing.decide(rid, True, "Owner"), {"ok": True})
        got = self.pairing.status(rid)
        self.assertEqual(got["status"], "approved")
        self.assertTrue(self.store.verify(got["token"]))
        self.assertEqual(self.pairing.status(rid), {"status": "expired"})  # the token is given out once
        with self.assertRaises(hub.ApiError):
            self.pairing.decide(rid, True, "Owner")

    def test_deny_and_expiry(self):
        self.pairing.request("Owner")
        rid = self.pairing.request("Stranger")["request_id"]
        self.pairing.decide(rid, False, "Owner")
        self.assertEqual(self.pairing.status(rid), {"status": "denied"})
        self.assertEqual(self.pairing.status(rid), {"status": "expired"})
        self.assertEqual(self.store.count(), 1)

        rid = self.pairing.request("Late")["request_id"]
        self.pairing.requests[rid]["created"] -= hub.PAIR_TTL + 1
        self.assertEqual(self.pairing.status(rid), {"status": "expired"})
        self.assertEqual(self.pairing.pending(), [])

    def test_approval_just_before_expiry_can_still_be_collected(self):
        self.pairing.request("Owner")
        rid = self.pairing.request("Slow")["request_id"]
        self.pairing.requests[rid]["created"] -= hub.PAIR_TTL - 1
        self.pairing.decide(rid, True, "Owner")
        time.sleep(1.2)
        self.assertEqual(self.pairing.status(rid)["status"], "approved")

    def test_pending_limit(self):
        self.pairing.request("Owner")
        for i in range(hub.PAIR_MAX_PENDING):
            self.pairing.request("Phone %d" % i)
        with self.assertRaises(hub.ApiError) as cm:
            self.pairing.request("One too many")
        self.assertEqual(cm.exception.status, 429)

    def test_only_one_owner_when_two_ask_at_once(self):
        n = hub.PAIR_MAX_PENDING + 1
        barrier = threading.Barrier(n)
        results = []

        def ask(i):
            barrier.wait()
            results.append(self.pairing.request("Phone %d" % i)["status"])

        threads = [threading.Thread(target=ask, args=(i,)) for i in range(n)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(sorted(results), ["approved"] + ["pending"] * (n - 1))
        self.assertEqual(self.store.count(), 1)


class CatalogTest(unittest.TestCase):
    def test_catalog_entries(self):
        cat = hub.load_catalog()
        self.assertGreater(len(cat), 0)
        ids = [e["id"] for e in cat]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(sum(1 for e in cat if e["recommended"]), 1)
        for e in cat:
            with self.subTest(id=e["id"]):
                self.assertTrue(hub.REPO_RE.match(e["repo"]))
                self.assertTrue(e["file"].endswith(".gguf"))
                self.assertNotIn("/", e["file"])
                self.assertEqual(e["id"] + ".gguf", e["file"])
                self.assertIsInstance(e["title"], str)
                self.assertIsInstance(e["note"], str)
                self.assertIsInstance(e["size"], int)
                self.assertGreaterEqual(e["ram_needed"], e["size"] + hub.RAM_OVERHEAD)
                self.assertIsInstance(e["tools"], bool)
                self.assertIsInstance(e["vision"], bool)
                self.assertTrue(e["langs"] and all(isinstance(x, str) for x in e["langs"]))

    def test_versions_match(self):
        with open(os.path.join(HUB_DIR, "Dockerfile"), encoding="utf-8") as f:
            label = re.search(r'image\.version="([^"]+)"', f.read()).group(1)
        self.assertEqual(label, hub.VERSION)


class JobManagerTest(unittest.TestCase):
    def wait_state(self, job, states, timeout=5.0):
        end = time.time() + timeout
        while job.state not in states and time.time() < end:
            time.sleep(0.01)
        return job.state

    def test_done_error_and_dedupe(self):
        jobs = hub.JobManager()
        gate = threading.Event()
        a = jobs.submit("download", "a", lambda j: gate.wait(5), key=("k", 1))
        self.assertIs(jobs.submit("download", "a", lambda j: None, key=("k", 1)), a)
        gate.set()
        self.assertEqual(self.wait_state(a, ("done",)), "done")
        self.assertEqual(a.to_dict()["progress"], 1.0)

        def boom(job):
            raise RuntimeError("disk full")

        b = jobs.submit("download", "b", boom)
        self.assertEqual(self.wait_state(b, ("error",)), "error")
        self.assertEqual(b.error, "disk full")
        self.assertEqual(jobs.get(b.id).id, b.id)
        self.assertIsNone(jobs.cancel("nope"))
        self.assertFalse(jobs.cancel(b.id))

    def test_cancel(self):
        jobs = hub.JobManager()

        def slow(job):
            while True:
                job.check()
                time.sleep(0.01)

        j = jobs.submit("download", "slow", slow)
        self.wait_state(j, ("running",))
        self.assertTrue(jobs.cancel(j.id))
        self.assertEqual(self.wait_state(j, ("cancelled",)), "cancelled")

    def test_prune_keeps_the_newest(self):
        jobs = hub.JobManager()
        made = [jobs.submit("x", str(i), lambda j: None) for i in range(jobs.KEEP + 10)]
        for j in made:
            self.wait_state(j, ("done",))
        jobs.submit("x", "last", lambda j: None)
        self.assertLessEqual(len(jobs.jobs), jobs.KEEP + 1)
        self.assertLessEqual(len(jobs.list()), jobs.KEEP)


class LlamaRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.now = 1000.0
        self.calls = []
        self.rec = hub.LlamaRecovery(restart=lambda: self.calls.append(self.now), clock=lambda: self.now)

    def trigger(self):
        state = self.rec.trigger()
        end = time.time() + 5
        while self.rec.running and time.time() < end:
            time.sleep(0.01)
        return state

    def test_backoff_and_limit(self):
        self.assertEqual(self.trigger(), "restarting")
        self.assertEqual(self.trigger(), "wait")
        for gap in (60, 120, 240, 480):
            self.now += gap - 1
            self.assertEqual(self.trigger(), "wait")
            self.now += 1
            self.assertEqual(self.trigger(), "restarting")
        self.assertEqual(len(self.calls), hub.LlamaRecovery.MAX_IN_ROW)
        self.now += 100000
        with self.assertLogs("nur-hub", level="ERROR") as logs:
            self.assertEqual(self.trigger(), "gave_up")
            self.assertEqual(self.trigger(), "gave_up")
        self.assertEqual(len(logs.output), 1)
        self.assertEqual(len(self.calls), hub.LlamaRecovery.MAX_IN_ROW)
        self.rec.reset()
        self.assertEqual(self.trigger(), "restarting")
        self.assertEqual(len(self.calls), hub.LlamaRecovery.MAX_IN_ROW + 1)

    def test_one_restart_at_a_time(self):
        gate = threading.Event()
        rec = hub.LlamaRecovery(restart=lambda: gate.wait(5), clock=lambda: self.now)
        self.assertEqual(rec.trigger(), "restarting")
        self.now += 100000
        self.assertEqual(rec.trigger(), "wait")
        gate.set()


class RunCappedTest(unittest.TestCase):
    def test_output_cap(self):
        rc, out, err, timed_out = hub.run_capped([sys.executable, "-c", "print('x' * 100000)"], timeout=30, cap=1000)
        self.assertEqual(rc, 0)
        self.assertFalse(timed_out)
        self.assertTrue(out.startswith("x" * 1000))
        self.assertTrue(out.endswith("[output truncated]"))

    def test_timeout(self):
        t0 = time.monotonic()
        rc, out, err, timed_out = hub.run_capped([sys.executable, "-c", "import time; time.sleep(30)"], timeout=1)
        self.assertTrue(timed_out)
        self.assertLess(time.monotonic() - t0, 10)

    @unittest.skipIf(os.name == "nt", "process groups are POSIX only")
    def test_timeout_also_stops_grandchildren(self):
        # The same shape as container mode: the direct child (nsenter there) forks the real command.
        script = ("import subprocess, sys, time\n"
                  "p = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                  "print(p.pid, flush=True)\n"
                  "time.sleep(60)\n")
        rc, out, err, timed_out = hub.run_capped([sys.executable, "-c", script], timeout=1.5)
        self.assertTrue(timed_out)
        pid = int(out.split()[0])
        end = time.time() + 5
        while time.time() < end:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            os.kill(pid, 9)
            self.fail("the grandchild survived the timeout")


class FakeUpstream(BaseHTTPRequestHandler):
    """Plays llama.cpp, SearXNG and Hugging Face for the HTTP tests."""

    seen_headers: dict = {}
    model_bytes = bytes(range(256)) * 40
    ignore_range = False
    child_dead = False  # llama.cpp router whose model process died

    def log_message(self, *args):
        pass

    def send_body(self, status, body, ctype="application/json", extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        FakeUpstream.seen_headers = dict(self.headers)
        path = self.path.split("?")[0]
        if path == "/health":
            return self.send_body(200, b'{"status": "ok"}')
        if path == "/models":
            return self.send_body(200, json.dumps({"data": [
                {"id": "loaded-model", "status": {"value": "loaded"}}]}).encode())
        if path == "/v1/models":
            return self.send_body(200, b'{"data": [{"id": "loaded-model"}]}')
        if path == "/search":
            results = [{"title": "Debian %d" % i, "url": "https://example.org/%d" % i, "content": "c"}
                       for i in range(10)] + ["junk"]
            return self.send_body(200, json.dumps({"results": results}).encode())
        if path == "/api/models/owner/name/tree/main":
            return self.send_body(200, json.dumps([
                {"type": "file", "path": "model.gguf", "size": 1, "lfs": {"size": len(self.model_bytes)}},
                {"type": "file", "path": "README.md", "size": 10}, {"type": "directory", "path": "x"},
                "junk"]).encode())
        if path == "/owner/name/resolve/main/model.gguf":
            data = self.model_bytes
            rng = self.headers.get("Range")
            if rng and not self.ignore_range:
                start = int(re.match(r"bytes=(\d+)-", rng).group(1))
                return self.send_body(206, data[start:], "application/octet-stream",
                                      {"Content-Range": "bytes %d-%d/%d" % (start, len(data) - 1, len(data))})
            return self.send_body(200, data, "application/octet-stream")
        if path == "/":
            return self.send_body(200, b"ok", "text/html")
        return self.send_body(404, b'{"error": "not found"}')

    def do_POST(self):
        FakeUpstream.seen_headers = dict(self.headers)
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/v1/chat/completions" and self.child_dead:
            return self.send_body(500, b'{"error": {"code": 500, "message": "Could not establish connection", '
                                       b'"type": "server_error"}}')
        if self.path == "/v1/other-error":
            return self.send_body(500, b'{"error": "boom"}')
        if self.path == "/v1/chat/completions":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for i in range(3):
                self.wfile.write(b"data: {\"n\": %d}\n\n" % i)
                self.wfile.flush()
                time.sleep(0.05)
            self.wfile.write(b"data: [DONE]\n\n")
            self.close_connection = True
            return
        self.send_body(200, json.dumps({"echo": len(body)}).encode())


class HttpTest(unittest.TestCase):
    """Starts the real server on 127.0.0.1 with temporary folders and a fake upstream."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.models = os.path.join(cls.tmp, "models")
        os.makedirs(cls.models)
        cls.upstream = ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstream)
        threading.Thread(target=cls.upstream.serve_forever, daemon=True).start()
        up = "http://127.0.0.1:%d" % cls.upstream.server_address[1]
        cls.hf_patch = mock.patch.object(hub, "HF", up)
        cls.hf_patch.start()
        hub.CFG = hub.parse_args([
            "--state-dir", os.path.join(cls.tmp, "state"), "--models-dir", cls.models,
            "--llama-url", up, "--ollama-url", "http://127.0.0.1:%d" % free_port(), "--searx-url", up,
            "--name", "test-hub", "--no-allow-admin"])
        os.makedirs(hub.CFG.state_dir)
        hub.DEVICES = hub.DeviceStore(os.path.join(hub.CFG.state_dir, "devices.json"))
        hub.PAIRING = hub.Pairing(hub.DEVICES)
        cls.server = hub.HubServer(("127.0.0.1", 0), hub.Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        status, _, body = cls.call("POST", "/api/v1/pair/request", {"device_name": "Test owner"})
        assert status == 200 and body["status"] == "approved", body
        cls.token = body["token"]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.upstream.shutdown()
        cls.upstream.server_close()
        cls.hf_patch.stop()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def call(cls, method, path, body=None, token=None, headers=None, raw=None):
        conn = http.client.HTTPConnection("127.0.0.1", cls.port, timeout=30)
        h = dict(headers or {})
        if token:
            h["Authorization"] = "Bearer " + token
        data = raw
        if body is not None:
            data = json.dumps(body).encode()
            h["Content-Type"] = "application/json"
        try:
            conn.request(method, path, body=data, headers=h)
            resp = conn.getresponse()
            payload = resp.read()
        finally:
            conn.close()
        ctype = resp.getheader("Content-Type") or ""
        parsed = json.loads(payload) if payload and "json" in ctype else payload
        return resp.status, resp, parsed

    def get(self, path, **kw):
        return self.call("GET", path, token=self.token, **kw)

    def test_info_is_public(self):
        status, _, info = self.call("GET", "/api/v1/info")
        self.assertEqual(status, 200)
        self.assertEqual(info["name"], "test-hub")
        self.assertEqual(info["version"], hub.VERSION)
        self.assertEqual(info["llm"], {"llamacpp": True, "ollama": False})
        self.assertTrue(info["searxng"])
        self.assertGreaterEqual(info["paired_devices"], 1)

    def test_auth_required(self):
        for path in ("/api/v1/system", "/api/v1/devices", "/api/v1/models/catalog", "/api/v1/jobs",
                     "/api/v1/pair/pending", "/llm/v1/models", "/ollama/api/tags"):
            with self.subTest(path=path):
                status, _, body = self.call("GET", path)
                self.assertEqual(status, 401)
                self.assertIn("error", body)
                self.assertEqual(self.call("GET", path, token="wrong")[0], 401)

    def test_unknown_path_and_method(self):
        self.assertEqual(self.get("/api/v1/nope")[0], 404)
        self.assertEqual(self.call("DELETE", "/api/v1/info")[0], 405)

    def test_pairing_over_http(self):
        status, _, req = self.call("POST", "/api/v1/pair/request", {"device_name": "Tablet\x07"})
        self.assertEqual((status, req["status"]), (200, "pending"))
        rid = req["request_id"]
        self.assertEqual(self.call("GET", "/api/v1/pair/status/" + rid)[2]["status"], "pending")
        pending = self.get("/api/v1/pair/pending")[2]
        self.assertIn({"id": rid, "device_name": "Tablet"},
                      [{k: p[k] for k in ("id", "device_name")} for p in pending])
        self.assertEqual(self.call("POST", "/api/v1/pair/approve/" + rid, token=self.token)[0], 200)
        with self.assertLogs("nur-hub", level="DEBUG") as logs:
            status, _, got = self.call("GET", "/api/v1/pair/status/" + rid)
            self.assertEqual(got["status"], "approved")
            self.assertEqual(self.call("GET", "/api/v1/system", token=got["token"])[0], 200)
        self.assertNotIn(got["token"], "\n".join(logs.output))
        self.assertEqual(self.call("GET", "/api/v1/pair/status/" + rid)[2], {"status": "expired"})
        devices = self.get("/api/v1/devices")[2]
        self.assertIn(got["device_id"], [d["id"] for d in devices])
        self.assertNotIn("token_sha256", json.dumps(devices))
        self.assertEqual(self.call("DELETE", "/api/v1/devices/" + got["device_id"], token=self.token)[0], 200)
        self.assertEqual(self.call("GET", "/api/v1/system", token=got["token"])[0], 401)
        self.assertEqual(self.call("DELETE", "/api/v1/devices/nope", token=self.token)[0], 404)

    def test_pairing_refuses_browsers(self):
        status, _, body = self.call("POST", "/api/v1/pair/request", {"device_name": "x"},
                                    headers={"Origin": "http://evil.example"})
        self.assertEqual(status, 403)

    def test_body_validation(self):
        self.assertEqual(self.call("POST", "/api/v1/exec", token=self.token, raw=b"{nope",
                                   headers={"Content-Type": "application/json"})[0], 400)
        self.assertEqual(self.call("POST", "/api/v1/exec", token=self.token, body=[1, 2])[0], 400)
        with socket.create_connection(("127.0.0.1", self.port), timeout=10) as s:
            s.sendall(b"POST /api/v1/exec HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer " + self.token.encode()
                      + b"\r\nContent-Length: 5000000\r\n\r\n")
            self.assertIn(b" 413 ", s.recv(4096))

    def test_chunked_body(self):
        body = json.dumps({"message": "hi"}).encode()
        chunked = b"%x\r\n%s\r\n0\r\n\r\n" % (len(body), body)
        status, _, res = self.call("POST", "/api/v1/agent", token=self.token, raw=chunked,
                                   headers={"Transfer-Encoding": "chunked", "Content-Type": "application/json"})
        self.assertEqual(status, 501)  # parsed fine; agent mode is simply not set up
        self.assertIn("Agent mode", res["error"])

    def test_exec_validation(self):
        cases = [({"command": "rm -rf /"}, 403), ({"command": "free", "mode": "admin"}, 403),
                 ({"command": "free", "mode": "root"}, 400), ({}, 400), ({"command": "x" * 5000}, 400)]
        for body, want in cases:
            with self.subTest(body=str(body)[:40]):
                self.assertEqual(self.call("POST", "/api/v1/exec", body, token=self.token)[0], want)
        status, _, res = self.call("POST", "/api/v1/exec", {"command": "uname -a"}, token=self.token)
        self.assertEqual(status, 200)
        if shutil.which("uname"):
            self.assertEqual(res["exit_code"], 0)
            self.assertTrue(res["stdout"].strip())
        else:
            self.assertEqual(res["exit_code"], 127)

    def test_docker_names_are_checked_before_docker_runs(self):
        with mock.patch.object(hub, "docker", side_effect=AssertionError("docker must not run")):
            for path in ("/api/v1/docker/containers/-rf/remove", "/api/v1/docker/containers/a%20b/stop"):
                self.assertEqual(self.call("POST", path, token=self.token)[0], 400)
            self.assertEqual(self.get("/api/v1/docker/containers/a%2Fb/logs")[0], 400)
        self.assertEqual(self.call("POST", "/api/v1/runtimes/nope/start", token=self.token)[0], 404)

    def test_model_delete_paths(self):
        keep = os.path.join(self.tmp, "keep.gguf")
        open(keep, "wb").close()
        with mock.patch.object(hub, "reload_llama_models") as reload:
            for mid in ("..%2Fkeep", "%2E%2E%2Fkeep", ".hidden", "a%5Cb", "sub%2Fx"):
                with self.subTest(mid=mid):
                    status = self.call("DELETE", "/api/v1/models/local/llamacpp/" + mid, token=self.token)[0]
                    self.assertEqual(status, 400)
            self.assertEqual(self.call("DELETE", "/api/v1/models/local/llamacpp/missing", token=self.token)[0], 404)
            path = os.path.join(self.models, "gone.gguf")
            open(path, "wb").close()
            self.assertEqual(self.call("DELETE", "/api/v1/models/local/llamacpp/gone", token=self.token)[0], 200)
            self.assertFalse(os.path.exists(path))
            self.assertEqual(self.call("DELETE", "/api/v1/models/local/ollama/bad%20name", token=self.token)[0], 400)
            time.sleep(0.2)
            reload.assert_called()
        self.assertTrue(os.path.exists(keep))

    def test_download_validation(self):
        cases = [{"runtime": "x"}, {"runtime": "llamacpp", "repo": "bad", "file": "a.gguf"},
                 {"runtime": "llamacpp", "repo": "owner/name", "file": "../a.gguf"},
                 {"runtime": "llamacpp", "repo": "owner/name", "file": "/a.gguf"},
                 {"runtime": "llamacpp", "repo": "owner/name", "file": "a.bin"},
                 {"runtime": "ollama", "name": "bad name"}]
        for body in cases:
            with self.subTest(body=body):
                self.assertEqual(self.call("POST", "/api/v1/models/download", body, token=self.token)[0], 400)

    def test_catalog_and_local_models(self):
        cat = hub.load_catalog()
        names = [cat[0]["file"], "loaded-model.gguf", "mmproj-x.gguf", "half.gguf.part", "notes.txt"]
        for n in names:
            open(os.path.join(self.models, n), "wb").close()
        try:
            status, _, out = self.get("/api/v1/models/catalog")
            self.assertEqual(status, 200)
            self.assertEqual(len(out), len(cat))
            self.assertTrue(out[0]["installed"])
            self.assertFalse(any(e["installed"] for e in out[1:]))
            self.assertTrue(all(isinstance(e["fits"], bool) for e in out))
            local = self.get("/api/v1/models/local")[2]
            files = {m["file"]: m for m in local if m["runtime"] == "llamacpp"}
            self.assertEqual(set(files), {cat[0]["file"], "loaded-model.gguf"})
            self.assertTrue(files["loaded-model.gguf"]["loaded"])
            self.assertFalse(files[cat[0]["file"]]["loaded"])
        finally:
            for n in names:
                os.unlink(os.path.join(self.models, n))

    def test_search(self):
        self.assertEqual(self.get("/api/v1/search")[0], 400)
        status, _, res = self.get("/api/v1/search?q=debian&limit=3")
        self.assertEqual(status, 200)
        self.assertEqual([r["title"] for r in res], ["Debian 0", "Debian 1", "Debian 2"])

    def test_system_and_jobs(self):
        status, _, s = self.get("/api/v1/system")
        self.assertEqual(status, 200)
        for key in ("cpu", "ram_used", "ram_total", "temp", "uptime", "disks", "net", "wifi"):
            self.assertIn(key, s)
        self.assertEqual(self.get("/api/v1/jobs")[0], 200)
        self.assertEqual(self.get("/api/v1/jobs/nope")[0], 404)
        self.assertEqual(self.call("POST", "/api/v1/jobs/nope/cancel", token=self.token)[0], 404)

    def test_proxy(self):
        status, _, body = self.get("/llm/v1/models")
        self.assertEqual(status, 200)
        self.assertEqual(body["data"][0]["id"], "loaded-model")
        self.assertNotIn("Authorization", FakeUpstream.seen_headers)
        status, resp, body = self.call("POST", "/llm/v1/chat/completions", {"stream": True}, token=self.token)
        self.assertEqual(status, 200)
        self.assertEqual(resp.getheader("Transfer-Encoding"), "chunked")
        self.assertEqual(body.count(b"data: "), 4)
        self.assertTrue(body.endswith(b"data: [DONE]\n\n"))
        self.assertEqual(self.get("/ollama/api/tags")[0], 502)  # nothing listens on the Ollama port

    def test_dead_model_process_restarts_llama_once(self):
        restarts = []
        rec = hub.LlamaRecovery(restart=lambda: restarts.append(1))
        chat = ("POST", "/llm/v1/chat/completions", {"stream": True})
        with mock.patch.object(hub, "LLAMA_RECOVERY", rec):
            FakeUpstream.child_dead = True
            try:
                first = self.call(*chat, token=self.token)
                second = self.call(*chat, token=self.token)
            finally:
                FakeUpstream.child_dead = False
            self.assertEqual((first[0], second[0]), (503, 503))
            self.assertIn("restarting it", first[2]["error"])
            self.assertIn("a moment ago", second[2]["error"])
            end = time.time() + 5
            while rec.running and time.time() < end:
                time.sleep(0.01)
            self.assertEqual(restarts, [1])
            status, _, body = self.call("POST", "/llm/v1/other-error", {}, token=self.token)
            self.assertEqual((status, body), (500, {"error": "boom"}))  # other errors pass through untouched
            self.assertEqual(rec.in_row, 1)
            self.assertEqual(self.call(*chat, token=self.token)[0], 200)
            self.assertEqual(rec.in_row, 0)  # a good answer resets the backoff


class DownloadTest(unittest.TestCase):
    """download_llama against the fake Hugging Face server: resume, servers that ignore Range, early stop."""

    @classmethod
    def setUpClass(cls):
        cls.upstream = ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstream)
        threading.Thread(target=cls.upstream.serve_forever, daemon=True).start()
        cls.url = "http://127.0.0.1:%d" % cls.upstream.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.upstream.shutdown()
        cls.upstream.server_close()

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.cfg = mock.patch.object(hub, "CFG", hub.parse_args(["--models-dir", self.dir]))
        self.cfg.start()
        self.hf = mock.patch.object(hub, "HF", self.url)
        self.hf.start()
        self.reload = mock.patch.object(hub, "reload_llama_models")
        self.reload.start()
        self.data = FakeUpstream.model_bytes

    def tearDown(self):
        FakeUpstream.ignore_range = False
        for p in (self.cfg, self.hf, self.reload):
            p.stop()
        shutil.rmtree(self.dir, ignore_errors=True)

    def run_download(self):
        job = hub.Job("download", "model.gguf")
        hub.download_llama(job, "owner/name", "model.gguf", hub.hf_file_size("owner/name", "model.gguf"))
        with open(os.path.join(self.dir, "model.gguf"), "rb") as f:
            self.assertEqual(f.read(), self.data)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "model.gguf.part")))
        return job

    def test_size_from_the_repo_tree(self):
        self.assertEqual(hub.hf_file_size("owner/name", "model.gguf"), len(self.data))
        with self.assertRaises(hub.ApiError) as cm:
            hub.hf_file_size("owner/name", "other.gguf")
        self.assertEqual(cm.exception.status, 404)

    def test_fresh_and_resumed_download(self):
        job = self.run_download()
        self.assertEqual(job.bytes, len(self.data))
        os.unlink(os.path.join(self.dir, "model.gguf"))
        with open(os.path.join(self.dir, "model.gguf.part"), "wb") as f:
            f.write(self.data[:1000])
        self.run_download()

    def test_server_ignores_range(self):
        FakeUpstream.ignore_range = True
        with open(os.path.join(self.dir, "model.gguf.part"), "wb") as f:
            f.write(b"stale bytes")
        self.run_download()

    def test_existing_file_is_kept(self):
        with open(os.path.join(self.dir, "model.gguf"), "wb") as f:
            f.write(self.data)
        job = hub.Job("download", "model.gguf")
        with mock.patch.object(hub, "HF", "http://127.0.0.1:%d" % free_port()):
            hub.download_llama(job, "owner/name", "model.gguf", len(self.data))
        self.assertEqual(job.bytes, len(self.data))

    def test_short_download_is_an_error(self):
        job = hub.Job("download", "model.gguf")
        with self.assertRaises(RuntimeError):
            hub.download_llama(job, "owner/name", "model.gguf", len(self.data) + 10)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "model.gguf")))


if __name__ == "__main__":
    unittest.main()
