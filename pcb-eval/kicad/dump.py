"""Dump a board to json: edge, copper thickness, footprints with pads, tracks, vias, zones, texts (KiCad python).
usage: dump.py <board.kicad_pcb> <out.json>     the input to dumpdiff.py and tracknet.py
copper_um is common/copper.py's layers(): each stackup copper layer's thickness in um, null with no stackup.
Added 2026-10-08 so tracknet.py reads the board's copper; tracknet refuses a dump without it."""

import os
import sys
import json
import pcbnew

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "common"),
)
import copper  # noqa: E402  (one copy of how a board's copper thickness is read)

b = pcbnew.LoadBoard(sys.argv[1])
mm = pcbnew.ToMM
out = {}
bb = b.GetBoardEdgesBoundingBox()
out["edge"] = [
    mm(bb.GetX()),
    mm(bb.GetY()),
    mm(bb.GetRight()),
    mm(bb.GetBottom()),
    mm(bb.GetWidth()),
    mm(bb.GetHeight()),
]
out["copper_um"] = copper.layers(open(sys.argv[1], encoding="utf-8").read())
ds = b.GetDesignSettings()
fps = []
for f in b.GetFootprints():
    d = dict(
        ref=f.GetReference(),
        val=f.GetValue(),
        fpid=str(f.GetFPID().GetUniStringLibId()),
        x=mm(f.GetPosition().x),
        y=mm(f.GetPosition().y),
        rot=f.GetOrientationDegrees(),
        side="B" if f.IsFlipped() else "F",
    )
    cy = f.GetCourtyard(pcbnew.F_CrtYd)
    try:
        cb = cy.BBox()
        d["crtyd"] = [
            mm(cb.GetX()),
            mm(cb.GetY()),
            mm(cb.GetRight()),
            mm(cb.GetBottom()),
        ]
    except Exception:
        d["crtyd"] = None
    fb = f.GetBoundingBox(False)
    d["bbox"] = [mm(fb.GetX()), mm(fb.GetY()), mm(fb.GetRight()), mm(fb.GetBottom())]
    pads = []
    for p in f.Pads():
        pads.append(
            dict(
                n=p.GetNumber(),
                net=p.GetNetname(),
                x=round(mm(p.GetPosition().x), 3),
                y=round(mm(p.GetPosition().y), 3),
                sx=round(mm(p.GetSize(pcbnew.F_Cu).x), 3),
                sy=round(mm(p.GetSize(pcbnew.F_Cu).y), 3),
                drill=round(mm(p.GetDrillSize().x), 3),
                attr=int(p.GetAttribute()),
            )
        )
    d["pads"] = pads
    d["models"] = [
        (m.m_Filename, [m.m_Offset.x, m.m_Offset.y, m.m_Offset.z], m.m_Show)
        for m in f.Models()
    ]
    fps.append(d)
out["fps"] = fps
tr = []
vias = []
for t in b.GetTracks():
    if t.GetClass() == "PCB_VIA":
        vias.append(
            dict(
                net=t.GetNetname(),
                x=round(mm(t.GetPosition().x), 3),
                y=round(mm(t.GetPosition().y), 3),
                d=round(mm(t.GetWidth(pcbnew.F_Cu)), 3),
                drill=round(mm(t.GetDrill()), 3),
            )
        )
    else:
        tr.append(
            dict(
                net=t.GetNetname(),
                w=round(mm(t.GetWidth()), 3),
                layer=t.GetLayerName(),
                x1=round(mm(t.GetStart().x), 3),
                y1=round(mm(t.GetStart().y), 3),
                x2=round(mm(t.GetEnd().x), 3),
                y2=round(mm(t.GetEnd().y), 3),
                L=round(mm(t.GetLength()), 3),
            )
        )
out["tracks"] = tr
out["vias"] = vias
zs = []
for z in b.Zones():
    zs.append(
        dict(
            net=z.GetNetname(),
            layers=[b.GetLayerName(ly) for ly in z.GetLayerSet().Seq()],
            clearance=mm(z.GetLocalClearance() or 0),
            minw=mm(z.GetMinThickness()),
            area_mm2=round(z.GetFilledArea() / 1e12, 1) if z.IsFilled() else None,
            keepout=z.GetIsRuleArea(),
        )
    )
out["zones"] = zs
txt = []
for d in b.GetDrawings():
    if d.GetClass() in ("PCB_TEXT", "PCB_TEXTBOX"):
        txt.append(
            dict(
                layer=d.GetLayerName(),
                text=d.GetText(),
                x=round(mm(d.GetPosition().x), 2),
                y=round(mm(d.GetPosition().y), 2),
            )
        )
out["texts"] = txt
json.dump(out, open(sys.argv[2], "w"), indent=1)
print(
    "ok",
    out["edge"],
    len(fps),
    "fps",
    len(tr),
    "tracks",
    len(vias),
    "vias",
    len(zs),
    "zones",
    "copper_um",
    out["copper_um"],
)
