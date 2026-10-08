"""Copper thickness of a board's outer layers, read from the (stackup) in its .kicad_pcb text.

Standard library only, so the kicad/ and solve/ tools both import it: one copy of how the thickness is read
(R10). KiCad 10's Python does not wrap the stackup (GetStackupDescriptor() returns a bare SwigPyObject), so
the board text is the only reader. Written 2026-10-08: until then every tool assumed 1 oz (35 um)."""

import re

ASSUMED = 35e-6  # m: what every tool assumed before 2026-10-08; used only when a board declares no stackup
COPPER = re.compile(r'\(layer "([^"]+)"\s*\(type "copper"\)\s*\(thickness ([0-9.]+)')


def outer(text):
    """(thickness in m, a note saying where it came from) for F.Cu and B.Cu of a .kicad_pcb text.

    ValueError when the stackup lacks either layer or gives them different thicknesses: the solvers give
    both layers one sheet resistance."""
    i = text.find("(stackup")
    if i < 0:
        return ASSUMED, "no stackup in the board, 35 um assumed"
    # in um, rounded: 0.035 mm * 1e-3 is 1 ulp off 35e-6, and 35.0 * 1e-6 is the value the tools used before
    um = {
        n: round(float(v) * 1e3, 6)
        for n, v in COPPER.findall(text, i)
        if n in ("F.Cu", "B.Cu")
    }
    if sorted(um) != ["B.Cu", "F.Cu"]:
        raise ValueError(
            f"the stackup gives copper for {sorted(um)}, not F.Cu and B.Cu"
        )
    if um["F.Cu"] != um["B.Cu"]:
        raise ValueError(
            f"F.Cu {um['F.Cu']:g} um and B.Cu {um['B.Cu']:g} um differ; "
            "these tools give both layers one thickness"
        )
    return um["F.Cu"] * 1e-6, f"stackup, F.Cu and B.Cu {um['F.Cu']:g} um"
