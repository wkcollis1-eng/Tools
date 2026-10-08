"""Regression and fault tests for pcb-eval: every tool, run through run.py on public boards.

usage: python tests/run_tests.py [--record] [NAME ...]
  no flag    compare each case with tests/expected/<case>.txt; exit 1 on any difference
  --record   rewrite those files (review the git diff before committing it)
  NAME       run only the cases whose name contains NAME

Each case runs its steps in an empty temporary directory and records every step's exit code, stdout and
stderr, and the sha256 of its named output files. Paths, CRLF, trailing blanks and wx's "duplicate image
handler" lines are normalised first. A case may also name patterns its last step's stdout and stderr must
or must not contain: the fault cases use them to show a check fires on a known fault and stays silent on
the clean board, and --record refuses to write a case whose patterns fail. Fixtures: fixtures/SOURCES.md.
Written 2026-10-08."""

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from run import KPY  # noqa: E402  (one copy of the KiCad Python path)

RUNPY = os.path.join(os.path.dirname(HERE), "run.py")
CLI = os.environ.get("KICAD_CLI", os.path.join(os.path.dirname(KPY), "kicad-cli.exe"))
F = os.path.join(HERE, "fixtures")
EXP = os.path.join(HERE, "expected")
T1100, T1709, UT = (
    "{F}/toc_1100.kicad_pcb",
    "{F}/toc_1709.kicad_pcb",
    "{F}/ups_tht.kicad_pcb",
)
DRC = ["CLI", "pcb", "drc", "--severity-all", "--format", "json", "-o"]
NOISE = re.compile(r"^Adding duplicate image handler")
# gnd_drop prints its wall-clock solve time. R13, 2026-10-08: 8317005 recorded "solve 0.6s", so the case
# failed whenever the solve rounded to another tenth: reproduced as "solve 0.7s" under CPU load [M, n=2].
TIMING = re.compile(r"\bsolve \d+\.\ds\b")
WIDE = "w=VIN+:B.Cu:3.40:33.57,55.75,24.24,55.75"
# R7: each fault case must show its fault, and the clean case beside it must not.
OSH_OK = [(r"^ALL WITHIN OSH 2-LAYER LIMITS$", True), (r"^\s+FAIL ", False)]
OSH_DRILL = [
    (r"^\s+FAIL min plated drill\s+0\.2000 mm", True),
    (r"^OUTSIDE OSH LIMITS: min plated drill$", True),
]
ISL_CUT = r"GND vias 0  GND pads \[\]  <- no GND via or pad$"  # islands.py's tag for a cut-off island
U1_PAST = r"^U1 .*\n(?:    .*\n)*?    F\.Fab .* PAST EDGE "  # U1's own block, which make_fault.py moves
VM_RULES = r"^# rules: clearance %.3f hole-to-hole %.3f copper-to-edge %.3f mm "  # read from the board
# viamove at= spots for the via at 14.50,21.00, each legal under toc_1100's 0.2/0.25/0.5 and not under the
# 0.25/0.30/0.60 of "make_fault.py rules": copper 0.55 mm inside the left edge; hole 0.275 mm from via
# 14.50,29.50's (0.575 - 0.15 - 0.15); copper 0.225 mm from the 3.40 mm VIN+ (57.975 - 55.75 - 1.70 - 0.30).
# common/copper.py's answer, as each tool that reads it prints it
CU_STACK = r"^copper %(t)d um: stackup, F\.Cu and B\.Cu %(t)d um$"
CU_MIXED = r"copper: F\.Cu 35 um and B\.Cu 70 um differ; these tools give both layers one thickness"
CU_NONE = r"^copper 35 um: no stackup in the board, 35 um assumed$"
VM_AT = [
    "at=14.50,21.00:14.35,21.00",
    "at=14.50,21.00:14.50,28.925",
    "at=14.50,21.00:30.00,57.975",
]
DUMP_SAME = [
    (r"^edge True ", True),
    (r"^fps added \[\] removed \[\]$", True),
    (r"^vias (\d+) -> \1 \+ \[\] - \[\]$", True),
    (r"texts same: True$", True),
    (r"CHANGED|NEW|ADDED|REMOVED|^  [+-] track|^ zone (?!same)", False),
]

