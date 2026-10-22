"""Tests for ipnas_panel_agent.py. psutil, nmcli and docker are faked, so they need neither the screen nor root:

    cd panel/pi_agent && python3 -m unittest -v
"""
import json, os, re, sys, types, unittest
from collections import namedtuple
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for missing in ("psutil", "serial"):               # not needed for the tests, so a PC without them works too
    try:
        __import__(missing)
    except ImportError:
        stub = types.ModuleType(missing)
        stub.SerialException = OSError
        sys.modules[missing] = stub
import ipnas_panel_agent as agent

Part = namedtuple("Part", "device mountpoint fstype opts")
Usage = namedtuple("Usage", "total used free percent")
Mem = namedtuple("Mem", "total available")
Net = namedtuple("Net", "bytes_sent bytes_recv")
GB = 10 ** 9


class FakeSh:
    """Stands in for agent.sh: answers by command prefix and records every call."""

    def __init__(self, *answers):
        self.answers, self.calls = list(answers), []

    def __call__(self, cmd, timeout=20):
        self.calls.append(cmd)
        for prefix, answer in self.answers:
            if cmd[:len(prefix)] == prefix:
                return answer() if callable(answer) else answer
        raise AssertionError(f"unexpected command {cmd}")

    def ran(self, prefix):
        return [c for c in self.calls if c[:len(prefix)] == prefix]


def patch_psutil(**funcs):
    return mock.patch.multiple(agent.psutil, create=True, **funcs)


def usage(total, used):
    return Usage(total, used, total - used, 0.0)


class TestHelpers(unittest.TestCase):
    def test_sh_ok(self):
        self.assertEqual(agent.sh([sys.executable, "-c", "print(' hi ')"]), (0, "hi", ""))

    def test_sh_missing_program(self):
        rc, out, err = agent.sh(["no-such-program-ipnas"])
        self.assertEqual((rc, out), (127, ""))
        self.assertIn("not found", err)

    def test_sh_timeout_hides_arguments(self):
        rc, out, err = agent.sh([sys.executable, "-c", "import time; time.sleep(5)", "password", "secret123"], 0.5)
        self.assertEqual(rc, 124)
        self.assertNotIn("secret123", err)

    def test_nm_fields(self):
        self.assertEqual(agent.nm_fields("yes:My\\:Net:80"), ["yes", "My:Net", "80"])
        self.assertEqual(agent.nm_fields("a\\\\:b"), ["a\\", "b"])
        self.assertEqual(agent.nm_fields("::"), ["", "", ""])

    def test_size_to_bytes(self):
        self.assertEqual(agent.size_to_bytes("12.5MiB"), 13107200)
        self.assertEqual(agent.size_to_bytes(" 3.8GiB "), int(3.8 * 1024 ** 3))
        self.assertEqual(agent.size_to_bytes("512KiB"), 524288)
        self.assertEqual(agent.size_to_bytes("1.2kB"), 1200)
        self.assertEqual(agent.size_to_bytes("1.5GB"), 1500000000)
        self.assertEqual(agent.size_to_bytes("0B"), 0)
        self.assertEqual(agent.size_to_bytes("--"), 0)


