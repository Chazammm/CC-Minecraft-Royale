# Performance baseline — 2026-10-10

Source tree: `a5fa72ba0c905896497d8fd180de5113ecd01833` (`main` when measurement branch was created).
Probe: `tests/performance_profile.lua` (read-only; invokes real
`Game.update`, `Bot.update`, `Runner.run`, `pixelArena.draw`).
GitHub Actions run: https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38062240691

## Results (Linux GitHub Actions runner, CPU time from os.clock)

Three deterministic full matches: exactly **9,231 ticks** and **340 successful bot actions** for both Lua versions. Timing is instrumented with wrappers around real functions. No `dt`, AI logic, game rule, entity or pixel quality was modified.

| Scenario | Lua 5.2 CPU | Lua 5.4 CPU |
| --- | ---: | ---: |
| 3 full headless matches, total | 0.632027 s | 0.442898 s |
| `Game.update` within those matches (9,141 calls) | 0.510897 s (80.8%) | 0.348674 s (78.7%) |
| `Bot.update` within those matches (18,288 calls) | 0.091631 s (14.5%) | 0.067408 s (15.2%) |
| Remaining match setup/housekeeping/instrumentation | 0.029499 s (4.7%) | 0.026816 s (6.1%) |
| 35 crowded decisions without Anvil, 30 enemy troops | 0.006507 s | 0.004772 s |
| 35 crowded decisions with Anvil, 30 enemy troops | 0.013053 s | 0.008482 s |
| 12 unchanged arena frames, two monitors, 0 extra troops | 0.025569 s | 0.014812 s |
| 12 unchanged arena frames, two monitors, 30 extra troops | 0.039687 s | 0.024754 s |

All static repeated frames emitted **zero** terminal `blit` updates
after the initial frame, despite performing a full PixelBox color/character
conversion. Each test window was 55×40 characters; with PixelBox 2×3
subpixels that means 110×120 logical pixels. Arena redraw timings include both
players' displays.

**Note:** These are microbenchmarks, not a statistically significant speed
comparison. Lua versions were run sequentially on shared runner hardware and
the initial PixelBox construction costs ~50–73 ms. The diagnostic report never
uses timing thresholds as CI acceptance criteria. Lua timing, CPU versus
wall-time, wireless monitor transmission and in-game TPS differ substantially
on actual CC:Tweaked/ATM10 computers. Always measure identical scenarios and
random seeds before/after optimization on the *same* machine.

## Priorities and proof obligations

1. **Game.update first for headless throughput** — dominates the measured
   deterministic match CPU time. Investigate entity targeting/pathing and
   combat passes (use finer-grained instrumentation). All optimizations must
   keep exact gameplay results and side symmetry; never increase `dt`, skip
   bot decisions, remove effects or reduce accuracy to accelerate benchmarks.
2. **Arena renderer for physical frame performance** — caching static terrain
   already helps; unchanged scanlines already avoid network writes, but
   complete canvas restoration and PixelBox conversion still execute. Explore
   dirty-rectangle/texel caching only with pixel-for-pixel validation on both
   display orientations and changed-effect animations. Before calling it a
   win, profile real monitor CPU and `blit` latency.
3. **Anvil scoring conditionally** — the candidate/target loop is quadratic
   in enemy entities but is only used when the Anvil card is in hand and
   affordable. Consider predicted-position spatial bucketing if heavy-crowd
   profiling shows a meaningful improvement; preserve exact score and
   tie-breaking choices with seeded parity checks.
4. **Main event loop** — real-time update clamps catch-up to 5 × 0.1s.
   Under lag simulated time may slow. Measure actual backlog before changing
   the policy (larger `dt` can skip fast collisions and cooldown edges).

## Hardware field sheet (not yet completed)

For the target ATM10 computer record:
- exact installed CODE_REVISION, monitor dimensions/text scale, CC version
- average / p95 frame CPU ms in lobby, idle battle, crowded battle
- average / p95 `Game.update` and `Bot.update` CPU ms
- emitted monitor blit rows/frame, display/network lag, tick backlog
- music enabled/disabled comparison on the same game scene
- identical bot decks, seeds, match totals before and after each patch

No performance improvement or hardware result is claimed here. This report is a baseline only.
