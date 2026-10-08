"""List each connector's pads (net, position) and the silk text within R mm, so labels can be
checked against copper. usage: KPY connsilk.py <board> REF[,REF...] [R=6]
Written 2026-10-06 (session c79d6a13): Rev 2 renumbered TB1 and J1 against the built Rev 1."""

import sys
import math
import pcbnew

b = pcbnew.LoadBoard(sys.argv[1])
refs = sys.argv[2].split(",")
R = float(sys.argv[3]) if len(sys.argv) > 3 else 6
mm = pcbnew.ToMM
bb = b.GetBoardEdgesBoundingBox()
print(
    f"edge x {mm(bb.GetX()):.2f}-{mm(bb.GetRight()):.2f} y {mm(bb.GetY()):.2f}-{mm(bb.GetBottom()):.2f}"
)
texts = [t for t in b.GetDrawings() if t.GetClass() == "PCB_TEXT"]
for f in b.GetFootprints():
    texts += [t for t in f.GraphicalItems() if t.GetClass() == "PCB_TEXT"] + [
        t for t in f.GetFields() if t.IsVisible()
    ]
texts = [t for t in texts if t.GetLayer() in (pcbnew.F_SilkS, pcbnew.B_SilkS)]
for f in b.GetFootprints():
    if f.GetReference() not in refs:
        continue
    print(
        f"\n{f.GetReference()} at ({mm(f.GetPosition().x):.2f},{mm(f.GetPosition().y):.2f}) rot {f.GetOrientationDegrees():.0f}"
    )
    for p in sorted(f.Pads(), key=lambda p: p.GetNumber()):
        q = p.GetPosition()
        print(
            f"   pad {p.GetNumber()} {p.GetNetname():10s} ({mm(q.x):.2f},{mm(q.y):.2f}) {'square' if p.GetShape(pcbnew.F_Cu) in (pcbnew.PAD_SHAPE_RECT, pcbnew.PAD_SHAPE_ROUNDRECT) else 'round'}"
        )
    c = f.GetPosition()
    near = []
    for t in texts:
        q = t.GetPosition()
        d = math.hypot(mm(q.x - c.x), mm(q.y - c.y))
        if d <= R:
            near.append(
                (
                    d,
                    t.GetShownText(False).replace("\n", "/"),
                    mm(q.x),
                    mm(q.y),
                    t.GetLayerName(),
                )
            )
    for d, s, x, y, L in sorted(near, key=lambda n: (n[3], n[2])):
        print(f"   silk '{s}' ({x:.2f},{y:.2f}) {L}")
