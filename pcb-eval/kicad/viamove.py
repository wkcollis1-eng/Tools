"""Nearest legal spot for each via that a widened track would hit (KiCad python). 2026-10-06, session 4dcbc5e4.
usage: viamove.py <board> <ops.txt> [rmax=2.0] [step=0.05]
ops.txt holds variant.py w= lines (target widths; other ops ignored, every w= must match a track). A via moves
only if a track whose width changed now violates it, so vias already in error stay where they are (they are
listed, not fixed). Legal at a spot = copper 0.2 mm from every pad of any net (no via-in-pad), every other-net
track at its target width and every other-net via; hole 0.25 mm from every other hole; copper 0.5 mm inside the
board outline; inside an own-net zone outline on every copper layer the via spans, and in no via keepout;
and the via centre plus >= FILLMIN of 16 points on its pad edge inside that zone's FILL on every layer, filled
with the target widths in place (fill=N, default 12: on the 20:07 board [M] 68/70 of 77 GND vias have 16/16 on
F.Cu/B.Cu and the owner's own worst non-error via has 11/16, so 12 is no worse than his practice).
R13 2026-10-06: without the fill rule 3 of 7 moved GND vias passed every clearance and sat outside the F.Cu
fill (viafill.py: 3 new misses, DRC: +1 via_dangling): copper clearance is not pour reach.
A via also moves if it passed the fill rule with the original widths and fails it with the targets: the pour keeps
0.5 mm from other-net copper, the DRC rule 0.2, so a via can stay clear and still lose the pour (R13 2026-10-06:
GND via 31.00,78.00 at 0.200 mm from a 3.40 mm BATT_RAW had its centre on the fill edge, and only a DRC hit triggered).
Rules are this board's .kicad_pro values (2026-10-06). Vias are moved in turn, each seeing the earlier moves.
2026-10-08: the 0.2 / 0.25 / 0.5 above were the Top Off Charger's, hard-coded. They are now read from the board's
design settings (the Default netclass clearance, min hole-to-hole, min copper-to-edge) and printed on the first
line. A board with a netclass of another clearance, or a .kicad_dru beside it, is refused: one clearance for
every net, and no custom rules, is all this tool applies.
Prints via=X,Y:X2,Y2 lines for variant.py. Fill coverage after refill and DRC remain the gate.
  at=X,Y:X2,Y2  instead of searching, print what the via at X,Y would break at X2,Y2 (repeatable)."""

import math
import os
import sys
import pcbnew

brd, opsf = sys.argv[1], sys.argv[2]
pos = [a for a in sys.argv[3:] if "=" not in a]
AT = [a[3:] for a in sys.argv[3:] if a.startswith("at=")]
FILLMIN = int(next((a[5:] for a in sys.argv[3:] if a.startswith("fill=")), 12))
RMAX = float(pos[0]) if len(pos) > 0 else 2.0
STEP = float(pos[1]) if len(pos) > 1 else 0.05
b = pcbnew.LoadBoard(brd)
u = 1e6
ds = b.GetDesignSettings()
ns = ds.m_NetSettings
CLR = ns.GetDefaultNetclass().GetClearance() / u
H2H, EDGE = ds.m_HoleToHoleMin / u, ds.m_CopperEdgeClearance / u
odd = [
    f"netclass {k} clearance {c.GetClearance() / u:g} mm"
    for k, c in ns.GetNetclasses().items()
    if c.HasClearance() and c.GetClearance() / u != CLR
]
if os.path.exists(os.path.splitext(brd)[0] + ".kicad_dru"):
    odd.append(
        "custom rules " + os.path.basename(os.path.splitext(brd)[0]) + ".kicad_dru"
    )
if odd:
    sys.exit(
        f"viamove applies one clearance ({CLR:g} mm) to every net and no custom rules; this board has "
        + "; ".join(odd)
    )
print(
    f"# rules: clearance {CLR:.3f} hole-to-hole {H2H:.3f} copper-to-edge {EDGE:.3f} mm (board design settings)"
)
CU = [ly for ly in (pcbnew.F_Cu, pcbnew.B_Cu)]


def pseg(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    t = 0 if L2 == 0 else max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L2))
    return math.hypot(px - ax - t * vx, py - ay - t * vy)


def inpoly(x, y, pts):
    c = False
    for i in range(len(pts)):
        (x1, y1), (x2, y2) = pts[i], pts[i - 1]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            c = not c
    return c


def polydist(x, y, pts):  # signed: negative inside
    d = min(pseg(x, y, *pts[i], *pts[i - 1]) for i in range(len(pts)))
    return -d if inpoly(x, y, pts) else d


