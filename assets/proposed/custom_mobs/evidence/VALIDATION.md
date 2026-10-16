# Validation evidence — 2026-10-16

Baseline `6e85dc77553bd17422deeb9cb51258cefda06fe5`. Host: Python3.12 / Pillow12.3.0, Lua5.2.4 and5.4.8. Captures use the unmodified production renderer, not independently generated scene images.

| Check | Result |
|---|---|
| Existing Lua suites | **47 × 2 versions = 94 passed, 0 failed**; per-suite exits in [regressions.json](regressions.json) |
| Native art + real renderer | **44,173 checks per Lua version**,12 unit poses +1 ground-effect study, each at3 monitor sizes ×2 viewers =78 cases, plus one four-unit full monitor capture |
| Python asset contracts | **253 passed**: PNG/alpha, bounds,40-color palette, connected silhouette, source export reproduction, hash integrity, critical cues after actual encoding, exact preview/GIF pixels, cross-Lua parity, baseline card snapshot and additive scope |
| Syntax | All110 repository Lua files parsed under both5.2 and5.4, including existing assets and the new package |
| Existing Python suite |5 passed (`python3 -m unittest discover -s tests -p 'test_*.py'`) |
| Original sprite functionality | Existing sprite-roster, frame-diff, cache, monitor-recovery, PixelBox and four-mob rendering regression suites remain green |
| Production changes | None; only this package and its dedicated CI workflow are added |

## Native checks actually exercised

- Empty-environment loading: art/metadata has no startup effects, global palette dependency or runtime imports.
-13 valid, nonempty, transparent rectangular rasters, dimensions≤16×18 and valid palette tokens.
- Unregistered keys resolve to the existing default, not a newly activated mob/card.
- Virtual monitor sizes45×42,51×40,57×62, both viewers. Same logical pixels as native rows over real terrain; correct transparency.
- Stationary draw emits no extra `blit`; forced full encode yields identical output.
- Main-pose→ability/reserve-pose→main-pose on the **same monitor/entity** refreshes without ghosts.
- For the12 unit poses, white damage flash covers all opaque pixels, then restores; low HP/team/enemy/web overlays refresh and restore. The warning study uses no entity or HP bar; its opaque/transparent raster, redundant blits and forced terrain restoration are checked separately.
- Move/return and entity removal restore terrain without ghosts. Rendering leaves state and the entire original sprite registry unchanged.
- Captured emitted sextant bytes and foreground/background tokens are identical under Lua5.2/5.4; parsed fresh captures match committed evidence.
- Crown tips and both pupils, the extended tongue ribbon, both orange claw interiors/cyan legs, Worm teeth/lava seam and all3 ore caches survive actual two-color encoding. The warning has no encoded HP-bar pixels; exposed emergence retains its health bar.
- Owner revision contracts enforce only two implementation candidates,3E/550HP Frog and3E/350HP Worm, separate hook/melee ranges, all ground-unit sizes, full building/unit damage and50% tower-only damage. These are design-data assertions, not implemented-mechanic tests.

Full-monitor evidence: [Lua5.2](full_monitor_lua52.json), [Lua5.4](full_monitor_lua54.json), [1× PNG](../previews/virtual_monitor_1x.png), [6× PNG](../previews/virtual_monitor_6x.png). Per-pose crop bytes: [Lua5.2](pixelbox_lua52.json), [Lua5.4](pixelbox_lua54.json). The full monitor is51×40 terminal cells =102×120 logical pixels; the enlarged PNG uses nearest-neighbor only. Labels exist on presentation sheets, not inside sprites or captures.

## Performance interpretation

No production renderer, palette, canvas size, cache key or global sprite scaling changed. Each native frame has at most272 logical pixels (Worm16×17), within the existing16×18 contract. Additional files are not imported or animated during a normal match, so the package does not add normal-match sprite traversal or animation work. A future activation must separately measure units, timers and VFX.

The tests prove cache correctness and suppressed terminal writes in stationary synthetic scenes. They are **not a many-unit throughput benchmark**. Regression timing fields record host test duration only. No physical ComputerCraft monitor, Minecraft server, GPU LÖVE run or real-hardware FPS comparison was available. There is no renderer before/after benchmark because no renderer code changed.

## Explicit limits of validation

No new guard, pull, Worm deployment or healing mechanic exists in production code. Therefore no new-card balance, bot performance, win rate, full gameplay animation or special-mechanic headless parity is claimed. Those are future acceptance tests described in the technical design. Visual fit still requires owner review. Full LÖVE animation sets and live monitor inspection remain open; the delivered static master poses and native data are usable assets.

## Second-review regression check

[second_review_tests.json](second_review_tests.json) records10 fresh passes: sprite roster, frame diff, existing four-mob rendering, monitor write recovery and monitor boundaries under Lua5.2/5.4. The package Lua files also pass both parsers. All four independent LÖVE source/master PNGs remain byte-for-byte unchanged; only the native tongue pose and warning capture method were corrected. The focused pair sheet is composed from those real files and current proposal metadata. No new gameplay mechanics or stat changes were applied to `src/cards.lua`.
