from PIL import Image
src = Image.open("brand/ip_logo.png").convert("RGBA")
out = ['#include "lvgl.h"', ""]
for name, h in (("img_logo_28", 28), ("img_logo_96", 96)):
    w = round(src.width * h / src.height); im = src.resize((w, h), Image.LANCZOS)
    data = []
    for r, g, b, a in im.getdata():
        c = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        data += [c & 0xFF, c >> 8, a]
    rows = ",".join(f"0x{v:02x}" for v in data)
    out.append(f"static const uint8_t {name}_map[] = {{{rows}}};")
    out.append(f"const lv_img_dsc_t {name} = {{ .header = {{ .cf = LV_IMG_CF_TRUE_COLOR_ALPHA, .always_zero = 0, .reserved = 0, .w = {w}, .h = {h} }}, .data_size = {len(data)}, .data = {name}_map }};")
    out.append("")
open("panel/firmware/src/logo.c", "w").write("\n".join(out))
