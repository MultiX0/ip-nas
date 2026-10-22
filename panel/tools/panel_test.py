# Fake Pi agent on the PC: feeds the panel sample data, taps, and grabs screenshots.
# usage: python panel_test.py COMx outdir "tap x y" "shot name" "wait s" ...
import sys, json, time, struct, zlib, serial

port, out = sys.argv[1], sys.argv[2]
s = serial.Serial(port, 115200, timeout=0.1); s.dtr = True
GB = 1024 ** 3
ctrs = [
    {"name": "jellyfin", "image": "jellyfin/jellyfin:latest", "state": "running", "status": "Up 3 hours", "cpu": 2.4, "mu": 412 * 1024 ** 2, "ml": 4 * GB},
    {"name": "llamacpp", "image": "ghcr.io/ggml-org/llama.cpp:server", "state": "running", "status": "Up 3 hours", "cpu": 0.3, "mu": 2.1 * GB, "ml": 4 * GB},
    {"name": "searxng", "image": "searxng/searxng:latest", "state": "exited", "status": "Exited (0) 2 hours ago", "cpu": 0, "mu": 0, "ml": 0},
]
wifi = [{"ssid": "HomeWiFi", "sig": 82, "sec": "WPA2", "cur": True}, {"ssid": "Orange-5G", "sig": 61, "sec": "WPA2 WPA3", "cur": False},
        {"ssid": "Cafe Free", "sig": 40, "sec": "open", "cur": False}]
def send(o): s.write((json.dumps(o, separators=(",", ":")) + "\n").encode())
def stat():
    send({"t": "stat", "cpu": 23.5, "ram_u": int(2.6 * GB), "ram_t": int(3.9 * GB), "temp": 54.2, "up": 93784,
          "disks": [{"n": "HDD1", "ok": True, "u": 41 * 10 ** 9, "t": 293 * 10 ** 9}, {"n": "HDD2", "ok": True, "u": 12 * 10 ** 9, "t": 146 * 10 ** 9},
                    {"n": "SD", "ok": True, "u": 9 * 10 ** 9, "t": 29 * 10 ** 9}],
          "ssid": "HomeWiFi", "rssi": 82, "ip": "192.168.1.50", "rx": 1250000, "tx": 84000, "clock": time.strftime("%H:%M")})
buf = b""
def pump(sec):
    global buf
    end = time.time() + sec; last = 0
    while time.time() < end:
        if time.time() - last > 1: stat(); send({"t": "ctrs", "list": ctrs, "err": ""}); last = time.time()
        buf += s.read(4096)
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try: m = json.loads(line)
            except Exception: continue
            if m.get("t") == "hi": send({"t": "hello", "host": "raspberrypi", "ip": "192.168.1.50", "agent": "1.0.0", "model": "Raspberry Pi 5 Model B Rev 1.0", "os": "Debian GNU/Linux 13 (trixie)"})
            elif m.get("t") == "cmd":
                print("CMD", m)
                if m["op"] == "wifi_scan": send({"t": "wifi", "list": wifi})
                else: send({"t": "res", "id": m["id"], "ok": True, "msg": f"{m.get('name', m.get('ssid'))}: {m.get('act', 'connect')} done"})
def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw, 6)) + ch(b"IEND", b""))
def shot(name):
    global buf
    pump(0.3); s.reset_input_buffer(); buf = b""
    s.write(b"SHOT\n"); data = b""; t0 = time.time()
    while b"SHOT 320 480\n" not in data and time.time() - t0 < 5: data += s.read(4096)
    data = data[data.index(b"SHOT 320 480\n") + 13:]
    while len(data) < 320 * 480 * 2 and time.time() - t0 < 20: data += s.read(65536)
    px = struct.unpack("<%dH" % (320 * 480), data[:320 * 480 * 2])
    W, H = 480, 320; rgb = bytearray(W * H * 3)
    for Y in range(H):
        for X in range(W):
            c = px[X * 320 + (319 - Y)]; i = (Y * W + X) * 3
            rgb[i] = (c >> 11) * 255 // 31; rgb[i + 1] = ((c >> 5) & 63) * 255 // 63; rgb[i + 2] = (c & 31) * 255 // 31
    png(f"{out}/{name}.png", W, H, bytes(rgb)); print("shot", name)
for step in sys.argv[3:]:
    a = step.split()
    if a[0] == "tap": s.write(f"TAP {a[1]} {a[2]}\n".encode()); pump(0.6)
    elif a[0] == "type":
        pass
    elif a[0] == "shot": shot(a[1])
    elif a[0] == "wait": pump(float(a[1]))
