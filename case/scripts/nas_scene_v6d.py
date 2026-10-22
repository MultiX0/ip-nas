# IP NAS case v6d: the 4 printed parts, the bought parts in their places, and the views.
# Run: blender -b -P scripts/nas_scene_v6d.py -- <view> [samples]
#   renders (written to render/): hero, rear, inside, exploded, top, legdetail
#   mass: part volumes and weights, then stop
#   stl: quick STL export of the 4 parts in print orientation to NAS_STL_DIR (default out/stl)
#   clash: fit check (nas_interference_v6d.py), export: the print package (nas_export_v6d.py)
# Layout: the screen in the base at the front, the UGREEN heads behind it with the drives standing on them (SATA end
# down) behind an X-braced front window, the Pi 5 on the back door with its ports up, the USB hub under the finned crown
# with its ports up through it, 4 corner legs.
# Axes: X = width (left to right seen from the front), Y = depth (front face y = 0), Z = up. Units mm.
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

_here = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(_here, "nas_scene.py"), encoding="utf-8").read())

# My caliper numbers. They replace the datasheet values from nas_scene.py.
SSD = (100.0, 69.5, 7.0)                      # drives measured 100 x 69.5; the thickness of each drive is in DRV_T
SATA_HEAD = (47.8, 50.0, 13.1)                # UGREEN head: 52.3 long, 4.5 of it over the drive, so it sticks out 47.8
SCR.update(L=94.6, H=61.8, T=12.3)            # screen frame 94.6 x 61.8, total thickness 12.3
SCR_FR, SCR_PLUG = 5.6, 11.1                  # front frame thickness; the angled USB-C plug sticks out 11.1 behind the back
DC_OUT, DC_BEND = 33.5, 10.0                  # 12 V plug (44 long, about 10.5 inside the head) + room for the wire bend
USB_PLUG = 39.1                               # UGREEN USB-A plug, tip to wire
HEAD_DX = -1.6                                # head centre vs drive centre, seen from the front (from a photo)
HUB_L, HUB_W, HUB_T = 77.0, 41.4, 12.1        # HAING HI-U302; the ports are on a 77 x 12.1 face
HUB_P0, HUB_PW, HUB_PG = 5.6, 12.96, 4.66     # edge to first port, port width (derived), gap between ports
HUB_PLUG = 39.4                               # hub USB-A plug, tip to wire

W, D = 100.0, 78.0                            # outer width, depth
T, TD = 1.6, 1.6                              # walls/floor, back door
XI0, XI1, YI0, YI1 = T, W - T, T, D - TD      # inside 1.6..98.4 x 1.6..76.4
# drives: face-on (label toward the front window), SATA end down; base height = head + 12 V plug + bend
HEAD_L = SATA_HEAD[0]
DRV_ZB = math.ceil(T + HEAD_L + DC_OUT + DC_BEND)   # 93
DRV_ZT = DRV_ZB + SSD[0]                            # 193
HB = DRV_ZT + 2.0                                   # 195
DRV_T = (6.4, 8.9)                                  # measured thickness of drive 1 and drive 2
DRV_YL = (21.7, 34.7)                               # y of each label face. The heads (13.1 thick) end up 2.4 apart; head 1
                                                    # stays behind y 15 (plugs on the screen's back), head 2 in front of y 49.1
DRV_X0 = W / 2 - SSD[1] / 2                         # 15.25
HEAD_X = W / 2 + HEAD_DX                            # 48.4
# screen centred in the base (its USB-C plug is on the back, so no side margin is needed)
SCR_X0, SCR_Y = (W - SCR["L"]) / 2, 2.0
SCR_Z0 = round((T + DRV_ZB) / 2 - SCR["H"] / 2, 1)  # 16.4
SCR_CX, SCR_CZ = SCR_X0 + SCR["L"] / 2, SCR_Z0 + SCR["H"] / 2
SLOT_Y = SCR_Y + SCR_FR + 0.3                       # the parts behind the frame flange start here
# Pi 5 standing at the back on the door: board bottom face y 69.6, u (85) up from z 6, v=0 (USB-C edge) 2.2 inside the right wall
PY, PZ0, PXV0 = 69.6, 6.0, W - T - 2.2
# hub: 77 along x (centred), 12.1 along y against the door, 41.4 tall, port face 0.3 under the crown plate
HUB_X0 = W / 2 - HUB_L / 2
HUB_Y0 = (D - 1.6) - 0.5 - HUB_T                 # 63.8
HUB_ZT = HB - 0.3
HUB_ZB = HUB_ZT - HUB_W                          # 153.3
HUB_PORTS = [HUB_X0 + HUB_P0 + k * (HUB_PW + HUB_PG) for k in range(4)]   # left edge x of each port
PI_HOLES_W = [(PXV0 - v, PZ0 + u) for u in PI_HOLES_U for v in PI_HOLES_V]   # (x, z)
USBC = (PZ0 + 11.2, PY - 3.2)                  # (z, y) centre of the USB-C on the right wall
PORT_Z = PZ0 + 88.0                            # top of the Pi's USB and Ethernet ports

def B(name, x0, x1, y0, y1, z0, z1, m=None, r=0.0, bevel=0.0):
    return box(name, x0, y0, z0, x1 - x0, y1 - y0, z1 - z0, m or M_CASE, r=r, bevel=bevel)
def _bool(target, other, op):
    md = target.modifiers.new("b", "BOOLEAN"); md.operation = op; md.object = other; md.solver = "EXACT"
    md.use_self = True; md.use_hole_tolerant = True
    bpy.context.view_layer.objects.active = target
    for o in bpy.context.selected_objects: o.select_set(False)
    target.select_set(True); bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.data.objects.remove(other, do_unlink=True); return target
# NAS_OFF=name1,name2 leaves those features out (by object name). I used it to find which feature caused a slicer warning.
NAS_OFF = set(x for x in os.environ.get("NAS_OFF", "").split(",") if x)
def _keep(objs):
    out = []
    for o in objs:
        if o.name.split(".")[0] in NAS_OFF: bpy.data.objects.remove(o, do_unlink=True)
        else: out.append(o)
    return out
