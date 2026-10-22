# Moves a binary STL so its bounding box is centred on (x, y). The OrcaSlicer command line refuses to slice a part that
# is not fully on the bed ("Nothing to be sliced"), and the STL files are centred on 0, 0.
# Usage: python shift_stl.py <in.stl> <out.stl> <x> <y>
import sys
import numpy as np

src, dst, x, y = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
b = open(src, "rb").read()
n = np.frombuffer(b[80:84], "<u4")[0]
dt = np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
t = np.frombuffer(b[84:84 + n * 50], dt).copy()
v = t["v"]
v[:, :, 0] += x - (v[:, :, 0].min() + v[:, :, 0].max()) / 2
v[:, :, 1] += y - (v[:, :, 1].min() + v[:, :, 1].max()) / 2
open(dst, "wb").write(b[:84] + t.tobytes())
