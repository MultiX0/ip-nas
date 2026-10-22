# A3 drawings for the v6d case, built from the Blender ortho views and dims.json written by nas_export_v6d.py, plus
# slicer.json (copy it from verification/results/ into <package>/_build/ first) and the hero render
# (<package>/05_RENDERS/v6d_A_hero.png).
# Usage: python scripts/nas_blueprints_v6d.py [package folder, default out/] [logo contours json]
# Every view is drawn at a true scale on the sheet (stated in the title block); all dimensions are in mm.
import json, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.patches import Rectangle, Polygon
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "out")
LOGO_JSON = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(ROOT), "brand", "ip_logo_contours.json")
B = os.path.join(PKG, "_build")
INFO = json.load(open(os.path.join(B, "dims.json")))
SL = json.load(open(os.path.join(B, "slicer.json")))
d = INFO["dims"]; VW = INFO["views"]
LOGO = json.load(open(LOGO_JSON))
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 7})
INK, DIM, ACC = "#111111", "#1a3d8f", "#5a7d00"
A3 = (420.0, 297.0)
DATE = "2026-10-17"

def mapper(view):
    return {"front": lambda x, y, z: (x, z), "back": lambda x, y, z: (-x, z), "right": lambda x, y, z: (y, z),
            "left": lambda x, y, z: (-y, z), "top": lambda x, y, z: (x, y)}[view]

class View:
    """Places one ortho render on the sheet. (u0, v0) of the part's own box lands at page (px, py); s = scale."""
    def __init__(self, ax, key, s, px, py, box, title):
        self.ax, self.s, self.px, self.py = ax, s, px, py
        self.view = key.split("_")[-1]; self.m = mapper(self.view)
        self.u0, self.u1, self.v0, self.v1 = box
        meta = VW[key]; im = Image.open(os.path.join(B, meta["file"]))
        ex = [self.P(meta["u"][0], 0)[0], self.P(meta["u"][1], 0)[0], self.P(0, meta["v"][0])[1], self.P(0, meta["v"][1])[1]]
        ax.imshow(im, extent=ex, zorder=2, interpolation="lanczos")
        cx = px + (self.u1 - self.u0) * s / 2
        ax.text(cx, py - 13, title, ha="center", va="top", fontsize=8.5, weight="bold", color=INK, zorder=6)
    def P(self, u, v): return (self.px + (u - self.u0) * self.s, self.py + (v - self.v0) * self.s)
    def W(self, x, y, z): return self.P(*self.m(x, y, z))

def dim(ax, p1, p2, off, text, horiz=True, fs=6.6, col=DIM):
    """Linear dimension between page points p1, p2. horiz: measured along x, dimension line offset in y by off."""
    (x1, y1), (x2, y2) = p1, p2
    if horiz:
        yl = max(y1, y2) + off if off > 0 else min(y1, y2) + off
        for x, y in ((x1, y1), (x2, y2)): ax.plot([x, x], [y, yl + (1.2 if off > 0 else -1.2)], lw=0.35, color=col, zorder=5)
        ax.annotate("", (x1, yl), (x2, yl), arrowprops=dict(arrowstyle="<|-|>", lw=0.45, color=col, shrinkA=0, shrinkB=0, mutation_scale=4), zorder=5)
        ax.text((x1 + x2) / 2, yl + 0.8, text, ha="center", va="bottom", fontsize=fs, color=col, zorder=6,
                bbox=dict(fc="white", ec="none", pad=0.15))
    else:
        xl = max(x1, x2) + off if off > 0 else min(x1, x2) + off
        for x, y in ((x1, y1), (x2, y2)): ax.plot([x, xl + (1.2 if off > 0 else -1.2)], [y, y], lw=0.35, color=col, zorder=5)
        ax.annotate("", (xl, y1), (xl, y2), arrowprops=dict(arrowstyle="<|-|>", lw=0.45, color=col, shrinkA=0, shrinkB=0, mutation_scale=4), zorder=5)
        ax.text(xl + (0.8 if off > 0 else -0.8), (y1 + y2) / 2, text, ha="left" if off > 0 else "right", va="center", rotation=90,
                fontsize=fs, color=col, zorder=6, bbox=dict(fc="white", ec="none", pad=0.15))

