"""Zone connection of every pad on the ground net, and every zone's own settings (KiCad python).
usage: padconn.py <board> [gnd=NAME]   the ground net is GND unless given, printed first, and refused when the
board has no net of that name (common/groundnet.py). Until 2026-10-08 GND was assumed, and this line said
"every power/GND through-hole pad": it has always printed every GND pad, SMD too, and no power pad."""

import os
import sys
import pcbnew

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "common"),
)
import groundnet  # noqa: E402  (one copy of how the ground net is named)

b = pcbnew.LoadBoard(sys.argv[1])
given = next((a[4:] for a in sys.argv[2:] if a.startswith("gnd=")), None)
try:
    gnd, line = groundnet.pick(given, groundnet.board_nets(b), "gnd=NAME")
except ValueError as e:
    sys.exit(str(e))
print(line)
u = 1e6
names = {
    pcbnew.ZONE_CONNECTION_INHERITED: "inherit",
    pcbnew.ZONE_CONNECTION_NONE: "none",
    pcbnew.ZONE_CONNECTION_THERMAL: "thermal",
    pcbnew.ZONE_CONNECTION_FULL: "solid",
    pcbnew.ZONE_CONNECTION_THT_THERMAL: "tht_thermal",
}
for z in b.Zones():
    print(
        "zone",
        z.GetNetname(),
        [b.GetLayerName(ly) for ly in z.GetLayerSet().Seq()],
        "conn",
        names.get(z.GetPadConnection()),
        "clear",
        z.GetLocalClearance(),
        "spoke",
        z.GetThermalReliefSpokeWidth() / u,
        "gap",
        z.GetThermalReliefGap() / u,
        "minw",
        z.GetMinThickness() / u,
    )
for f in b.GetFootprints():
    for p in f.Pads():
        if p.GetNetname() == gnd:
            print(
                f"{f.GetReference()}.{p.GetNumber()}",
                "pad:",
                names.get(p.GetLocalZoneConnection()),
                "fp:",
                names.get(f.GetLocalZoneConnection()),
            )
