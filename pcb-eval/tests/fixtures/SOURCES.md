# Fixtures

Each board here was copied byte for byte from the public repo
[DIY-LiFePO4-UPS](https://github.com/wkcollis1-eng/DIY-LiFePO4-UPS) at the commit named. They are
kept as stored (`-text` in `.gitattributes`): `ups_tht.kicad_pcb` has CRLF line endings and must keep
them. Boards that are in no public repo are never copied here.

| file | repo path at that commit | commit | sha256 |
|---|---|---|---|
| `toc_1709.kicad_pcb` | `Top-Off-Charger/pcb/Top Off Charger- Oct 2026.kicad_pcb` | f77169e5dffa4ec9f539b9598c331e888f9e6057 (2026-10-06, Kelvin GND for the INA228) | f141be03aa21f8603825f59d2e9ac5b4dba23db41a2cc76aac1e34f071ec0bf6 |
| `toc_1709.kicad_pro` | `Top-Off-Charger/pcb/Top Off Charger- Oct 2026.kicad_pro` | f77169e5dffa4ec9f539b9598c331e888f9e6057 | c2c4390b8853b105a179ccb513242b1f844c5a0ecbd582b303f57a4ee791b847 |
| `toc_1100.kicad_pcb` | `Top-Off-Charger/pcb/Top Off Charger- Oct 2026.kicad_pcb` | e27eeab9b91296a3c5d64c00ccc1cb1f324e05e7 (2026-10-08, rev 0.8) | aaa9e15839149177f0d6b3867c41cc5a0832db0a3e18ae6439577525eda6e6d4 |
| `toc_1100.kicad_pro` | `Top-Off-Charger/pcb/Top Off Charger- Oct 2026.kicad_pro` | e27eeab9b91296a3c5d64c00ccc1cb1f324e05e7 | abb4d3f13d19d1a4fbb53a2cd935b50558ca129046a85dc00457706d6852c5eb |
| `ups_tht.kicad_pcb` | `UPS-Monitor/UPS-Monitor-THT.kicad_pcb` | 7180fb2795e8d54934609276e452900c9bbed3d6 (2026-06-08) | 751e09147656592ebf484f154a1962a2046d37dc76e5c7382ab7653b6f096a8b |

The names say which save each board is in the Top-Off Charger review kit: `toc_1709` is the
2026-10-06 17:09 save and `toc_1100` the 2026-10-08 11:00 save (same content once line endings are
normalised). `ups_tht` replaced the rev 3 board at 0651bde, which is in KiCad 7 format: KiCad 10's
`pcbnew.LoadBoard` returned None for it.

KiCad writes a `.kicad_prl` (local view settings) beside each `.kicad_pro` when a board is loaded.
The suite passed with them deleted beforehand (2026-10-08), so they are ignored rather than kept.

Faulty boards are not stored. `../make_fault.py` builds each one from a clean board above when the
suite runs.