def cut_many(target, cutters):
    cutters = _keep(cutters)
    if cutters: _bool(target, join("cutters", cutters) if len(cutters) > 1 else cutters[0], "DIFFERENCE")
def unite(target, others):
    others = _keep(others)
    if others: _bool(target, join("adds", others) if len(others) > 1 else others[0], "UNION")
    return target
def hexhole(x, y, z, af, depth, axis):
    o = cyl("hex", x, y, z, af / math.sqrt(3), depth, M_CASE, axis=axis, seg=6)
    if axis == "X": o.rotation_euler = (math.pi / 6, math.pi / 2, 0)
    if axis == "Y": o.rotation_euler = (math.pi / 2, math.pi / 6, 0)
    return o
def place(root, rot, loc):
    R = Matrix(rot).transposed().to_4x4(); R.translation = Vector(tuple(M(v) for v in loc)); root.matrix_world = R
def yz(name, pts, x0, x1, m=None): return prism(name, pts, x0, x1, m or M_CASE, plane="YZ")
def xz(name, pts, y0, y1, m=None): return prism(name, pts, y0, y1, m or M_CASE, plane="XZ")
def octagon(cx, cz, w, h, c):
    x0, x1, z0, z1 = cx - w / 2, cx + w / 2, cz - h / 2, cz + h / 2
    return [(x0, z0 + c), (x0 + c, z0), (x1 - c, z0), (x1, z0 + c), (x1, z1 - c), (x1 - c, z1), (x0 + c, z1), (x0, z1 - c)]