# name, steps, output files, [(regex, must match)] on the last step's stdout and stderr.
# A step is ["RUN", tool, args...], ["KPY", script in tests/, args...], ["CLI", args...] or ["WRITE", file, text].
CASES = [
    ("dump toc_1100", [["RUN", "dump", T1100, "o.json"]], ["o.json"], []),
    ("dump ups_tht", [["RUN", "dump", UT, "o.json"]], ["o.json"], []),
    ("connsilk toc_1100", [["RUN", "connsilk", T1100, "TB1,TB2,U4"]], [], []),
    ("connsilk ups_tht", [["RUN", "connsilk", UT, "TB1,TB2"]], [], []),
    ("fabcheck toc_1100", [["RUN", "fabcheck", T1100]], [], OSH_OK),
    ("fabcheck ups_tht", [["RUN", "fabcheck", UT]], [], OSH_OK),
    (
        "fabcheck fault drill",
        [
            ["KPY", "make_fault.py", "drill", T1100, "f.kicad_pcb"],
            ["RUN", "fabcheck", "f.kicad_pcb"],
        ],
        [],
        OSH_DRILL,
    ),
    ("inplace toc_1100", [["RUN", "inplace", T1100, "VIN+", "B.Cu"]], [], []),
    ("islands toc_1100", [["RUN", "islands", T1100]], [], [(ISL_CUT, False)]),
    ("islands ups_tht", [["RUN", "islands", UT]], [], [(ISL_CUT, False)]),
    (
        "islands fault toc_1100",
        [
            ["KPY", "make_fault.py", "island", T1100, "f.kicad_pcb"],
            ["RUN", "islands", "f.kicad_pcb"],
        ],
        [],
        [(ISL_CUT, True)],
    ),
    # R13 2026-10-08: an "islands fault ups_tht" case, added in 8317005, was removed. Every F.Cu island on
    # ups_tht touches a GND pad, so deleting its vias cuts none off. The old centre test hid that, and the
    # case passed on an island still tied through U2.2 and C2.1.
    (
        "narrow toc_1100",
        [["RUN", "narrow", T1100, "o.kicad_pcb", "1.5", "NONE"]],
        ["o.kicad_pcb"],
        [],
    ),
    ("offcentre toc_1100", [["RUN", "offcentre", T1100]], [], []),
    ("outlines toc_1100", [["RUN", "outlines", T1100]], [], [(U1_PAST, False)]),
    ("outlines ups_tht", [["RUN", "outlines", UT]], [], []),
    (
        "outlines fault pastedge",
        [
            ["KPY", "make_fault.py", "pastedge", T1100, "f.kicad_pcb", "U1"],
            ["RUN", "outlines", "f.kicad_pcb"],
        ],
        [],
        [(U1_PAST, True)],
    ),
    ("padconn toc_1100", [["RUN", "padconn", T1100]], [], []),
    ("padconn ups_tht", [["RUN", "padconn", UT]], [], []),
    (
        "variant relief+pad",
        [["RUN", "variant", T1100, "o.kicad_pcb", "relief=TB1.1", "pad=TB1.1:2.6"]],
        ["o.kicad_pcb"],
        [],
    ),
    (
        "variant solid",
        [["RUN", "variant", T1100, "o.kicad_pcb", "solid=TB1.1"]],
        ["o.kicad_pcb"],
        [],
    ),
    (
        "variant width",
        [["RUN", "variant", T1100, "o.kicad_pcb", WIDE]],
        ["o.kicad_pcb"],
        [],
    ),
    ("viafill toc_1100", [["RUN", "viafill", T1100]], [], []),
    (
        "viamove toc_1100",
        [["WRITE", "ops.txt", WIDE + "\n"], ["RUN", "viamove", T1100, "ops.txt"]],
        [],
        [(VM_RULES % (0.200, 0.250, 0.500), True)],
    ),
    (
        "viamove at toc_1100",
        [
            ["WRITE", "ops.txt", WIDE + "\n"],
            ["RUN", "viamove", T1100, "ops.txt", *VM_AT],
        ],
        [],
        [
            (r"-> 14\.35,21\.00: legal$", True),
            (r"-> 14\.50,28\.93: legal$", True),
            (r"trk VIN\+ ", False),
        ],
    ),
    (
        "viamove fault rules",
        [
            ["KPY", "make_fault.py", "rules", T1100, "f.kicad_pcb"],
            ["WRITE", "ops.txt", WIDE + "\n"],
            ["RUN", "viamove", "f.kicad_pcb", "ops.txt"],
            ["RUN", "viamove", "f.kicad_pcb", "ops.txt", *VM_AT],
        ],
        [],
        [
            (VM_RULES % (0.250, 0.300, 0.600), True),
            (r"-> 14\.35,21\.00: edge$", True),
            (r"-> 14\.50,28\.93: hole via@14\.50,29\.50$", True),
            (r"-> 30\.00,57\.98: .*trk VIN\+ 0\.225", True),
        ],
    ),
    (
        "viamove fault netclass",
        [
            ["KPY", "make_fault.py", "netclass", T1100, "f.kicad_pcb", "VIN+"],
            ["WRITE", "ops.txt", WIDE + "\n"],
            ["RUN", "viamove", "f.kicad_pcb", "ops.txt"],
        ],
        [],
        [
            (r"this board has netclass Power clearance 0\.3 mm$", True),
            (r"^# rules", False),
        ],
    ),
    (
        "viamove fault dru",
        [
            ["KPY", "make_fault.py", "rules", T1100, "f.kicad_pcb"],
            ["WRITE", "f.kicad_dru", "(version 1)\n"],
            ["WRITE", "ops.txt", WIDE + "\n"],
            ["RUN", "viamove", "f.kicad_pcb", "ops.txt"],
        ],
        [],
        [(r"this board has custom rules f\.kicad_dru$", True), (r"^# rules", False)],
    ),
    (
        "drcset 1709 vs 1100",
        [
            DRC + ["a.json", T1709],
            DRC + ["b.json", T1100],
            ["RUN", "drcset", "a.json", "b.json"],
        ],
        [],
        [(r"^\s+[+-]\s+warning ", True), (r"set-identical", False)],
    ),
    (
        "drcset same",
        [DRC + ["a.json", T1100], ["RUN", "drcset", "a.json", "a.json"]],
        [],
        [(r"set-identical to baseline", True), (r"^\s+[+-]\s", False)],
    ),
    (
        "dumpdiff 1709 vs 1100",
        [
            ["RUN", "dump", T1709, "a.json"],
            ["RUN", "dump", T1100, "b.json"],
            ["RUN", "dumpdiff", "a.json", "b.json"],
        ],
        [],
        [(r" CHANGED ", True), (r"^  [+-] track", True)],
    ),
    (
        "dumpdiff same",
        [["RUN", "dump", T1100, "a.json"], ["RUN", "dumpdiff", "a.json", "a.json"]],
        [],
        DUMP_SAME,
    ),
    (
        "tracknet 1709 vs 1100",
        [
            ["RUN", "dump", T1709, "a.json"],
            ["RUN", "dump", T1100, "b.json"],
            ["RUN", "tracknet", "a.json", "b.json"],
        ],
        [],
        [],
    ),
    ("netdrop toc_1100", [["RUN", "netdrop", T1100, "--h", "0.1"]], [], []),
    (
        "netdrop self-test",
        [["RUN", "netdrop", "--self-test"]],
        [],
        [(r"SELF-TEST PASSED", True)],
    ),
    (
        "gnd_drop toc_1100",
        [["RUN", "gnd_drop", T1100, "--h", "0.1"]],
        [],
        [(CU_STACK % {"t": 35}, True), (r"  t=35 um  ", True)],
    ),
    (
        "gnd_drop fault copper 70",
        [
            ["KPY", "make_fault.py", "copper", T1100, "f.kicad_pcb", "70"],
            ["RUN", "gnd_drop", "f.kicad_pcb", "--h", "0.1"],
        ],
        [],
        [(CU_STACK % {"t": 70}, True), (r"  t=70 um  ", True)],
    ),
    (
        "gnd_drop fault copper mixed",
        [
            ["KPY", "make_fault.py", "copper", T1100, "f.kicad_pcb", "35,70"],
            ["RUN", "gnd_drop", "f.kicad_pcb", "--h", "0.1"],
        ],
        [],
        [(CU_MIXED, True), (r"^whole pour ", False)],
    ),
    (
        "gnd_drop fault copper none",
        [
            ["KPY", "make_fault.py", "copper", T1100, "f.kicad_pcb", "none"],
            ["RUN", "gnd_drop", "f.kicad_pcb", "--h", "0.1"],
        ],
        [],
        [(CU_NONE, True), (r"  t=35 um  ", True)],
    ),
    (
        "gnd_drop self-test",
        [["RUN", "gnd_drop", "--self-test"]],
        [],
        [(r"SELF-TEST PASSED", True)],
    ),
    ("run.py unknown tool", [["RUN", "nosuchtool"]], [], []),
]


