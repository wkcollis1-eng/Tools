"""Design rules a tool applies to every net, read from a loaded board's design settings.

Called with a pcbnew BOARD by the kicad/ tools; it imports nothing from KiCad, so it sits in common/ and
viamove.py and inplace.py read the rules one way (R10). Moved here from viamove.py on 2026-10-08."""

import os


def read(b, brd):
    """(clearance, hole-to-hole, copper-to-edge in mm, [what one clearance does not cover]) for board b,
    loaded from the file brd.

    The clearance is the Default netclass's. The list names each netclass with another clearance, and a
    .kicad_dru beside the board: a tool that applies one clearance and no custom rules must refuse them."""
    u = 1e6
    ds = b.GetDesignSettings()
    ns = ds.m_NetSettings
    clr = ns.GetDefaultNetclass().GetClearance() / u
    odd = [
        f"netclass {k} clearance {c.GetClearance() / u:g} mm"
        for k, c in ns.GetNetclasses().items()
        if c.HasClearance() and c.GetClearance() / u != clr
    ]
    if os.path.exists(os.path.splitext(brd)[0] + ".kicad_dru"):
        odd.append(
            "custom rules " + os.path.basename(os.path.splitext(brd)[0]) + ".kicad_dru"
        )
    return clr, ds.m_HoleToHoleMin / u, ds.m_CopperEdgeClearance / u, odd