def note(ax, p, txt, dx, dy, fs=6.4, col=INK, ha=None):
    ax.annotate(txt, p, (p[0] + dx, p[1] + dy), fontsize=fs, color=col, zorder=7, ha=ha or ("left" if dx >= 0 else "right"), va="center",
                arrowprops=dict(arrowstyle="-", lw=0.4, color=col, shrinkA=0, shrinkB=1), bbox=dict(fc="white", ec="none", pad=0.2))

def sheet(title, no, part, scale_txt, mass_txt, notes):
    fig = plt.figure(figsize=(A3[0] / 25.4, A3[1] / 25.4))
    ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, A3[0]); ax.set_ylim(0, A3[1]); ax.set_aspect("equal"); ax.axis("off")
    ax.add_patch(Rectangle((8, 8), A3[0] - 16, A3[1] - 16, fill=False, lw=0.9, color=INK))
    ax.add_patch(Rectangle((10, 10), A3[0] - 20, A3[1] - 20, fill=False, lw=0.3, color=INK))
    for i in range(1, 8):                                    # zone ticks
        x = 10 + i * (A3[0] - 20) / 8; ax.plot([x, x], [10, 13], lw=0.3, color=INK); ax.plot([x, x], [A3[1] - 13, A3[1] - 10], lw=0.3, color=INK)
    # title block
    tx, ty, tw, th = A3[0] - 10 - 150, 10, 150, 42
    ax.add_patch(Rectangle((tx, ty), tw, th, fill=True, fc="white", lw=0.6, ec=INK, zorder=8))
    for yy in (ty + 14, ty + 24, ty + 32): ax.plot([tx, tx + tw], [yy, yy], lw=0.3, color=INK, zorder=9)
    ax.plot([tx + 95, tx + 95], [ty, ty + 24], lw=0.3, color=INK, zorder=9)
    ax.text(tx + 3, ty + th - 4, "IP NAS ENCLOSURE v6d", fontsize=10, weight="bold", va="top", zorder=10)
    ax.text(tx + 3, ty + 29, title, fontsize=8.2, weight="bold", va="center", zorder=10)
    ax.text(tx + 3, ty + 19, part, fontsize=6.6, va="center", zorder=10)
    ax.text(tx + 3, ty + 7, f"Material: PLA black, {mass_txt}", fontsize=6.4, va="center", zorder=10)
    ax.text(tx + 98, ty + 19, f"Sheet {no} / 5", fontsize=6.6, va="center", zorder=10)
    ax.text(tx + 98, ty + 7, f"{scale_txt}, A3, mm", fontsize=6.4, va="center", zorder=10)
    ax.text(tx + tw - 3, ty + th - 4, DATE, fontsize=6.4, va="top", ha="right", zorder=10)
    if notes:
        nx, ny, nw = A3[0] - 10 - 150, 55, 150
        nh = 6 + 4.1 * len(notes)
        ax.add_patch(Rectangle((nx, ny), nw, nh, fill=True, fc="white", lw=0.4, ec=INK, zorder=8))
        ax.text(nx + 3, ny + nh - 3, "NOTES", fontsize=7, weight="bold", va="top", zorder=10)
        for i, n in enumerate(notes):
            ax.text(nx + 3, ny + nh - 8 - i * 4.1, f"{i + 1}. {n}", fontsize=6.2, va="top", zorder=10)
    return fig, ax

def logo_outline(ax, v, cy, cz, size):
    for c in LOGO["contours"]:
        pts = [v.W(98.4, cy + u * size, cz + w * size) for u, w in c]
        ax.add_patch(Polygon(pts, closed=True, fill=False, lw=0.5, ec=ACC, zorder=4))

W, D, HB = d["W"], d["D"], d["HB"]
out = PdfPages(os.path.join(PKG, "02_DOCUMENTS", "NAS_v6d_2D_Blueprints_A3.pdf"))

