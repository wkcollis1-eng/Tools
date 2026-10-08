"""Narrow every track of the named nets to one width, in place (centrelines unchanged), refill, save.
usage: narrow.py <in.kicad_pcb> <out.kicad_pcb> <width_mm> <net> [<net> ...]"""

import shutil
import sys
import pcbnew
from pathlib import Path

src, out, w = sys.argv[1], sys.argv[2], float(sys.argv[3])
nets = set(sys.argv[4:])
b = pcbnew.LoadBoard(src)
n = 0
for t in b.GetTracks():
    if t.GetClass() == "PCB_TRACK" and t.GetNetname() in nets:
        t.SetWidth(pcbnew.FromMM(w))
        n += 1
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(out, b)
shutil.copy(Path(src).with_suffix(".kicad_pro"), Path(out).with_suffix(".kicad_pro"))
print(f"{n} segments of {sorted(nets)} -> {w} mm")
for z in b.Zones():
    print(
        " zone",
        z.GetNetname(),
        [b.GetLayerName(ly) for ly in z.GetLayerSet().Seq()],
        round(z.GetFilledArea() / 1e12, 1),
        "mm2",
    )
