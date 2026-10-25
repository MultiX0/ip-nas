# A4 print-shop instructions for the v6d case (reportlab). Numbers come from <package>/_build/dims.json (Blender export)
# and <package>/_build/slicer.json (copied from verification/results/); the pictures from <package>/05_RENDERS/.
# Usage: python scripts/nas_instructions_v6d.py [package folder, default out/]
import json, os, re, sys
from PIL import Image as PILImage
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, Image, PageBreak

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "out")
B = os.path.join(PKG, "_build"); R = os.path.join(PKG, "05_RENDERS")
INFO = json.load(open(os.path.join(B, "dims.json"))); SL = json.load(open(os.path.join(B, "slicer.json")))
P = INFO["parts"]; DATE = "2026-10-17"; PRICE = 0.12
INK = colors.HexColor("#111111"); GREY = colors.HexColor("#5b6068"); LINE = colors.HexColor("#c9ced6")
LIME = colors.HexColor("#ccff00"); OLIVE = colors.HexColor("#4f6e00"); WARN = colors.HexColor("#fff4d6")

st = {
    "h1": ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=22, leading=26, textColor=INK, spaceAfter=4),
    "sub": ParagraphStyle("sub", fontName="Helvetica", fontSize=11, leading=14, textColor=GREY, spaceAfter=10),
    "h2": ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=14, leading=18, textColor=INK, spaceBefore=4, spaceAfter=6),
    "h3": ParagraphStyle("h3", fontName="Helvetica-Bold", fontSize=10.5, leading=13, textColor=INK, spaceBefore=6, spaceAfter=3),
    "b": ParagraphStyle("b", fontName="Helvetica", fontSize=9.3, leading=12.6, textColor=INK, spaceAfter=4),
    "sm": ParagraphStyle("sm", fontName="Helvetica", fontSize=8, leading=10.5, textColor=GREY),
    "cell": ParagraphStyle("cell", fontName="Helvetica", fontSize=8.6, leading=10.8, textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="Helvetica-Bold", fontSize=8.6, leading=10.8, textColor=INK),
    "big": ParagraphStyle("big", fontName="Helvetica-Bold", fontSize=17, leading=20, textColor=INK),
    "lab": ParagraphStyle("lab", fontName="Helvetica", fontSize=7.8, leading=9.5, textColor=GREY),
}
def p(t, s="b"): return Paragraph(t, st[s])
def c(t, bold=False): return Paragraph(t, st["cellb" if bold else "cell"])

def img(path, w):
    im = PILImage.open(path); h = w * im.size[1] / im.size[0]; return Image(path, width=w, height=h)

def table(rows, widths, head=True, zebra=True, extra=None):
    t = Table(rows, colWidths=widths, repeatRows=1 if head else 0)
    style = [("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
             ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4), ("LEFTPADDING", (0, 0), (-1, -1), 5)]
    if head: style += [("BACKGROUND", (0, 0), (-1, 0), INK), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white), ("LINEBELOW", (0, 0), (-1, 0), 1.2, LIME)]
    if zebra:
        for i in range(1 if head else 0, len(rows)):
            if i % 2 == 0: style.append(("BACKGROUND", (0, i), (-1, i), colors.HexColor("#f4f5f7")))
    t.setStyle(TableStyle(style + (extra or []))); return t

def hcell(t): return Paragraph(f"<font color='white'><b>{t}</b></font>", st["cell"])

def box(flow, bg=WARN, border=colors.HexColor("#e0b84a")):
    t = Table([[flow]], colWidths=[174 * mm]); t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), bg), ("BOX", (0, 0), (-1, -1), 0.6, border),
                                                                    ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                                                                    ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    return t