def norm(data, tmp):
    t = data.decode("utf-8", "replace")
    for p, tag in ((F, "{F}"), (tmp, "{T}")):
        for form in (p, p.replace("\\", "/"), p.replace("/", "\\")):
            t = t.replace(form, tag)
    t = TIMING.sub("solve {t}s", t)
    lines = [
        ln.rstrip() for ln in t.replace("\r\n", "\n").split("\n") if not NOISE.match(ln)
    ]
    return "\n".join(lines).strip("\n")


def command(step):
    kind, rest = step[0], [a.replace("{F}", F) for a in step[1:]]
    if kind == "RUN":
        return [sys.executable, RUNPY, *rest]
    if kind == "KPY":
        return [KPY, os.path.join(HERE, rest[0]), *rest[1:]]
    if kind == "CLI":
        return [CLI, *rest]
    raise ValueError(kind)


def run_case(steps, outs):
    tmp = tempfile.mkdtemp(prefix="pcbeval_")
    try:
        parts, last = [], ""
        for i, step in enumerate(steps, 1):
            if step[0] == "WRITE":
                with open(os.path.join(tmp, step[1]), "w", newline="\n") as fh:
                    fh.write(step[2])
                parts.append(f"== step {i}: WRITE {step[1]}")
                continue
            p = subprocess.run(
                command(step), cwd=tmp, capture_output=True, timeout=1800
            )
            out, err = norm(p.stdout, tmp), norm(p.stderr, tmp)
            last = out + "\n" + err  # what the patterns read: a refusal goes to stderr
            label = (
                " ".join(step[:2]) if step[0] != "CLI" else "CLI " + " ".join(step[1:3])
            )
            parts += [
                f"== step {i}: {label} exit {p.returncode}",
                "-- stdout",
                out,
                "-- stderr",
                err,
            ]
        parts.append("== files")
        for o in outs:
            fp = os.path.join(tmp, o)
            if os.path.exists(fp):
                body = norm(open(fp, "rb").read(), tmp)
                parts.append(
                    f"{o} sha256 {hashlib.sha256(body.encode()).hexdigest()} lines {body.count(chr(10)) + 1}"
                )
            else:
                parts.append(f"{o} MISSING")
        return "\n".join(parts) + "\n", last
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    record = "--record" in argv
    only = [a for a in argv if a != "--record"]
    os.makedirs(EXP, exist_ok=True)
    bad = 0
    for name, steps, outs, pats in CASES:
        if only and not any(o in name for o in only):
            continue
        t0 = time.time()
        got, last = run_case(steps, outs)
        missed = [
            f"{'no' if want else 'unwanted'} {rx!r}"
            for rx, want in pats
            if bool(re.search(rx, last, re.M)) != want
        ]
        path = os.path.join(
            EXP, re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") + ".txt"
        )
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if missed:
            verdict = "FAIL patterns: " + "; ".join(missed)
        elif record:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(got)
            verdict = "RECORDED" if old != got else "RECORDED (unchanged)"
        elif old is None:
            verdict = "FAIL no expected file (run --record)"
        else:
            verdict = "PASS" if old == got else "FAIL differs from expected"
        bad += verdict.startswith("FAIL")
        print(f"{verdict:28} {name}  ({time.time() - t0:.1f} s)", flush=True)
    print("SUITE PASSED" if not bad else f"SUITE FAILED: {bad} case(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
