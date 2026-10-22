# Print package export for the v6d case. Runs inside nas_scene_v6d.py (view "export") after the model is built.
# Writes to NAS_PKG (default out/ in the case folder): the STL print files in print orientation, the GLB, the .blend
# with packed textures, and in _build/ the workbench views for the drawings, Cycles views of each part in print
# orientation and of the full plate, and dims.json (every number the drawings and the instructions use).
import json, bpy, bmesh, math, os, shutil
from mathutils import Vector, Matrix

PKG = os.environ.get("NAS_PKG", os.path.join(ROOT, "out"))
D_STL, D_BL, D_3D, D_IMG = (os.path.join(PKG, d) for d in ("01_PRINT_FILES_STL", "03_BLENDER", "04_3D_MODEL", "_build"))
for d in (D_STL, D_BL, D_3D, D_IMG): os.makedirs(d, exist_ok=True)
sc = bpy.context.scene

PARTS = {"A_body": body, "B_back_door": door, "C_crown": crown, "D_legs_x4": legs_cluster}
ENV_NAMES = {"desk", "wall"}

def tree(o):
    out = [o]
    for c in o.children: out += tree(c)
    return out

def eval_copy(o, name):
    """New mesh object = o with all modifiers applied and the world transform baked in."""
    dg = bpy.context.evaluated_depsgraph_get(); oe = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(oe); me.transform(o.matrix_world)
    n = bpy.data.objects.new(name, me); sc.collection.objects.link(n)
    for m in o.data.materials: n.data.materials.append(m)
    return n

def bbox_mm(o):
    vs = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = [min(v[i] for v in vs) * 1000 for i in range(3)]; hi = [max(v[i] for v in vs) * 1000 for i in range(3)]
    return lo, hi

def vol_cm3(o):
    dg = bpy.context.evaluated_depsgraph_get(); oe = o.evaluated_get(dg); me = oe.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me); bm.transform(o.matrix_world); v = abs(bm.calc_volume(signed=True)) * 1e6
    nm = sum(1 for e in bm.edges if not e.is_manifold); bm.free(); oe.to_mesh_clear(); return v, nm

# 1. print-orientation copies + STL
PRINT_ROT = {"A_body": Matrix.Identity(4),                                  # upright, open top up
             "B_back_door": Matrix.Rotation(math.radians(-90), 4, "X"),     # outside face (y = D) down on the bed
             "C_crown": Matrix.Identity(4),                                 # plate down, fins up
             "D_legs_x4": Matrix.Identity(4)}                               # foot face down, pegs up
info = {"parts": {}}
print_objs = {}
for key, o in PARTS.items():
    c = eval_copy(o, key + "_print")
    c.data.transform(PRINT_ROT[key]); c.data.update()
    vs = [v.co for v in c.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))); c.data.update()
    print_objs[key] = c
    for x in bpy.context.selected_objects: x.select_set(False)
    c.select_set(True); bpy.context.view_layer.objects.active = c
    path = os.path.join(D_STL, f"NAS_v6d_{key}.stl")
    bpy.ops.wm.stl_export(filepath=path, export_selected_objects=True, global_scale=1000.0, apply_modifiers=True, ascii_format=False)
    v, nm = vol_cm3(c)
    size = [(hi - lo)[i] * 1000 for i in range(3)]
    info["parts"][key] = {"stl": os.path.basename(path), "volume_cm3": round(v, 2), "mass_g_solid_PLA": round(v * 1.24, 1),
                          "print_size_mm": [round(s, 1) for s in size], "non_manifold_edges": nm, "faces": len(c.data.polygons)}
    print("STL", key, info["parts"][key])

# 2. all numbers for the drawings
info["dims"] = {
    "W": W, "D": D, "HB": HB, "T": T, "TD": TD, "crown_plate": 1.6, "fin_h": FIN_H, "total_h": LEG_H + HB + 1.6 + FIN_H,
    "leg_h": LEG_H, "leg_arm": LEG_ARM, "leg_w": LEG_W, "leg_block": LEG_BLOCK, "leg_pin_d": LEG_PIN_D, "leg_pin_hole": LEG_PIN_HOLE,
    "leg_pin_h": LEG_PIN_H, "leg_screws": [list(p) for p in LEG_SCREWS], "leg_pins": [list(p) for p in LEG_PINS], "leg_nut_af": LEG_NUT_AF,
    "leg_nut_depth": LEG_NUT_DEPTH, "leg_screw_d": LEG_SCREW_D, "guide_bands": [list(b) for b in GUIDE_BANDS],
    "inner": [XI0, XI1, YI0, YI1], "drv_zb": DRV_ZB, "drv_zt": DRV_ZT, "drv_x0": DRV_X0, "drv_w": SSD[1], "drv_t": list(DRV_T), "drv_yl": list(DRV_YL),
    "scr_x0": SCR_X0, "scr_z0": SCR_Z0, "scr_L": SCR["L"], "scr_H": SCR["H"], "scr_cx": SCR_CX, "scr_cz": SCR_CZ, "scr_win": [75.4, 51.0],
    "win": list(WIN), "logo_c": list(LOGO_C), "logo_h": LOGO_H, "logo_depth": LOGO_DEPTH,
    "usbc": list(USBC), "usbc_win": [8.2, 14.0], "dcin": list(DCIN), "dcin_d": 7.0,
    "door_screws": [list(p) for p in DOOR_SCREWS], "pi_holes": [list(p) for p in PI_HOLES_W], "pi_y": PY, "pxv0": PXV0, "pz0": PZ0,
    "eth_hole": [PXV0 - 10.2 - 7.0, PZ0 + 88.0 + 39.0, 14.0, 11.0],
    "hub": [HUB_X0, HUB_Y0, HUB_ZB, HUB_L, HUB_T, HUB_W], "hub_ports": HUB_PORTS, "hub_pw": HUB_PW,
    "pegs": [list(p) for p in PEGS], "fin_x": [SCR_CX - 24 + 12 * k for k in range(5)],
}

