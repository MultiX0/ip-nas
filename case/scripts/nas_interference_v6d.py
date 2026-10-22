# Fit check for the v6d case. Runs inside nas_scene_v6d.py (view "clash") after the model is built.
# 1. Clash: every printed part against every other part and every bought part in the assembled position (BVH triangle
#    overlap on the evaluated meshes). 2. Sweep: each bought part slides out along the path it goes in by, and must not
#    touch the body on the way.
import bpy, bmesh, os
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

def meshes(o):
    out = []
    def walk(x):
        if x.type == "MESH": out.append(x)
        for ch in x.children: walk(ch)
    walk(o); return out

dg = bpy.context.evaluated_depsgraph_get()
INSET = float(os.environ.get("NAS_INSET", "0.15")) * 0.001     # every surface pulled in by this (m): touching faces no longer count
def bvh(o):
    oe = o.evaluated_get(dg); me = oe.to_mesh(); bm = bmesh.new(); bm.from_mesh(me); bm.transform(o.matrix_world)
    bm.normal_update()
    for v in bm.verts: v.co -= v.normal * INSET
    verts = [v.co.copy() for v in bm.verts]; polys = [tuple(x.index for x in f.verts) for f in bm.faces]
    bm.free(); oe.to_mesh_clear(); return BVHTree.FromPolygons(verts, polys, epsilon=0.0)

GROUPS = {"A body": [body], "B door": [door], "C crown": [crown]}
for i, lg in enumerate(legs): GROUPS[f"D leg {i + 1}"] = [lg]
BOUGHT = {"Pi 5": meshes(pi), "screen": meshes(scr), "hub": meshes(hub)}
for i, h in enumerate(hdds): BOUGHT[f"HDD {i + 1}"] = meshes(h)
for i, h in enumerate(heads): BOUGHT[f"UGREEN head {i + 1}"] = meshes(h)
BOUGHT["Pi M2.5 nuts"] = pi_nuts; BOUGHT["door M3 screws"] = door_hw; BOUGHT["leg M3 screws+nuts"] = leg_hw
# contacts that are meant to be there (a part rests on or is clamped by the other): reported, but not as clashes
INTENDED = {("B door", "Pi 5"), ("B door", "Pi M2.5 nuts"), ("B door", "door M3 screws"), ("A body", "door M3 screws"),
            ("A body", "leg M3 screws+nuts"), ("A body", "D leg 1"), ("A body", "D leg 2"), ("A body", "D leg 3"), ("A body", "D leg 4"),
            ("A body", "B door"), ("A body", "C crown"), ("A body", "screen"), ("A body", "HDD 1"), ("A body", "HDD 2"),
            ("A body", "hub"), ("C crown", "hub"), ("Pi 5", "Pi M2.5 nuts"),
            ("D leg 1", "leg M3 screws+nuts"), ("D leg 2", "leg M3 screws+nuts"), ("D leg 3", "leg M3 screws+nuts"), ("D leg 4", "leg M3 screws+nuts"),
            ("HDD 1", "UGREEN head 1"), ("HDD 2", "UGREEN head 2")}
trees = {}
for k, objs in list(GROUPS.items()) + list(BOUGHT.items()):
    trees[k] = [(o.name, bvh(o)) for o in objs]
keys = list(trees)
clashes, contacts = [], []
for i in range(len(keys)):
    for j in range(i + 1, len(keys)):
        a, b = keys[i], keys[j]
        if a not in GROUPS and b not in GROUPS:
            # bought vs bought: only the pairs that could meet inside the case
            if not ({a, b} & {"hub", "screen"} or ("UGREEN" in a and "UGREEN" in b) or {a, b} == {"Pi 5", "UGREEN head 2"}): continue
        hits = 0; who = set()
        for na, ta in trees[a]:
            for nb, tb in trees[b]:
                n = len(ta.overlap(tb)); hits += n
                if n: who.add(f"{na.split('.')[0]}/{nb.split('.')[0]}")
        if hits:
            print(f"    detail {a} x {b}: {sorted(who)[:6]}")
            (contacts if (a, b) in INTENDED or (b, a) in INTENDED else clashes).append((a, b, hits))
print("CLASH CHECK")
for a, b, n in clashes: print(f"  CLASH   {a} x {b}: {n} triangle pairs")
for a, b, n in contacts: print(f"  contact {a} x {b}: {n} (intended)")
print(f"CLASH TOTAL {len(clashes)}")

def moved_tree(objs, dx, dy, dz):
    out = []
    for o in objs:
        oe = o.evaluated_get(dg); me = oe.to_mesh(); bm = bmesh.new(); bm.from_mesh(me)
        bm.transform(Matrix.Translation(Vector((dx * 0.001, dy * 0.001, dz * 0.001))) @ o.matrix_world); bm.normal_update()
        for v in bm.verts: v.co -= v.normal * INSET
        out.append(BVHTree.FromPolygons([v.co.copy() for v in bm.verts], [tuple(x.index for x in f.verts) for f in bm.faces], epsilon=0.0))
        bm.free(); oe.to_mesh_clear()
    return out
body_t = trees["A body"][0][1]
def sweep(label, objs, axis, dist, step=3.0):
    worst = None
    n = int(dist / step) + 1
    for i in range(1, n + 1):
        d = min(i * step, dist)
        dx, dy, dz = (d if axis == "x" else 0), (d if axis == "y" else 0), (d if axis == "z" else 0)
        ts = moved_tree(objs, dx, dy, dz); per = [len(t.overlap(body_t)) for t in ts]; hits = sum(per)
        if hits:
            worst = (d, hits); print("     hit by:", sorted({objs[k].name for k, n in enumerate(per) if n})[:8])
            pairs = [pr for k, t in enumerate(ts) for pr in t.overlap(body_t)][:400]
            bm2 = bmesh.new(); oe = body.evaluated_get(dg); me = oe.to_mesh(); bm2.from_mesh(me); bm2.transform(body.matrix_world); bm2.faces.ensure_lookup_table()
            cs = [bm2.faces[j].calc_center_median() for _, j in pairs]
            if cs: print("     body faces hit around x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f (at the moved position)" % (
                min(c.x for c in cs) * 1000, max(c.x for c in cs) * 1000, min(c.y for c in cs) * 1000, max(c.y for c in cs) * 1000,
                min(c.z for c in cs) * 1000, max(c.z for c in cs) * 1000))
            bm2.free(); oe.to_mesh_clear(); break
    print(f"  SWEEP {label}: " + ("free path" if worst is None else f"HITS the body {worst[0]:.0f} mm along +{axis} ({worst[1]} pairs)"))
    return worst is None
print("SWEEP CHECK (part slid out along its assembly path; inset", INSET * 1000, "mm)")
ok = [sweep("screen  (slides down from the top)", meshes(scr), "z", HB + 10 - SCR_Z0),
      sweep("drive 1 + head (drops in from the top)", meshes(hdds[0]) + meshes(heads[0]), "z", HB + 10 - (DRV_ZB - HEAD_L)),
      sweep("drive 2 + head (drops in from the top)", meshes(hdds[1]) + meshes(heads[1]), "z", HB + 10 - (DRV_ZB - HEAD_L)),
      sweep("hub (drops onto its ledges)", meshes(hub), "z", HB + 10 - HUB_ZB),
      sweep("Pi + door + plugged USB/Ethernet (closes from the back)", meshes(pi) + [door] + plugs[:4] + eth[:2], "y", 60.0)]
print(f"SWEEP TOTAL {ok.count(False)} blocked")
