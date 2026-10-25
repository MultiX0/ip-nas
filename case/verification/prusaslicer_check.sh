#!/usr/bin/env bash
# Slices the 4 case parts with PrusaSlicer (the settings in prusaslicer_settings.txt, supports off, no brim) and prints
# the filament weight, the print time and PrusaSlicer's "print stability issues" warning for each part.
# Usage: PRUSA=/path/to/prusa-slicer-console ./prusaslicer_check.sh [folder with the STL files]
# The default folder is ../print_package/01_PRINT_FILES_STL; the stl view of the generator (out/stl) works too.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
STL_DIR="${1:-$HERE/../print_package/01_PRINT_FILES_STL}"
PRUSA="${PRUSA:-prusa-slicer-console}"
OUT="$(mktemp -d)"
SETTINGS="$(cat "$HERE/prusaslicer_settings.txt")"
for p in A_body B_back_door C_crown D_legs_x4; do
  stl="$STL_DIR/NAS_v6d_$p.stl"
  [ -f "$stl" ] || stl="$STL_DIR/$p.stl"
  # $SETTINGS is a list of options, so it is left unquoted on purpose
  "$PRUSA" --export-gcode $SETTINGS --brim-width 0 --output "$OUT/$p.gcode" "$stl" > "$OUT/$p.log" 2>&1
  w=$(grep -A3 "stability issues" "$OUT/$p.log" | sed -n 4p)
  g=$(grep -m1 -E "^; filament used \[g\]" "$OUT/$p.gcode" | sed 's/.*= //')
  t=$(grep -m1 -E "^; estimated printing time \(normal mode\)" "$OUT/$p.gcode" | sed 's/.*= //')
  echo "$p: ${g:-?} g, ${t:-?}, warnings: ${w:-none}"
done
echo "G-code and logs: $OUT"
