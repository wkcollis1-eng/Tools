"""Pad-to-pad resistance of the power tracks, from dump.json: segments as rs*L/w resistors,
endpoints snapped to 1 um, T-junctions split, every endpoint inside a pad's copper tied to
that pad; multi-pin module terminals (U4 11+12, U4 5+6) treated as one node (the module
joins them). Leaves out pad copper, solder joints, sockets and the module internals.
R13 2026-10-06: overlapping colinear segments (routing debris) are solved as parallel copper, which
they are not; on the 19:25 save one read VIN+ 0.10 mohm low. Remove debris from the dump first.
R13 2026-10-06 (session 673cc9d3): on the 21:54 save VIN- joins by OVERLAP (3.85 mm run ends at 34.5,28.0, the
1.7 mm stub starts at 34.92,29.42), so its graph is open; lstsq on the singular matrix printed 0.16 mohm instead
of refusing. Now refused (nan). The same save charges Batt_SW +1.46 mohm for a 0.2 x 0.59 mm link that a 4 mm
end cap covers. Both are the 1-D model, not the board: use netdrop.py (2-D) when joins are overlaps or stubs.
rs is each dump's copper (dump.py's copper_um, read by common/copper.py), printed first per board; a dump
without copper_um is refused. Until 2026-10-08 it was RS = 1.724e-8 / 35e-6 (1 oz), fixed.
The nets, the pads each runs between and the sum line are each dump's profile (dump.py's profile,
common/boardprofile.py), printed per board; a dump without one is refused, as are two dumps whose profiles
name different nets. Until 2026-10-08 they were the Top Off Charger's PATHS, here, for every board."""

import json
import os
import sys
import numpy as np

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "common"),
)
import boardprofile  # noqa: E402  (one copy of what a board's profile holds)
import copper  # noqa: E402  (one copy of how a board's copper thickness is read)


def solve(d, net, frm, to, rs):  # rs: sheet resistance, ohm/sq
    segs = [t for t in d["tracks"] if t["net"] == net]

    def key(x, y):
        return (round(x, 3), round(y, 3))

    pts = {key(s["x1"], s["y1"]) for s in segs} | {key(s["x2"], s["y2"]) for s in segs}
    # split segments at endpoints lying on their interior (T-junctions)
    edges = []
    for s in segs:
        a = np.array([s["x1"], s["y1"]])
        b = np.array([s["x2"], s["y2"]])
        v = b - a
        L = np.hypot(*v)
        cuts = [0.0, 1.0]
        for p in pts:
            q = np.array(p) - a
            t = (q @ v) / (L * L)
            if 1e-6 < t < 1 - 1e-6 and abs(q[0] * v[1] - q[1] * v[0]) / L < 2e-3:
                cuts.append(t)
        cuts = sorted(set(cuts))
        for t0, t1 in zip(cuts, cuts[1:]):
            p0, p1 = a + t0 * v, a + t1 * v
            edges.append((key(*p0), key(*p1), rs * (t1 - t0) * L / s["w"], s["layer"]))
    pads = {
        (f["ref"], p["n"]): p for f in d["fps"] for p in f["pads"] if p["net"] == net
    }

    def members(spec):
        out = []
        for ref, n in spec:
            out += [k for k in pads if k[0] == ref and (n is None or k[1] == n)]
        return out

    A, B = members(frm), members(to)
    nodes = {}

    def nid(k):
        return nodes.setdefault(k, len(nodes))

    alias = {}
    for k, p in pads.items():
        tag = "A" if k in A else "B" if k in B else str(k)
        for q in pts:
            if (
                abs(q[0] - p["x"]) <= p["sx"] / 2 + 1e-3
                and abs(q[1] - p["y"]) <= p["sy"] / 2 + 1e-3
            ):
                alias[q] = ("pad", tag)
    E = [(nid(alias.get(u, u)), nid(alias.get(w, w)), r) for u, w, r, _ in edges]
    if ("pad", "A") not in nodes or ("pad", "B") not in nodes:
        return None, len(segs), sum(s["L"] for s in segs)
    n = len(nodes)
    G = np.zeros((n, n))
    for u, w, r in E:
        if u == w:
            continue
        G[u, u] += 1 / r
        G[w, w] += 1 / r
        G[u, w] -= 1 / r
        G[w, u] -= 1 / r
    a, b = nodes[("pad", "A")], nodes[("pad", "B")]
    seen, todo = (
        {a},
        [a],
    )  # refuse an open net rather than let lstsq invent a number (R13 above)
    while todo:
        i = todo.pop()
        for j in np.flatnonzero(G[i]):
            if j not in seen:
                seen.add(j)
                todo.append(j)
    if b not in seen:
        return None, len(segs), sum(s["L"] for s in segs)
    keep = [i for i in range(n) if i != b]
    Gr = G[np.ix_(keep, keep)]
    rhs = np.zeros(len(keep))
    rhs[keep.index(a)] = 1.0
    V = np.linalg.lstsq(Gr, rhs, rcond=None)[0]
    return V[keep.index(a)], len(segs), sum(s["L"] for s in segs)


