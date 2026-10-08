# Per-footprint graphic extents on silk/fab/courtyard layers, and 3D model list.
import sys
import pcbnew

b = pcbnew.LoadBoard(sys.argv[1])
mm = pcbnew.ToMM
refs = sys.argv[2].split(",") if len(sys.argv) > 2 else None
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
        print(
            "   ",
            ln,
            [round(v, 2) for v in e],
            "size",
            round(e[2] - e[0], 2),
            "x",
            round(e[3] - e[1], 2),
        )
    for m in f.Models():
        print("    model", m.m_Filename, "show", m.m_Show)
