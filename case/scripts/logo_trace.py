# Traces brand/ip_logo.png (opaque pixels = glyph) into polygons for the debossed logo on the case.
# Writes brand/ip_logo_contours.json: points normalised so the logo's height is 1.0, origin at its centre, y up.
import cv2, json, os, numpy as np
from PIL import Image

BRAND = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "brand")
a = np.array(Image.open(os.path.join(BRAND, "ip_logo.png")).convert("RGBA"))[:, :, 3]
m = (a > 127).astype(np.uint8) * 255
cs, hier = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
h, w = m.shape; s = 1.0 / h
out = []
for c in cs:
    if cv2.contourArea(c) < 30: continue
    c = cv2.approxPolyDP(c, 0.8, True)[:, 0, :]
    out.append([[round((x - w / 2) * s, 5), round((h / 2 - y) * s, 5)] for x, y in c])
json.dump({"aspect": w / h, "contours": out}, open(os.path.join(BRAND, "ip_logo_contours.json"), "w"))
print(len(out), "contours", sum(len(c) for c in out), "points")