def deco(canv, doc):
    canv.saveState(); w, h = A4
    canv.setFillColor(INK); canv.rect(0, h - 11 * mm, w, 11 * mm, stroke=0, fill=1)
    canv.setFillColor(LIME); canv.rect(0, h - 11.8 * mm, w, 0.8 * mm, stroke=0, fill=1)
    canv.setFillColor(colors.white); canv.setFont("Helvetica-Bold", 9); canv.drawString(18 * mm, h - 7 * mm, "IP NAS ENCLOSURE v6d, PRINT PACKAGE")
    canv.setFont("Helvetica", 8.5); canv.drawRightString(w - 18 * mm, h - 7 * mm, f"Rev v6d, {DATE}")
    canv.setFillColor(GREY); canv.setFont("Helvetica", 7.5)
    canv.drawString(18 * mm, 10 * mm, "All dimensions in mm. Weights: PrusaSlicer 2.9.6; times: OrcaSlicer 2.4.2, Bambu X1C profile. Both on the supplied files.")
    canv.drawRightString(w - 18 * mm, 10 * mm, f"Page {doc.page}")
    canv.restoreState()

doc = BaseDocTemplate(os.path.join(PKG, "02_DOCUMENTS", "NAS_v6d_01_Print_Instructions_A4.pdf"), pagesize=A4,
                      leftMargin=18 * mm, rightMargin=18 * mm, topMargin=18 * mm, bottomMargin=16 * mm,
                      title="IP NAS Enclosure v6d, Print Instructions", author="IP NAS project")
doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(18 * mm, 16 * mm, A4[0] - 36 * mm, A4[1] - 34 * mm, id="f")], onPage=deco)])
S = []
tot_g = SL["total_g"]; cost = tot_g * PRICE
def hm(t):
    m = re.findall(r"(\d+)([hms])", t); return sum(int(v) * {"h": 60, "m": 1, "s": 1 / 60}[u] for v, u in m)
tmin = hm(SL["orca_plate"]["time"])                       # Bambu X1C profile, whole plate (Orca)
ttxt = f"{int(tmin // 60)} h {int(round(tmin % 60))} min"
KEYS = ("A_body", "B_back_door", "C_crown", "D_legs_x4")

# cover
S += [p("IP NAS Enclosure v6d", "h1"), p("Print package for the print shop: 4 parts, PLA black, one plate, no supports, 0 slicer warnings", "sub"),
      img(os.path.join(R, "v6d_A_hero.png"), 174 * mm), Spacer(1, 6 * mm)]
kp = [[p(f"{tot_g:.1f} g", "big"), p(f"{cost:.2f} JOD", "big"), p(ttxt, "big"), p("0", "big")],
      [p("total filament (slicer)", "lab"), p(f"at {PRICE:.2f} JOD per gram", "lab"), p("Bambu X1C estimate, one plate", "lab"), p("slicer warnings", "lab")]]
kt = Table(kp, colWidths=[43.5 * mm] * 4); kt.setStyle(TableStyle([("LINEABOVE", (0, 0), (-1, 0), 1.5, INK), ("TOPPADDING", (0, 0), (-1, -1), 3)]))
S += [kt, Spacer(1, 6 * mm)]
S += [p("What is in this document", "h3"),
      p("1. What to print (parts, files, weights). 2. Exact print settings. 3. Parts in print orientation. "
        "4. Checks after printing. 5. How the parts go together. 6. Files in the package."),
      p("Companion document: <b>NAS_v6d_2D_Blueprints_A3.pdf</b> (5 dimensioned A3 sheets). Print files: folder <b>01_PRINT_FILES_STL</b> "
        "(4 STL files + a ready Bambu Studio / OrcaSlicer project <b>NAS_v6d_plate_Bambu_X1C_PLA.3mf</b>).", "b"),
      PageBreak()]

# 1. what to print
S += [p("1. What to print", "h2"),
      p("Four print files, all in <b>black PLA</b> (the legs file holds all 4 legs). The STL files are already in the correct print "
        "orientation and in millimetres: import them at 100 %, do not rotate, do not scale. Fastest route: open "
        "<b>NAS_v6d_plate_Bambu_X1C_PLA.3mf</b> in Bambu Studio or OrcaSlicer: all parts are already arranged and set up.")]
rows = [[hcell("Part"), hcell("File"), hcell("Print orientation"), hcell("Size on the bed (mm)"), hcell("Filament"), hcell("Time*")]]
names = {"A_body": ("A  Body", "Upright, open top up"), "B_back_door": ("B  Back door", "Flat, outside face down, standoffs up"),
         "C_crown": ("C  Crown", "Flat, plate down, fins up"), "D_legs_x4": ("D  Legs (x4)", "Flat, foot face down, pegs up")}
