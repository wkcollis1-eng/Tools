"""Zone connection of every power/GND through-hole pad, and the zones' own settings (KiCad python)."""

import sys
import pcbnew

b = pcbnew.LoadBoard(sys.argv[1])
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
        if p.GetNetname() == "GND":
            print(
                f"{f.GetReference()}.{p.GetNumber()}",
                "pad:",
                names.get(p.GetLocalZoneConnection()),
                "fp:",
                names.get(f.GetLocalZoneConnection()),
            )