class TestDrives(unittest.TestCase):
    def drives(self, parts, sizes, realpath=None):
        def disk_usage(path):
            if sizes[path] is None:
                raise PermissionError(path)
            return usage(sizes[path], sizes[path] // 4)
        with patch_psutil(disk_partitions=lambda all=False: parts, disk_usage=disk_usage), \
                mock.patch.object(agent.os.path, "realpath", realpath or (lambda p: p)):
            return [mount for mount, _ in agent.data_drives()]

    def test_sd_card_left_out_and_disk_order(self):
        parts = [Part("/dev/mmcblk0p2", "/", "ext4", ""), Part("/dev/mmcblk0p1", "/boot/firmware", "vfat", ""),
                 Part("/dev/sdb1", "/media/devmon/HDD2", "ext4", ""),
                 Part("/dev/sda1", "/media/devmon/HDD1", "ext4", "")]
        sizes = {"/media/devmon/HDD1": 320 * GB, "/media/devmon/HDD2": 160 * GB}
        self.assertEqual(self.drives(parts, sizes), ["/media/devmon/HDD1", "/media/devmon/HDD2"])

    def test_one_row_per_disk_largest_partition(self):
        parts = [Part("/dev/sda1", "/mnt/small", "vfat", ""), Part("/dev/sda2", "/srv/big", "ext4", ""),
                 Part("/dev/sda2", "/DATA/bind", "ext4", "")]
        sizes = {"/mnt/small": 1 * GB, "/srv/big": 500 * GB, "/DATA/bind": 500 * GB}
        self.assertEqual(self.drives(parts, sizes), ["/srv/big"])

    def test_any_name_nvme_first_unreadable_skipped(self):
        parts = [Part("/dev/sdc1", "/whatever/My Disk", "exfat", ""), Part("/dev/nvme0n1p1", "/data", "ext4", ""),
                 Part("/dev/sdd1", "/locked", "ext4", ""), Part("/dev/loop0", "/snap/x", "squashfs", ""),
                 Part("/dev/disk/by-label/BACKUP", "/backup", "ext4", "")]
        sizes = {"/whatever/My Disk": 2 * GB, "/data": 1000 * GB, "/locked": None, "/backup": 4 * GB}
        real = {"/dev/disk/by-label/BACKUP": "/dev/sde1"}
        self.assertEqual(self.drives(parts, sizes, lambda p: real.get(p, p)), ["/data", "/whatever/My Disk", "/backup"])

    def stat_disks(self, drives):
        with mock.patch.object(agent, "data_drives", return_value=drives), \
                patch_psutil(virtual_memory=lambda: Mem(4 * GB, 3 * GB), disk_usage=lambda p: usage(32 * GB, 9 * GB),
                             net_io_counters=lambda: Net(0, 0), cpu_percent=lambda: 12.34, boot_time=lambda: 0), \
                mock.patch.object(agent, "cpu_temp", return_value=48.5), \
                mock.patch.object(agent, "primary_ip", return_value="192.168.1.50"):
            return agent.stat_msg({"ssid": "MyWiFi", "signal": 70})["disks"]

    def test_stat_rows(self):
        three = [("/a", usage(320 * GB, 41 * GB)), ("/b", usage(160 * GB, 12 * GB)), ("/c", usage(GB, 0))]
        self.assertEqual(self.stat_disks(three), [{"n": "HDD1", "ok": True, "u": 41 * GB, "t": 320 * GB},
                                                  {"n": "HDD2", "ok": True, "u": 12 * GB, "t": 160 * GB},
                                                  {"n": "SD", "ok": True, "u": 9 * GB, "t": 32 * GB}])
        self.assertEqual([d["ok"] for d in self.stat_disks([])], [False, False, True])


class TestStat(unittest.TestCase):
    def test_fields_units_and_rates(self):
        net = iter([Net(1000, 5000), Net(3000, 9000)])
        clock = iter([1000.0, 1002.0])
        with patch_psutil(virtual_memory=lambda: Mem(4 * GB, 1 * GB), net_io_counters=lambda: next(net),
                          cpu_percent=lambda: 23.456, boot_time=lambda: 1000.0 - 93784,
                          disk_usage=lambda p: usage(1, 1)), \
                mock.patch.object(agent, "data_drives", return_value=[]), \
                mock.patch.object(agent, "cpu_temp", return_value=None), \
                mock.patch.object(agent, "primary_ip", return_value="192.168.1.50"), \
                mock.patch.object(agent.time, "time", lambda: next(clock)), \
                mock.patch.object(agent, "_net_prev", [None, 0.0]):
            first = agent.stat_msg({"ssid": "", "signal": 0})
            second = agent.stat_msg({"ssid": "MyWiFi", "signal": 82})
        self.assertEqual((first["rx"], first["tx"]), (0, 0))
        self.assertEqual((second["rx"], second["tx"]), (2000, 1000))          # bytes per second
        self.assertEqual((second["cpu"], second["ram_u"], second["ram_t"]), (23.5, 3 * GB, 4 * GB))
        self.assertEqual((second["up"], second["ssid"], second["rssi"]), (93786, "MyWiFi", 82))
        self.assertIsNone(second["temp"])
        self.assertRegex(second["clock"], r"^\d\d:\d\d$")
        self.assertEqual(set(second), {"t", "cpu", "ram_u", "ram_t", "temp", "up", "disks", "ssid", "rssi", "ip",
                                       "rx", "tx", "clock"})
        json.dumps(second)

    def test_hello(self):
        files = {"/proc/device-tree/model": "Raspberry Pi 5 Model B Rev 1.0\x00",
                 "/etc/os-release": 'NAME="Debian GNU/Linux"\nPRETTY_NAME="Debian GNU/Linux 13 (trixie)"\n'}
        with mock.patch.object(agent, "read_text", lambda p: files.get(p, "")), \
                mock.patch.object(agent, "primary_ip", return_value="192.168.1.50"):
            h = agent.hello_msg()
        self.assertEqual((h["t"], h["agent"], h["model"], h["os"]),
                         ("hello", agent.VERSION, "Raspberry Pi 5 Model B Rev 1.0", "Debian GNU/Linux 13 (trixie)"))
        with mock.patch.object(agent, "read_text", lambda p: ""):
            self.assertEqual((agent.hello_msg()["model"], agent.hello_msg()["os"]), ("", ""))
        self.assertRegex(agent.VERSION, r"^\d+\.\d+\.\d+$")


def docker(ps_lines, stats_lines, ps_rc=0):
    return FakeSh((["docker", "ps"], (ps_rc, "\n".join(json.dumps(x) for x in ps_lines), "permission denied")),
                  (["docker", "stats"], (0, "\n".join(json.dumps(x) for x in stats_lines), "")))


def ps_row(name, state, status, image="img"):
    return {"Names": name, "Image": image, "State": state, "Status": status}


class TestContainers(unittest.TestCase):
    def test_list_sorted_and_measured(self):
        ps = [ps_row("searxng", "exited", "Exited (0) 2 hours ago", "searxng/searxng:latest"),
              ps_row("Jellyfin", "running", "Up 3 hours", "jellyfin/jellyfin"),
              ps_row("immich", "paused", "Up 1 hour (Paused)", "x" * 80),
              ps_row("llamacpp", "running", "Up 3 hours", "ghcr.io/ggml-org/llama.cpp:server")]
        stats = [{"Name": "Jellyfin", "CPUPerc": "2.41%", "MemUsage": "412MiB / 3.8GiB"},
                 {"Name": "llamacpp", "CPUPerc": "--", "MemUsage": "2.1GiB / 3.8GiB"}]
        with mock.patch.object(agent, "sh", docker(ps, stats)):
            lst, err = agent.containers()
        self.assertEqual(err, "")
        self.assertEqual([c["name"] for c in lst], ["Jellyfin", "llamacpp", "immich", "searxng"])
        self.assertEqual((lst[0]["cpu"], lst[0]["mu"], lst[0]["ml"]), (2.4, 412 * 1024 ** 2, int(3.8 * 1024 ** 3)))
        self.assertEqual(lst[1]["cpu"], 0.0)
        self.assertEqual(len(lst[2]["image"]), 48)
        self.assertEqual(set(lst[0]), {"name", "image", "state", "status", "cpu", "mu", "ml"})

    def test_capped_for_the_screen(self):
        ps = [ps_row(f"app{i:02}", "exited", "Exited (0)") for i in range(30)]
        with mock.patch.object(agent, "sh", docker(ps, [])):
            lst, _ = agent.containers()
        self.assertEqual(len(lst), agent.MAX_CTRS)

    def test_docker_error(self):
        with mock.patch.object(agent, "sh", docker([], [], ps_rc=1)):
            self.assertEqual(agent.containers(), (None, "permission denied"))


class TestCommands(unittest.TestCase):
    def run_ctr(self, act, name, rc=0):
        fake = FakeSh((["docker"], (rc, "", "Error response from daemon: No such container")))
        state = {"ctr_due": 99}
        with mock.patch.object(agent, "sh", fake), mock.patch.object(agent, "log"):
            reply = agent.run_command({"t": "cmd", "id": 7, "op": "ctr", "act": act, "name": name}, state)
        return reply, fake.calls, state

    def test_allowed_actions(self):
        for act in ("start", "stop", "restart", "pause", "unpause"):
            reply, calls, state = self.run_ctr(act, "jellyfin")
            self.assertEqual(calls, [["docker", act, "jellyfin"]])
            self.assertEqual(reply, {"t": "res", "id": 7, "ok": True, "msg": f"jellyfin: {act} done"})
            self.assertEqual(state["ctr_due"], 0)
        reply, calls, _ = self.run_ctr("rm", "old-app_1.2")
        self.assertEqual(calls, [["docker", "rm", "-f", "old-app_1.2"]])

    def test_rejected(self):
        for act, name in [("kill", "jellyfin"), ("exec", "jellyfin"), (["stop"], "jellyfin"), ("stop", "-rf"),
                          ("stop", "a;reboot"), ("stop", "../x"), ("stop", ""), ("stop", "jellyfin\n"),
                          ("stop", "x" * 129), ("stop", None)]:
            reply, calls, _ = self.run_ctr(act, name)
            self.assertEqual(calls, [], (act, name))
            self.assertEqual((reply["ok"], reply["msg"], reply["id"]), (False, "bad request", 7))

    def test_docker_failure_reported(self):
        reply, _, _ = self.run_ctr("start", "jellyfin", rc=1)
        self.assertEqual(reply["ok"], False)
        self.assertIn("No such container", reply["msg"])

    def test_unknown_op_and_wifi_scan_error(self):
        with mock.patch.object(agent, "log"):
            self.assertEqual(agent.run_command({"op": "format", "id": 3}, {})["ok"], False)
            with mock.patch.object(agent, "sh", FakeSh((["nmcli"], (127, "", "nmcli not found")))):
                self.assertEqual(agent.run_command({"op": "wifi_scan", "id": 4}, {}),
                                 {"t": "res", "id": 4, "ok": False, "msg": "nmcli not found"})


CONNECT = ["nmcli", "--wait", "45"]
ROLLBACK = ["nmcli", "--wait", "30"]
DELETE = ["nmcli", "con", "delete"]
ACTIVE = (["nmcli", "-t", "-f", "NAME,UUID,TYPE", "con", "show", "--active"],
          (0, "Home:uuid-home:802-11-wireless\ndocker0:uuid-docker0:bridge", ""))
BEFORE = (0, "uuid-home:802-11-wireless\nuuid-eth:802-3-ethernet", "")
AFTER = (0, "uuid-home:802-11-wireless\nuuid-new:802-11-wireless\nuuid-eth:802-3-ethernet\nuuid-veth:bridge", "")


def profiles(*outputs):
    seq = iter(outputs)
    return ["nmcli", "-t", "-f", "UUID,TYPE", "con", "show"], lambda: next(seq)


def now_on(ssid):
    return ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi"], (0, f"no:Other:30\nyes:{ssid}:70", "")


class TestWifi(unittest.TestCase):
    def connect(self, fake, ssid="Cafe", psk="secret123"):
        with mock.patch.object(agent, "sh", fake):
            return agent.wifi_connect(ssid, psk)

    def test_now_and_scan_parsing(self):
        with mock.patch.object(agent, "sh", FakeSh(now_on("My\\:Net"))):
            self.assertEqual(agent.wifi_now(), {"ssid": "My:Net", "signal": 70})
        with mock.patch.object(agent, "sh", FakeSh((["nmcli"], (0, "no:Other:30", "")))):
            self.assertEqual(agent.wifi_now(), {"ssid": "", "signal": 0})
        scan = "\n".join([":Cafe:20:", "*:Home:61:WPA2", ":Home:80:WPA2", "::90:WPA2", ":Office\\:2:55:WPA1 WPA2",
                          ":Home:40:WPA2"] + [f":N{i}:10:WPA2" for i in range(30)])
        with mock.patch.object(agent, "sh", FakeSh((["nmcli"], (0, scan, "")))):
            nets = agent.wifi_scan()
        self.assertEqual(nets[:3], [{"ssid": "Home", "sig": 80, "sec": "WPA2", "cur": True},
                                    {"ssid": "Office:2", "sig": 55, "sec": "WPA1 WPA2", "cur": False},
                                    {"ssid": "Cafe", "sig": 20, "sec": "open", "cur": False}])
        self.assertEqual(len(nets), agent.MAX_NETS)

    def test_connect_ok(self):
        fake = FakeSh(ACTIVE, profiles(BEFORE), now_on("Cafe"), (CONNECT, (0, "successfully activated", "")))
        self.assertEqual(self.connect(fake), (True, "Connected to Cafe"))
        self.assertEqual(fake.ran(DELETE) + fake.ran(ROLLBACK), [])
        self.assertIn(CONNECT + ["dev", "wifi", "connect", "Cafe", "password", "secret123"], fake.calls)

    def test_wrong_password_rolls_back(self):
        err = "Error: Connection activation failed: Secrets were required, but not provided."
        fake = FakeSh(ACTIVE, profiles(BEFORE, AFTER), (CONNECT, (4, "", err)), (DELETE, (0, "", "")),
                      (ROLLBACK, (0, "", "")))
        ok, msg = self.connect(fake)
        self.assertFalse(ok)
        self.assertEqual(msg, "Connection activation failed: Secrets were required, but not provided. Back on Home")
        self.assertEqual(fake.ran(DELETE), [DELETE + ["uuid", "uuid-new"]])
        self.assertEqual(fake.ran(ROLLBACK), [ROLLBACK + ["con", "up", "uuid", "uuid-home"]])

    def test_timeout_still_rolls_back_without_leaking_the_password(self):
        fake = FakeSh(ACTIVE, profiles(BEFORE, BEFORE), (CONNECT, (124, "", "nmcli timed out")),
                      (ROLLBACK, (0, "", "")))
        ok, msg = self.connect(fake)
        self.assertEqual((ok, msg), (False, "nmcli timed out. Back on Home"))
        self.assertNotIn("secret123", msg)

    def test_connected_elsewhere_counts_as_failure(self):
        fake = FakeSh(ACTIVE, profiles(BEFORE, BEFORE), (CONNECT, (0, "", "")), now_on("Neighbour"),
                      (ROLLBACK, (0, "", "")))
        self.assertFalse(self.connect(fake)[0])
        self.assertEqual(len(fake.ran(ROLLBACK)), 1)

    def test_rollback_failure_is_reported(self):
        err = "Error: No network with SSID 'Cafe' found."
        fake = FakeSh(ACTIVE, profiles(BEFORE, BEFORE), (CONNECT, (10, "", err)), (ROLLBACK, (4, "", "")))
        self.assertEqual(self.connect(fake), (False, "No network with SSID 'Cafe' found. Could not go back to Home"))

    def test_no_previous_wifi_and_open_network(self):
        fake = FakeSh((ACTIVE[0], (0, "Wired:uuid-eth:802-3-ethernet", "")), profiles(BEFORE, BEFORE),
                      (CONNECT, (10, "", "Error: Connection activation failed.")))
        self.assertEqual(self.connect(fake, psk=""), (False, "Connection activation failed"))
        self.assertEqual(fake.ran(CONNECT), [CONNECT + ["dev", "wifi", "connect", "Cafe"]])
        self.assertEqual(fake.ran(ROLLBACK), [])

    def test_no_profile_deleted_when_the_list_fails(self):
        fake = FakeSh(ACTIVE, profiles((8, "", "error"), AFTER), (CONNECT, (4, "", "Error: failed")),
                      (ROLLBACK, (0, "", "")))
        self.connect(fake)
        self.assertEqual(fake.ran(DELETE), [])

    def test_command_reply(self):
        with mock.patch.object(agent, "wifi_connect", return_value=(True, "Connected to Cafe")) as wc, \
                mock.patch.object(agent, "log"):
            state = {"wifi_due": 50}
            reply = agent.run_command({"op": "wifi_connect", "id": 9, "ssid": "Cafe" * 10, "psk": "p" * 70}, state)
        wc.assert_called_once_with(("Cafe" * 10)[:32], "p" * 63)
        self.assertEqual((reply, state["wifi_due"]), ({"t": "res", "id": 9, "ok": True, "msg": "Connected to Cafe"}, 0))
        with mock.patch.object(agent, "wifi_connect") as wc, mock.patch.object(agent, "log"):
            for bad in ({"ssid": None}, {"ssid": ""}, {"ssid": "Cafe", "psk": 12345678}):
                self.assertEqual(agent.run_command(dict(bad, op="wifi_connect", id=2), {})["ok"], False)
        wc.assert_not_called()


class FakePort:
    def __init__(self, chunks):
        self.chunks = list(chunks)

    def read(self, n):
        return self.chunks.pop(0) if self.chunks else b""


class TestLink(unittest.TestCase):
    def test_lines(self):
        link = object.__new__(agent.Link)
        link.s = FakePort([b'{"t":"hi","fw":"1.1.0"}\r\nSHOT 320 480\n{"t":"cmd",', b'"id":1}\n', b"x" * 9000])
        link.buf = b""
        got = [json.loads(line) for _ in range(3) for line in link.lines()]
        self.assertEqual(got, [{"t": "hi", "fw": "1.1.0"}, {"t": "cmd", "id": 1}])
        self.assertEqual(link.buf, b"")


FIRMWARE = os.path.join(HERE, "..", "firmware", "src", "main.cpp")


@unittest.skipUnless(os.path.exists(FIRMWARE), "firmware source not found next to the agent")
class TestProtocolMatchesFirmware(unittest.TestCase):
    """Every field the firmware reads is one the agent sends, and the agent stays inside the firmware's limits."""

    @classmethod
    def setUpClass(cls):
        with open(FIRMWARE, encoding="utf-8") as f:
            cls.src = f.read()

    def body(self, signature):
        return re.search(re.escape(signature) + r" \{\n(.*?)\n\}", self.src, re.S).group(1)

    def read_by(self, handler):
        return set(re.findall(r'\b[dkco]\["(\w+)"\]', self.body(f"static void {handler}(JsonDocument &d)")))

    def define(self, name):
        return int(re.search(r"#define %s (\d+)" % name, self.src).group(1))

    def test_message_fields(self):
        with patch_psutil(virtual_memory=lambda: Mem(4 * GB, GB), disk_usage=lambda p: usage(GB, 1),
                          net_io_counters=lambda: Net(0, 0), cpu_percent=lambda: 1.0, boot_time=lambda: 0), \
                mock.patch.object(agent, "data_drives", return_value=[("/a", usage(GB, 1))]), \
                mock.patch.object(agent, "primary_ip", return_value=""):
            stat = agent.stat_msg({"ssid": "", "signal": 0})
            hello = agent.hello_msg()
        ctr = {"name": "a", "image": "", "state": "running", "status": "", "cpu": 0.0, "mu": 0, "ml": 0}
        sent = {"handle_stat": set(stat) | set(stat["disks"][0]),
                "handle_ctrs": {"list", "err"} | set(ctr),
                "handle_wifi": {"list", "ssid", "sig", "sec", "cur"},
                "handle_res": {"id", "ok", "msg"},
                "handle_hello": set(hello)}
        for handler, fields in sent.items():
            self.assertLessEqual(self.read_by(handler), fields, handler)
        types = re.findall(r'!strcmp\(t, "(\w+)"\)', self.body("static void handle_line(char *line)"))
        self.assertEqual(set(types), {"stat", "ctrs", "wifi", "res", "hello"})

    def test_commands_and_limits(self):
        acts = set(re.findall(r'run_ctr_action\("(\w+)"', self.src))
        self.assertTrue(acts and acts <= agent.ACTIONS, acts)
        self.assertEqual(set(re.findall(r'd\["op"\] = "(\w+)"', self.src)), {"ctr", "wifi_scan", "wifi_connect"})
        self.assertEqual(self.define("MAX_CTR"), agent.MAX_CTRS)
        self.assertEqual(self.define("MAX_NET"), agent.MAX_NETS)
        row = {"name": "n" * 47, "image": "i" * 48, "state": "restarting", "status": "s" * 40, "cpu": 100.0,
               "mu": 2 ** 40, "ml": 2 ** 40}
        line = json.dumps({"t": "ctrs", "err": "", "list": [row] * agent.MAX_CTRS}, separators=(",", ":"))
        self.assertLess(len(line), self.define("RXMAX"))


if __name__ == "__main__":
    unittest.main()
