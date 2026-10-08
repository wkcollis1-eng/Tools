"""Write a copy of a clean board with one known fault, for the fault cases in run_tests.py (KiCad python).

usage: make_fault.py <kind> <in.kicad_pcb> <out.kicad_pcb> [REF]
  island    delete the GND vias of one F.Cu GND fill island that no GND pad touches (the one with the
            fewest vias), without refilling: the island is left cut off. islands.py must tag it
            "no GND via or pad".
  pastedge  move footprint REF so its centre sits on the right board edge. outlines.py must flag it.
  drill     set the first via's drill (sorted by position) to 0.20 mm. fabcheck.py must FAIL it.
Written 2026-10-08 for the pcb-eval regression suite."""

import os
import sys

import pcbnew

kind, src, dst = sys.argv[1:4]
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
else:
    sys.exit(f"unknown kind {kind!r}")
pcbnew.SaveBoard(dst, b)