for k in KEYS:
    sz = " x ".join(f"{v:g}" for v in P[k]["print_size_mm"])
    tt = SL["orca"][k]["time"]; tt = " ".join(x for x in tt.split() if not x.endswith("s"))
    rows.append([c(names[k][0], True), c(P[k]["stl"]), c(names[k][1]), c(sz), c(f"{SL[k]['g']:.1f} g"), c(tt or SL["orca"][k]["time"])])
rows.append([c("TOTAL", True), c("4 files"), c("one 256 x 256 plate"), c(""), c(f"<b>{tot_g:.1f} g</b>"), c(f"<b>{ttxt}</b>")])
S += [table(rows, [24 * mm, 43 * mm, 38 * mm, 30 * mm, 18 * mm, 21 * mm], extra=[("BACKGROUND", (0, 5), (-1, 5), colors.HexColor("#e8f5b8"))]),
      Spacer(1, 2 * mm),
      p(f"* Filament per part from PrusaSlicer 2.9.6 with the settings in section 2 ({SL['total_m']:.1f} m of 1.75 mm). "
        f"Cross-check in OrcaSlicer 2.4.2 with the stock Bambu Lab X1 Carbon profile: {SL['orca_total_g']:.1f} g per part sum, "
        f"{SL['orca_plate']['g']:.1f} g and {SL['orca_plate']['time']} for the whole plate (time column = whole plate, Bambu). "
        f"Cost {tot_g:.1f} g x {PRICE:.2f} JOD = <b>{cost:.2f} JOD</b>. Optional 5 mm brim on the body: total {SL['total_g_brim']:.1f} g.", "sm"),
      Spacer(1, 4 * mm), p("Plate layout (all four files on one 256 x 256 bed)", "h3"),
      img(os.path.join(R, "pkg_plate.png"), 150 * mm),
      p("Any arrangement works. The body is 197.5 mm tall, so the printer needs at least 200 mm of Z height. "
        "A bed smaller than 200 x 200 mm: print the back door (193.4 mm long) on its own plate.", "sm"), PageBreak()]

# 2. settings
S += [p("2. Print settings", "h2"), p("Use the shop's standard PLA profile and set these values. Everything not listed: printer default.")]
cfg = [[hcell("Setting"), hcell("Value"), hcell("Why")],
       [c("Material"), c("<b>PLA, black</b>, 1.75 mm, any good brand"), c("One colour only. No AMS colour changes, no purge waste.")],
       [c("Nozzle / layer height"), c("0.4 mm / <b>0.20 mm</b> (first layer 0.20)"), c("Wall thickness is designed as 1.6 mm = 4 lines.")],
       [c("Walls (perimeters)"), c("<b>4</b>"), c("Walls print solid; no infill inside 1.6 mm walls.")],
       [c("Top / bottom layers"), c("<b>5 / 5</b>"), c("Floor and plates are 1.6 mm = 8 layers.")],
       [c("Infill"), c("<b>15 % gyroid</b>"), c("Only bosses and thick corners get infill.")],
       [c("Supports"), c("<b>OFF</b>"), c("Designed support-free: overhangs are 45 deg or short bridges.")],
       [c("Brim"), c("None. Optional 5 mm on the body only"), c("Body is tall (197.5) on a 100 x 78 footprint. Adds 0.45 g.")],
       [c("Temperatures"), c("Nozzle 210-220 C, bed 55-60 C"), c("Standard PLA.")],
       [c("Cooling / bridges"), c("Part fan 100 % from layer 3; bridge fan 100 %"), c("Needed for the screen window bridge (see below).")],
       [c("Elephant-foot comp."), c("0.15 mm"), c("Keeps the bottom edges and the leg holes true.")],
       [c("Scale / rotation"), c("<b>100 %, as exported</b>"), c("Fits are measured to 0.1 mm; do not scale.")],
       [c("Seam"), c("Aligned, rear"), c("Keeps the front face clean.")]]