# sheet 1: assembly
s = 0.7
fig, ax = sheet("GENERAL ARRANGEMENT (assembled)", 1, "4 printed parts + bought parts (Pi 5, 2 HDD, 3.5in screen, USB hub)",
                "Scale 1:1.43", f"total {SL['total_g']:.1f} g (slicer)", [
                    f"Overall 100 W x 78 D x {d['total_h']:.1f} H (legs 5 + body 195 + crown 11.6).",
                    "Parts: A body, B back door (Pi mount), C crown, D 4 corner legs.",
                    "Front: 3.5in screen (base) and X-braced drive window.",
                    "Right side: USB-C power, 12 V lead, debossed logo.",
                    "Top: 4 USB ports of the internal hub, exhaust slots.",
                    "Back: hex vents, Ethernet exit, 4 x M3 door screws."])
vf = View(ax, "assembly_front", s, 30, 66, (0, W, -d["leg_h"], d["total_h"] - d["leg_h"]), "FRONT")
vr = View(ax, "assembly_right", s, 122, 66, (0, D, -d["leg_h"], d["total_h"] - d["leg_h"]), "RIGHT")
vt = View(ax, "assembly_top", s, 190, 66, (0, W, 0, D), "TOP")
dim(ax, vf.W(0, 0, 0), vf.W(W, 0, 0), -5, "100")
dim(ax, vf.W(0, 0, -d["leg_h"]), vf.W(0, 0, d["total_h"] - d["leg_h"]), -6, f"{d['total_h']:.1f}", horiz=False)
dim(ax, vf.W(W, 0, 0), vf.W(W, 0, HB), 6, "195 (body)", horiz=False)
dim(ax, vr.W(0, 0, 0), vr.W(0, D, 0), -5, "78")
ax.text(*vf.W(50, 0, d["scr_cz"]), "3.5in screen", ha="center", va="center", fontsize=6.4, zorder=7, bbox=dict(fc="white", ec="none", pad=0.3))
note(ax, vf.W(30, 0, 175), "drive window", -2, 30, ha="center")
note(ax, vf.W(97, 0, -2), "4 corner legs (part D)", 14, -10)
note(ax, vr.W(0, d["usbc"][1], d["usbc"][0]), "USB-C power", 18, 8)
note(ax, vr.W(0, d["dcin"][0], d["dcin"][1]), "12 V in", -6, -14, ha="right")
note(ax, vr.W(0, 38, 145), "logo (debossed 0.8)", 0, 50, ha="center")
note(ax, vt.W(30, 70, 0), "4 x USB (hub)", 0, 26, ha="center")
note(ax, vt.W(50, 30, 0), "exhaust", 40, 20)
img = Image.open(os.path.join(PKG, "05_RENDERS", "v6d_A_hero.png"))
w = 150; h = w * img.size[1] / img.size[0]
ax.imshow(img, extent=[A3[0] - 10 - 150, A3[0] - 10, 285 - h, 285], zorder=3)
out.savefig(fig); plt.close(fig)

# sheet 2: body
s = 0.85
fig, ax = sheet("PART A - BODY", 2, "File NAS_v6d_A_body.stl, print UPRIGHT (as drawn), no supports",
                "Scale 1:1.18", f"{SL['A_body']['g']:.1f} g (slicer)", [
                    "Walls and floor 1.6 (4 perimeters). Open top and open back.",
                    "Drive guides: wall fins 1.2 at z 89..111 and 171..191, lanes 6.8 / 9.3.",
                    "Drive shelves z 91..93 under each drive end; hub ledges z 151.3..153.3.",
                    "Screen: ledge z 16.4 + lip behind the bottom edge (x 15..85), fin behind it on the right.",
                    "4 M3 nut slots open at the top (drop-in). 4 crown pegs dia 2.8 x 2.7.",
                    "Floor: 4 x dia 3.4 (leg screws) + 4 x dia 3.5 (leg pins). X brace raised 1.2 on the front.",
                    "Slicer check: 0 warnings (PrusaSlicer 2.9.6, Orca 2.4.2 Bambu X1C)."])
