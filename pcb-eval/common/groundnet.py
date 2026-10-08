"""The ground net's name, for islands.py, padconn.py and gnd_drop.py: GND unless given, and refused when the
board has no net of that name, so a wrong name stops the tool instead of finding nothing.
Until 2026-10-08 the three assumed GND."""

DEFAULT = "GND"


def board_nets(b):
    """Every net name on the pads, tracks, vias and zones of a board a kicad/ tool has loaded. It is
    handed the board, so it imports nothing from KiCad."""
    nets = {p.GetNetname() for f in b.GetFootprints() for p in f.Pads()}
    return (
        nets
        | {t.GetNetname() for t in b.GetTracks()}
        | {z.GetNetname() for z in b.Zones()}
    )


def pick(given, nets, option):
    """(name, line): the ground net and the line a tool prints for it, or ValueError when the board has
    no net of that name. given is the tool's argument or None; nets is every net name on the board's
    copper; option is how the tool's user gives the name, for the message."""
    name = given or DEFAULT
    if name not in nets:
        have = ", ".join(sorted(n for n in nets if n))
        raise ValueError(
            f"this board has no net {name}; give {option} (its nets: {have})"
        )
    return name, f"ground net {name} ({'given' if given else 'default'})"