# Body: floor + front + 2 side walls, open top and open back.
WIN = (SCR_CX, (DRV_ZB + DRV_ZT) / 2 + 0.5, 64.0, 92.0, 14.0)   # front drive window: centre x, centre z, w, h, corner chamfer
PEG_FRONT_Y = 18.5                                   # front crown pegs sit behind the screen pocket (y 1.6..14.6)
PEGS = ((4.8, PEG_FRONT_Y), (W - 4.8, PEG_FRONT_Y), (4.8, 72.7), (W - 4.8, 72.7))   # crown pegs on the top rim (x, y)
GUIDE_BANDS = ((DRV_ZB - 4.0, DRV_ZB + 18.0), (DRV_ZT - 22.0, DRV_ZT - 2.0))   # z ranges of the drive guide fins
def build_body():
    body = B("body", 0, W, 0, D, 0, HB, r=4.0, bevel=0.5)
    _bool(body, B("inner", XI0, XI1, YI0, D + 5, T, HB + 10), "DIFFERENCE")
    adds = []
    # Screen: it slides down from the top. The corner bosses on its back (5.1 from the sides, 4.85 from top and bottom,
    # r 2.9) must pass freely, so nothing touches the side flanges. It stands on a ledge with a lip behind the bottom flange
    # (x 15..85, clear of the bosses; the lip top is 0.45 below the raised back). One fin behind the raised back on the
    # right holds the top (the cable plug is on the left). With the bottom edge locked and the fin, the screen cannot tip.
    LIP_Y1, LIP_Z1 = SLOT_Y + 1.8, SCR_Z0 + 1.6
    adds.append(B("scr_ledge", 15.0, 85.0, YI0 - 0.3, SLOT_Y, SCR_Z0 - 2.0, SCR_Z0))
    adds.append(B("scr_lip", 15.0, 85.0, SLOT_Y, LIP_Y1, SCR_Z0 - 2.0, LIP_Z1))
    adds.append(yz("scr_ledge45", [(YI0 - 0.3, SCR_Z0 - 2.0 - (LIP_Y1 - YI0 + 0.3)), (LIP_Y1, SCR_Z0 - 2.0), (YI0 - 0.3, SCR_Z0 - 2.0)], 15.0, 85.0))
    FIN_Y0 = SCR_Y + SCR["T"] + 0.3                                  # 0.3 behind the raised back
    adds.append(B("scr_fin", 80.0, XI1 + 0.3, FIN_Y0, FIN_Y0 + 1.8, T - 0.3, SCR_Z0 + SCR["H"] + 1.0))
    # Drive guides: every guide grows out of a side wall, so nothing needs supports.
    # Per side and per height band: 4 fins (lane walls, 1.2) from the wall to 2.3 past the drive edge, a back plate that stops the
    # drive edge in x, 45 deg fin bottoms, and (bottom band only) a 2 mm shelf under each drive end, bridging fin to fin.
    lanes = [(DRV_YL[k] - 0.2, DRV_YL[k] + DRV_T[k] + 0.2) for k in range(2)]
    for side in (0, 1):
        xw = XI0 - 0.3 if side == 0 else XI1 + 0.3                      # wall face (0.3 into the wall)
        xt = DRV_X0 + 2.3 if side == 0 else DRV_X0 + SSD[1] - 2.3       # fin tip: 2.3 past the drive edge
        xe = DRV_X0 - 0.3 if side == 0 else DRV_X0 + SSD[1] + 0.3       # back plate face: 0.3 clear of the drive edge
        xp = xe - 1.2 if side == 0 else xe + 1.2
        depth = abs(xt - xw)
        for zb, zt in GUIDE_BANDS:
            def fin_prism(name, y0, y1, x_from, x_to):
                lo, hi = min(x_from, x_to), max(x_from, x_to)
                wall_x, tip_x = (lo, hi) if side == 0 else (hi, lo)
                pts = [(wall_x, zb - depth), (tip_x, zb), (tip_x, zt), (wall_x, zt)]
                return xz(name, pts, y0, y1)
            for ya, yb in lanes:
                for y0, y1 in ((ya - 1.2, ya), (yb, yb + 1.2)):
                    adds.append(fin_prism("gfin", y0, y1, xw, xt))
                bx0, bx1 = min(xe, xp), max(xe, xp)                    # back plate: stops the drive edge in x
                adds.append(B("gback", bx0, bx1, ya - 0.1, yb + 0.1, zb, zt))
                if zb < DRV_ZB:                                        # shelf under the drive end, top face = drive bottom
                    adds.append(B("gshelf", min(xp, xt), max(xp, xt), ya - 0.1, yb + 0.1, DRV_ZB - 2.0, DRV_ZB))
    # door screw bosses (sides, near the back) with 45 deg corbels; the top ones carry the back crown pegs
    for (xc_, zc) in DOOR_SCREWS:
        xa, xb = ((XI0 - 0.3, 8.0) if xc_ < 50 else (W - 8.0, XI1 + 0.3))
        top = HB if zc > 150 else zc + 6.0
        adds.append(B("dboss", xa, xb, 70.5, YI1, zc - 6.0, top))         # y 70.5: 0.9 behind the Pi board (69.6)
        if xa < 50: adds.append(xz("dcorbel", [(xa, zc - 6.0), (xb, zc - 6.0), (xa, zc - 6.0 - (xb - xa))], 70.5, YI1))
        else: adds.append(xz("dcorbel", [(xa, zc - 6.0), (xb, zc - 6.0), (xb, zc - 6.0 - (xb - xa))], 70.5, YI1))
    for xa, xb in ((XI0 - 0.3, 8.0), (W - 8.0, XI1 + 0.3)):                     # front corner blocks for the crown pegs
        adds.append(B("cblock", xa, xb, PEG_FRONT_Y - 3.5, PEG_FRONT_Y + 3.5, HB - 9.0, HB))   # behind the screen's slide path
        adds.append(xz("ccorbel", [(xa, HB - 9.0), (xb, HB - 9.0), ((xa if xa < 50 else xb), HB - 9.0 - (xb - xa))], PEG_FRONT_Y - 3.5, PEG_FRONT_Y + 3.5))
    for x, y in PEGS:
        adds.append(cyl("peg", x, y, HB - 0.2, 1.4, 2.7, M_CASE, seg=20))
    # hub ledges on both side walls (3 under each hub end), front lips, 45 deg corbels; the left one is notched for the hub cable
    for xa, xb in ((XI0 - 0.3, HUB_X0 + 3.0), (W - HUB_X0 - 3.0, XI1 + 0.3)):
        adds.append(B("hub_ledge", xa, xb, HUB_Y0 - 2.0, YI1, HUB_ZB - 2.0, HUB_ZB))
        adds.append(B("hub_lip", xa, xb, HUB_Y0 - 2.0, HUB_Y0 - 0.3, HUB_ZB - 2.0, HUB_ZB + 4.0))
        adds.append(xz("hub_corbel", [(xa, HUB_ZB - 2.0), (xb, HUB_ZB - 2.0), ((xa if xa < 50 else xb), HUB_ZB - 2.0 - (xb - xa))], HUB_Y0 - 2.0, YI1))
    unite(body, adds)
    cuts = [B("hub_cable_notch", XI0 + 2.0, HUB_X0 + 4.0, HUB_Y0 + 2.0, HUB_Y0 + 10.0, HUB_ZB - 30.0, HUB_ZB + 1.0)]
    # front: drive window (octagon) and screen window
    cx, cz, ww, wh, wc = WIN
    cuts.append(xz("dwin", octagon(cx, cz, ww, wh, wc), -1, T + 1))
    cuts.append(xz("swin", [(SCR_CX - 37.7 + a, SCR_CZ - 25.5 + b) for a, b in rrect_pts(75.4, 51.0, 1.5)], -1, T + 1))
    # sides: one tall slot on the left near the front edge (the wall behind it stays braced), 6 short slots on both sides
    # over the heads; right side: USB-C window, 12 V hole and the logo
    for xw in (-1.0, XI1 - 1.0):
        for yc in ((10.5,) if xw < 0 else ()):
            cuts.append(yz("sslot", [(yc - 4.0 + a, DRV_ZB + 12.0 + b) for a, b in rrect_pts(8.0, 76.0, 4.0)], xw, xw + T + 2))
        for k in range(6):
            cuts.append(yz("lslot", [(20.0 + 9.0 * k + a, DRV_ZB - 53.0 + b) for a, b in rrect_pts(3.0, 30.0, 1.5)], xw, xw + T + 2))   # ends 3 below the fin roots
    cuts.append(yz("usbc", [(USBC[1] - 4.1 + a, USBC[0] - 7.0 + b) for a, b in rrect_pts(8.2, 14.0, 3.5)], XI1 - 1, W + 1))
    cuts.append(yz("dcin", [(DCIN[0] - 3.5 + a, DCIN[1] - 3.5 + b) for a, b in rrect_pts(7.0, 7.0, 3.4)], XI1 - 1, W + 1))
    cuts.append(logo_cutter(LOGO_C[0], LOGO_C[1], LOGO_H, W, LOGO_DEPTH))
    # door screw holes (axis Y) + nut slots from the inner side face
    for xc, zc in DOOR_SCREWS:
        cuts.append(cyl("dh", xc, 66.0, zc, 1.7, 14.0, M_CASE, axis="Y", seg=24))
        sx0, sx1 = (xc - 3.2, 8.5) if xc < 50 else (W - 8.5, xc + 3.2)
        cuts.append(B("dnut", sx0, sx1, 72.0, 74.8, zc - 2.9, (HB if zc > 150 else zc + 6.0) + 1.0))   # open to the top: drop-in nut
    # hex vents in the floor under the heads
    for i in range(12):
        for j in range(11):
            x, y = 13.0 + i * 6.5 + (3.25 if j % 2 else 0), 9.5 + j * 5.6
            if any(math.hypot(x - hx, y - hy) < 6.5 for hx, hy in LEG_SCREWS + LEG_PINS): continue
            if x > 77.0 and 11.5 < y < 19.5: continue                      # nothing under the screen fin (it stands on the floor)
            cuts.append(hexhole(x, y, -1, 4.8, T + 2, "Z"))
    for x, y in LEG_SCREWS: cuts.append(cyl("leg_hole", x, y, -1, LEG_SCREW_D / 2, T + 2, M_CASE, seg=32))
    for x, y in LEG_PINS: cuts.append(cyl("leg_hole", x, y, -1, LEG_PIN_HOLE / 2, T + 2, M_CASE, seg=32))
    cut_many(body, cuts)
    # X brace in the drive window
    x0, x1, z0, z1 = cx - ww / 2, cx + ww / 2, cz - wh / 2, cz + wh / 2
    bars = []
    for (xa, za), (xb_, zb) in (((x0, z0), (x1, z1)), ((x0, z1), (x1, z0))):
        L = math.hypot(xb_ - xa, zb - za); nx, nz = -(zb - za) / L * 4.0, (xb_ - xa) / L * 4.0
        pts = [(xa + nx, za + nz), (xb_ + nx, zb + nz), (xb_ - nx, zb - nz), (xa - nx, za - nz)]
        bars.append(xz("xbar", pts, -1.2, T - 0.05))                         # 8 wide, raised 1.2 on the front, 0.05 short of the inside face
    rz = bars[0]; _bool(rz, bars[1], "UNION")                                # one solid X
    _bool(rz, xz("win_clip", octagon(cx, cz, ww + 2.0, wh + 2.0, wc + 0.41), -3.0, 3.0), "INTERSECT")   # ends 1 mm into the wall, on the 45 deg chamfers
    unite(body, [rz])
    return body

