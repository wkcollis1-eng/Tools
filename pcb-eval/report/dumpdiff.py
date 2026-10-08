"""What changed between two dump.py json files: edge, copper thickness, footprints and pads, tracks, vias, zones.
usage: dumpdiff.py <old.json> <new.json>"""

import json
import sys

A = json.load(open(sys.argv[1]))
B = json.load(open(sys.argv[2]))
print("edge", A["edge"] == B["edge"], B["edge"])
cu = [D.get("copper_um", "not recorded (dump.py before 2026-10-08)") for D in (A, B)]
print("copper_um", cu[0] == cu[1], cu[1])
fa = {f["ref"]: f for f in A["fps"]}
fb = {f["ref"]: f for f in B["fps"]}
print("fps added", sorted(set(fb) - set(fa)), "removed", sorted(set(fa) - set(fb)))
for r in sorted(set(fa) & set(fb)):
    a, b = fa[r], fb[r]
    diffs = [k for k in a if a[k] != b.get(k)]
    if diffs:
        print(" CHANGED", r, diffs)
        if "pads" in diffs:
            pa = {p["n"]: p for p in a["pads"]}
            pb = {p["n"]: p for p in b["pads"]}
            for n in sorted(set(pa) | set(pb)):
                if n not in pb:
                    print("    pad", n, "REMOVED", pa[n])
                    continue
                if n not in pa:
                    print("    pad", n, "ADDED", pb[n])
                    continue
                if pa[n] != pb[n]:
                    print(
                        "    pad",
                        n,
                        {
                            k: (pa[n][k], pb[n].get(k))
                            for k in pa[n]
                            if pa[n][k] != pb[n].get(k)
                        },
                    )
        for k in diffs:
            if k != "pads":
                print("   ", k, a[k], "->", b[k])
for r in sorted(set(fb) - set(fa)):
    f = fb[r]
    print(" NEW", r, f["val"], f["fpid"], f["x"], f["y"], f["rot"], f["side"])
    [print("    pad", p) for p in f["pads"]]


def key(t):
    return (
        t["net"],
        t["layer"],
        round(t["w"], 3),
        tuple(
            sorted(
                [
                    (round(t["x1"], 3), round(t["y1"], 3)),
                    (round(t["x2"], 3), round(t["y2"], 3)),
                ]
            )
        ),
    )


ta = set(map(key, A["tracks"]))
tb = set(map(key, B["tracks"]))
print("tracks", len(A["tracks"]), "->", len(B["tracks"]))
for t in sorted(tb - ta):
    print("  + track", t)
for t in sorted(ta - tb):
    print("  - track", t)


def vk(v):
    return (v["net"], v["x"], v["y"], v["d"], v["drill"])


va = set(map(vk, A["vias"]))
vb = set(map(vk, B["vias"]))
print("vias", len(va), "->", len(vb), "+", sorted(vb - va), "-", sorted(va - vb))
for za, zb in zip(A["zones"], B["zones"]):
    print(
        " zone",
        {k: (za[k], zb[k]) for k in za if za[k] != zb[k]} or "same",
        zb["net"],
        zb["layers"],
        zb["area_mm2"],
    )
print(
    "zones count",
    len(A["zones"]),
    len(B["zones"]),
    "| texts same:",
    A["texts"] == B["texts"],
)
