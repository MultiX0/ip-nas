# Shared base for the case model: paths, scene reset, materials, mesh helpers, the bought parts (Pi 5 with the
# Active Cooler, the UGREEN SATA head), the studio and the camera. nas_scene_v6d.py runs this file first.
# All dimensions in mm (converted with M()). Axes: X = case width, Y = depth (front face at y = 0), Z = up.
# Numbers here are datasheet values; nas_scene_v6d.py replaces them with caliper numbers where I measured the part.
import bpy, bmesh, math, sys, os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(os.path.dirname(ROOT), "brand")
OUT = os.path.join(ROOT, "render")
UI = os.path.join(ROOT, "data", "ui_dashboard.png")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VIEW = argv[0] if argv else "hero"
SAMPLES = int(argv[1]) if len(argv) > 1 else 256

def M(v): return v * 0.001

PI_L, PI_W, PI_T = 85.0, 56.0, 1.6           # Raspberry Pi 5 mechanical drawing
PI_HOLES_U, PI_HOLES_V = (3.5, 61.5), (3.5, 52.5)
COOL = (63.5, 42.5, 13.7)                    # Active Cooler product brief (L, W, H above board)
SSD = (100.0, 69.85, 7.0)                    # SFF-8201, 7 mm drive
SCR = dict(L=94.5, H=62.0, T=12.0, vis=(73.4, 49.0))   # Guition JC3248W535 drawing; vis = visible screen area
SATA_HEAD = (42.0, 50.0, 12.5)               # UGREEN 20611 head: along the drive, width, height (retailer spec)
WIN_E, FILL_E = float(os.environ.get("WIN_E", 60)), float(os.environ.get("FILL_E", 12))
RES = tuple(int(v) for v in os.environ.get("RES", "2400x1600").split("x"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"

def link(o):
    sc.collection.objects.link(o); return o

def mat(name, color, rough=0.5, metal=0.0, emit=None, emit_str=0.0, coat=0.0, spec=0.5):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Specular IOR Level"].default_value = spec
    if coat: b.inputs["Coat Weight"].default_value = coat
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1); b.inputs["Emission Strength"].default_value = emit_str
    return m

def printed(name, color):
    """Printed plastic: horizontal 0.2 mm layer lines from a bump wave."""
    m = bpy.data.materials.get(name)
    if m: return m
    m = mat(name, color, rough=0.62, spec=0.35)
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 2 * math.pi / M(0.2)
    sn = nt.nodes.new("ShaderNodeMath"); sn.operation = "SINE"
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 900
    mix = nt.nodes.new("ShaderNodeMath"); mix.operation = "MULTIPLY_ADD"; mix.inputs[1].default_value = 0.85
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = M(0.03)
    nt.links.new(tc.outputs["Object"], sep.inputs[0]); nt.links.new(sep.outputs["Z"], mul.inputs[0])
    nt.links.new(mul.outputs[0], sn.inputs[0]); nt.links.new(sn.outputs[0], mix.inputs[0]); nt.links.new(noise.outputs["Fac"], mix.inputs[2])
    nt.links.new(mix.outputs[0], bump.inputs["Height"]); nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m

def image_mat(name, path, emit_str=0.0, rough=0.4, alpha=False):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(path)
    tex.extension = "CLIP"
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    if emit_str:
        nt.links.new(tex.outputs["Color"], b.inputs["Emission Color"]); b.inputs["Emission Strength"].default_value = emit_str
    if alpha:
        nt.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
    return m

M_CASE = printed("case_pla", (0.012, 0.012, 0.013))
M_PCB = mat("pcb_green", (0.02, 0.16, 0.05), rough=0.35, coat=0.6)
M_SILVER = mat("tin", (0.75, 0.75, 0.74), rough=0.28, metal=1.0)
M_GOLD = mat("gold", (0.9, 0.65, 0.3), rough=0.25, metal=1.0)
M_BRASS = mat("brass", (0.78, 0.55, 0.25), rough=0.35, metal=1.0)
M_BLACKPL = mat("black_plastic", (0.015, 0.015, 0.016), rough=0.45)
M_SOFT = mat("soft_black", (0.02, 0.02, 0.022), rough=0.7)
M_CHIP = mat("chip", (0.03, 0.03, 0.035), rough=0.35)
M_ALU = mat("alu_black_anod", (0.02, 0.02, 0.022), rough=0.38, metal=1.0)
M_BLUE = mat("usb3_blue", (0.0, 0.12, 0.55), rough=0.45)
M_WHITEPL = mat("white_plastic", (0.8, 0.8, 0.78), rough=0.45)
M_GLASS = mat("screen_glass", (0.0, 0.0, 0.0), rough=0.04, spec=0.5, coat=1.0)
M_STEEL = mat("steel", (0.55, 0.55, 0.56), rough=0.3, metal=1.0)
M_NYLON = mat("nylon_black", (0.02, 0.02, 0.02), rough=0.55)
M_UI = image_mat("ui", UI, emit_str=3.0, rough=0.08)

def rrect_pts(w, h, r, seg=8):
    r = min(r, w / 2, h / 2); pts = []
    for cx, cy, a0 in ((w - r, h - r, 0), (r, h - r, 90), (r, r, 180), (w - r, r, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg); pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def prism(name, pts2d, z0, z1, m, plane="XY", bevel=0.0):
    """Extrude a 2D outline. plane XY: pts are (x,y) extruded in z. XZ: pts are (x,z) extruded in y. YZ: (y,z) in x."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    def P(a, b, c):
        if plane == "XY": return (M(a), M(b), M(c))
        if plane == "XZ": return (M(a), M(c), M(b))
        return (M(c), M(a), M(b))
    lo = [bm.verts.new(P(x, y, z0)) for x, y in pts2d]; hi = [bm.verts.new(P(x, y, z1)) for x, y in pts2d]
    bm.faces.new(lo[::-1]); bm.faces.new(hi)
    n = len(pts2d)
    for i in range(n):
        j = (i + 1) % n; bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); o.data.materials.append(m)
    if bevel:
        md = o.modifiers.new("bev", "BEVEL"); md.width = M(bevel); md.segments = 3; md.limit_method = "ANGLE"
        md.harden_normals = False
    return o

def box(name, x, y, z, w, d, h, m, r=0.0, bevel=0.0):
    pts = [(x + px, y + py) for px, py in rrect_pts(w, d, r)] if r else [(x, y), (x + w, y), (x + w, y + d), (x, y + d)]
    return prism(name, pts, z, z + h, m, bevel=bevel)

def cyl(name, x, y, z, rad, h, m, axis="Z", seg=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=M(rad), depth=M(h))
    o = bpy.context.active_object; o.name = name; o.data.materials.append(m)
    if axis == "X": o.rotation_euler = (0, math.pi / 2, 0)
    if axis == "Y": o.rotation_euler = (math.pi / 2, 0, 0)
    off = {"Z": (0, 0, h / 2), "X": (h / 2, 0, 0), "Y": (0, h / 2, 0)}[axis]
    o.location = (M(x + off[0]), M(y + off[1]), M(z + off[2]))
    return o

def cut(target, cutter):
    md = target.modifiers.new("cut", "BOOLEAN"); md.operation = "DIFFERENCE"; md.object = cutter; md.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    for o in bpy.context.selected_objects: o.select_set(False)
    target.select_set(True)
    bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

def join(name, objs):
    for o in bpy.context.selected_objects: o.select_set(False)
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join(); objs[0].name = name; return objs[0]

def parent(children, p):
    bpy.context.view_layer.update()
    for c in children:
        mw = c.matrix_world.copy(); c.parent = p; c.matrix_world = mw

def empty(name, loc=(0, 0, 0)):
    e = link(bpy.data.objects.new(name, None)); e.location = loc; return e

def decal(name, x, y, z, w, h, m, face="front"):
    """Flat textured plane. face front: on XZ plane facing -Y. top: XY facing +Z."""
    bpy.ops.mesh.primitive_plane_add(size=1)
    o = bpy.context.active_object; o.name = name; o.data.materials.append(m)
    o.scale = (M(w), M(h), 1)
    if face == "front": o.rotation_euler = (math.pi / 2, 0, 0)
    o.location = (M(x), M(y), M(z))
    return o

def cable(name, pts, rad, m):
    cu = bpy.data.curves.new(name, "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = M(rad); cu.bevel_resolution = 4
    sp = cu.splines.new("BEZIER"); sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = Vector((M(p[0]), M(p[1]), M(p[2]))); bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = link(bpy.data.objects.new(name, cu)); o.data.materials.append(m); return o

def build_pi(name):
    """Raspberry Pi 5 + Active Cooler. Local frame: u along 85 mm (0 = microSD edge, 85 = USB/Ethernet edge) on X,
    v along 56 mm on Y (0 = USB-C/micro-HDMI edge, 56 = GPIO edge), board bottom at z=0."""
    root = empty(name); parts = []
    pcb = prism(name + "_pcb", rrect_pts(PI_L, PI_W, 3), 0, PI_T, M_PCB)
    for hu in PI_HOLES_U:
        for hv in PI_HOLES_V:
            c = cyl("h", hu, hv, -1, 1.35, 4, M_PCB, seg=24); cut(pcb, c)
            ring = cyl("ring", hu, hv, PI_T - 0.02, 3.0, 0.04, M_SILVER, seg=24); cut(ring, cyl("rh", hu, hv, PI_T - 1, 1.35, 2, M_PCB)); parts.append(ring)
    parts.append(pcb)
    t = PI_T
    # ports on the 85 edge: Ethernet + two stacked USB-A (Pi 5 swaps Ethernet to the corner)
    parts.append(box("eth", 64.5, 2.2, t, 21.5 + 2.5, 16.0, 13.5, M_SILVER, bevel=0.3))
    parts.append(box("eth_hole", 87.6, 4.7, t + 2.0, 0.6, 11.0, 9.0, M_BLACKPL))
    for vc, tongue in ((29.1, M_BLUE), (47.0, M_BLACKPL)):
        parts.append(box("usb", 68.0, vc - 7.25, t, 20.0, 14.5, 16.0, M_SILVER, bevel=0.3))
        for zz in (2.5, 10.0):
            parts.append(box("usb_mouth", 87.6, vc - 6.2, t + zz, 0.6, 12.4, 5.2, M_SOFT))
            parts.append(box("usb_tongue", 87.0, vc - 5.5, t + zz + 2.6, 1.2, 11.0, 1.9, tongue))
    # USB-C + 2 micro-HDMI on the v=0 edge
    parts.append(box("usbc", 11.2 - 4.5, -1.2, t, 9.0, 7.5, 3.2, M_SILVER, r=1.4, bevel=0.2))
    for uc in (25.8, 39.2):
        parts.append(box("uhdmi", uc - 3.75, -1.0, t, 7.5, 6.5, 3.5, M_SILVER, bevel=0.2))
    # GPIO 2x20 header along the v=56 edge
    parts.append(box("gpio", 32.5 - 25.5, 50.0, t, 51.0, 5.0, 2.5, M_BLACKPL))
    pins = []
    for i in range(20):
        for j in range(2):
            pins.append(box("pin", 32.5 - 24.13 + i * 2.54 - 0.32, 51.25 + j * 2.54 - 0.32, t + 2.5, 0.64, 0.64, 6.0, M_GOLD))
    parts.append(join(name + "_pins", pins))
    # small chips around the cooler
    for (u, v, w, d, h) in ((70, 20.5, 8, 8, 1.0), (58, 4, 5, 5, 1.0), (4.5, 40, 5, 9, 1.2), (52, 46, 6, 2.5, 3.0)):
        parts.append(box("ic", u, v, t, w, d, h, M_CHIP))
    parts.append(box("fan_jst", 60.5, 47.0, t, 3.5, 6.0, 4.0, M_WHITEPL))
    parts.append(box("pwr_btn", -0.45, 13.3 - 2.25, t, 3.5, 4.5, 2.5, M_BLACKPL))
    # microSD slot under the board, card sticking out of the 0 edge
    parts.append(box("sd_slot", 1.5, 21.0, -1.5, 13.0, 14.0, 1.5, M_SILVER))
    parts.append(box("sd_card", -2.5, 22.0, -1.3, 6.0, 11.0, 0.8, M_SOFT))
    # Active Cooler: aluminium fin block + blower fan, 63.5 x 42.5 x 13.7 over the SoC
    cu0, cv0 = 4.0, 6.0
    hs = box("cooler_base", cu0, cv0, t + 3.5, COOL[0], COOL[1], 2.0, M_ALU, r=1.5, bevel=0.3); parts.append(hs)
    fins = []
    for k in range(13):
        fins.append(box("fin", cu0 + 28.0, cv0 + 1.0 + k * 3.15, t + 5.5, COOL[0] - 29.0, 1.0, COOL[2] - 5.5, M_ALU))
    parts.append(join("fins", fins))
    shroud = box("fan_shroud", cu0, cv0, t + 5.5, 28.0, COOL[1], COOL[2] - 5.5, M_BLACKPL, r=2.0, bevel=0.4)
    hole = cyl("fan_hole", cu0 + 14, cv0 + COOL[1] / 2, t + COOL[2] - 1.5, 11.5, 4, M_BLACKPL, seg=48); cut(shroud, hole)
    parts.append(shroud)
    hub = cyl("fan_hub", cu0 + 14, cv0 + COOL[1] / 2, t + 7.0, 5.0, COOL[2] - 7.6, M_BLACKPL, seg=32); parts.append(hub)
    blades = []
    for k in range(17):
        a = 2 * math.pi * k / 17
        bl = box("blade", 0, -0.35, 0, 5.5, 0.7, COOL[2] - 8.2, M_BLACKPL)
        bl.location = (M(cu0 + 14 + 5.2 * math.cos(a)), M(cv0 + COOL[1] / 2 + 5.2 * math.sin(a)), M(t + 7.2))
        bl.rotation_euler = (0, 0, a + 0.5); blades.append(bl)
    parts.append(join("blades", blades))
    for pu, pv in ((cu0 + 2.5, cv0 + 2.5), (cu0 + COOL[0] - 2.5, cv0 + COOL[1] - 2.5)):
        parts.append(cyl("pushpin", pu, pv, t, 1.6, COOL[2] + 0.4, M_BLACKPL, seg=16))
    parent(parts, root)
    return root

def build_sata_adapter(name):
    """UGREEN 20611 SATA head (size from SATA_HEAD). Local: front face plugs into the drive at x=0."""
    root = empty(name)
    L, W, H = SATA_HEAD
    body = box(name + "_body", 0, -W / 2, -H / 2 + 3.5, L, W, H, M_SOFT, r=3.0, bevel=1.2)
    ridge = box(name + "_ridge", L - 14, -W / 2 + 4, H / 2 + 3.5 - 0.1, 10, W - 8, 1.2, M_SOFT, r=2.0, bevel=0.5)
    led = box(name + "_led", L - 20, W / 2 - 9, H / 2 + 3.5 - 0.05, 3, 1.6, 0.2, mat("led_blue", (0.02, 0.15, 1.0), emit=(0.1, 0.35, 1.0), emit_str=12))
    dc = cyl(name + "_dc", L - 0.5, W / 2 - 10, 3.5, 3.0, 1.0, M_SOFT, axis="X", seg=20)
    dch = cyl(name + "_dch", L - 0.2, W / 2 - 10, 3.5, 1.1, 1.5, M_STEEL, axis="X", seg=16)
    parent([body, ridge, led, dc, dch], root); return root

def env():
    """Studio: matte black desk, white wall, a big soft window light from the left and a dim fill."""
    desk = box("desk", -900, -700, -25, 2200, 1500, 25, mat("desk", (0.018, 0.018, 0.019), rough=0.9, spec=0.25))
    n = desk.active_material.node_tree; b = n.nodes["Principled BSDF"]
    nz = n.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 60; nz.inputs["Detail"].default_value = 8
    bp = n.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.08
    n.links.new(nz.outputs["Fac"], bp.inputs["Height"]); n.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    wall = box("wall", -900, 420, -25, 2200, 20, 1400, mat("wall", (0.78, 0.78, 0.76), rough=0.95, spec=0.2))
    nw = wall.active_material.node_tree; bw = nw.nodes["Principled BSDF"]
    nz2 = nw.nodes.new("ShaderNodeTexNoise"); nz2.inputs["Scale"].default_value = 400; nz2.inputs["Detail"].default_value = 6
    bp2 = nw.nodes.new("ShaderNodeBump"); bp2.inputs["Strength"].default_value = 0.12
    nw.links.new(nz2.outputs["Fac"], bp2.inputs["Height"]); nw.links.new(bp2.outputs["Normal"], bw.inputs["Normal"])
    bpy.ops.object.light_add(type="AREA", location=(M(-900), M(80), M(520)))
    win = bpy.context.active_object; win.data.shape = "RECTANGLE"; win.data.size = M(900); win.data.size_y = M(1100)
    win.data.energy = WIN_E; win.data.color = (1.0, 0.97, 0.93)
    win.rotation_euler = (0, math.radians(-62), 0)
    bpy.ops.object.light_add(type="AREA", location=(M(300), M(-1200), M(700)))
    fill = bpy.context.active_object; fill.data.size = M(1500); fill.data.energy = FILL_E; fill.data.color = (0.95, 0.97, 1.0)
    fill.rotation_euler = (math.radians(55), 0, math.radians(14))
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.5, 0.52, 1); w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25

def camera(loc, target, lens=50, fstop=None):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); link(cam)
    cam.location = tuple(M(v) for v in loc); cam.data.lens = lens; cam.data.sensor_width = 36
    d = Vector(tuple(M(v) for v in target)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if fstop:
        cam.data.dof.use_dof = True; cam.data.dof.focus_distance = d.length; cam.data.dof.aperture_fstop = fstop
    sc.camera = cam; return cam

def render(name, res=None):
    res = res or RES
    sc.render.engine = "CYCLES"; cy = sc.cycles
    cy.samples = SAMPLES; cy.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences; prefs.compute_device_type = "OPTIX"; prefs.get_devices()
        for d in prefs.devices: d.use = True
        cy.device = "GPU"
    except Exception as e: print("no OptiX GPU, rendering on the CPU:", e)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.view_transform = "AgX"; sc.view_settings.look = "AgX - Base Contrast"
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True); print("RENDERED", sc.render.filepath)
