# Phase-1 validation status

Baseline: GitHub main `4490cbdd00c2a7995155eb6bcb5828b3ac65d04e`.
The original working area contained the previous audit's uncommitted local
diff, so it was left untouched. This package was developed in a fresh isolated
snapshot. All 164 baseline files were initially byte-verified against GitHub.
Current safety checks verify them again, allowing only the additive VIS-003
documentation block. A new host-only workflow and all art/tools are separate.

| Required check | Status | Evidence |
| --- | --- | --- |
| Files present/readable | PASS | Eight Lua data files, four atlases, ten PNGs, eleven GIFs |
| Existing format/palette | PASS | Native row tables, 16 original palette tokens, dot transparency |
| Valid dimensions / coordinates | PASS | Max 16×18; all frames checked against three actual UI arena sizes |
| Valid colour values | PASS | Every source token, native canvas pixel and terminal palette checked |
| Consistent animation canvases | PASS | Fixed width/height per set; all eleven sequence references/durations valid |
| Projectile/effect definitions | PASS | 15 actual static effect rasters; explicitly unwired |
| Existing sprites preserved | PASS | Original renderer and art-file Git blob hashes unchanged |
| Existing gameplay preserved | PASS | Card, config, Game, Bot, Arena, Runner and installer hashes unchanged |
| Renderer compatibility | PASS | 188 actual arena/PixelBox captures across both cameras and 45×42, 51×52, 57×62 monitor layouts |
| Preview authenticity | PASS | Every atlas pixel and every GIF frame compared with actual row/terminal captures |
| No runtime dependency/activation | PASS | No normal import/installer entry, no new cards or Evo registered; host injection restored |
| Existing regressions | PASS | All 44 Lua suites on 5.2/5.4, both syntax/profile checks, five Python tests |
| New-asset host portability | PASS | 382,035 assertions per Lua version; all 40 new frames have exact displayed-pixel parity |
| Validator failure detection | PASS | Bad token, ragged rows, oversized dimensions and empty frame rejected |
| Arithmetic preparation | PASS | Derived Spider bonuses, Ravager scaling and two-hit Zombie bounds; no new combat executed |
| Live movement/attack animation selection | NOT TESTED | Current renderer has no general frame dispatcher; Phase 2 not authorized |
| New projectile/effect live dispatch | NOT TESTED | Only isolated row overlays, not registered effect IDs |
| New units/Evo/Hero Web mechanics and balance | NOT TESTED | No integration, new mechanic tests or new-unit simulations run |
| Physical CC:Tweaked/ATM10/Cobalt monitors | NOT TESTED | Host virtual monitors only; no hardware claim |
| Phase-2 implementation/merge | BLOCKED | Explicit user authorization has not been given |

Final asset tests: 25 unit frames + 15 projectile/effect frames, 188 captures,
382,035 assertions in each Lua version. Independent PNG/GIF/source/arithmetic
validation: 383 checks. Detailed JSON results are in `evidence/`.

During asset refinement the new capture tools initially exposed two host-only
issues (wrong reference helper name and space glyph handling); both were
corrected before verification. Cross-Lua captures then revealed colour ties
in small multi-colour cells. New art shades were grouped to remove displayed
pixel drift, without changing the encoder. The original Spider reference still
has a two-pixel cross-host difference from the pre-existing encoder tie rule;
this is documented rather than hiding it or redesigning an approved asset.

Native rows and displayed pixels are compared exactly. Raw foreground bytes
on unused/blank glyphs are not a valid image oracle. GIF sequences are honest
offline demonstrations of prepared frames; they do not prove gameplay timing.
Concept/preparation animation and effect dispatch remain Phase-2 work.

**PHASE 1: ASSET CREATION COMPLETE.**

**PHASE 2: NOT STARTED — WAITING FOR EXPLICIT APPROVAL.**
