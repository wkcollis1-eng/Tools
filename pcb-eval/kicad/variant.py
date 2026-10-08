"""Build a what-if copy of a board, refill, save (KiCad python). 2026-10-06, session 4dcbc5e4.
usage: variant.py <in.kicad_pcb> <out.kicad_pcb> [solid=REF.PAD] [w=NET:LAYER:WIDTH[:X1,Y1,X2,Y2]] ...
  solid=TB1.1               set that pad's zone connection to solid (full)
  relief=TB1.1              clear that pad's override: back to the zone's thermal relief (2026-10-07)
  pad=TB1.1:2.6 | pad=TB1.1:2.0,3.0   set that pad's size (mm); unequal sizes make it OVAL (2026-10-07)
  w=VIN+:B.Cu:3.0           set every NET track on LAYER to WIDTH mm
  w=VIN+:B.Cu:4.0:37.46,31.62,37.46,51.81   only the segment with those end points (either order, 0.02 mm)
  del=NET:LAYER:X1,Y1,X2,Y2  delete that track segment (debris)
  via=X,Y:X2,Y2             move the via at X,Y (0.02 mm) to X2,Y2
  mv=NET:LAYER:X,Y:DX,DY    move every NET track end on LAYER at X,Y (0.003 mm) by exactly DX,DY mm (joins stay joined)
Every op must hit at least one item or the script stops (R7: an op that matched nothing is not a variant)."""

import shutil
import sys
import pcbnew
from pathlib import Path

src, out = sys.argv[1], sys.argv[2]
b = pcbnew.LoadBoard(src)
mm = pcbnew.FromMM
u = 1e6
doomed = []  # removed after every op has matched: b.Remove() mid-loop breaks the next GetTracks()
for op in sys.argv[3:]:
    kind, arg = op.split("=", 1)
    hits = 0
    if kind in ("solid", "relief"):
        ref, num = arg.split(".")
        conn = (
            pcbnew.ZONE_CONNECTION_FULL
            if kind == "solid"
            else pcbnew.ZONE_CONNECTION_INHERITED
        )
        for p in b.FindFootprintByReference(ref).Pads():
            if p.GetNumber() == num:
                p.SetLocalZoneConnection(conn)
                hits += 1
    elif kind == "pad":
        refpad, size = arg.split(":")
        ref, num = refpad.split(".")
        sx, sy = (float(v) for v in (size.split(",") * 2)[:2])
        for p in b.FindFootprintByReference(ref).Pads():
            if p.GetNumber() == num:
                if sx != sy:
                    p.SetShape(pcbnew.PAD_SHAPE_OVAL)
                p.SetSize(pcbnew.VECTOR2I(mm(sx), mm(sy)))
                hits += 1
    elif kind in ("w", "del"):
        parts = arg.split(":")
        if kind == "del":
            parts = parts[:2] + ["0"] + parts[2:]
        net, layer, w = parts[0], parts[1], float(parts[2])
        seg = [float(v) for v in parts[3].split(",")] if len(parts) > 3 else None
        lid = b.GetLayerID(layer)
        assert kind == "w" or seg, "del needs X1,Y1,X2,Y2"
        for t in list(b.GetTracks()):
            if (
                t.GetClass() != "PCB_TRACK"
                or t.GetNetname() != net
                or t.GetLayer() != lid
            ):
                continue
            if seg:
                a = (t.GetStart().x / u, t.GetStart().y / u)
                e = (t.GetEnd().x / u, t.GetEnd().y / u)

                def near(p, q):
                    return abs(p[0] - q[0]) < 0.02 and abs(p[1] - q[1]) < 0.02

                s1, s2 = (seg[0], seg[1]), (seg[2], seg[3])
                if not ((near(a, s1) and near(e, s2)) or (near(a, s2) and near(e, s1))):
                    continue
            if kind == "del":
                doomed.append(t)
            else:
                t.SetWidth(mm(w))
            hits += 1
    elif kind == "mv":
        net, layer, xy, dxy = arg.split(":")
        (fx, fy), (dx, dy) = (
            [float(v) for v in xy.split(",")],
            [float(v) for v in dxy.split(",")],
        )
        lid = b.GetLayerID(layer)

        def hit(q):
            return abs(q.x / u - fx) < 0.003 and abs(q.y / u - fy) < 0.003

        for t in [
            t
            for t in b.GetTracks()
            if t.GetClass() == "PCB_TRACK"
            and t.GetNetname() == net
            and t.GetLayer() == lid
        ]:
            for get, put in ((t.GetStart, t.SetStart), (t.GetEnd, t.SetEnd)):
                q = get()
                if hit(q):
                    put(pcbnew.VECTOR2I(q.x + mm(dx), q.y + mm(dy)))
                    hits += 1
    elif kind == "via":
        (fx, fy), (tx, ty) = [
            [float(v) for v in xy.split(",")] for xy in arg.split(":")
        ]
        for t in b.GetTracks():
            if (
                t.GetClass() == "PCB_VIA"
                and abs(t.GetPosition().x / u - fx) < 0.02
                and abs(t.GetPosition().y / u - fy) < 0.02
            ):
                t.SetPosition(pcbnew.VECTOR2I(mm(tx), mm(ty)))
                hits += 1
    else:
        sys.exit(f"unknown op {op}")
    print(f"{op}: {hits} item(s)")
    if hits == 0:
        sys.exit(f"op {op} matched nothing")
for t in doomed:
    b.Remove(t)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(out, b)
shutil.copy(Path(src).with_suffix(".kicad_pro"), Path(out).with_suffix(".kicad_pro"))
for z in b.Zones():
    print(
        " zone",
        z.GetNetname(),
        [b.GetLayerName(ly) for ly in z.GetLayerSet().Seq()],
        round(z.GetFilledArea() / 1e12, 1),
        "mm2",
    )