LOGO_C, LOGO_H, LOGO_DEPTH = (38.0, (DRV_ZB + DRV_ZT) / 2 + 2.0), 50.0, 0.8     # debossed logo on the right side: centre (y, z), height, depth
def logo_cutter(cy, cz, size, x_face, depth):
    """The traced logo (brand/ip_logo_contours.json, made by logo_trace.py) as a closed mesh, depth on each side of x_face.
    Seen from the right (+x), image right = +y and image up = +z, so it reads correctly from outside."""
    d = json.load(open(os.path.join(BRAND, "ip_logo_contours.json")))
    cu = bpy.data.curves.new("logo_cut", "CURVE"); cu.dimensions = "2D"; cu.fill_mode = "BOTH"; cu.extrude = M(depth)
    for c in d["contours"]:
        sp = cu.splines.new("POLY"); sp.points.add(len(c) - 1); sp.use_cyclic_u = True
        for pt, (u, v) in zip(sp.points, c): pt.co = (M(u * size), M(v * size), 0.0, 1.0)
    o = link(bpy.data.objects.new("logo_cut", cu)); o.data.materials.append(M_CASE)
    place(o, ((0, 1, 0), (0, 0, 1), (1, 0, 0)), (x_face, cy, cz))
    for x in bpy.context.selected_objects: x.select_set(False)
    bpy.context.view_layer.objects.active = o; o.select_set(True); bpy.ops.object.convert(target="MESH")
    return o

DOOR_SCREWS = ((4.8, 36.0), (W - 4.8, 106.0), (4.8, HB - 13.0), (W - 4.8, HB - 13.0))   # right-low screw above the Pi: the Pi + door slide in past it
LEG_H, LEG_ARM, LEG_W, LEG_BLOCK = 5.0, 16.0, 3.6, 13.0         # corner legs: height, arm length, arm width, corner block
# Fixing (no press fit): M3 x 6 low-head screw from inside the case, down through a 3.4 hole in the 1.6 floor, into an M3 nut
# (5.5 AF x 2.4) that drops into a 6.0 AF x 2.6 hex pocket in the top of the leg; the floor clamps the nut. A loose 3.0 locating
# pin in a 3.5 floor hole stops the leg turning. Screw: head on the floor at z 1.6, tip at z -4.4, 0.6 inside the 5.0 leg.
LEG_SCREW_D, LEG_NUT_AF, LEG_NUT_DEPTH, LEG_PIN_D, LEG_PIN_HOLE, LEG_PIN_H = 3.4, 6.0, 2.6, 3.0, 3.5, 1.3
LEG_SCREW_OFF, LEG_PIN_OFF = (5.0, 4.6), (10.5, 10.5)            # from the body corner, along x and y
CORNERS = ((0, 0), (W, 0), (0, D), (W, D))
def _corner_pt(cx, cy, off):
    sx, sy = (1 if cx == 0 else -1), (1 if cy == 0 else -1); return (cx + sx * off[0], cy + sy * off[1])
LEG_SCREWS = [_corner_pt(cx, cy, LEG_SCREW_OFF) for cx, cy in CORNERS]
LEG_PINS = [_corner_pt(cx, cy, LEG_PIN_OFF) for cx, cy in CORNERS]
def build_leg(cx, cy):
    """One corner leg, flush with the body corner (outer corner r 4), nut pocket and locating pin on top."""
    sx, sy = (1 if cx == 0 else -1), (1 if cy == 0 else -1)
    def bx(x0, x1, y0, y1): return B("leg", min(cx + sx * x0, cx + sx * x1), max(cx + sx * x0, cx + sx * x1),
                                     min(cy + sy * y0, cy + sy * y1), max(cy + sy * y0, cy + sy * y1), -LEG_H, 0.0)
    leg = bx(0, LEG_ARM, 0, LEG_W)
    unite(leg, [bx(0, LEG_W, 0, LEG_ARM), bx(0, LEG_BLOCK, 0, LEG_BLOCK)])
    rc = cyl("leg_rnd", cx + sx * 4.0, cy + sy * 4.0, -LEG_H - 1, 4.0, LEG_H + 2, M_CASE, seg=40)
    cutter = B("leg_corner", min(cx, cx + sx * 4.0), max(cx, cx + sx * 4.0), min(cy, cy + sy * 4.0), max(cy, cy + sy * 4.0), -LEG_H - 1, 1.0)
    _bool(cutter, rc, "DIFFERENCE"); _bool(leg, cutter, "DIFFERENCE")
    ends = [prism("leg_end", [(cx + sx * LEG_ARM, cy - sy * 1), (cx + sx * LEG_ARM, cy + sy * (LEG_W + 1)), (cx + sx * (LEG_ARM - 2.5), cy + sy * (LEG_W + 1))], -LEG_H - 1, 1, M_CASE),
            prism("leg_end", [(cx - sx * 1, cy + sy * LEG_ARM), (cx + sx * (LEG_W + 1), cy + sy * LEG_ARM), (cx + sx * (LEG_W + 1), cy + sy * (LEG_ARM - 2.5))], -LEG_H - 1, 1, M_CASE)]
    for e in ends: _bool(leg, e, "DIFFERENCE")
    qx, qy = _corner_pt(cx, cy, LEG_SCREW_OFF); px, py = _corner_pt(cx, cy, LEG_PIN_OFF)
    _bool(leg, cyl("leg_screw", qx, qy, -LEG_H + 0.2, LEG_SCREW_D / 2, LEG_H + 1, M_CASE, seg=32), "DIFFERENCE")    # blind: 0.2 skin at the bottom
    _bool(leg, hexhole(qx, qy, -LEG_NUT_DEPTH, LEG_NUT_AF, LEG_NUT_DEPTH + 1, "Z"), "DIFFERENCE")                 # nut pocket, open at the top
    unite(leg, [cyl("leg_pin", px, py, -0.1, LEG_PIN_D / 2, LEG_PIN_H + 0.1, M_CASE, seg=32)])
    leg.name = "leg"; return leg