def outlines(ps):
    return [
        [
            (ps.Outline(i).CPoint(k).x / u, ps.Outline(i).CPoint(k).y / u)
            for k in range(ps.Outline(i).PointCount())
        ]
        for i in range(ps.OutlineCount())
    ]


def fillprob(v, x, y):
    """The fill rule: centre and >= FILLMIN of 16 points just outside the via pad in own-net fill, on each layer."""
    out = []
    net = v.GetNetname()
    for ly in CU:
        r = v.GetWidth(ly) / u / 2 + 0.01

        def infill(px, py):
            return any(
                z.GetNetname() == net
                and not z.GetIsRuleArea()
                and z.IsOnLayer(ly)
                and z.HitTestFilledArea(
                    ly, pcbnew.VECTOR2I(pcbnew.FromMM(px), pcbnew.FromMM(py))
                )
                for z in b.Zones()
            )

        k = sum(
            infill(x + r * math.cos(i * math.pi / 8), y + r * math.sin(i * math.pi / 8))
            for i in range(16)
        )
        if not infill(x, y) or k < FILLMIN:
            out.append(
                f"fill {b.GetLayerName(ly)} {k}/16{'' if infill(x, y) else ' centre out'}"
            )
    return out


vias = [t for t in b.GetTracks() if t.GetClass() == "PCB_VIA"]
pcbnew.ZONE_FILLER(b).Fill(
    b.Zones()
)  # original widths: which vias the pour reaches before any change
fill0 = {id(v): fillprob(v, v.GetPosition().x / u, v.GetPosition().y / u) for v in vias}

# targets
trk = [t for t in b.GetTracks() if t.GetClass() == "PCB_TRACK"]
width = {id(t): t.GetWidth() / u for t in trk}
changed = set()
for line in open(opsf):
    line = line.strip()
    if not line.startswith("w="):
        continue
    net, layer, w, seg = line[2:].split(":")
    s = [float(v) for v in seg.split(",")]
    lid = b.GetLayerID(layer)
    hits = 0
    for t in trk:
        a = (t.GetStart().x / u, t.GetStart().y / u)
        e = (t.GetEnd().x / u, t.GetEnd().y / u)

        def near(p, q):
            return abs(p[0] - q[0]) < 0.02 and abs(p[1] - q[1]) < 0.02

        if (
            t.GetNetname() == net
            and t.GetLayer() == lid
            and (
                (near(a, s[:2]) and near(e, s[2:]))
                or (near(a, s[2:]) and near(e, s[:2]))
            )
        ):
            width[id(t)] = float(w)
            hits += 1
            if abs(float(w) - t.GetWidth() / u) > 1e-6:
                changed.add(id(t))
            t.SetWidth(
                pcbnew.FromMM(float(w))
            )  # in memory only, so the fill below sees the targets
    if hits != 1:
        sys.exit(f"{line}: matched {hits} tracks, expected 1")
pcbnew.ZONE_FILLER(b).Fill(b.Zones())

pads = []
for f in b.GetFootprints():
    for p in f.Pads():
        per = {}
        for ly in CU:
            if p.IsOnLayer(ly):
                ps = pcbnew.SHAPE_POLY_SET()
                p.TransformShapeToPolygon(
                    ps, ly, 0, pcbnew.FromMM(0.005), pcbnew.ERROR_INSIDE
                )
                per[ly] = outlines(ps)
        hole = max(p.GetDrillSizeX(), p.GetDrillSizeY()) / u / 2
        pads.append(
            (
                f"{f.GetReference()}.{p.GetNumber()}",
                p.GetPosition().x / u,
                p.GetPosition().y / u,
                per,
                hole,
            )
        )
vpos = {id(v): (v.GetPosition().x / u, v.GetPosition().y / u) for v in vias}
ps = pcbnew.SHAPE_POLY_SET()
b.GetBoardPolygonOutlines(ps, True)
edge = outlines(ps)