# 3. collections, GLB and the .blend with packed textures
def coll(name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in sc.collection.children]: sc.collection.children.link(c)
    return c
def to_collection(objs, cname):
    c = coll(cname)
    for o in objs:
        for u in list(o.users_collection): u.objects.unlink(o)
        c.objects.link(o)
printed_set = [body, door, crown] + legs + door_hw
bought_roots = [pi, scr, hub] + hdds + heads + pi_nuts + leg_hw
bought = [x for r in bought_roots for x in tree(r)]
to_collection(printed_set, "1_PRINTED_PARTS_assembled")
to_collection(bought, "2_BOUGHT_PARTS")
to_collection(plugs + cables + eth + pwr, "3_CABLES")
to_collection(list(print_objs.values()) + [legs_cluster], "4_PRINT_ORIENTATION_like_the_STL")
studio = [o for o in sc.objects if o.name in ENV_NAMES or o.type in ("LIGHT", "CAMERA")]
to_collection(studio, "5_STUDIO_desk_lights")
for o in print_objs.values(): o.location.x += M(400)                       # park the print copies beside the assembly
for x in bpy.context.selected_objects: x.select_set(False)
for o in printed_set + bought: o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(D_3D, "NAS_v6d_assembly.glb"), use_selection=True, export_format="GLB", export_apply=True)
for o in print_objs.values(): o.location.x -= M(400)

# 4. workbench ortho views for the drawings
def set_visible(objs):
    keep = set()
    for o in objs: keep |= {x.name for x in tree(o)}
    for o in sc.objects:
        if o.type in ("MESH", "CURVE"): o.hide_render = o.name not in keep
cam = bpy.data.objects.new("bp_cam", bpy.data.cameras.new("bp_cam")); sc.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.clip_start = 0.001; cam.data.clip_end = 10.0; sc.camera = cam
VIEWDEF = {  # camera rotation, axis map world -> (u, v), camera offset direction
    "front": ((math.pi / 2, 0, 0), lambda p: (p[0], p[2]), (0, -1, 0)),
    "back":  ((math.pi / 2, 0, math.pi), lambda p: (-p[0], p[2]), (0, 1, 0)),
    "right": ((math.pi / 2, 0, math.pi / 2), lambda p: (p[1], p[2]), (1, 0, 0)),
    "left":  ((math.pi / 2, 0, -math.pi / 2), lambda p: (-p[1], p[2]), (-1, 0, 0)),
    "top":   ((0, 0, 0), lambda p: (p[0], p[1]), (0, 0, 1)),
}
def wb_setup():
    sc.render.engine = "BLENDER_WORKBENCH"; s = sc.display.shading
    s.light = "STUDIO"; s.color_type = "SINGLE"; s.single_color = (0.82, 0.83, 0.85)
    s.show_object_outline = True; s.object_outline_color = (0, 0, 0); s.show_cavity = True; s.cavity_type = "BOTH"
    s.show_shadows = False; s.show_specular_highlight = False
    sc.render.film_transparent = True; sc.view_settings.view_transform = "Standard"; sc.view_settings.look = "None"
    sc.render.resolution_x = sc.render.resolution_y = 2000; sc.render.resolution_percentage = 100
