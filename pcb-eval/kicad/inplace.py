"""Widest in-place width for each track of NET on LAYER (KiCad python). 2026-10-06, session 4dcbc5e4.
usage: inplace.py <board> <NET> <LAYER> [clearance_mm=0.2] [edge_mm=0.5] [novia=GND] [t_um=N]
novia=NET leaves that net's vias out of the obstacles: the width a segment could reach if they moved (viamove.py).
R uses the board's copper thickness, from its stackup (common/copper.py), printed first; t_um=N overrides it.
Until 2026-10-08 it was RS = 0.4926 mohm/sq (35 um), fixed.
Exact over the whole segment, end caps included (corridor.py samples the interior only and skips 1.5 mm at
each end, so it missed GND vias and U4 pads there: DRC caught 7 errors on its widths). Obstacles: other-net
pad outlines on LAYER (real polygons), other-net vias, other-net tracks on LAYER, NPTH holes, board edge.
The GND pour is ignored (it reflows). Width = 2 x (nearest obstacle - clearance). DRC remains the gate."""

import math
import os
import sys
import pcbnew

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "common"),
)
import copper  # noqa: E402  (one copy of how a board's copper thickness is read)

brd, NET, LAYER = sys.argv[1], sys.argv[2], sys.argv[3]
pos = [a for a in sys.argv[4:] if "=" not in a]
NOVIA = {a[6:] for a in sys.argv[4:] if a.startswith("novia=")}
T_UM = next((float(a[5:]) for a in sys.argv[4:] if a.startswith("t_um=")), None)
CLR = float(pos[0]) if len(pos) > 0 else 0.2
EDGE = float(pos[1]) if len(pos) > 1 else 0.5
try:
    t_cu, line = copper.thickness(open(brd, encoding="utf-8").read(), T_UM, "t_um=")
except ValueError as e:
    sys.exit(f"copper: {e}; give t_um=N")
print(line)
b = pcbnew.LoadBoard(brd)
u = 1e6
lid = b.GetLayerID(LAYER)


def pseg(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    t = 0 if L2 == 0 else max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L2))
    return math.hypot(px - ax - t * vx, py - ay - t * vy)


def segseg(a, b_, c, d):
    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    o1, o2, o3, o4 = (
        orient(a, b_, c),
        orient(a, b_, d),
        orient(c, d, a),
        orient(c, d, b_),
    )
    if o1 * o2 < 0 and o3 * o4 < 0:
        return 0.0
    return min(
        pseg(*c, *a, *b_), pseg(*d, *a, *b_), pseg(*a, *c, *d), pseg(*b_, *c, *d)
    )


obs = []  # (name, kind, data): kind "poly" list of edges, "circ" (x, y, r), "cap" (seg, hw)
for f in b.GetFootprints():
    for p in f.Pads():
        if p.GetNetname() == NET:
            continue
        if p.IsOnLayer(lid):
            ps = pcbnew.SHAPE_POLY_SET()
            p.TransformShapeToPolygon(
                ps, lid, 0, pcbnew.FromMM(0.005), pcbnew.ERROR_INSIDE
            )
            for i in range(ps.OutlineCount()):
                o = ps.Outline(i)
                pts = [
                    (o.CPoint(k).x / u, o.CPoint(k).y / u)
                    for k in range(o.PointCount())
                ]
                obs.append(
                    (
                        f"{f.GetReference()}.{p.GetNumber()}",
                        "poly",
                        [(pts[k], pts[(k + 1) % len(pts)]) for k in range(len(pts))],
                    )
                )
        elif (
            p.GetDrillSizeX() > 0
        ):  # NPTH or a pad with no copper here: keep copper off the hole
            obs.append(
                (
                    f"{f.GetReference()}.{p.GetNumber()} hole",
                    "circ",
                    (
                        p.GetPosition().x / u,
                        p.GetPosition().y / u,
                        p.GetDrillSizeX() / u / 2,
                    ),
                )
            )
for t in b.GetTracks():
    if t.GetNetname() == NET:
        continue
    if t.GetClass() == "PCB_VIA" and t.GetNetname() not in NOVIA:
        obs.append(
            (
                f"via {t.GetNetname()}@{t.GetPosition().x / u:.2f},{t.GetPosition().y / u:.2f}",
                "circ",
                (t.GetPosition().x / u, t.GetPosition().y / u, t.GetWidth(lid) / u / 2),
            )
        )
    elif t.GetClass() == "PCB_TRACK" and t.GetLayer() == lid:
        obs.append(
            (
                f"trk {t.GetNetname()}",
                "cap",
                (
                    (t.GetStart().x / u, t.GetStart().y / u),
                    (t.GetEnd().x / u, t.GetEnd().y / u),
                    t.GetWidth() / u / 2,
                ),
            )
        )
bb = b.GetBoardEdgesBoundingBox()
ex0, ey0, ex1, ey1 = (
    bb.GetLeft() / u,
    bb.GetTop() / u,
    bb.GetRight() / u,
    bb.GetBottom() / u,
)

RS = copper.RHO / t_cu * 1e3  # mohm/sq; was 0.4926, the 35 um value rounded to 4 dp
for t in b.GetTracks():
    if t.GetClass() != "PCB_TRACK" or t.GetNetname() != NET or t.GetLayer() != lid:
        continue
    a = (t.GetStart().x / u, t.GetStart().y / u)
    e = (t.GetEnd().x / u, t.GetEnd().y / u)
    best, who = 1e9, None
    for name, kind, g in obs:
        if kind == "poly":
            dist = min(segseg(a, e, p, q) for p, q in g)
        elif kind == "circ":
            dist = pseg(g[0], g[1], *a, *e) - g[2]
        else:
            dist = segseg(a, e, g[0], g[1]) - g[2]
        if dist - CLR < best:
            best, who = dist - CLR, name
    edge = (
        min(
            min(a[0], e[0]) - ex0,
            ex1 - max(a[0], e[0]),
            min(a[1], e[1]) - ey0,
            ey1 - max(a[1], e[1]),
        )
        - EDGE
    )
    if edge < best:
        best, who = edge, "edge"
    L = math.hypot(e[0] - a[0], e[1] - a[1])
    w = t.GetWidth() / u
    print(
        f"{a[0]:.2f},{a[1]:.2f},{e[0]:.2f},{e[1]:.2f}  L {L:5.2f}  w {w:.2f}  max in-place {2 * best:5.2f} mm  limit {who:22s}  R {RS * L / w:5.2f} mohm"
    )
