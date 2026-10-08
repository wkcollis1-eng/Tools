"""2-D resistance of one net's copper between two pad groups: its tracks, THT pads, vias and zone fills.

Finite differences on the rasterised copper, the discretisation of the repo's pcb/gnd_drop.py (whose
parser this imports). It answers what tracknet.py (1-D, rs*L/w per segment, centre to centre) cannot:
what copper wider than the pads, joins made by overlap rather than a shared endpoint, and stubs inside
other copper do to the pad-to-pad resistance. Written 2026-10-06 (session 673cc9d3) for the 21:54 save,
on which tracknet reads VIN- as open (overlap join) and charges Batt_SW for a 0.2 mm stub that a 4 mm
end cap covers.

Contact model at the source and sink pads (--contact):
  pad    the whole pad copper is one equipotential node: a solder-filled joint (gnd_drop's model)
  drill  only the drill circle is (the pin); the annular ring is ordinary copper
A soldered THT pin lies between the two [I]. Every other pad of the net, and every via, ties F.Cu to
B.Cu over its own copper as one ideal node. Leaves out solder joints, pins, socket contacts, modules.

The copper thickness is the board's own, from its stackup (common/copper.py), and is printed first;
--t-um overrides it. Until 2026-10-08 it was 35 um, fixed.

usage:
  python netdrop.py <board> [--h 0.05] [--contact pad|drill] [--net NET ...] [--t-um N]
  python netdrop.py --self-test
"""

import argparse
import os
import sys

import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla
from scipy.sparse.csgraph import connected_components

# gnd_drop and tracknet sit beside this file in Tools/pcb-eval/solve (2026-10-08: was the
# DIY-LiFePO4-UPS repo's Top-Off-Charger/pcb and each kit's tools/), also when imported
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gnd_drop import RHO, kid, kids, netname, parse, xf  # noqa: E402
from tracknet import PATHS  # noqa: E402  (one definition of which pads each net runs between)

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "common"),
)
import copper  # noqa: E402  (one copy of how a board's copper thickness is read)


class NotConnected(Exception):
    pass


def pads_of(T, net):
    """[(ref, number, x, y, sx, sy, shape, drill, layers)] for every pad on `net`."""
    out = []
    for fp in kids(T, "footprint"):
        at = kid(fp, "at")
        ref = {p[1]: p[2] for p in kids(fp, "property")}.get("Reference")
        for p in kids(fp, "pad"):
            if netname(p) != net:
                continue
            pa = kid(p, "at")
            x, y = xf(at, float(pa[1]), float(pa[2]))
            sz = kid(p, "size")
            sx, sy = float(sz[1]), float(sz[2])
            if abs((float(pa[3]) if len(pa) > 3 else 0) % 180 - 90) < 1:
                sx, sy = sy, sx
            dr = kid(p, "drill")
            drill = (
                float(dr[1])
                if dr and dr[1] != "oval"
                else (float(dr[2]) if dr else 0.0)
            )
            lay = (
                (0, 1)
                if p[2] == "thru_hole"
                else tuple(
                    {"F.Cu": 0, "B.Cu": 1}[n]
                    for n in kid(p, "layers")[1:]
                    if n in ("F.Cu", "B.Cu")
                )
            )
            out.append((ref, p[1], x, y, sx, sy, p[3], drill, lay))
    return out