vf = View(ax, "body_front", s, 44, 66, (0, W, 0, HB), "FRONT")
vr = View(ax, "body_right", s, 160, 66, (0, D, 0, HB), "RIGHT")
vb = View(ax, "body_back", s, 300, 112, (-W, 0, 0, HB), "BACK (door removed)")
dim(ax, vf.W(0, 0, 0), vf.W(W, 0, 0), -5, "100")
dim(ax, vf.W(0, 0, 0), vf.W(0, 0, HB), -6, "195", horiz=False)
sw, sh = d["scr_win"]; scx, scz = d["scr_cx"], d["scr_cz"]
dim(ax, vf.W(scx - sw / 2, 0, scz + sh / 2), vf.W(scx + sw / 2, 0, scz + sh / 2), 4, f"{sw}")
dim(ax, vf.W(scx + sw / 2, 0, scz - sh / 2), vf.W(scx + sw / 2, 0, scz + sh / 2), 5, f"{sh}", horiz=False)
dim(ax, vf.W(0, 0, 0), vf.W(0, 0, scz - sh / 2), -14, f"{scz - sh / 2:.1f}", horiz=False)
wx, wz, ww, wh, wc = d["win"]
dim(ax, vf.W(wx - ww / 2, 0, wz + wh / 2), vf.W(wx + ww / 2, 0, wz + wh / 2), 5, f"{ww:.0f}")
dim(ax, vf.W(wx + ww / 2, 0, wz - wh / 2), vf.W(wx + ww / 2, 0, wz + wh / 2), 5, f"{wh:.0f}", horiz=False)
dim(ax, vf.W(0, 0, 0), vf.W(0, 0, wz - wh / 2), -22, f"{wz - wh / 2:.1f}", horiz=False)
note(ax, vf.W(wx + ww / 2 - wc / 2, 0, wz + wh / 2 - wc / 2), "corners 14 x 45°, X bars 8 wide, raised 1.2", 22, 16)
dim(ax, vr.W(0, 0, 0), vr.W(0, D, 0), -5, "78")
uy, uz = d["usbc"][1], d["usbc"][0]
note(ax, vr.W(0, uy, uz), f"USB-C window 8.2 x 14\ncentre y {uy:.1f}, z {uz:.1f}", 20, 22)
note(ax, vr.W(0, d["dcin"][0], d["dcin"][1]), "12 V hole dia 7\ny 22, z 9", -16, -2, ha="right")
note(ax, vr.W(0, 60, 168), "logo 50 high, 0.8 deep", 26, 24)
logo_outline(ax, vr, 38.0, 145.0, 50.0)
note(ax, vr.W(0, 60, 66), "6 slots 3 x 30 (both sides)", 30, 6)
note(ax, vb.W(95.2, D, 182), "M3 drop-in nut slot (x4)", -14, 12, ha="right")
note(ax, vb.W(80, D, 92), "drive shelves z 91..93", 24, -14)
note(ax, vb.W(8, D, 152.3), "hub ledges\nz 151.3..153.3", -8, 26, ha="right")
note(ax, vb.W(8, D, 100), "drive guide fins", -22, -10, ha="right")
out.savefig(fig); plt.close(fig)

# sheet 3: back door
s = 0.95
fig, ax = sheet("PART B - BACK DOOR (Pi 5 mount)", 3, "File NAS_v6d_B_back_door.stl, print FLAT, outside face down",
                "Scale 1:1.05", f"{SL['B_back_door']['g']:.1f} g (slicer)", [
                    "Plate 96.5 x 193.4 x 1.6 with hex vents (4.8 across flats).",
                    "4 standoffs dia 6.0 x 6.8 high, hole dia 2.9 (M2.5 x 12 from outside).",
                    "Standoff pattern 49 x 58 = Raspberry Pi 5 mounting holes.",
                    "4 holes dia 3.5 for M3 x 10 into the body bosses.",
                    "Ethernet exit 14 x 11, rounded r3.",
                    "Standoffs point UP on the print bed, so no supports."])