DCIN = (22.0, 9.0)                                  # 12 V lead hole in the right wall (y, z), front bottom

# Back door with the Pi: 4 standoffs, hex vents, Ethernet exit, 4 screw holes.
def build_door():
    door = B("door", XI0 + 0.15, XI1 - 0.15, YI1, D, T, HB, bevel=0.4)
    unite(door, [cyl("standoff", x, PY, z, 3.0, YI1 - PY + 0.3, M_CASE, axis="Y", seg=32) for x, z in PI_HOLES_W])
    cuts = [cyl("soh", x, PY - 1, z, 1.45, 12, M_CASE, axis="Y", seg=20) for x, z in PI_HOLES_W]
    cuts += [cyl("dsh", x, YI1 - 1, z, 1.75, 4, M_CASE, axis="Y", seg=20) for x, z in DOOR_SCREWS]
    cuts.append(xz("eth_hole", [(PXV0 - 10.2 - 7.0 + a, PZ0 + 88.0 + 39.0 + b) for a, b in rrect_pts(14.0, 11.0, 3.0)], YI1 - 1, D + 1))
    ez = PZ0 + 88.0 + 39.0 + 5.5                          # Ethernet hole centre z
    for i in range(12):
        for j in range(31):
            x, z = 14.0 + i * 6.5 + (3.25 if j % 2 else 0), 12.0 + j * 5.6
            if z > HB - 22 or (abs(x - (PXV0 - 10.2)) < 13 and abs(z - ez) < 11): continue
            if any(math.hypot(x - hx, z - hz) < 7.0 for hx, hz in PI_HOLES_W): continue
            if math.hypot(x - 4.8, z - 36) < 8 or math.hypot(x - (W - 4.8), z - 36) < 8 or x > W - 10: continue
            cuts.append(hexhole(x, YI1 - 1, z, 4.8, TD + 2, "Y"))
    cut_many(door, cuts)
    hw = [cyl("m25_head", x, D, z, 2.25, 1.6, M_NYLON, axis="Y", seg=24) for x, z in PI_HOLES_W]
    for x, z in DOOR_SCREWS:
        s = cyl("m3_head", x, D, z, 2.9, 1.0, M_BLACKPL, axis="Y", seg=24); _bool(s, hexhole(x, D + 0.3, z, 2.0, 2, "Y"), "DIFFERENCE"); hw.append(s)
    return door, hw

# Crown: printed plate down, fins up. It sits on the 4 body pegs and holds the hub down.
FIN_H = 10.0
def build_crown():
    PT = 1.6
    crown = B("crown", 0, W, 0, D, HB, HB + PT, r=4.0, bevel=0.5)
    adds = []
    fin_x = [SCR_CX - 24 + 12 * k for k in range(5)]
    for fx in fin_x:                                        # 5 fins, 2.4 wide x 10 tall, 45 deg ends
        adds.append(yz("fin", [(6.0, HB + PT - 0.2), (58.0, HB + PT - 0.2), (58.0 - FIN_H, HB + PT + FIN_H), (6.0 + FIN_H, HB + PT + FIN_H)], fx - 1.2, fx + 1.2))
    unite(crown, adds)
    cuts = []
    for k in range(4):                                       # exhaust slots between the fins
        xc = (fin_x[k] + fin_x[k + 1]) / 2
        cuts.append(prism("ex", [(xc - 3.5 + a, 12.0 + b) for a, b in rrect_pts(7.0, 42.0, 3.0)], HB - 1, HB + PT + 1, M_CASE))
    for xc in (12.0, W - 12.0):                              # side exhaust over the drive zone
        cuts.append(prism("ex2", [(xc - 3.0 + a, 28.0 + b) for a, b in rrect_pts(6.0, 22.0, 3.0)], HB - 1, HB + PT + 1, M_CASE))
    for px in HUB_PORTS:                                     # 4 hub port windows (port + 0.8 per side)
        cuts.append(prism("hubwin", [(px - 0.8 + a, HUB_Y0 + HUB_T / 2 - 3.9 + b) for a, b in rrect_pts(HUB_PW + 1.6, 7.8, 1.2)], HB - 1, HB + PT + 1, M_CASE))
    for x, y in PEGS:
        cuts.append(cyl("peg_h", x, y, HB - 1, 1.65, PT + 0.2 + 1, M_CASE, seg=20))
    cut_many(crown, cuts)
    return crown