S += [table(cfg, [36 * mm, 62 * mm, 76 * mm]), Spacer(1, 4 * mm)]
sc_rows = [[hcell("Part"), hcell("PrusaSlicer 2.9.6"), hcell("OrcaSlicer 2.4.2, Bambu X1C profile"), hcell("Warnings")]]
for k in KEYS:
    sc_rows.append([c(names[k][0], True), c(f"{SL[k]['g']:.1f} g, {SL[k]['time']}"), c(f"{SL['orca'][k]['g']:.1f} g, {SL['orca'][k]['time']}"), c("<b>none</b>")])
sc_rows.append([c("Whole plate", True), c(""), c(f"{SL['orca_plate']['g']:.1f} g, {SL['orca_plate']['time']}"), c("<b>none</b>")])
S += [box([p("<b>Slicer check, done before delivery: 0 warnings</b>", "b"),
           p("Every file was sliced with supports OFF in two slicers. PrusaSlicer's stability check (floating anchors, long bridges, "
             "thin fragile parts) and Orca/Bambu's support check (floating regions, cantilevers) report <b>nothing</b> on any part "
             "or on the full plate. Overhangs are 45 deg or steeper; the screen window top (75.4 mm) is a normal bridge both slicers accept."),
           p("<b>Fit check, done before delivery: 0 collisions, 5 of 5 assembly paths free.</b> In the 3D model every printed part was "
             "tested against every other part and every bought part (Pi 5, both drives with their USB-SATA heads, screen, hub, screws, nuts), "
             "with all surfaces pulled in by 0.15 mm so only real overlaps count. Then the screen, each drive, the hub and the Pi door "
             "(with the USB and Ethernet plugs in) were slid along their real assembly path: nothing touches on the way in."),
           table(sc_rows, [30 * mm, 42 * mm, 72 * mm, 18 * mm], zebra=False)], bg=colors.HexColor("#eef7d6"), border=OLIVE), PageBreak()]

# 3. parts
S += [p("3. The four print files in print orientation", "h2")]
desc = {
 "A_body": ("A  Body", f"{SL['A_body']['g']:.1f} g, {SL['A_body']['time']}",
            "Upright, open top facing up, floor on the bed. Front: screen window and X-braced drive window. Right side: debossed logo, "
            "USB-C power window, 12 V hole. Inside: drive guide fins on both side walls with lanes, drive shelves at 91-93 mm, hub ledges at "
            "151-153 mm, 4 drop-in M3 nut slots for the door, 4 pegs on the top rim for the crown, 4 holes in the floor for the legs."),
 "B_back_door": ("B  Back door", f"{SL['B_back_door']['g']:.1f} g, {SL['B_back_door']['time']}",
            "Flat, the smooth outside face on the bed, the four Raspberry Pi standoffs pointing up. Hex vents, Ethernet exit, "
            "4 screw holes for M3."),
 "C_crown": ("C  Crown", f"{SL['C_crown']['g']:.1f} g, {SL['C_crown']['time']}",
            "Flat, plate on the bed, the five fins pointing up. 4 USB port windows at the back edge, exhaust slots, 4 peg holes."),
 "D_legs_x4": ("D  Legs (x4, one file)", f"{SL['D_legs_x4']['g']:.1f} g, {SL['D_legs_x4']['time']}",
            "Four L-shaped corner legs, 5 mm high, foot face on the bed. On top: a hex pocket for an M3 nut and a 3 mm locating pin. "
            "Each leg is screwed on from inside the case (M3 x 6 through the floor into the nut), so the case stands 5 mm off the desk.")}
for k in KEYS:
    t, sub, text = desc[k]
    row = Table([[img(os.path.join(R, f"pkg_{k}_print.png"), 50 * mm), [p(t, "h3"), p(sub, "sm"), Spacer(1, 2 * mm), p(text)]]],
                colWidths=[54 * mm, 120 * mm])
    row.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    S += [row, Spacer(1, 3 * mm)]
S += [PageBreak()]

