"""Write a copy of a clean board with one known fault, for the fault cases in run_tests.py (KiCad python).

usage: make_fault.py <kind> <in.kicad_pcb> <out.kicad_pcb> [REF]
  island    delete the GND vias of one F.Cu GND fill island that has no GND pad in it (the one with the
            fewest vias), without refilling: the island is left cut off. islands.py must show it with 0 vias.
  pastedge  move footprint REF so its centre sits on the right board edge. outlines.py must flag it.
  drill     set the first via's drill (sorted by position) to 0.20 mm. fabcheck.py must FAIL it.
Written 2026-10-08 for the pcb-eval regression suite."""

import sys

import pcbnew

kind, src, dst = sys.argv[1:4]
b = pcbnew.LoadBoard(src)
mm = pcbnew.ToMM
if kind == "island":
    merged = pcbnew.SHAPE_POLY_SET()
    for z in b.Zones():
        if z.GetNetname() == "GND" and z.IsOnLayer(pcbnew.F_Cu):
            merged.BooleanAdd(z.GetFilledPolysList(pcbnew.F_Cu))
    merged.Simplify()
    vias = [
        t
        for t in b.GetTracks()
        if t.GetClass() == "PCB_VIA" and t.GetNetname() == "GND"
    ]
    pads = [p for f in b.GetFootprints() for p in f.Pads() if p.GetNetname() == "GND"]
    best = None
    for i in range(merged.OutlineCount()):
        if any(merged.Contains(p.GetPosition(), i) for p in pads):
            continue
        inside = [v for v in vias if merged.Contains(v.GetPosition(), i)]
        if inside and (best is None or len(inside) < len(best[1])):
            best = (i, inside)
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
