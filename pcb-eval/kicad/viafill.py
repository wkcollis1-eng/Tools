"""Does each via sit in its own net's zone FILL on each copper layer it spans? (KiCad python). 2026-10-06, session 4dcbc5e4.
usage: viafill.py <board> [fill=12]    (uses the fill saved in the file; refill first if the copper moved)
A stitching via the fill no longer reaches stitches nothing, and DRC does not say so until it is fully cut off
(via_dangling). Rule, as in viamove.py: centre and >= fill= of 16 points just outside the via pad in the fill.
Prints each via that misses on a layer with its count, then the totals.
R13 2026-10-06: the first version tested the centre only and passed f1_final, whose widths had left 4 GND
vias with 7-9 of 16 points in the F.Cu fill (viamove.py's fill-loss trigger found them)."""

import math
import sys
import pcbnew

FILLMIN = int(next((a[5:] for a in sys.argv[2:] if a.startswith("fill=")), 12))
b = pcbnew.LoadBoard(sys.argv[1])
u = 1e6
miss = 0
n = 0
for v in b.GetTracks():
    if v.GetClass() != "PCB_VIA":
        continue
    zones = [
        z
        for z in b.Zones()
        if z.GetNetname() == v.GetNetname() and not z.GetIsRuleArea()
    ]
    if not zones:
        continue
    n += 1
    x, y = v.GetPosition().x / u, v.GetPosition().y / u
    for ly in (pcbnew.F_Cu, pcbnew.B_Cu):

        def infill(px, py):
            return any(
                z.IsOnLayer(ly)
                and z.HitTestFilledArea(
                    ly, pcbnew.VECTOR2I(pcbnew.FromMM(px), pcbnew.FromMM(py))
                )
                for z in zones
            )

        r = v.GetWidth(ly) / u / 2 + 0.01
        k = sum(
            infill(x + r * math.cos(i * math.pi / 8), y + r * math.sin(i * math.pi / 8))
            for i in range(16)
        )
        if not infill(x, y) or k < FILLMIN:
            miss += 1
            print(
                f"{v.GetNetname()} via @{x:.2f},{y:.2f} {b.GetLayerName(ly)} {k}/16{'' if infill(x, y) else ' centre out'}"
            )
print(f"{n} zone-net vias, {miss} layer misses (rule: centre + >= {FILLMIN}/16)")