# 4. checks
dm = INFO["dims"]
S += [p("4. Checks after printing", "h2"), p("Measure with a caliper before handing the parts over. These are the fits that matter.")]
chk = [[hcell("#"), hcell("Check"), hcell("Where"), hcell("Target"), hcell("OK range")],
       [c("1"), c("Body width / depth"), c("outside, at the bottom"), c("100.0 / 78.0"), c("+-0.4")],
       [c("2"), c("Body height to the rim"), c("floor to top rim (not the pegs)"), c("195.0"), c("+-0.5")],
       [c("3"), c("Drive lane 1"), c("inside, gap between the front ribs"), c(f"{dm['drv_t'][0] + 0.4:.1f}"), c("6.6 - 7.1")],
       [c("4"), c("Drive lane 2"), c("inside, gap between the back ribs"), c(f"{dm['drv_t'][1] + 0.4:.1f}"), c("9.1 - 9.6")],
       [c("5"), c("Screen slot"), c("front wall to the bottom lip (centre)"), c("6.3 deep"), c("6.1 - 6.6")],
       [c("6"), c("Crown fit"), c("put the crown on the body"), c("pegs 2.8 into holes 3.3"), c("drops on by hand")],
       [c("7"), c("Pi standoff pattern"), c("door, centre to centre"), c("49 x 58"), c("+-0.3")],
       [c("8"), c("Door holes"), c("4 corners of the door"), c("dia 3.5"), c("M3 passes freely")],
       [c("9"), c("Screen window top edge"), c("front of the body"), c("straight"), c("sag < 0.5 mm")],
       [c("10"), c("Vents clean"), c("door hex vents, floor vents, side slots"), c("no strings"), c("clear by hand")],
       [c("11"), c("Leg fit"), c("M3 nut into the leg pocket, pin into the floor hole"), c("nut 5.5 in 6.0, pin 3.0 in 3.5"), c("drops in by hand")],
       [c("12"), c("Nut slots"), c("4 slots inside the body, at the back"), c("M3 nut drops in"), c("no force needed")]]
S += [table(chk, [8 * mm, 40 * mm, 62 * mm, 34 * mm, 30 * mm]), Spacer(1, 5 * mm),
      p("Weights to expect on a scale", "h3"),
      table([[hcell("Part"), hcell("Slicer weight"), hcell("Accept")],
             [c("A Body"), c(f"{SL['A_body']['g']:.1f} g"), c(f"{SL['A_body']['g'] * 0.95:.0f} - {SL['A_body']['g'] * 1.06:.0f} g")],
             [c("B Back door"), c(f"{SL['B_back_door']['g']:.1f} g"), c(f"{SL['B_back_door']['g'] * 0.95:.0f} - {SL['B_back_door']['g'] * 1.06:.0f} g")],
             [c("C Crown"), c(f"{SL['C_crown']['g']:.1f} g"), c(f"{SL['C_crown']['g'] * 0.95:.0f} - {SL['C_crown']['g'] * 1.06:.0f} g")],
             [c("D Legs (4)"), c(f"{SL['D_legs_x4']['g']:.1f} g"), c(f"{SL['D_legs_x4']['g'] * 0.9:.1f} - {SL['D_legs_x4']['g'] * 1.15:.1f} g")],
             [c("Total", True), c(f"<b>{tot_g:.1f} g</b>"), c(f"{tot_g * 0.95:.0f} - {tot_g * 1.06:.0f} g")]],
            [50 * mm, 50 * mm, 74 * mm]), PageBreak()]

# 5. assembly
S += [p("5. How the parts go together (for reference)", "h2"), img(os.path.join(R, "v6d_D_exploded.png"), 150 * mm), Spacer(1, 3 * mm)]
hw = [[hcell("Not printed (bought)"), hcell("Qty"), hcell("Used for")],
      [c("M3 x 10 screw + M3 hex nut"), c("4 + 4"), c("back door to body (nuts slide into slots inside the body)")],
      [c("M2.5 x 12 nylon screw + M2.5 nut"), c("4 + 4"), c("Raspberry Pi 5 to the door standoffs")],
      [c("M3 x 6 low-head screw + M3 hex nut"), c("4 + 4"), c("legs: screw from inside the floor into the nut in each leg")]]
