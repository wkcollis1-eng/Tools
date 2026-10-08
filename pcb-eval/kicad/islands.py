# For each copper layer, list GND fill islands: area, bbox, and how many GND vias / PTH GND pads land in each.
import sys
import pcbnew

b = pcbnew.LoadBoard(sys.argv[1])
mm = pcbnew.ToMM
gnd = [
    v for v in b.GetTracks() if v.GetClass() == "PCB_VIA" and v.GetNetname() == "GND"
]
gpads = [p for f in b.GetFootprints() for p in f.Pads() if p.GetNetname() == "GND"]
for lay, name in ((pcbnew.F_Cu, "F.Cu"), (pcbnew.B_Cu, "B.Cu")):
    merged = pcbnew.SHAPE_POLY_SET()
    for z in b.Zones():
        if z.GetNetname() == "GND" and z.IsOnLayer(lay):
            merged.BooleanAdd(z.GetFilledPolysList(lay))
    merged.Simplify()
    print(name, "islands", merged.OutlineCount())
    for i in range(merged.OutlineCount()):
        o = merged.Outline(i)
        bb = o.BBox()
        area = merged.Area() if merged.OutlineCount() == 1 else None
        nv = sum(1 for v in gnd if merged.Contains(v.GetPosition(), i))
        npd = [
            p.GetParentFootprint().GetReference() + "." + p.GetNumber()
            for p in gpads
            if merged.Contains(p.GetPosition(), i)
        ]
        print(
            "  #%d bbox x %.2f-%.2f y %.2f-%.2f  holes %d  GND vias %d  GND pads %s"
            % (
                i,
                mm(bb.GetX()),
                mm(bb.GetRight()),
                mm(bb.GetY()),
                mm(bb.GetBottom()),
                merged.HoleCount(i),
                nv,
                npd,
            )
        )
