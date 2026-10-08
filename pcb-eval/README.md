# pcb-eval

Review tools for KiCad 10 boards. Each tool exists here once and is used for every board.

They were moved here on 2026-10-08 from three places:

- the local review kits in `C:\Users\wkcol\pcb-eval\<board>\tools\` (Top Off Charger, Battery Bank Monitor, UPS Monitor);
- `DIY-LiFePO4-UPS/Top-Off-Charger/pcb/gnd_drop.py`.

The kits keep their boards, results and one-off scripts. Commands in their READMEs that predate the move still say `tools/`.

## Run

```text
python run.py --list               every tool, with the first line of its docstring
python run.py <tool> [args...]     e.g. python run.py dump board.kicad_pcb dump.json
```

`run.py` picks the interpreter from the tool's folder:

| folder | needs | runs under | tools |
|---|---|---|---|
| `kicad/` | `pcbnew` | KiCad's Python: `KICAD_PYTHON`, default `C:/Program Files/KiCad/10.0/bin/python.exe` (it has no scipy) | dump, connsilk, fabcheck, inplace, islands, narrow, offcentre, outlines, padconn, variant, viafill, viamove |
| `solve/` | numpy, scipy | the Python that runs `run.py` | gnd_drop, netdrop, tracknet |
| `report/` | standard library | the Python that runs `run.py` | drcset, dumpdiff |

`run.py` returns the tool's exit code. It exits 2 itself, without running anything, in four cases:

- the tool name is unknown;
- no arguments were given;
- KiCad's Python is missing;
- a tool name appears in two folders. There is one copy of each tool.

Each tool's docstring gives its own arguments.

## Still tied to one board

These tools were copied as they were. The board-specific values are moving to a profile file beside each board, one tool at a time. Until then:

- **Top Off Charger only:**
  - `solve/tracknet.py`'s `PATHS` table (which pads each net runs between). `netdrop.py` imports it.
  - `solve/gnd_drop.py`'s pad set (design doc §7.3).
  - `kicad/viamove.py`'s clearances `CLR, H2H, EDGE = 0.2, 0.25, 0.5`, taken from that board's `.kicad_pro`.
- **All boards, as an assumption:**
  - 1 oz copper (35 µm), fixed in `tracknet.py`, `inplace.py` and `netdrop.py`. `gnd_drop.py` takes the thickness as an argument, default 35 µm.
  - The ground net is named `GND`, in `islands.py`, `padconn.py` and `gnd_drop.py`.
  - `tracknet.py` treats vias as ideal links, because its track keys ignore the layer. Add each via barrel's resistance by hand.

On another board, check these values against its `.kicad_pro` and stackup before reading a figure from these tools.

## Tests

```text
python tests/run_tests.py            compare every case with tests/expected/; exit 1 on any difference
python tests/run_tests.py --record   rewrite tests/expected/ (read the git diff before committing it)
python tests/run_tests.py islands    run only the cases whose name contains "islands"
```

The suite runs every tool through `run.py` on public boards (`tests/fixtures/SOURCES.md`). For each case it compares the exit code, the output and any output files with the recorded run. It needs KiCad 10 (`KICAD_PYTHON`, and `KICAD_CLI` for the DRC cases) and a Python with numpy and scipy.

- A change that should leave a tool's output alone must pass unchanged.
- A change that should alter it is re-recorded with `--record`. The diff of `tests/expected/` then shows exactly what moved.

**Fault cases.** `tests/make_fault.py` writes a copy of a clean board with one fault:

- a 0.20 mm via drill;
- a ground island with its vias deleted;
- a module moved past the board edge.

Each fault case names a pattern its output must contain. The clean case beside it must not contain that pattern. `--record` will not write a case whose patterns fail.

Proven on 2026-10-08:

- Two runs in a row passed.
- In a copy of this folder, each of these failed the suite with exit 1: a looser drill limit in `fabcheck.py`, a changed copper thickness in `netdrop.py`, and a deleted expected file.

## Tried on a board with a known fault (2026-10-08)

`kicad/outlines.py` and `kicad/islands.py` had never been run on a board with a known fault (UPS Monitor review, 2026-10-07). The fault cases above did that:

- **`islands.py`** shows the island whose vias were deleted as `GND vias 0`. On the clean rev 0.8 Top Off Charger it also prints `GND vias 0  GND pads []` for four slivers that are connected: each one touches a U4 GND pad. The tool finds a pad by testing whether the pad's centre lies in the fill. A thermal-relief pad's centre sits in a cutout, so the test misses it. Until that is fixed, `GND pads []` does not mean that no pad touches the island.
- **`outlines.py`** prints each footprint's extents but not the board edge, so a module moved past the edge is not flagged. Compare the extents with the `edge` line from `dump.py` by hand. Its fault case has no pattern yet for this reason.

## How the move was proven

The Tools pre-commit hooks (`ruff --fix`, `ruff-format`) reformatted every moved file except `gnd_drop.py`, so a byte comparison of source files proves nothing. Some code also changed to satisfy the linter:

- variables named `l` became `ly`;
- one-line `lambda`s became `def`s;
- unused imports were removed.

Instead, each old and new copy was run with the same arguments in an empty directory, and exit code, stdout, stderr and output files were compared byte for byte. There were 29 cases, run against the three kits' boards:

- **28 were identical.**
- **1 differed, as expected.** Comparing the 2026-10-06 17:09 and 2026-10-08 11:00 Top Off Charger dumps, the old Battery Bank Monitor `dumpdiff.py` silently dropped `pad D6 ADDED`, and this copy reports it.

Two copies of tools had drifted between kits. Each was merged into the version that does more:

- `dumpdiff.py` is the UPS kit's: it reports added and removed pads, where the others raised KeyError on a removed pad.
- `variant.py` is the Top Off Charger kit's: it adds the `relief=` and `pad=` operations.

## Adding a tool

1. Put the tool in the folder for the runtime it needs. Its name must not already exist in another folder.
2. Make the first line of its docstring the summary that `--list` prints, and say there what the tool assumes about the board.
3. Before trusting the tool, prove it on a board with a known fault and on a clean board. It must report the fault and stay silent on the clean board.
4. Add its cases to `tests/run_tests.py`: a clean case, and a fault case built by `tests/make_fault.py` with the pattern that shows the fault. Record them with `--record`, and run the suite before committing.