views_meta = {}
def ortho(name, objs, view, pad=1.18):
    bpy.context.view_layer.update()
    set_visible(objs)
    rot, uv, off = VIEWDEF[view]
    pts = []
    for o in objs:
        for x in tree(o):
            if x.type in ("MESH", "CURVE") and not x.hide_render:
                pts += [x.matrix_world @ Vector(c) for c in x.bound_box]
    pts_mm = [(p.x * 1000, p.y * 1000, p.z * 1000) for p in pts]
    us = [uv(p)[0] for p in pts_mm]; vs = [uv(p)[1] for p in pts_mm]
    uc, vc = (min(us) + max(us)) / 2, (min(vs) + max(vs)) / 2
    S = max(max(us) - min(us), max(vs) - min(vs)) * pad
    c3 = [(min(p[i] for p in pts_mm) + max(p[i] for p in pts_mm)) / 2 for i in range(3)]
    cam.rotation_euler = rot; cam.data.ortho_scale = S / 1000
    cam.location = Vector(tuple(M(c3[i] + off[i] * 1500) for i in range(3)))
    sc.render.filepath = os.path.join(D_IMG, f"bp_{name}_{view}.png"); bpy.ops.render.render(write_still=True)
    views_meta[f"{name}_{view}"] = {"file": f"bp_{name}_{view}.png", "u": [uc - S / 2, uc + S / 2], "v": [vc - S / 2, vc + S / 2]}
wb_setup()
ASM = [body, door, crown, pi, scr, hub] + hdds + heads + legs
for v in ("front", "right", "back", "top"): ortho("assembly", ASM, v)
for v in ("front", "right", "left", "back", "top"): ortho("body", [body], v)
for v in ("back", "front", "right"): ortho("door", [door], v)
for v in ("top", "front", "right"): ortho("crown", [crown], v)
for v in ("top", "front"): ortho("legs", [print_objs["D_legs_x4"]], v, pad=1.25)
# print plate layout (top view) with the print copies placed on a 256 x 256 plate
PLATE = {"B_back_door": (-70.0, 0.0), "A_body": (55.0, 52.0), "C_crown": (55.0, -52.0), "D_legs_x4": (117.0, 0.0)}
for k, (px, py) in PLATE.items(): print_objs[k].location = (M(px), M(py), 0)
ortho("plate", list(print_objs.values()), "top", pad=1.02)
info["plate"] = {k: list(v) for k, v in PLATE.items()}
info["views"] = views_meta
for k, o in print_objs.items():
    lo, hi = bbox_mm(o); info["parts"][k]["plate_bbox_mm"] = [lo, hi]

# 5. Cycles views: each part alone in print orientation, and the full plate
for o in sc.objects:
    if o.type in ("MESH", "CURVE"): o.hide_render = True
for o in sc.objects:
    if o.name in ENV_NAMES: o.hide_render = False
sc.render.film_transparent = False
def beauty(name, objs, cam_loc, target, lens=50, res=(1600, 1100)):
    for o in sc.objects:
        if o.type in ("MESH", "CURVE") and o.name not in ENV_NAMES and not o.name.startswith("buildplate"): o.hide_render = True
    for o in objs: o.hide_render = False
    camera(cam_loc, target, lens=lens, fstop=None); render(f"pkg_{name}", res=res)
    shutil.copyfile(os.path.join(OUT, f"pkg_{name}.png"), os.path.join(D_IMG, f"pkg_{name}.png"))
bp = box("buildplate", -128, -128, 0.0, 256, 256, 1.2, mat("pei_textured", (0.03, 0.03, 0.032), rough=0.85), r=4.0)
n = bp.active_material.node_tree; b = n.nodes["Principled BSDF"]
nz = n.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2500
bm_ = n.nodes.new("ShaderNodeBump"); bm_.inputs["Strength"].default_value = 0.15
n.links.new(nz.outputs["Fac"], bm_.inputs["Height"]); n.links.new(bm_.outputs["Normal"], b.inputs["Normal"])
for k, (px, py) in PLATE.items(): print_objs[k].location = (M(px), M(py), M(1.2))
beauty("plate", list(print_objs.values()) + [bp], (260, -420, 420), (0, 0, 40), lens=40)
for k, o in print_objs.items(): o.location = (0, 0, 0)
bp.hide_render = True
beauty("A_body_print", [print_objs["A_body"]], (230, -300, 260), (0, 0, 95), lens=50, res=(1100, 1100))
beauty("B_back_door_print", [print_objs["B_back_door"]], (220, -260, 260), (0, 0, 4), lens=50, res=(1100, 1100))
beauty("C_crown_print", [print_objs["C_crown"]], (160, -200, 170), (0, 0, 6), lens=50, res=(1100, 1100))
beauty("D_legs_x4_print", [print_objs["D_legs_x4"]], (70, -110, 90), (0, 0, 2), lens=50, res=(1100, 1100))

# 6. save
for o in print_objs.values(): o.location.x += M(400)
sc.render.engine = "CYCLES"; sc.render.film_transparent = False
for o in sc.objects: o.hide_render = False
for o in plugs + cables + eth + pwr: o.hide_render = False
bp.hide_render = True; cam.hide_render = True
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(D_BL, "NAS_v6d_assembly.blend"), compress=True)
json.dump(info, open(os.path.join(D_IMG, "dims.json"), "w"), indent=1)
print("EXPORT DONE", PKG)
