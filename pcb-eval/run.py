"""Run a pcb-eval tool under the Python it needs.

usage: python run.py <tool> [args...]     e.g. python run.py dump board.kicad_pcb dump.json
       python run.py --list               every tool and the first line of its docstring

kicad/   imports pcbnew: runs under KiCad's own Python (KICAD_PYTHON, default
         C:/Program Files/KiCad/10.0/bin/python.exe), which has no scipy
solve/   needs numpy and scipy: runs under the Python running this script
report/  standard library only: runs under the Python running this script

A tool name found in two folders is refused: there is one copy of each tool (R10).
"""

import ast
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KPY = os.environ.get("KICAD_PYTHON", "C:/Program Files/KiCad/10.0/bin/python.exe")
DIRS = ("kicad", "solve", "report")


def tools():
    found = {}
    for d in DIRS:
        for f in sorted(os.listdir(os.path.join(HERE, d))):
            if f.endswith(".py"):
                found.setdefault(f[:-3], []).append(d)
    return found


def summary(path):
    src = open(path, encoding="utf-8").read()
    doc = ast.get_docstring(ast.parse(src))
    if doc:
        return doc.strip().splitlines()[0]
    first = src.lstrip().splitlines()[0]
    return first.lstrip("# ") if first.startswith("#") else "-"


def main(argv):
    found = tools()
    twice = {n: d for n, d in found.items() if len(d) > 1}
    if twice:
        print(f"refused: tool names in more than one folder: {twice}", file=sys.stderr)
        return 2
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    if argv[0] == "--list":
        for n in sorted(found):
            d = found[n][0]
            print(f"{d + '/' + n:22} {summary(os.path.join(HERE, d, n + '.py'))}")
        return 0
    name = argv[0].removesuffix(".py")
    if name not in found:
        print(f"no tool {name!r}; try --list", file=sys.stderr)
        return 2
    d = found[name][0]
    interp = sys.executable
    if d == "kicad":
        if not os.path.exists(KPY):
            print(
                f"KiCad's Python not found at {KPY}; set KICAD_PYTHON", file=sys.stderr
            )
            return 2
        interp = KPY
    return subprocess.call([interp, os.path.join(HERE, d, name + ".py"), *argv[1:]])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
