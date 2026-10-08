# For each copper layer, list GND fill islands: bbox, holes, and the GND vias and pads that touch each.
# A via or pad touches an island when its copper on that layer, grown by 0.01 mm, overlaps the fill: a
# pad on thermal reliefs sits in a cutout and meets the fill only at its spokes. Tracks are not checked,
# so an island tagged "no GND via or pad" may still reach GND through a track.
# R13 2026-10-08: vias and pads were counted when their centre lay in the fill. That missed every pad on
# thermal reliefs: on the rev 0.8 Top Off Charger four slivers between U4's GND pins printed
# "GND vias 0  GND pads []" though each touches a U4 GND pad, and the main pour listed none of the 17
# GND pads it touches. Found by the pcb-eval fault tests (Tools 8317005).
# usage: islands.py <board> [gnd=NAME]   the ground net is GND unless given, printed first, and refused when
# the board has no net of that name (common/groundnet.py). Until 2026-10-08 GND was assumed.
import os
import sys

import pcbnew

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "common"),
)
import groundnet  # noqa: E402  (one copy of how the ground net is named)

GROW = pcbnew.FromMM(0.01)


def copper(item, lay):
    s = pcbnew.SHAPE_POLY_SET()
    item.TransformShapeToPolygon(
        s, lay, GROW, pcbnew.FromMM(0.005), pcbnew.ERROR_OUTSIDE
    )
    return s


def touching(isl, shapes):
    bb = isl.BBox()
    hit = []
    for item, s in shapes:
        if s.OutlineCount() and s.BBox().Intersects(bb):
            s2 = pcbnew.SHAPE_POLY_SET(s)
            s2.BooleanIntersection(isl)
            if s2.OutlineCount():
                hit.append(item)
    return hit


def islands(b, lay, net="GND"):
    """[(island, vias, pads)] for net's fill on layer lay; island is a SHAPE_POLY_SET with its holes."""
    merged = pcbnew.SHAPE_POLY_SET()
    for z in b.Zones():
        if z.GetNetname() == net and z.IsOnLayer(lay):
            merged.BooleanAdd(z.GetFilledPolysList(lay))
    merged.Simplify()
    vias = [
        t for t in b.GetTracks() if t.GetClass() == "PCB_VIA" and t.GetNetname() == net
    ]
    pads = [
        p
        for f in b.GetFootprints()
        for p in f.Pads()
        if p.GetNetname() == net and p.IsOnLayer(lay)
    ]
    vs = [(v, copper(v, lay)) for v in vias]
    ps = [(p, copper(p, lay)) for p in pads]
    out = []
    for i in range(merged.OutlineCount()):
        isl = merged.Subset(i, i + 1)
        out.append((isl, touching(isl, vs), touching(isl, ps)))
    return out


if __name__ == "__main__":
    b = pcbnew.LoadBoard(sys.argv[1])
    given = next((a[4:] for a in sys.argv[2:] if a.startswith("gnd=")), None)
    try:
        gnd, line = groundnet.pick(given, groundnet.board_nets(b), "gnd=NAME")
    except ValueError as e:
        sys.exit(str(e))
    print(line)
    mm = pcbnew.ToMM
    for lay, name in ((pcbnew.F_Cu, "F.Cu"), (pcbnew.B_Cu, "B.Cu")):
        found = islands(b, lay, gnd)
        print(name, "islands", len(found))
        for i, (isl, vias, pads) in enumerate(found):
            bb = isl.BBox()
            npd = [
                p.GetParentFootprint().GetReference() + "." + p.GetNumber()
                for p in pads
            ]
            print(
                "  #%d bbox x %.2f-%.2f y %.2f-%.2f  holes %d  %s vias %d  %s pads %s%s"
                % (
                    i,
                    mm(bb.GetX()),
                    mm(bb.GetRight()),
                    mm(bb.GetY()),
                    mm(bb.GetBottom()),
                    isl.HoleCount(0),
                    gnd,
                    len(vias),
                    gnd,
                    npd,
                    "" if vias or pads else f"  <- no {gnd} via or pad",
                )
            )