# Bought parts that only this case uses (the Pi and the UGREEN head come from nas_scene.py).
M_COVER = mat("hdd_cover", (0.62, 0.62, 0.6), rough=0.35, metal=1.0)
M_CAST = mat("hdd_casting", (0.06, 0.06, 0.065), rough=0.5, metal=0.6)
M_HLABEL = mat("hdd_label", (0.85, 0.86, 0.86), rough=0.6)
M_HBAND = mat("hdd_band", (0.05, 0.25, 0.65), rough=0.5)
M_ETH = mat("eth_cable", (0.25, 0.32, 0.42), rough=0.55)
M_CLEAR = mat("rj45_clear", (0.8, 0.8, 0.8), rough=0.15)
def build_hdd(name, t):
    root = empty(name)
    cast = box(name + "_cast", 0, 0, 0.9, SSD[0], SSD[1], t - 1.6, M_CAST, r=1.5, bevel=0.4)
    cover = box(name + "_cover", 0.6, 0.6, t - 0.7, SSD[0] - 1.2, SSD[1] - 1.2, 0.7, M_COVER, r=2.5, bevel=0.3)
    label = box(name + "_label", 12, 5, t, 68, SSD[1] - 10, 0.06, M_HLABEL, r=2.0)
    band = box(name + "_band", 12, 5, t + 0.01, 10, SSD[1] - 10, 0.06, M_HBAND)
    pcb = box(name + "_pcb", 28, 3, 0.0, 70, SSD[1] - 6, 0.95, M_PCB)
    sata = box(name + "_sata", SSD[0] - 0.8, 5.0, 0.8, 1.0, 40.0, 5.0, M_BLACKPL)
    parent([cast, cover, label, band, pcb, sata], root); return root

body = build_body()
door, door_hw = build_door()
crown = build_crown()
legs = [build_leg(cx, cy) for cx, cy in ((0, 0), (W, 0), (0, D), (W, D))]
leg_hw = []
for qx, qy in LEG_SCREWS:
    h = cyl("leg_m3_head", qx, qy, T, 2.75, 1.8, M_BLACKPL, seg=24); _bool(h, hexhole(qx, qy, T + 0.6, 2.0, 2, "Z"), "DIFFERENCE"); leg_hw.append(h)
    leg_hw.append(hexhole(qx, qy, -LEG_NUT_DEPTH, 5.5, 2.4, "Z")); leg_hw[-1].data.materials.clear(); leg_hw[-1].data.materials.append(M_STEEL)
def make_legs_cluster():
    """The 4 legs as one print object: a column of 4, 4 mm apart, pegs up (print orientation = assembled orientation)."""
    dg = bpy.context.evaluated_depsgraph_get(); objs = []
    for i, lg in enumerate(legs):
        me = bpy.data.meshes.new_from_object(lg.evaluated_get(dg)); me.transform(lg.matrix_world)
        xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
        me.transform(Matrix.Translation(Vector((-min(xs), -min(ys) + i * M(LEG_ARM + 4.0), -min(zs)))))
        o = bpy.data.objects.new(f"legp{i}", me); sc.collection.objects.link(o); o.data.materials.append(M_CASE); objs.append(o)
    j = join("D_legs_x4", objs); j.location = (M(600), 0, 0); j.hide_render = True; return j
legs_cluster = make_legs_cluster()
PRINTED = {"body": body, "back door": door, "crown": crown, "legs (x4)": legs}

def volume_mm3(objs):
    if not isinstance(objs, list): objs = [objs]
    dg = bpy.context.evaluated_depsgraph_get(); v = 0.0
    for o in objs:
        oe = o.evaluated_get(dg); me = oe.to_mesh(); bm = bmesh.new(); bm.from_mesh(me); bm.transform(o.matrix_world)
        v += abs(bm.calc_volume(signed=True)) * 1e9; bm.free(); oe.to_mesh_clear()
    return v
def mass_report():
    """Solid volume x 1.24 g/cm3 (PLA). The slicer weight is a bit lower because of the 15 % infill."""
    tot = 0.0; lines = []
    for k, o in PRINTED.items():
        v = volume_mm3(o) / 1000.0; g = v * 1.24; tot += g
        lines.append(f"{k:18s} {v:7.1f} cm3  {g:6.1f} g")
    lines.append(f"{'TOTAL':18s}              {tot:6.1f} g  ({tot * 0.12:5.2f} JOD at 0.12 JOD per gram)")
    print("MASS\n" + "\n".join(lines)); return tot

# Pi: local u -> +Z, v -> -X, top side (cooler) -> -Y
pi = build_pi("pi5"); place(pi, ((0, 0, 1), (-1, 0, 0), (0, -1, 0)), (PXV0, PY, PZ0))
pi_nuts = [cyl("m25_nut", x, PY - PI_T - 2.0, z, 2.85, 2.0, M_NYLON, axis="Y", seg=6) for x, z in PI_HOLES_W]
def build_screen_measured(name):
    root = empty(name); L, H, Tt, FRm = SCR["L"], SCR["H"], SCR["T"], SCR_FR
    frame = prism(name + "_frame", rrect_pts(L, H, 3.0), 0.0, FRm, M_BLACKPL, plane="XZ", bevel=0.4)
    shell = prism(name + "_shell", [((L - 82.0) / 2 + a, (H - 57.7) / 2 + b) for a, b in rrect_pts(82.0, 57.7, 2.0)], FRm - 0.05, Tt, M_BLACKPL, plane="XZ", bevel=0.4)
    glass = prism(name + "_glass", rrect_pts(L - 1.0, H - 1.0, 2.6), -0.02, 0.6, M_GLASS, plane="XZ"); glass.location.x += M(0.5); glass.location.z += M(0.5)
    ui = decal(name + "_ui", L / 2, -0.04, H / 2, SCR["vis"][0], SCR["vis"][1], M_UI)
    parts = [frame, shell, glass, ui]
    for bx_ in (5.1, L - 5.1):
        for bz in (4.85, H - 4.85):
            parts.append(cyl(name + "_boss", bx_, FRm - 0.05, bz, 2.9, Tt - FRm + 0.05, M_BLACKPL, axis="Y", seg=24))
            parts.append(cyl(name + "_insert", bx_, Tt - 3.0, bz, 1.6, 3.01, M_BRASS, axis="Y", seg=16))
    parent(parts, root); return root