S += [table(hw, [62 * mm, 18 * mm, 94 * mm]), Spacer(1, 3 * mm),
      p("Order: legs screwed on (M3 x 6 + nut each); screen slides into the front slot from the top; drives (with their USB-SATA heads) "
        "slide down the guide fins onto the shelves; M3 nuts dropped into their slots; Pi screwed to the door, cables plugged, door "
        "closed with 4 screws; hub drops onto its ledges; crown pressed onto the 4 pegs.", "sm"),
      Spacer(1, 3 * mm), p("Leg fixing (exploded): M3 x 6 screw from inside, through the floor, into the nut in the leg's hex pocket; the 3 mm pin locates the leg.", "sm"),
      img(os.path.join(R, "v6d_F_leg_detail.png"), 105 * mm),
      PageBreak()]

# 6. files
S += [p("6. Files in this package", "h2")]
files = [[hcell("Folder / file"), hcell("What it is")],
         [c("01_PRINT_FILES_STL/NAS_v6d_A_body.stl", True), c("Body. Binary STL, mm, print orientation. 0 non-manifold edges.")],
         [c("01_PRINT_FILES_STL/NAS_v6d_B_back_door.stl", True), c("Back door. Binary STL, mm, print orientation. 0 non-manifold edges.")],
         [c("01_PRINT_FILES_STL/NAS_v6d_C_crown.stl", True), c("Crown. Binary STL, mm, print orientation. 0 non-manifold edges.")],
         [c("01_PRINT_FILES_STL/NAS_v6d_D_legs_x4.stl", True), c("The 4 legs in one file. Binary STL, mm, print orientation.")],
         [c("01_PRINT_FILES_STL/NAS_v6d_plate_Bambu_X1C_PLA.3mf", True), c("Ready project: all 4 files arranged on one plate, "
                                                                        "Bambu X1C 0.4 / 0.20 mm / PLA, sliced. Opens in Bambu Studio and OrcaSlicer.")],
         [c("02_DOCUMENTS/NAS_v6d_01_Print_Instructions_A4.pdf"), c("This document.")],
         [c("02_DOCUMENTS/NAS_v6d_2D_Blueprints_A3.pdf"), c("5 dimensioned A3 drawings: assembly, body, door, crown, plate layout.")],
         [c("03_BLENDER/NAS_v6d_assembly.blend"), c("Full model (Blender 5.2), textures packed. Collections: 1 printed parts (assembled), "
                                                   "2 bought parts, 3 cables, 4 print-orientation copies, 5 studio.")],
         [c("04_3D_MODEL/NAS_v6d_assembly.glb"), c("3D view of the assembly. Opens in Windows 3D Viewer or any web glTF viewer.")],
         [c("05_RENDERS/"), c("All renders used here (front, back, inside, exploded, top, plate, part views).")],
         [c("case/ folder of the project repo"), c("The Blender and Python scripts that generate the model, the STL files, the drawings "
                                                   "and this PDF; the caliper measurements; the slicer and fit-check results.")]]
S += [table(files, [78 * mm, 96 * mm]), Spacer(1, 5 * mm),
      p("Editing the design", "h3"),
      p("The geometry is generated by script, so a change is one number and one command. Example: open "
        "<b>case/scripts/nas_scene_v6d.py</b> in the project repo, change a value (wall thickness <b>T</b>, lane clearance, window size), then run "
        "<b>blender -b -P scripts/nas_scene_v6d.py -- export</b>. It rebuilds the model, re-exports the four STL files, the views and the .blend. "
        "Direct edits in the .blend are also fine for small changes; export the edited part with File > Export > STL (scale 1000, selection only)."),
      p("Measured parts this design is built on (my caliper numbers): drives 100 x 69.5 x 6.4 / 8.9; USB-SATA head 52.3 x 50 x 13.1 "
        "(47.8 outside the drive); 12 V plug 44; screen 94.6 x 61.8 x 12.3; USB hub 77 x 41.4 x 12.1. All of them: case/README.md in the project repo.", "sm"),
      p("Power test already done on the real hardware: both drives on the 12 V adapter wake together in 2.0 s, 5 of 5 runs, no USB resets.", "sm")]
doc.build(S); print("instructions ok")
