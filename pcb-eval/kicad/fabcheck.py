"""Measure a board's as-drawn fab geometry against OSH Park's 2-layer limits.
usage: KPY fabcheck.py <board.kicad_pcb>

Written 2026-10-06 (session c79d6a13) for the Battery Bank Monitor Rev 2 review. The Top Off
Charger's same check (session 673cc9d3) was run inline and not kept; this is it, persisted.
Limits [S]: docs.oshpark.com/services/two-layer (copy in ../osh-spec/). Every figure printed is
measured from the geometry [K], not read from the design rules, because a rule only bounds what
DRC flags and this board's via-annular rule (0.1) is looser than OSH Park's 0.127.
Copper-to-edge assumes an axis-aligned rectangular outline (checked, and refused otherwise)."""

import sys
import math
import itertools
import pcbnew

OSH = dict(
    drill=0.254,
    ring=0.127,
    track=0.1524,
    space=0.1524,
    edge=0.381,
    hole_hole=0.127,
    slot=0.508,
    web=0.1016,
    silk_rec=0.127,
    silk_min=0.0762,
)
mm = pcbnew.ToMM
b = pcbnew.LoadBoard(sys.argv[1])
fails = []


def chk(name, val, lim, where=""):
    ok = val >= lim - 1e-9
    print(
        f"  {'ok  ' if ok else 'FAIL'} {name:34s} {val:8.4f} mm  (OSH >= {lim})  {where}"
    )
    if not ok:
        fails.append(name)


# outline
edges = [d for d in b.GetDrawings() if d.GetLayer() == pcbnew.Edge_Cuts]
bb = b.GetBoardEdgesBoundingBox()
X0, Y0, X1, Y1 = mm(bb.GetX()), mm(bb.GetY()), mm(bb.GetRight()), mm(bb.GetBottom())
kinds = sorted(d.GetShapeStr() for d in edges)
print(
    f"outline: {len(edges)} Edge.Cuts item(s) {kinds}; bbox incl. line width {X1 - X0:.3f} x {Y1 - Y0:.3f} mm"
)
rect = [d for d in edges if d.GetShape() == pcbnew.SHAPE_T_RECT]
if len(edges) != 1 or not rect:
    sys.exit(
        "outline is not a single rectangle: copper-to-edge needs a polygon method - refusing"
    )
r = rect[0]
s, e = r.GetStart(), r.GetEnd()
ex0, ex1 = sorted((mm(s.x), mm(e.x)))
ey0, ey1 = sorted((mm(s.y), mm(e.y)))
print(
    f"  rectangle centreline {ex1 - ex0:.3f} x {ey1 - ey0:.3f} mm, line width {mm(r.GetWidth()):.3f}"
)


def dedge(x, y):
    return min(x - ex0, ex1 - x, y - ey0, ey1 - y)


# holes
holes = []  # (x, y, r_min, kind, label)
vias = [t for t in b.GetTracks() if t.GetClass() == "PCB_VIA"]
tracks = [t for t in b.GetTracks() if t.GetClass() in ("PCB_TRACK", "PCB_ARC")]
for v in vias:
    p = v.GetPosition()
    holes.append(
        (
            mm(p.x),
            mm(p.y),
            mm(v.GetDrillValue()) / 2,
            "via",
            f"via {v.GetNetname()} ({mm(p.x):.2f},{mm(p.y):.2f})",
        )
    )
pads = [p for f in b.GetFootprints() for p in f.Pads()]
pth = [p for p in pads if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH]
npth = [p for p in pads if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH]
slots = []
for p in pth + npth:
    d = p.GetDrillSize()
    dx, dy = mm(d.x), mm(d.y)
    q = p.GetPosition()
    lab = f"{p.GetParentFootprint().GetReference()}.{p.GetNumber()}"
    if abs(dx - dy) > 1e-6:
        slots.append((lab, dx, dy))
    holes.append(
        (mm(q.x), mm(q.y), min(dx, dy) / 2, "pth" if p in pth else "npth", lab)
    )

print(
    f"\nholes: {len(vias)} vias, {len(pth)} PTH pads, {len(npth)} NPTH, {len(slots)} slots {slots}"
)
vmin = min(vias, key=lambda v: v.GetDrillValue()) if vias else None
pmin = (
    min(pth, key=lambda p: min(p.GetDrillSize().x, p.GetDrillSize().y)) if pth else None
)
dmin = min(h[2] * 2 for h in holes if h[3] != "npth")
chk("min plated drill", dmin, OSH["drill"])
for lab, dx, dy in slots:
    chk(f"slot width {lab}", min(dx, dy), OSH["slot"])
