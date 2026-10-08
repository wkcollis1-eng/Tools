"""A board's profile: what the review tools must know about a board and cannot read from its file.

Which pads each power net runs between (tracknet.py, netdrop.py), and the ground pour's source, sink and
shared pads (gnd_drop.py). It is the json file given with --profile (dump.py: profile=), else
<board stem>.pcb-eval.json beside the .kicad_pcb. A board with neither is refused, never given another
board's pads (R8): until 2026-10-08 every board got the Top Off Charger's, from tracknet.py's PATHS and
gnd_drop.py's TB2, TB1 and U2.2.

  {"about": "free text",
   "paths": {"NET": [[["REF", "PAD" or null], ...], [["REF", "PAD" or null], ...]], ...},  from pads, to pads
   "total": {"name": "label", "nets": ["NET", ...]},  tracknet.py's sum line
   "gnd": {"source": ["REF", "PAD" or null], "sink": [...], "shared": [...]}}  1 A in, 1 A out; shared optional

A null PAD means every pad of REF on the net. A tool refuses a profile without the key it uses. Any other
key is refused, so a misspelt one is not silently ignored. Written 2026-10-08."""

import json
import os

KEYS = ("about", "paths", "total", "gnd")


class Missing(ValueError):
    """No profile given and none beside the board."""


def beside(board):
    return os.path.splitext(board)[0] + ".pcb-eval.json"


def load(board, given=None, option="--profile FILE"):
    """(profile, path, how): the profile given, else the one beside the board; ValueError if neither."""
    path = given or beside(board)
    if not os.path.exists(path):
        if given:
            raise ValueError(f"profile {given} does not exist")
        raise Missing(f"no profile: no {path}; write one there or give {option}")
    with open(path, encoding="utf-8") as f:
        try:
            prof = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"profile {path}: {e}")
    validate(prof, f"profile {path}")
    return prof, path, "given" if given else "beside the board"


def _pad(x, where):
    if not (
        isinstance(x, list)
        and len(x) == 2
        and isinstance(x[0], str)
        and x[0]
        and (x[1] is None or isinstance(x[1], str))
    ):
        raise ValueError(f'{where}: {json.dumps(x)} is not ["REF", "PAD" or null]')


def validate(prof, where):
    """Raise ValueError, naming `where`, unless `prof` has the shape the module docstring gives."""
    if not isinstance(prof, dict):
        raise ValueError(f"{where}: not a json object")
    bad = sorted(set(prof) - set(KEYS))
    if bad:
        raise ValueError(f"{where}: unknown keys {bad}; known: {list(KEYS)}")
    paths = prof.get("paths", {})
    if not isinstance(paths, dict):
        raise ValueError(f"{where}: paths is not an object")
    for net, ends in paths.items():
        if not (
            isinstance(ends, list)
            and len(ends) == 2
            and all(isinstance(e, list) and e for e in ends)
        ):
            raise ValueError(
                f"{where}: paths.{net} is not [from pads, to pads], each a non-empty list"
            )
        for e in ends:
            for x in e:
                _pad(x, f"{where}: paths.{net}")
    t = prof.get("total")
    if t is not None:
        if not (
            isinstance(t, dict)
            and set(t) == {"name", "nets"}
            and isinstance(t["name"], str)
            and isinstance(t["nets"], list)
        ):
            raise ValueError(
                f'{where}: total is not {{"name": "label", "nets": [...]}}'
            )
        lost = [n for n in t["nets"] if n not in paths]
        if lost:
            raise ValueError(f"{where}: total names nets not in paths: {lost}")
    g = prof.get("gnd")
    if g is not None:
        if not (
            isinstance(g, dict)
            and {"source", "sink"} <= set(g) <= {"source", "sink", "shared"}
        ):
            raise ValueError(
                f"{where}: gnd needs source and sink, and may have shared, nothing else"
            )
        for k, x in g.items():
            _pad(x, f"{where}: gnd.{k}")
        if g["source"] == g["sink"]:
            raise ValueError(f"{where}: gnd.source and gnd.sink are the same pad")


def need(prof, key, path, tool):
    if key not in prof:
        raise ValueError(f'profile {path} has no "{key}", which {tool} needs')


def paths(prof):
    """{net: (from, to)}, each a list of (ref, pad or None), the shape tracknet.py's PATHS had."""
    return {
        net: tuple([tuple(x) for x in e] for e in ends)
        for net, ends in prof["paths"].items()
    }


def label(spec):
    return spec[0] if spec[1] is None else f"{spec[0]}.{spec[1]}"


def unknown(prof, have):
    """Each pad the profile names that the board has not, as REF or REF.PAD; have is {(ref, pad)}."""
    refs = {r for r, _ in have}
    specs = [x for ends in prof.get("paths", {}).values() for e in ends for x in e]
    specs += list(prof.get("gnd", {}).values())
    out = []
    for r, n in specs:
        if (r not in refs if n is None else (r, n) not in have) and label(
            (r, n)
        ) not in out:
            out.append(label((r, n)))
    return out
