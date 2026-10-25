# Draws the dashboard picture that sits on the screen in the renders (480 x 320, drawn at 2x).
# It is only a texture for the 3D model; the real screen UI is the panel firmware. Writes data/ui_dashboard.png.
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(os.path.dirname(ROOT), "brand", "ip_logo.png")
S = 2; W, H = 480 * S, 320 * S
LIME, BG, CARD, TXT, DIM = (204, 255, 0), (12, 14, 16), (26, 29, 33), (235, 238, 240), (130, 138, 146)
def f(sz, b=False):
    try: return ImageFont.truetype("segoeuib.ttf" if b else "segoeui.ttf", sz * S)
    except OSError: return ImageFont.load_default()   # Segoe UI only exists on Windows
def card(x, y, w, h): d.rounded_rectangle((x * S, y * S, (x + w) * S, (y + h) * S), 8 * S, fill=CARD)
logo = Image.open(LOGO).convert("RGBA"); logo.thumbnail((26 * S, 26 * S))
im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
im.paste(logo, (14 * S, 10 * S), logo)
d.text((46 * S, 12 * S), "IP NAS", font=f(17, True), fill=TXT)
d.text((300 * S, 15 * S), "Wi-Fi  -52 dBm", font=f(12), fill=DIM)
d.ellipse((288 * S, 20 * S, 294 * S, 26 * S), fill=LIME)
d.text((410 * S, 15 * S), "14:32", font=f(12, True), fill=TXT)
for i, (name, used, tot, pct) in enumerate([("HDD 1", "212 GB", "320 GB", .66), ("HDD 2", "71 GB", "160 GB", .44)]):
    y = 48 + i * 66; card(12, y, 456, 58)
    d.text((24 * S, (y + 7) * S), name, font=f(14, True), fill=TXT)
    d.text((300 * S, (y + 8) * S), f"{used} / {tot}", font=f(13), fill=DIM)
    d.rounded_rectangle((24 * S, (y + 34) * S, 456 * S, (y + 44) * S), 5 * S, fill=(48, 52, 58))
    d.rounded_rectangle((24 * S, (y + 34) * S, int((24 + 432 * pct) * S), (y + 44) * S), 5 * S, fill=LIME)
for i, (k, v) in enumerate([("CPU", "41°C"), ("LOAD", "7%"), ("RAM", "1.9/4 GB"), ("UPTIME", "4d 06h")]):
    x = 12 + i * 116; card(x, 186, 108, 62)
    d.text(((x + 10) * S, 193 * S), k, font=f(11), fill=DIM)
    d.text(((x + 10) * S, 211 * S), v, font=f(18, True), fill=TXT)
card(12, 256, 296, 52); card(316, 256, 152, 52)
d.text((26 * S, 262 * S), "LOCAL AI", font=f(11), fill=DIM)
d.text((26 * S, 278 * S), "online  ·  15 tok/s", font=f(15, True), fill=LIME)
d.text((330 * S, 271 * S), "Backup", font=f(15, True), fill=TXT)
out = os.path.join(ROOT, "data", "ui_dashboard.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
im.save(out); print("wrote", out)