scr = build_screen_measured("screen")
place(scr, ((1, 0, 0), (0, 1, 0), (0, 0, 1)), (SCR_X0, SCR_Y, SCR_Z0))
DRV_ROT = ((0, 0, -1), (1, 0, 0), (0, -1, 0))               # length -> -Z (SATA down), width -> +X, thickness -> -Y (label to the front)
hdds, heads = [], []
for k in range(2):
    pcb_y = DRV_YL[k] + DRV_T[k]
    h = build_hdd(f"hdd{k+1}", DRV_T[k]); place(h, DRV_ROT, (DRV_X0, pcb_y, DRV_ZT)); hdds.append(h)
    a = build_sata_adapter(f"sata{k+1}"); place(a, DRV_ROT, (HEAD_X, pcb_y, DRV_ZB)); heads.append(a)

HEAD_BOT = DRV_ZB - HEAD_L
y_near, y_far = PY - 6.7, PY - 14.2                         # USB rows (near the board / far)
blue_x, black_x = PXV0 - 29.1, PXV0 - 47.0
def usb_plug(name, x, y, length=USB_PLUG): return B(name, x - 8, x + 8, y - 3.5, y + 3.5, PORT_Z - 0.2, PORT_Z + length, M_SOFT, r=1.5, bevel=0.6)
plugs = [usb_plug("sata_usb1", blue_x, y_near), usb_plug("sata_usb2", blue_x, y_far), usb_plug("scr_usb", black_x, y_near, 30),
         usb_plug("hub_usb", black_x, y_far, HUB_PLUG)]
def build_hub():
    hub = B("hub", HUB_X0, HUB_X0 + HUB_L, HUB_Y0, HUB_Y0 + HUB_T, HUB_ZB, HUB_ZT, M_SOFT, r=1.5, bevel=0.8)
    parts = [hub]
    yc = HUB_Y0 + HUB_T / 2
    for px in HUB_PORTS:
        parts.append(B("hub_port", px, px + HUB_PW, yc - 3.0, yc + 3.0, HUB_ZT - 0.6, HUB_ZT + 0.05, M_SILVER))
        parts.append(B("hub_tongue", px + 0.9, px + HUB_PW - 0.9, yc - 0.9, yc + 0.9, HUB_ZT - 0.7, HUB_ZT + 0.08, M_BLUE))
    root = empty("hub_root"); parent(parts, root); return root
hub = build_hub()
cables = []
for k in range(2):
    hx, hy = HEAD_X, DRV_YL[k] + DRV_T[k] - 3.5
    py_ = y_near if k == 0 else y_far
    cables.append(cable(f"sata_c{k}", [(hx, hy, HEAD_BOT), (hx, hy, HEAD_BOT - 8), (hx - 6, hy + 6, 7), (20, 56, 8), (14, 60, 60),
                                       (16, 58, PORT_Z + 40), (36, 58, PORT_Z + 52), (blue_x, py_, PORT_Z + USB_PLUG + 14), (blue_x, py_, PORT_Z + USB_PLUG)], 2.2, M_SOFT))
# screen cable: the angled plug lies on the screen's back near its left edge (front view), runs down, the cable leaves below the corner
px0 = SCR_X0 + 5.0; pyb = SCR_Y + SCR["T"]
pl = B("us284_head", px0, px0 + 10.0, pyb, pyb + SCR_PLUG, SCR_Z0 - 2.0, SCR_Z0 + 30.0, M_SOFT, r=2.0, bevel=0.6)
plugs.append(pl)
cables.append(cable("scr_cable", [(px0 + 5, pyb + 5.5, SCR_Z0 - 2), (px0 + 5, pyb + 6, 6), (8, 50, 5), (8, 62, 60), (10, 62, PORT_Z + 40),
                                  (30, 64, PORT_Z + 52), (black_x, y_near, PORT_Z + USB_PLUG + 12), (black_x, y_near, PORT_Z + USB_PLUG)], 1.9, M_SOFT))
ex, ey = PXV0 - 10.2, PY - 8.35
eth = [B("rj45", ex - 5.85, ex + 5.85, ey - 4, ey + 4, PORT_Z - 2.0, PORT_Z + 21, M_CLEAR, bevel=0.4),
       B("rj45_boot", ex - 5, ex + 5, ey - 4, ey + 4.5, PORT_Z + 21, PORT_Z + 33, M_ETH, r=2.0, bevel=0.8),
       cable("eth_c", [(ex, ey, PORT_Z + 33), (ex, ey + 4, PORT_Z + 40), (ex - 0.5, D - 4, PORT_Z + 44.5), (ex - 1, D + 8, PORT_Z + 42), (ex - 1, D + 13, 100), (ex - 1, D + 15, 20), (ex - 1, D + 40, 3), (ex - 5, D + 260, 3)], 3.0, M_ETH)]
pwr = [B("pwr_plug", XI1 - 1.0, W + 22.0, USBC[1] - 5.5, USBC[1] + 5.5, USBC[0] - 3.0, USBC[0] + 3.0, M_WHITEPL, r=2.0, bevel=0.5),
       cable("pwr_cable", [(W + 22, USBC[1], USBC[0]), (W + 40, USBC[1] + 10, 4), (W + 70, USBC[1] + 40, 1.8), (W + 120, D + 240, 1.8)], 1.8, M_WHITEPL)]
dc = []
for k in range(2):
    jx, jy = HEAD_X + 15.0, DRV_YL[k] + DRV_T[k] - 3.5
    dc.append(cyl(f"dc_plug{k}", jx, jy, HEAD_BOT - DC_OUT, 4.8, DC_OUT, M_SOFT, seg=24))
    dc.append(cable(f"dc_tail{k}", [(jx, jy, HEAD_BOT - DC_OUT), (jx + 3, jy - 3, 5), (72, 24, 5), (76, 22, 6)], 1.8, M_SOFT))
dc.append(B("dc_splitter", 74.0, 86.0, 18.5, 30.5, 2.0, 10.0, M_SOFT, r=2.0, bevel=0.8))
dc.append(cable("dc_in", [(86, 22, 6), (W - 2, DCIN[0], DCIN[1]), (W + 12, DCIN[0], DCIN[1]), (W + 40, DCIN[0] + 12, 2.5), (W + 90, D + 240, 2.5)], 1.9, M_SOFT))
cables += dc
cables.append(cable("hub_cable", [(HUB_X0, HUB_Y0 + 6.0, HUB_ZB + 4.0), (HUB_X0 - 3.0, HUB_Y0 + 6.0, HUB_ZB - 6.0), (12.0, 62.0, HUB_ZB - 20.0),
                                   (30.0, 58.0, PORT_Z + HUB_PLUG + 16.0), (black_x, y_far, PORT_Z + HUB_PLUG + 8.0), (black_x, y_far, PORT_Z + HUB_PLUG)], 1.9, M_SOFT))