def solve(T, net, frm, to, h=0.05, contact="pad", t_cu=35e-6):
    """Ohms between pad groups `frm` and `to` [(ref, number or None)] on `net`."""
    rs = RHO / t_cu
    segs = [s for s in kids(T, "segment") if netname(s) == net]
    if kids(T, "arc") and any(netname(a) == net for a in kids(T, "arc")):
        raise ValueError(
            f"{net} has arc tracks; this tool rasterises straight segments only"
        )
    vias = [v for v in kids(T, "via") if netname(v) == net]
    pads = pads_of(T, net)
    fills = [
        fp
        for z in kids(T, "zone")
        if (kid(z, "net_name") or kid(z, "net") or [None, ""])[1] == net
        for fp in kids(z, "filled_polygon")
    ]
    # window: the net's copper plus a margin, so the grid holds only what matters
    xs, ys = [], []
    for s in segs:
        w = float(kid(s, "width")[1])
        for e in ("start", "end"):
            xs += [float(kid(s, e)[1]) - w, float(kid(s, e)[1]) + w]
            ys += [float(kid(s, e)[2]) - w, float(kid(s, e)[2]) + w]
    for _, _, x, y, sx, sy, *_ in pads:
        xs += [x - sx, x + sx]
        ys += [y - sy, y + sy]
    for fp in fills:
        for q in kids(kid(fp, "pts"), "xy"):
            xs.append(float(q[1]))
            ys.append(float(q[2]))
    X0, Y0 = min(xs) - 1, min(ys) - 1
    NX, NY = int((max(xs) + 1 - X0) / h) + 1, int((max(ys) + 1 - Y0) / h) + 1
    xc, yc = X0 + (np.arange(NX) + 0.5) * h, Y0 + (np.arange(NY) + 0.5) * h
    XX, YY = np.meshgrid(xc, yc)
    cu = np.zeros((2, NY, NX), bool)

    def win(x0, x1, y0, y1):
        i0, i1 = max(0, int((x0 - X0) / h) - 1), min(NX, int((x1 - X0) / h) + 2)
        j0, j1 = max(0, int((y0 - Y0) / h) - 1), min(NY, int((y1 - Y0) / h) + 2)
        return slice(j0, j1), slice(i0, i1)

    def shape_mask(x, y, sx, sy, kind):  # as gnd_drop.solve's
        sj, si = win(x - sx, x + sx, y - sy, y + sy)
        dx, dy = XX[sj, si] - x, YY[sj, si] - y
        if kind == "circle" or (kind == "oval" and abs(sx - sy) < 1e-6):
            m = dx**2 + dy**2 <= (sx / 2) ** 2
        elif kind == "oval":
            r = min(sx, sy) / 2
            ex, ey = max(0, sx / 2 - r), max(0, sy / 2 - r)
            m = (
                np.maximum(abs(dx) - ex, 0) ** 2 + np.maximum(abs(dy) - ey, 0) ** 2
            ) <= r**2
        else:  # rect / roundrect, 0/90/180/270 only
            m = (abs(dx) <= sx / 2) & (abs(dy) <= sy / 2)
        return sj, si, m

    if fills:
        from matplotlib.path import Path

        for fp in fills:
            P = np.array(
                [(float(q[1]), float(q[2])) for q in kids(kid(fp, "pts"), "xy")]
            )
            sj, si = win(P[:, 0].min(), P[:, 0].max(), P[:, 1].min(), P[:, 1].max())
            pts = np.column_stack([XX[sj, si].ravel(), YY[sj, si].ravel()])
            cu[{"F.Cu": 0, "B.Cu": 1}[kid(fp, "layer")[1]], sj, si] |= (
                Path(P).contains_points(pts).reshape(XX[sj, si].shape)
            )
    for s in segs:
        a = np.array([float(v) for v in kid(s, "start")[1:3]])
        b = np.array([float(v) for v in kid(s, "end")[1:3]])
        w = float(kid(s, "width")[1])
        L = {"F.Cu": 0, "B.Cu": 1}[kid(s, "layer")[1]]
        sj, si = win(
            min(a[0], b[0]) - w,
            max(a[0], b[0]) + w,
            min(a[1], b[1]) - w,
            max(a[1], b[1]) + w,
        )
        px, py = XX[sj, si] - a[0], YY[sj, si] - a[1]
        d = b - a
        t = np.clip((px * d[0] + py * d[1]) / max(d @ d, 1e-12), 0, 1)
        cu[L, sj, si] |= (px - t * d[0]) ** 2 + (py - t * d[1]) ** 2 <= (w / 2) ** 2

    def members(spec):
        return [
            p
            for p in pads
            if any(p[0] == r and (n is None or p[1] == n) for r, n in spec)
        ]

    A_, B_ = members(frm), members(to)
    if not A_ or not B_:
        raise ValueError(f"{net}: no pad for {frm if not A_ else to}")
    groups = {"SRC": [], "SNK": []}
    for p in pads:
        ref, n, x, y, sx, sy, kind, drill, lay = p
        sj, si, m = shape_mask(x, y, sx, sy, kind)
        for L in lay:
            cu[L, sj, si] |= m
        tag = "SRC" if p in A_ else "SNK" if p in B_ else f"{ref}.{n}"
        if tag in ("SRC", "SNK") and contact == "drill":
            if not drill:
                raise ValueError(
                    f"{ref}.{n} has no drill; --contact drill needs THT terminals"
                )
            sj, si, m = shape_mask(x, y, drill, drill, "circle")
        groups.setdefault(tag, []).extend((L, sj, si, m) for L in lay)
    for v in vias:
        x, y, d = (
            float(kid(v, "at")[1]),
            float(kid(v, "at")[2]),
            float(kid(v, "size")[1]),
        )
        sj, si, m = shape_mask(x, y, d, d, "circle")
        cu[0, sj, si] |= m
        cu[1, sj, si] |= m
        groups[f"via@{x},{y}"] = [(0, sj, si, m), (1, sj, si, m)]

    N = NY * NX
    node = np.full(2 * N, -1, np.int64)
    cid = np.flatnonzero(cu.ravel())
    node[cid] = np.arange(cid.size)
    nxt, gnode = cid.size, {}
    for lab, parts in groups.items():
        for L, sj, si, m in parts:
            node[
                (
                    L * N
                    + np.add.outer(
                        np.arange(sj.start, sj.stop) * NX, np.arange(si.start, si.stop)
                    )
                )[m]
            ] = nxt
        gnode[lab] = nxt
        nxt += 1
    c3, n3 = cu, node.reshape(2, NY, NX)
    rows, cols = [], []
    for L in (0, 1):
        for a, b in (
            ((slice(None), slice(0, -1)), (slice(None), slice(1, None))),
            ((slice(0, -1), slice(None)), (slice(1, None), slice(None))),
        ):
            ok = c3[L][a] & c3[L][b]
            u, w = n3[L][a][ok], n3[L][b][ok]
            k = u != w
            rows.append(u[k])
            cols.append(w[k])
    u, w = np.concatenate(rows), np.concatenate(cols)
    g = np.full(u.size, 1.0 / rs)
    used = np.unique(np.concatenate([u, w]))
    remap = -np.ones(nxt, np.int64)
    remap[used] = np.arange(used.size)
    u, w = remap[u], remap[w]
    M = used.size
    A = sp.coo_matrix(
        (
            np.concatenate([-g, -g, g, g]),
            (np.concatenate([u, w, u, w]), np.concatenate([w, u, u, w])),
        ),
        (M, M),
    ).tocsr()
    s, k = remap[gnode["SRC"]], remap[gnode["SNK"]]
    if s < 0 or k < 0:
        raise NotConnected(f"{net}: a terminal has no copper neighbour")
    _, comp = connected_components(A, directed=False)
    if comp[s] != comp[k]:
        raise NotConnected(f"{net}: {frm} and {to} are not joined by copper")
    keep = np.flatnonzero(comp == comp[k])
    red = keep[keep != k]
    rhs = np.zeros(red.size)
    rhs[np.flatnonzero(red == s)[0]] = 1.0
    V = spla.spsolve(A[red][:, red].tocsc(), rhs)
    return V[np.flatnonzero(red == s)[0]]