# usage: tracknet.py <old dump.json> <new dump.json>   (dumps written by dump.py)
# Track keys are layer-agnostic, so every via is an ideal link: add barrel resistance by hand.
# PATHS, which netdrop.py imported, moved to each board's profile 2026-10-08
if __name__ == "__main__":
    res, prof = {}, {}
    for brd, path in (("old", sys.argv[1]), ("new", sys.argv[2])):
        d = json.load(open(path))
        # R8: an old dump says nothing about its copper; do not assume 35 um
        if "copper_um" not in d:
            sys.exit(
                f"{path}: no copper_um (written by dump.py before 2026-10-08); re-run dump.py"
            )
        try:
            t_cu, line = copper.thickness(d["copper_um"])
        except ValueError as e:
            sys.exit(f"{path}: copper: {e}")
        print(f"{brd}: {line}")
        # R8: a dump without a profile says nothing about which pads each net runs between
        if not d.get("profile"):
            sys.exit(
                f"{path}: no profile (dump.py found none, or predates 2026-10-08); re-run dump.py with profile=FILE"
            )
        try:
            boardprofile.validate(d["profile"], f"{path}: profile")
            boardprofile.need(
                d["profile"], "paths", d.get("profile_file"), "tracknet.py"
            )
        except ValueError as e:
            sys.exit(str(e))
        bad = boardprofile.unknown(
            d["profile"], {(f["ref"], p["n"]) for f in d["fps"] for p in f["pads"]}
        )
        if bad:
            sys.exit(
                f"{path}: profile {d.get('profile_file')} names pads this board does not have: {', '.join(bad)}"
            )
        print(f"{brd}: profile {d.get('profile_file')} (recorded in the dump)")
        prof[brd] = d["profile"]
        for net, (f, t) in boardprofile.paths(d["profile"]).items():
            res[(brd, net)] = solve(d, net, f, t, copper.RHO / t_cu)
    if list(prof["old"]["paths"]) != list(prof["new"]["paths"]) or prof["old"].get(
        "total"
    ) != prof["new"].get("total"):
        sys.exit(
            "the old and new dumps' profiles name different nets or sums; tracknet compares like with like"
        )
    print(
        f"{'net':9} {'old mohm':>9} {'new mohm':>9} {'new-old':>8}   (segs, summed mm old -> new)"
    )
    total = prof["new"].get("total") or {"name": None, "nets": []}
    tot = {"old": 0, "new": 0}
    for net in prof["new"]["paths"]:
        o, n_ = res[("old", net)], res[("new", net)]
        ro, rn = (o[0] or float("nan")) * 1e3, (n_[0] or float("nan")) * 1e3
        if net in total["nets"]:
            tot["old"] += ro
            tot["new"] += rn
        print(
            f"{net:9} {ro:9.2f} {rn:9.2f} {rn - ro:+8.2f}   ({o[1]}, {o[2]:.1f} -> {n_[1]}, {n_[2]:.1f})"
        )
    if total["name"] is not None:
        print(
            f"{total['name']:27} old {tot['old']:.2f}  new {tot['new']:.2f}  diff {tot['new'] - tot['old']:+.2f} mohm"
        )
