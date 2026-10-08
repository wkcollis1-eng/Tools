"""Write a copy of a clean board with one known fault, for the fault cases in run_tests.py (KiCad python).

usage: make_fault.py <kind> <in.kicad_pcb> <out.kicad_pcb> [REF]
  island    delete the GND vias of one F.Cu GND fill island that no GND pad touches (the one with the
            fewest vias), without refilling: the island is left cut off. islands.py must tag it
            "no GND via or pad".
  pastedge  move footprint REF so its centre sits on the right board edge. outlines.py must flag it.
  drill     set the first via's drill (sorted by position) to 0.20 mm. fabcheck.py must FAIL it.
  rules     set the Default netclass clearance to 0.25, hole-to-hole to 0.30 and copper-to-edge to 0.60 mm
            (a board with other rules). viamove.py must print and apply them.
  netclass  add netclass Power, clearance 0.30 mm, for net REF. viamove.py must refuse the board.
  copper    set the stackup's F.Cu and B.Cu thickness: REF is "70" (both, um), "35,70" (F, B) or "none"
            (remove the stackup). Edits the text: KiCad 10's Python does not wrap the stackup. The tools
            that read common/copper.py must follow it, refuse "35,70", and say "assumed" for "none".
SaveBoard also writes the .kicad_pro beside <out>, which carries the rules and netclasses.
Written 2026-10-08 for the pcb-eval regression suite."""

import os
import re
import sys

import pcbnew

kind, src, dst = sys.argv[1:4]
if kind == "copper":
    text = open(src, encoding="utf-8", newline="").read()
    i = text.index("(stackup")
    if sys.argv[4] == "none":
        depth, j = 0, i
        while depth or j == i:  # to the parenthesis that closes (stackup
            depth += {"(": 1, ")": -1}.get(text[j], 0)
            j += 1
        text, n = text[:i] + text[j:], 1
    else:
        um = dict(zip(("F.Cu", "B.Cu"), (sys.argv[4].split(",") * 2)[:2]))
        tail, n = re.subn(
            r'(\(layer "(F\.Cu|B\.Cu)"\s*\(type "copper"\)\s*\(thickness )[0-9.]+',
            lambda m: m.group(1) + f"{float(um[m.group(2)]) / 1e3:g}",
            text[i:],
        )
        text = text[:i] + tail
    if n != (1 if sys.argv[4] == "none" else 2):
        sys.exit(f"copper: changed {n} stackup layers")
    open(dst, "w", encoding="utf-8", newline="").write(text)
    print(f"copper: {sys.argv[4]}")
    sys.exit()
b = pcbnew.LoadBoard(src)
mm = pcbnew.ToMM
if kind == "island":
    sys.path.insert(
        0,
        os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "kicad"
        ),
    )
    from islands import islands  # one copy of what "touches an island" means (R10)

    best = None
    for i, (_, vias, pads) in enumerate(islands(b, pcbnew.F_Cu)):
        if vias and not pads and (best is None or len(vias) < len(best[1])):
            best = (i, vias)
    if best is None:
        sys.exit("no F.Cu GND island without a GND pad has a via: pick another board")
    for v in best[1]:
        b.Remove(v)
    print(f"island: removed {len(best[1])} GND via(s) from F.Cu island #{best[0]}")
elif kind == "pastedge":
    f = b.FindFootprintByReference(sys.argv[4])
    dx = b.GetBoardEdgesBoundingBox().GetRight() - f.GetBoundingBox().GetCenter().x
    f.Move(pcbnew.VECTOR2I(dx, 0))
    print(f"pastedge: moved {sys.argv[4]} by {mm(dx):.2f} mm in x")
elif kind == "drill":
    v = sorted(
        (t for t in b.GetTracks() if t.GetClass() == "PCB_VIA"),
        key=lambda t: (t.GetX(), t.GetY()),
    )[0]
    v.SetDrill(pcbnew.FromMM(0.2))
    print(f"drill: via at {mm(v.GetX()):.2f},{mm(v.GetY()):.2f} set to 0.20 mm")
elif kind == "rules":
    ds = b.GetDesignSettings()
    ds.m_NetSettings.GetDefaultNetclass().SetClearance(pcbnew.FromMM(0.25))
    ds.m_HoleToHoleMin = pcbnew.FromMM(0.3)
    ds.m_CopperEdgeClearance = pcbnew.FromMM(0.6)
    print("rules: clearance 0.25, hole-to-hole 0.30, copper-to-edge 0.60 mm")
elif kind == "netclass":
    ns = b.GetDesignSettings().m_NetSettings
    nc = pcbnew.NETCLASS("Power")
    nc.SetClearance(pcbnew.FromMM(0.3))
    ns.SetNetclass("Power", nc)
    ns.SetNetclassPatternAssignment(sys.argv[4], "Power")
    print(f"netclass: Power, clearance 0.30 mm, for net {sys.argv[4]}")
else:
    sys.exit(f"unknown kind {kind!r}")
pcbnew.SaveBoard(dst, b)