def synth(L, w, pad=2.0, drill=1.1, shape="circle", gap=0.0):
    """Two pads `L` mm apart (centres) joined by one track of width `w`; `gap` > 0 cuts the track."""
    seg = (
        f'(segment (start 0 0) (end {L} 0) (width {w}) (layer "F.Cu") (net "N"))'
        if not gap
        else f'(segment (start 0 0) (end {L / 2 - gap / 2 - w / 2} 0) (width {w}) (layer "F.Cu") (net "N"))'
        f'(segment (start {L / 2 + gap / 2 + w / 2} 0) (end {L} 0) (width {w}) (layer "F.Cu") (net "N"))'
    )
    fp = (
        '(footprint "t" (at {x} 0) (property "Reference" "{r}") (pad "1" thru_hole {sh} (at 0 0) '
        '(size {sx} {sy}) (drill {d}) (layers "*.Cu") (net "N")))'
    )
    sx, sy = (
        (pad, pad) if shape == "circle" else (1.0, w)
    )  # rect: 1 mm long, the track's full width
    return parse(
        "(kicad_pcb "
        + fp.format(x=0, r="A", sh=shape, sx=sx, sy=sy, d=drill)
        + fp.format(x=L, r="B", sh=shape, sx=sx, sy=sy, d=drill)
        + seg
        + ")"
    )


def self_test():
    ok = True
    rs = RHO / 35e-6
    # 1: full-width rect pads 1 mm long at each end -> exact rs*(L-1)/w between their inner edges
    for L, w in ((10, 2.0), (20, 2.95), (6, 3.85)):
        exact = rs * (L - 1) / w
        for h in (0.05, 0.025):
            got = solve(synth(L, w, shape="rect"), "N", [("A", None)], [("B", None)], h)
            err = (got - exact) / exact
            print(
                f"strip L={L} w={w} h={h}: {got * 1e3:.4f} vs {exact * 1e3:.4f} mohm exact ({err * 100:+.2f}%)"
            )
            ok &= abs(err) < (0.03 if h == 0.05 else 0.015)
    # 2: a cut track must be refused, not solved
    try:
        solve(synth(10, 2.0, gap=0.2), "N", [("A", None)], [("B", None)])
        print("cut track: SOLVED - the connectivity check did not fire")
        ok = False
    except NotConnected as e:
        print(f"cut track: refused ({e})")
    # 3: a missing terminal must be refused, not guessed at
    try:
        solve(synth(10, 2.0), "N", [("A", None)], [("C", None)])
        print("no pad C: SOLVED - the pad selection did not fire")
        ok = False
    except ValueError as e:
        print(f"no pad C: refused ({e})")
    print("SELF-TEST PASSED" if ok else "SELF-TEST FAILED")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("board", nargs="?")
    ap.add_argument("--h", type=float, default=0.05)
    ap.add_argument("--contact", choices=("pad", "drill"), default="pad")
    ap.add_argument("--net", nargs="*", default=list(PATHS))
    ap.add_argument(
        "--t-um",
        type=float,
        default=None,
        help="copper thickness, um (default: the board's stackup)",
    )
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    text = open(a.board, encoding="utf-8").read()
    try:
        t_cu, line = copper.thickness(text, a.t_um)
    except ValueError as e:
        ap.error(f"copper: {e}; give --t-um")
    print(line)
    T = parse(text)
    for net in a.net:
        frm, to = PATHS[net]
        try:
            r = solve(T, net, frm, to, a.h, a.contact, t_cu)
            print(f"{net:9} {r * 1e3:8.3f} mohm   h={a.h} contact={a.contact}")
        except (NotConnected, ValueError) as e:
            print(f"{net:9}  REFUSED: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