xd0, xd1, zd0, zd1 = 1.75, 98.25, 1.6, HB
vo = View(ax, "door_back", s, 30, 66, (-xd1, -xd0, zd0, zd1), "OUTSIDE (seen from behind)")
vi = View(ax, "door_front", s, 142, 66, (xd0, xd1, zd0, zd1), "INSIDE (Pi side)")
vs_ = View(ax, "door_right", s, 250, 66, (68.0, D, zd0, zd1), "SIDE")
dim(ax, vo.W(xd1, D, zd0), vo.W(xd0, D, zd0), -5, "96.5")
dim(ax, vo.W(xd1, D, zd0), vo.W(xd1, D, zd1), -6, "193.4", horiz=False)
dim(ax, vi.W(43.7, 0, 67.5), vi.W(92.7, 0, 67.5), 8, "49")
dim(ax, vi.W(92.7, 0, 9.5), vi.W(92.7, 0, 67.5), 8, "58", horiz=False)
dim(ax, vi.W(xd0, 0, zd0), vi.W(43.7, 0, zd0), -5, f"{43.7 - xd0:.2f}")
dim(ax, vi.W(xd1, 0, zd0), vi.W(xd1, 0, 9.5), 6, f"{9.5 - zd0:.1f}", horiz=False)
note(ax, vi.W(43.7, 0, 9.5), "standoff dia 6 x 6.8, hole 2.9 (x4)", -6, -14, ha="right")
ex, ez, ew, eh = d["eth_hole"]
note(ax, vo.W(ex + ew / 2, D, ez + eh / 2), f"Ethernet 14 x 11\n(x {ex:.0f}..{ex + ew:.0f}, z {ez:.0f}..{ez + eh:.0f})", 40, 38)
note(ax, vo.W(4.8, D, 182), "M3 dia 3.5 (x4)", -2, 22, ha="center")
dim(ax, vs_.W(0, D - 1.6 - 6.8, 9.5), vs_.W(0, D, 9.5), -6, "8.4")
out.savefig(fig); plt.close(fig)

# sheet 4: crown and legs
s = 1.4
fig, ax = sheet("PART C - CROWN  +  PART D - LEGS", 4, "NAS_v6d_C_crown.stl (fins up), NAS_v6d_D_legs_x4.stl (pegs up)",
                "Scale 1.4:1", f"C {SL['C_crown']['g']:.1f} g, D {SL['D_legs_x4']['g']:.1f} g (slicer)", [
                    "Crown plate 100 x 78 x 1.6, corners r4.",
                    "5 fins 2.4 wide x 10 high, pitch 12, 45° ends.",
                    "4 exhaust slots 7 x 42 between the fins, 2 side slots 6 x 22.",
                    "4 hub port windows 14.56 x 7.8 at the back edge.",
                    "4 peg holes dia 3.3 (body pegs dia 2.8): x 4.8 from the sides, y 18.5 / 72.7.",
                    "Crown sits on the body pegs; no screws.",
                    "Legs: 4 x L 16 x 16 x 5 high; M3 nut pocket 6.0 AF x 2.6 on top.",
                    "Leg fixing: M3 x 6 from inside + nut in the pocket; pin dia 3.0 locates."])