if vias:
    ring = min((mm(v.GetWidth(pcbnew.F_Cu)) - mm(v.GetDrillValue())) / 2 for v in vias)
    chk(
        "via annular ring",
        ring,
        OSH["ring"],
        f"(sizes {sorted(set((round(mm(v.GetWidth(pcbnew.F_Cu)), 3), round(mm(v.GetDrillValue()), 3)) for v in vias))})",
    )
worst = None
for p in pth:
    for L in (pcbnew.F_Cu, pcbnew.B_Cu):
        sz = p.GetSize(L)
        d = p.GetDrillSize()
        off = p.GetOffset(L)
        rr = (min(mm(sz.x), mm(sz.y)) - min(mm(d.x), mm(d.y))) / 2 - math.hypot(
            mm(off.x), mm(off.y)
        )
        if worst is None or rr < worst[0]:
            worst = (
                rr,
                f"{p.GetParentFootprint().GetReference()}.{p.GetNumber()} pad {mm(sz.x):.2f}x{mm(sz.y):.2f} drill {mm(d.x):.2f}",
            )
chk("PTH pad annular ring", worst[0], OSH["ring"], worst[1])
for p in npth:
    if p.GetSize(pcbnew.F_Cu).x > p.GetDrillSize().x + 1e-6 and p.IsOnCopperLayer():
        print(
            f"  note NPTH {p.GetParentFootprint().GetReference()} has a copper pad larger than its hole"
        )

hh = None
for a, c in itertools.combinations(holes, 2):
    g = math.hypot(a[0] - c[0], a[1] - c[1]) - a[2] - c[2]
    if hh is None or g < hh[0]:
        hh = (g, f"{a[4]} / {c[4]}")
chk("hole-to-hole edge gap", hh[0], OSH["hole_hole"], hh[1])

# copper
print("\ncopper:")
if tracks:
    tw = min(tracks, key=lambda t: t.GetWidth())
    chk(
        "min track width",
        mm(tw.GetWidth()),
        OSH["track"],
        f"{tw.GetNetname()} {tw.GetLayerName()}",
    )
cl = [
    c.GetClearance()
    for c in b.GetDesignSettings().m_NetSettings.GetNetclasses().values()
] + [b.GetDesignSettings().m_NetSettings.GetDefaultNetclass().GetClearance()]
chk(
    "netclass clearance (DRC-enforced)",
    mm(min(cl)),
    OSH["space"],
    f"{len(cl)} class(es)",
)

ce = None
for t in tracks:
    for pt in (t.GetStart(), t.GetEnd()):
        g = dedge(mm(pt.x), mm(pt.y)) - mm(t.GetWidth()) / 2
        if ce is None or g < ce[0]:
            ce = (g, f"track {t.GetNetname()} {t.GetLayerName()}")
for v in vias:
    p = v.GetPosition()
    g = dedge(mm(p.x), mm(p.y)) - mm(v.GetWidth(pcbnew.F_Cu)) / 2
    if g < ce[0]:
        ce = (g, f"via {v.GetNetname()}")
for p in pads:
    if not p.IsOnCopperLayer():
        continue
    for L in (pcbnew.F_Cu, pcbnew.B_Cu):
        if not p.IsOnLayer(L):
            continue
        ps = p.GetEffectivePolygon(L, pcbnew.ERROR_INSIDE)
        for i in range(ps.OutlineCount()):
            o = ps.Outline(i)
            for k in range(o.PointCount()):
                q = o.CPoint(k)
                g = dedge(mm(q.x), mm(q.y))
                if g < ce[0]:
                    ce = (
                        g,
                        f"pad {p.GetParentFootprint().GetReference()}.{p.GetNumber()}",
                    )
for z in b.Zones():
    for L in (pcbnew.F_Cu, pcbnew.B_Cu):
        if not z.IsOnLayer(L) or not z.HasFilledPolysForLayer(L):
            continue
        fp = z.GetFilledPolysList(L)
        for i in range(fp.OutlineCount()):
            o = fp.Outline(i)
            for k in range(o.PointCount()):
                q = o.CPoint(k)
                g = dedge(mm(q.x), mm(q.y))
                if g < ce[0]:
                    ce = (
                        g,
                        f"zone {z.GetNetname()} {pcbnew.LayerName(L) if hasattr(pcbnew, 'LayerName') else L} fill",
                    )
chk("copper to edge (centreline)", ce[0], OSH["edge"], ce[1])

