"""Compare kicad-cli DRC json reports against a baseline: counts, and violations added/removed.
usage: drcset.py <baseline.json> <other.json> [...]"""

import json
import sys
from collections import Counter


def load(p):
    d = json.load(open(p))
    v = []
    for sec in ("violations", "unconnected_items", "schematic_parity"):
        for x in d.get(sec, []):
            items = tuple(sorted(i.get("description", "") for i in x.get("items", [])))
            v.append((sec, x.get("severity"), x.get("type"), items))
    return Counter(v)


base = load(sys.argv[1])
for p in sys.argv[2:]:
    o = load(p)
    sev = Counter(k[1] for k in o.elements())
    unc = sum(n for k, n in o.items() if k[0] == "unconnected_items")
    print(f"{p}: {dict(sev)}, unconnected {unc}")
    # R13 2026-10-06: printed each differing key once, hiding its count; on the 19:25 save a
    # +2 silk_overlap read as +1, so the +/- lines summed to 26 against a 27-warning report.
    for k, n in (o - base).items():
        print("   + ", k[1], k[2], k[3], f"x{n}" if n > 1 else "")
    for k, n in (base - o).items():
        print("   - ", k[1], k[2], k[3], f"x{n}" if n > 1 else "")
    if o == base:
        print("   set-identical to baseline")