vt = View(ax, "crown_top", s, 40, 160, (0, W, 0, D), "TOP")
vfr = View(ax, "crown_front", s, 40, 116, (0, W, HB, HB + 11.6), "FRONT")
View(ax, "crown_right", s, 40, 70, (0, D, HB, HB + 11.6), "RIGHT")
dim(ax, vt.W(0, 0, 0), vt.W(W, 0, 0), -6, "100")
dim(ax, vt.W(0, 0, 0), vt.W(0, D, 0), -6, "78", horiz=False)
fx = d["fin_x"]
dim(ax, vt.W(fx[0], 58, 0), vt.W(fx[1], 58, 0), 24, "12")
hp = d["hub_ports"]; hy = d["hub"][1] + d["hub"][4] / 2
dim(ax, vt.W(hp[0] - 0.8, hy + 3.9, 0), vt.W(hp[0] + d["hub_pw"] + 0.8, hy + 3.9, 0), 8, "14.56")
dim(ax, vt.W(0, hy, 0), vt.W(hp[0] - 0.8, hy, 0), 14, f"{hp[0] - 0.8:.1f}")
dim(ax, vt.W(W, 0, 0), vt.W(W, hy, 0), 6, f"{hy:.2f}", horiz=False)
note(ax, vt.W(95.2, 18.5, 0), "peg hole dia 3.3 (x4)", 26, -16)
dim(ax, vfr.W(0, 0, HB), vfr.W(0, 0, HB + 1.6 + d["fin_h"]), -6, f"{1.6 + d['fin_h']:.1f}", horiz=False)
vlt = View(ax, "legs_top", s, 215, 140, (-7.8, 7.8, -37.8, 37.8), "D  LEGS x4 (top)")
vlf = View(ax, "legs_front", s, 250, 140, (-7.8, 7.8, 0, 6.3), "D  side")
dim(ax, vlt.W(-7.8, -37.8, 0), vlt.W(7.8, -37.8, 0), -6, "15.6")
dim(ax, vlf.W(-7.8, 0, 0), vlf.W(-7.8, 0, 5.0), -5, "5.0", horiz=False)
dim(ax, vlf.W(7.8, 0, 0), vlf.W(7.8, 0, 6.3), 5, "6.3", horiz=False)
dim(ax, vfr.W(W, 0, HB), vfr.W(W, 0, HB + 1.6), 6, "1.6", horiz=False)
out.savefig(fig); plt.close(fig)

# sheet 5: print plate
s = 0.82
fig, ax = sheet("PRINT PLATE LAYOUT (single plate, one colour)", 5, "All 4 STL files on one 256 x 256 bed, as exported (no rotation needed)",
                "Scale 1:1.22", f"plate total {SL['total_g']:.1f} g", [
                    "STL files are already in print orientation and in mm.",
                    "Body upright (197.5 high incl. pegs). Door flat, standoffs up.",
                    "Crown fins up, legs pegs up. No supports anywhere.",
                    "Ready project: NAS_v6d_plate_Bambu_X1C_PLA.3mf (Bambu/Orca).",
                    "Any arrangement is fine if the bed is >= 200 x 200.",
                    "Smaller bed: print the door on its own plate."])
px0, py0 = 30, 66
vp = View(ax, "plate_top", s, px0 + 0 * s, py0 + 0 * s, (-128, 128, -128, 128), "")
ax.add_patch(Rectangle(vp.P(-128, -128), 256 * s, 256 * s, fill=False, lw=0.8, ls="--", ec=INK, zorder=3))
ax.text(*vp.P(-126, 124), "build plate 256 x 256", fontsize=6.5, va="top", zorder=6)
for k, (cx, cy) in INFO["plate"].items():
    lo, hi = INFO["parts"][k]["plate_bbox_mm"]
    lbl = {"A_body": "A  BODY  100 x 78 x 197.5  (upright)", "B_back_door": "B  BACK DOOR  96.5 x 193.4 x 8.4  (flat)",
           "C_crown": "C  CROWN  100 x 78 x 11.6  (fins up)", "D_legs_x4": "D  LEGS x4"}[k]
    if k == "D_legs_x4":
        ax.text(*vp.P(hi[0] + 2, (lo[1] + hi[1]) / 2), "D  LEGS x4\n15.6 x 75.6 x 6.3", fontsize=6.4, weight="bold", va="center", zorder=6,
                bbox=dict(fc="white", ec="none", pad=0.2)); continue
    mid = vp.P((lo[0] + hi[0]) / 2, hi[1] if k != "C_crown" else lo[1])
    ax.text(mid[0], mid[1] + (3 if k != "C_crown" else -3), lbl, ha="center", va="bottom" if k != "C_crown" else "top",
            fontsize=6.6, weight="bold", zorder=6, bbox=dict(fc="white", ec="none", pad=0.2))
img = Image.open(os.path.join(B, "pkg_plate.png"))
w = 150; h = w * img.size[1] / img.size[0]
ax.imshow(img, extent=[A3[0] - 10 - 150, A3[0] - 10, 285 - h, 285], zorder=3)
out.savefig(fig); plt.close(fig)
out.close(); print("blueprints ok")
