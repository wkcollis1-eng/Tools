# Per-footprint graphic extents on silk/fab/courtyard layers, each flagged PAST EDGE, and 3D model list.
# PAST EDGE compares an extent with the board edge's bounding box (including its line width), so on a
# non-rectangular outline it misses an overhang into a notch. Added 2026-10-08: the pcb-eval fault test
# moved U1 past the edge and this tool, which printed no edge, flagged nothing.
import sys
import pcbnew

b = pcbnew.LoadBoard(sys.argv[1])
mm = pcbnew.ToMM
refs = sys.argv[2].split(",") if len(sys.argv) > 2 else None
eb = b.GetBoardEdgesBoundingBox()
edge = [mm(eb.GetX()), mm(eb.GetY()), mm(eb.GetRight()), mm(eb.GetBottom())]
print("board edge", [round(v, 2) for v in edge], "(bounding box, including line width)")
for f in b.GetFootprints():
    r = f.GetReference()
    if refs and r not in refs:
        continue
    per = {}
    for g in f.GraphicalItems():
        ln = g.GetLayerName()
        if not any(k in ln for k in ("Silk", "Fab", "CrtYd")):
            continue
        bb = g.GetBoundingBox()
        e = per.setdefault(ln, [1e9, 1e9, -1e9, -1e9])
        e[0] = min(e[0], mm(bb.GetX()))
        e[1] = min(e[1], mm(bb.GetY()))
        e[2] = max(e[2], mm(bb.GetRight()))
        e[3] = max(e[3], mm(bb.GetBottom()))
    print(r, f.GetValue(), "rot", f.GetOrientationDegrees())
    for ln, e in per.items():
        past = max(edge[0] - e[0], edge[1] - e[1], e[2] - edge[2], e[3] - edge[3])
        print(
            "   ",
            ln,
            [round(v, 2) for v in e],
            "size",
            round(e[2] - e[0], 2),
            "x",
            round(e[3] - e[1], 2),
            *(["PAST EDGE", round(past, 2), "mm"] if past >= 0.005 else []),
        )
    for m in f.Models():
        print("    model", m.m_Filename, "show", m.m_Show)
