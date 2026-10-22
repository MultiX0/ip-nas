# Builds the 3 profiles in orca_profiles/ from an OrcaSlicer install. The command line needs flat profiles: this resolves
# the "inherits" chains, marks them as system profiles (without that OrcaSlicer says the process is not compatible with the
# printer) and applies the case settings to the process.
# Usage: python orca_flatten.py <OrcaSlicer>/resources/profiles/BBL [out folder, default orca_profiles]
import glob, json, os, sys

MACHINE, PROCESS, FILAMENT = "Bambu Lab X1 Carbon 0.4 nozzle", "0.20mm Standard @BBL X1C", "Bambu PLA Basic @BBL X1C"
CASE_SETTINGS = {"layer_height": "0.2", "initial_layer_print_height": "0.2", "wall_loops": "4", "top_shell_layers": "5",
                 "bottom_shell_layers": "5", "sparse_infill_density": "15%", "sparse_infill_pattern": "gyroid",
                 "enable_support": "0", "brim_type": "no_brim"}
root = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "orca_profiles")
os.makedirs(out, exist_ok=True)
idx = {}
for f in glob.glob(os.path.join(root, "**", "*.json"), recursive=True):
    try: d = json.load(open(f, encoding="utf-8"))
    except (ValueError, UnicodeDecodeError): continue      # a few files in the profile folders are not profiles
    if isinstance(d, dict) and "name" in d: idx.setdefault((d.get("type"), d["name"]), f); idx.setdefault((None, d["name"]), f)
def load(name, typ):
    f = idx.get((typ, name)) or idx.get((None, name)); d = json.load(open(f, encoding="utf-8"))
    if d.get("inherits"):
        base = load(d["inherits"], typ); base.update(d); d = base
    return d
for typ, name, fn in (("machine", MACHINE, "machine.json"), ("process", PROCESS, "process.json"), ("filament", FILAMENT, "filament.json")):
    d = load(name, typ); d.pop("inherits", None); d["from"] = "system"; d["is_custom_defined"] = "1"
    if typ == "process": d.update(CASE_SETTINGS)
    json.dump(d, open(os.path.join(out, fn), "w"), indent=1); print(fn, d.get("name"))
