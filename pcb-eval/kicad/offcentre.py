"""Track end points that land inside a same-net pad but not on its centre (KiCad python). 2026-10-06, session 4dcbc5e4.
usage: offcentre.py <board> [tol_mm=0.005]
Prints the end point, the pad, the offset, and every same-net track that shares the point (moving it moves them)."""

import math
import sys
import pcbnew

b = pcbnew.LoadBoard(sys.argv[1])
u = 1e6
tol = float(sys.argv[2]) if len(sys.argv) > 2 else 0.005
pads = [
    (f.GetReference(), p) for f in b.GetFootprints() for p in f.Pads() if p.GetNetname()
]
trk = [t for t in b.GetTracks() if t.GetClass() == "PCB_TRACK"]
seen = set()
for t in trk:
    for pt in (t.GetStart(), t.GetEnd()):
        key = (t.GetNetname(), round(pt.x / u, 3), round(pt.y / u, 3))
        if key in seen:
            continue
        seen.add(key)
        for ref, p in pads:
            if (
                p.GetNetname() != t.GetNetname()
                or not p.IsOnLayer(t.GetLayer())
                or not p.HitTest(pt)
            ):
                continue
            c = p.GetPosition()
            off = math.hypot(pt.x - c.x, pt.y - c.y) / u
            if off > tol:
                share = [
                    f"({s.GetStart().x / u:.3f},{s.GetStart().y / u:.3f})-({s.GetEnd().x / u:.3f},{s.GetEnd().y / u:.3f}) w{s.GetWidth() / u:.2f}"
                    for s in trk
                    if s.GetNetname() == t.GetNetname()
                    and s.GetLayer() == t.GetLayer()
                    and (s.GetStart() == pt or s.GetEnd() == pt)
                ]
                print(
                    f"{t.GetNetname():9s} {b.GetLayerName(t.GetLayer())} end ({pt.x / u:.3f},{pt.y / u:.3f}) in {ref}.{p.GetNumber()} "
                    f"centre ({c.x / u:.3f},{c.y / u:.3f}) off {off:.3f} mm; segs: {'; '.join(share)}"
                )