def problems(v, x, y, only_changed=False):
    """Every rule the via at (x, y) breaks; only_changed: just copper against tracks whose width changed."""
    out = []
    net = v.GetNetname()
    h = v.GetDrillValue() / u / 2
    for t in trk:
        if (
            t.GetNetname() == net
            or t.GetLayer() not in CU
            or (only_changed and id(t) not in changed)
        ):
            continue
        r = v.GetWidth(t.GetLayer()) / u / 2
        d = (
            pseg(
                x,
                y,
                t.GetStart().x / u,
                t.GetStart().y / u,
                t.GetEnd().x / u,
                t.GetEnd().y / u,
            )
            - width[id(t)] / 2
            - r
        )
        if d < CLR - 1e-4:
            out.append(
                f"trk {t.GetNetname()} {d:.3f}"
                + (
                    f" @{t.GetStart().x / u:.2f},{t.GetStart().y / u:.2f},{t.GetEnd().x / u:.2f},{t.GetEnd().y / u:.2f}"
                    if only_changed
                    else ""
                )
            )
    if only_changed:
        return out
    for name, px, py, per, ph in pads:
        if math.hypot(px - x, py - y) > RMAX + 15:
            continue
        for ly, polys in per.items():
            r = v.GetWidth(ly) / u / 2
            for poly in polys:
                d = polydist(x, y, poly) - r
                if d < CLR - 1e-4:
                    out.append(f"pad {name} {d:.3f}")
        if ph > 0 and math.hypot(px - x, py - y) - ph - h < H2H - 1e-4:
            out.append(f"hole {name}")
    for w in vias:
        if w is v:
            continue
        wx, wy = vpos[id(w)]
        dc = math.hypot(wx - x, wy - y)
        if dc - w.GetDrillValue() / u / 2 - h < H2H - 1e-4:
            out.append(f"hole via@{wx:.2f},{wy:.2f}")
        if (
            w.GetNetname() != net
            and dc - w.GetWidth(pcbnew.F_Cu) / u / 2 - v.GetWidth(pcbnew.F_Cu) / u / 2
            < CLR - 1e-4
        ):
            out.append(f"via {w.GetNetname()}@{wx:.2f},{wy:.2f}")
    r = v.GetWidth(pcbnew.F_Cu) / u / 2
    if (
        not any(inpoly(x, y, o) for o in edge)
        or min(polydist(x, y, o) for o in edge) > -(r + EDGE) + 1e-4
    ):
        out.append("edge")
    for ly in CU:
        if not any(
            z.GetNetname() == net
            and not z.GetIsRuleArea()
            and z.IsOnLayer(ly)
            and z.Outline().Contains(
                pcbnew.VECTOR2I(pcbnew.FromMM(x), pcbnew.FromMM(y))
            )
            for z in b.Zones()
        ):
            out.append(f"no {net} zone on {b.GetLayerName(ly)}")
    out += fillprob(v, x, y)
    for z in b.Zones():
        if (
            z.GetIsRuleArea()
            and z.GetDoNotAllowVias()
            and z.Outline().Contains(
                pcbnew.VECTOR2I(pcbnew.FromMM(x), pcbnew.FromMM(y))
            )
        ):
            out.append("keepout")
    return out


if AT:
    for a in AT:
        (fx, fy), (tx, ty) = [[float(v) for v in xy.split(",")] for xy in a.split(":")]
        v = [
            w
            for w in vias
            if abs(vpos[id(w)][0] - fx) < 0.02 and abs(vpos[id(w)][1] - fy) < 0.02
        ]
        if len(v) != 1:
            sys.exit(f"at={a}: {len(v)} vias at {fx},{fy}")
        print(
            f"at {fx:.2f},{fy:.2f} -> {tx:.2f},{ty:.2f}: {'; '.join(problems(v[0], tx, ty)) or 'legal'}"
        )
    sys.exit()
n = int(round(RMAX / STEP))
cands = sorted(
    (
        (i * STEP, j * STEP)
        for i in range(-n, n + 1)
        for j in range(-n, n + 1)
        if math.hypot(i, j) * STEP <= RMAX + 1e-9
    ),
    key=lambda d: (round(math.hypot(*d), 6), d),
)
for v in vias:
    x0, y0 = vpos[id(v)]
    pre = problems(v, x0, y0)
    hit = problems(v, x0, y0, only_changed=True)
    now = fillprob(v, x0, y0)
    if now and not fill0[id(v)]:
        hit += [f"{p} (was in fill)" for p in now]
    elif now != fill0[id(v)]:
        print(
            f"# fill already under the rule before the widths: {v.GetNetname()} via @{x0:.2f},{y0:.2f} was {'; '.join(fill0[id(v)])} now {'; '.join(now)}"
        )
    if not hit:
        if pre and any(not p.startswith(("no ", "edge", "fill")) for p in pre):
            print(
                f"# left alone: {v.GetNetname()} via @{x0:.2f},{y0:.2f} already breaks: {'; '.join(pre)}"
            )
        continue
    for dx, dy in cands:
        if not problems(v, x0 + dx, y0 + dy):
            vpos[id(v)] = (x0 + dx, y0 + dy)
            print(
                f"via={x0:.2f},{y0:.2f}:{x0 + dx:.2f},{y0 + dy:.2f}   # {v.GetNetname()} moved {math.hypot(dx, dy):.3f} mm; was hit by {'; '.join(hit)}"
            )
            break
    else:
        print(
            f"# NO SPOT within {RMAX} mm: {v.GetNetname()} via @{x0:.2f},{y0:.2f} hit by {'; '.join(hit)}"
        )