if VIEW == "mass":
    mass_report(); sys.exit(0)
mass_report()
env()
for _o in ("desk", "wall"):                      # the case stands on 5 mm legs (z -5..0): lower the studio floor and wall
    bpy.data.objects[_o].location.z -= M(LEG_H)
def lift(objs, dx=0, dy=0, dz=0):
    for o in objs: o.location = (o.location.x + M(dx), o.location.y + M(dy), o.location.z + M(dz))
DOOR_SET = [door, *door_hw, pi, *pi_nuts]
def view_hero():
    camera((W + 320, -360, 220), (W / 2 + 4, D / 2, 95), lens=52, fstop=7); render("v6d_A_hero")
def view_rear():
    camera((-250, D + 330, 250), (W / 2, D / 2, 98), lens=46, fstop=7); render("v6d_B_rear")
def spin_z(objs, deg, pivot):
    T_ = Matrix.Translation(Vector(tuple(M(v) for v in pivot)))
    R_ = T_ @ Matrix.Rotation(math.radians(deg), 4, "Z") @ T_.inverted()
    for o in objs: o.matrix_world = R_ @ o.matrix_world
def view_inside():                                      # door turned round (Pi facing the camera) and set to the right, crown off
    spin_z(DOOR_SET, 180, (W / 2, D, 0)); lift(DOOR_SET, dx=150, dy=110); lift([crown], dx=-150, dy=40)
    for c in cables:
        if c.name.startswith("hub_cable"): c.hide_render = True
    for c in plugs + eth + pwr + [c for c in cables if c.name.startswith(("sata_c", "scr_cable"))]: c.hide_render = True
    camera((-150, 395, 320), (W / 2 + 70, D / 2 + 60, 85), lens=28, fstop=11); render("v6d_C_inside_open")
def view_exploded():
    lift(DOOR_SET, dy=140); lift([crown], dz=175); lift([hub], dz=95, dy=40)
    lift(hdds + heads, dz=120); lift([scr], dz=0, dy=-70)
    for c in cables + plugs + eth + pwr: c.hide_render = True
    camera((W + 560, -580, 580), (W / 2 + 10, 40, 200), lens=40, fstop=11); render("v6d_D_exploded")
def view_top():
    camera((W / 2 + 60, D + 170, HB + 230), (W / 2, D / 2 + 12, HB + 4), lens=50, fstop=8); render("v6d_E_top_hub")
if VIEW == "clash":
    exec(open(os.path.join(_here, "nas_interference_v6d.py"), encoding="utf-8").read()); sys.exit(0)
if VIEW == "stl":                                    # the 4 printed parts in print orientation, each moved down to z 0
    _d = os.environ.get("NAS_STL_DIR", os.path.join(ROOT, "out", "stl")); os.makedirs(_d, exist_ok=True)
    _rot = {"A_body": Matrix.Identity(4), "B_back_door": Matrix.Rotation(math.radians(-90), 4, "X"), "C_crown": Matrix.Identity(4), "D_legs_x4": Matrix.Identity(4)}
    for _k, _o in (("A_body", body), ("B_back_door", door), ("C_crown", crown), ("D_legs_x4", legs_cluster)):
        _dg = bpy.context.evaluated_depsgraph_get(); _me = bpy.data.meshes.new_from_object(_o.evaluated_get(_dg)); _me.transform(_o.matrix_world)
        _me.transform(_rot[_k]); _n = bpy.data.objects.new(_k + "_stl", _me); sc.collection.objects.link(_n)
        _zs = [v.co.z for v in _me.vertices]; _me.transform(Matrix.Translation(Vector((0, 0, -min(_zs)))))
        for _x in bpy.context.selected_objects: _x.select_set(False)
        _n.select_set(True); bpy.context.view_layer.objects.active = _n
        bpy.ops.wm.stl_export(filepath=os.path.join(_d, f"{_k}.stl"), export_selected_objects=True, global_scale=1000.0)
    print("STL QUICK DONE", _d, "features left out:", sorted(NAS_OFF)); sys.exit(0)
if VIEW == "export":
    exec(open(os.path.join(_here, "nas_export_v6d.py"), encoding="utf-8").read()); sys.exit(0)
def view_legdetail():                                 # cut-away of the front-left corner, exploded: screw / floor / nut / leg
    for o in sc.objects:
        if o.type in ("MESH", "CURVE"): o.hide_render = True
    dg = bpy.context.evaluated_depsgraph_get(); me = bpy.data.meshes.new_from_object(body.evaluated_get(dg)); me.transform(body.matrix_world)
    chunk = bpy.data.objects.new("corner_chunk", me); sc.collection.objects.link(chunk); chunk.data.materials.append(M_CASE)
    _bool(chunk, B("keep", -1, 24, -1, 22, -1, 14), "INTERSECT")
    for o in (chunk, legs[0], leg_hw[0], leg_hw[1]): o.hide_render = False
    lift([legs[0]], dz=-20); lift([leg_hw[1]], dx=-14, dz=-12); lift([leg_hw[0]], dz=24)
    qx, qy = LEG_SCREWS[0]; cyl("screw_shank", qx, qy, T + 24 - 6.0, 1.45, 6.0, M_STEEL, seg=24)
    camera((-30, -70, 80), (9, 9, -2), lens=50, fstop=11); render("v6d_F_leg_detail")
VIEWS = {"legdetail": view_legdetail, "top": view_top, "hero": view_hero, "rear": view_rear, "inside": view_inside, "exploded": view_exploded}
if VIEW not in VIEWS:
    sys.exit(f"unknown view '{VIEW}'. Views: {', '.join(VIEWS)}, mass, stl, clash, export")
VIEWS[VIEW]()
