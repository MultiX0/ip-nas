#!/usr/bin/env bash
# Slices the case with OrcaSlicer and the Bambu Lab X1 Carbon profile (orca_profiles/) and prints the filament weight,
# the print time, max_cantilever_dist (0 = nothing floating) and OrcaSlicer's slicing warnings.
# Usage: ORCA=/path/to/orca-slicer ./orca_check.sh [folder with the STL files]           each part on its own
#        ORCA=/path/to/orca-slicer ./orca_check.sh --plate [folder with the STL files]   all 4 arranged on one plate,
#                                                         saved as NAS_v6d_plate_Bambu_X1C_PLA.3mf (that is how I made it)
# Needs python with numpy (shift_stl.py). Output goes to a temp folder.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PLATE=0
if [ "${1:-}" = "--plate" ]; then PLATE=1; shift; fi
STL_DIR="$(cd "${1:-$HERE/../print_package/01_PRINT_FILES_STL}" && pwd)"
ORCA="${ORCA:-orca-slicer}"
PY="${PYTHON:-$(command -v python || command -v python3)}"
PROF="$HERE/orca_profiles"
OUT="$(mktemp -d)"
PARTS="A_body B_back_door C_crown D_legs_x4"
stl_of() { if [ -f "$STL_DIR/NAS_v6d_$1.stl" ]; then echo "$STL_DIR/NAS_v6d_$1.stl"; else echo "$STL_DIR/$1.stl"; fi; }

report() {  # $1 = label, $2 = folder with 00000.log and plate_1.gcode
  w=$(grep -iE "slicing warnings|slicing errors|seems object|critical" "$2/00000.log" | head -3)
  g=$(grep -m1 -E "^; filament used \[g\]" "$2/plate_1.gcode" | sed 's/.*= //')
  t=$(grep -m1 -E "^; model printing time" "$2/plate_1.gcode" | sed -e 's/^; model printing time: //' -e 's/;.*//')
  c=$(grep -m1 "max_cantilever_dist" "$2/00000.log")
  echo "$1: ${g:-?} g, ${t:-?}, ${c:-max_cantilever_dist ?}, warnings: ${w:-none}"
}

if [ "$PLATE" = 1 ]; then
  # plain file names in the working folder, so the objects in the 3MF get clean names
  for p in $PARTS; do cp "$(stl_of "$p")" "$OUT/NAS_v6d_$p.stl"; done
  cd "$OUT"
  timeout 400 "$ORCA" --debug 3 --arrange 1 --slice 0 --load-settings "$PROF/machine.json;$PROF/process.json" \
    --load-filaments "$PROF/filament.json" --outputdir "$OUT" --export-3mf NAS_v6d_plate_Bambu_X1C_PLA.3mf \
    NAS_v6d_A_body.stl NAS_v6d_B_back_door.stl NAS_v6d_C_crown.stl NAS_v6d_D_legs_x4.stl > /dev/null 2>&1
  echo "exit code $?"
  report "full plate" "$OUT"
else
  for p in $PARTS; do
    mkdir -p "$OUT/$p" && cd "$OUT/$p"
    "$PY" "$HERE/shift_stl.py" "$(stl_of "$p")" "$OUT/$p/$p.stl" 128 128
    # with --debug, OrcaSlicer writes its log (00000.log) into the current folder
    timeout 400 "$ORCA" --debug 3 --slice 0 --load-settings "$PROF/machine.json;$PROF/process.json" \
      --load-filaments "$PROF/filament.json" --outputdir "$OUT/$p" "$OUT/$p/$p.stl" > /dev/null 2>&1
    report "$p (exit code $?)" "$OUT/$p"
  done
fi
echo "Output: $OUT"