# mask web: pad-to-pad gap, same side, pad_to_mask_clearance added twice
ds = b.GetDesignSettings()
pm = mm(ds.m_SolderMaskExpansion)
print(
    f"\nsolder mask: board expansion {pm} mm, min web rule {mm(ds.m_SolderMaskMinWidth)} mm"
)
polys = []
for p in pads:
    for L, M in ((pcbnew.F_Cu, pcbnew.F_Mask), (pcbnew.B_Cu, pcbnew.B_Mask)):
        if p.IsOnLayer(L) and p.IsOnLayer(M):
            ps = p.GetEffectivePolygon(L, pcbnew.ERROR_INSIDE)
            pts = [
                (mm(ps.Outline(0).CPoint(k).x), mm(ps.Outline(0).CPoint(k).y))
                for k in range(ps.Outline(0).PointCount())
            ]
            m = (
                mm(p.GetSolderMaskExpansion(L))
                if hasattr(p, "GetSolderMaskExpansion")
                else pm
            )
            polys.append(
                (
                    L,
                    p.GetNetname(),
                    f"{p.GetParentFootprint().GetReference()}.{p.GetNumber()}",
                    pts,
                    m,
                )
            )


def segd(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    t = 0 if L2 == 0 else max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L2))
    return math.hypot(px - ax - t * vx, py - ay - t * vy)


def pdist(A, B):
    best = 1e9
    for P, Q in ((A, B), (B, A)):
        for px, py in P:
            for i in range(len(Q)):
                ax, ay = Q[i]
                bx, by = Q[(i + 1) % len(Q)]
                best = min(best, segd(px, py, ax, ay, bx, by))
    return best


webs = {"diff": None, "same": None}
for a, c in itertools.combinations(polys, 2):
    if a[0] != c[0]:
        continue
    ax = [q[0] for q in a[3]]
    ay = [q[1] for q in a[3]]
    cx = [q[0] for q in c[3]]
    cy = [q[1] for q in c[3]]
    if (
        min(cx) - max(ax) > 1.5
        or min(ax) - max(cx) > 1.5
        or min(cy) - max(ay) > 1.5
        or min(ay) - max(cy) > 1.5
    ):
        continue
    g = pdist(a[3], c[3]) - a[4] - c[4]
    k = "same" if a[1] == c[1] and a[1] else "diff"
    if webs[k] is None or g < webs[k][0]:
        webs[k] = (g, f"{a[2]} [{a[1]}] / {c[2]} [{c[1]}]")
chk("mask web, different-net pads", webs["diff"][0], OSH["web"], webs["diff"][1])
if webs["same"]:
    print(
        f"  info mask web, same-net pads           {webs['same'][0]:8.4f} mm  {webs['same'][1]} (a web under OSH's min is removed, not a defect)"
    )

# silk
print("\nsilkscreen:")
SILK = (pcbnew.F_SilkS, pcbnew.B_SilkS)
lines, texts = [], []
items = (
    list(b.GetDrawings())
    + [g for f in b.GetFootprints() for g in f.GraphicalItems()]
    + [t for f in b.GetFootprints() for t in (f.Reference(), f.Value())]
    + [t for f in b.GetFootprints() for t in f.GetFields()]
)
seen = set()
for it in items:
    if id(it) in seen or it.GetLayer() not in SILK:
        continue
    seen.add(id(it))
    cls = it.GetClass()
    if cls == "PCB_SHAPE":
        if it.GetWidth() > 0:
            lines.append(
                (
                    mm(it.GetWidth()),
                    it.GetParentFootprint().GetReference()
                    if it.GetParentFootprint()
                    else "board",
                )
            )
    elif cls in ("PCB_TEXT", "PCB_FIELD", "FP_TEXT"):
        if hasattr(it, "IsVisible") and not it.IsVisible():
            continue
        # R13 2026-10-06: read GetTextThickness(), which is 0 when the file omits (thickness ...); KiCad then
        # plots with a default pen, so the 3V3 test point's reference false-FAILed at 0.000 mm.
        texts.append(
            (
                mm(it.GetTextHeight()),
                mm(it.GetEffectiveTextPenWidth()),
                it.GetShownText(False)[:20],
            )
        )
if lines:
    w = min(lines)
    n_rec = sum(1 for x in lines if x[0] < OSH["silk_rec"] - 1e-9)
    chk(
        "silk line width (min)",
        w[0],
        OSH["silk_min"],
        f"{w[1]}; {n_rec} of {len(lines)} lines under the 0.127 recommended",
    )
if texts:
    th = min(texts, key=lambda t: t[1])
    chk("silk text stroke (min)", th[1], OSH["silk_min"], f"'{th[2]}' height {th[0]}")
    print(
        f"  info smallest text height {min(t[0] for t in texts):.3f} mm over {len(texts)} visible texts"
    )

print(
    f"\n{'ALL WITHIN OSH 2-LAYER LIMITS' if not fails else 'OUTSIDE OSH LIMITS: ' + ', '.join(fails)}"
)
