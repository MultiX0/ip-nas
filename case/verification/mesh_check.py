# Checks the 4 STL files and the 3MF plate: size, volume, solid PLA weight, open edges, and that every part of the 3MF
# sits inside the 256 x 256 bed. Needs numpy.
# Usage: python verification/mesh_check.py [print_package folder]
import os, re, struct, sys, zipfile
import xml.etree.ElementTree as ET
import numpy as np

PKG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "print_package")
STL_DIR = os.path.join(PKG, "01_PRINT_FILES_STL")
PARTS = ["A_body", "B_back_door", "C_crown", "D_legs_x4"]
NS = {"m": "http://schemas.microsoft.com/3dmanufacturing/core/2015/02",
      "p": "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"}


def read_stl(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[80:84])[0]
    if len(b) != 84 + 50 * n:
        sys.exit(f"{path}: not a binary STL")
    dt = np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    return np.frombuffer(b[84:84 + 50 * n], dt)["v"].astype(np.float64)


def stats(tris):
    """Bounding box, volume, open edges and zero-area triangles of a triangle soup (vertices welded on a 0.0001 mm grid)."""
    v = tris.reshape(-1, 3)
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    vol = np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0
    _, inv = np.unique(np.round(v / 1e-4).astype(np.int64), axis=0, return_inverse=True)
    f = inv.reshape(-1, 3)
    flat = (f[:, 0] == f[:, 1]) | (f[:, 1] == f[:, 2]) | (f[:, 0] == f[:, 2])
    f = f[~flat]                                  # slicers drop zero-area triangles when they load the file
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    _, cnt = np.unique(e, axis=0, return_counts=True)
    return v.min(0), v.max(0), vol, int((cnt != 2).sum()), int(flat.sum())


def matrix(s):
    a = [float(x) for x in s.split()]
    m = np.eye(4); m[:3, :3] = np.array(a[:9]).reshape(3, 3); m[3, :3] = a[9:12]
    return m


print("STL files (mm)")
size = {}
for p in PARTS:
    lo, hi, vol, open_edges, flat = stats(read_stl(os.path.join(STL_DIR, f"NAS_v6d_{p}.stl")))
    size[p] = hi - lo
    print(f"  {p:12s} {size[p][0]:6.1f} x {size[p][1]:6.1f} x {size[p][2]:6.1f}   {vol / 1000:6.2f} cm3   "
          f"solid PLA {vol / 1000 * 1.24:5.1f} g   open edges {open_edges}   zero-area triangles {flat}")

print("3MF plate (256 x 256)")
z = zipfile.ZipFile(os.path.join(STL_DIR, "NAS_v6d_plate_Bambu_X1C_PLA.3mf"))
root = ET.fromstring(z.read("3D/3dmodel.model"))
comp = {}
for o in root.find("m:resources", NS).findall("m:object", NS):
    c = o.find("m:components", NS).find("m:component", NS)
    comp[o.get("id")] = (c.get("{%s}path" % NS["p"]), matrix(c.get("transform")))
ok = True
for it in root.find("m:build", NS).findall("m:item", NS):
    path, ct = comp[it.get("objectid")]
    mesh = ET.fromstring(z.read(path.lstrip("/"))).find("m:resources", NS).find("m:object", NS).find("m:mesh", NS)
    vs = np.array([[float(v.get(k)) for k in "xyz"] for v in mesh.find("m:vertices", NS)])
    w = (np.c_[vs, np.ones(len(vs))] @ ct @ matrix(it.get("transform")))[:, :3]
    lo, hi = w.min(0), w.max(0)
    name = re.search(r"NAS_v6d_(\w+?)\.stl", path).group(1)
    same = np.allclose(np.sort(hi - lo), np.sort(size[name]), atol=0.02)
    inside = lo[0] >= 0 and lo[1] >= 0 and hi[0] <= 256 and hi[1] <= 256 and abs(lo[2]) < 0.01
    ok &= same and inside
    print(f"  {name:12s} x {lo[0]:5.1f}..{hi[0]:5.1f}  y {lo[1]:5.1f}..{hi[1]:5.1f}  z {lo[2]:4.1f}..{hi[2]:5.1f}   "
          f"same size as the STL: {'yes' if same else 'NO'}   on the bed: {'yes' if inside else 'NO'}")
info = {m.group(1): m.group(2) for m in re.finditer(r'key="(\w+)" value="([^"]*)"', z.read("Metadata/slice_info.config").decode())}
print(f"  sliced in the project: {info.get('weight')} g, {int(info.get('prediction', 0)) // 60} min with the start-up, supports used: {info.get('support_used')}")
print("MESH CHECK", "OK" if ok else "FAILED")
