# First targeted optimization pass — 2026-10-10

## Scope and safeguards

Three source hot paths were changed: `src/game.lua`, `src/bot.lua`,
`src/pixel_arena.lua`. **No card values, time step, combat
rules, spell damage, AI scoring coefficients, sprite definitions, image
resolution or monitor text scale have changed.**

CPU baseline revision: `5b4aed24361ad852d79aacbd63c69ef683d7dfca`
(see `PERFORMANCE_BASELINE_20261010.md`).
Performance branch diagnostics:
- https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38066404380
- https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38066682128

The automated performance runner is Linux and cannot reproduce Minecraft
server TPS, wired/wireless terminal traffic or speaker performance.
Time comparisons are indicative rather than statistically controlled.

## Changes

1. **Combat CPU:** reuse static, immutable target-kind predicates instead of
   recreating filter closures for each acquisition. Inline Euclidean
   distance arithmetic in highly frequent target scans and distance checks,
   retaining the same coordinate subtraction and strict tie comparison.
2. **Anvil AI:** when at least 24 enemies exist, partition their predicted
   positions into radius-sized spatial cells. Candidate centers inspect only
   nine neighboring cells; entries are restored to their original entity
   order before scoring to preserve exact floating-point accumulation and
   strict first-best ties. Small boards keep the original exhaustive scan.
   The old exhaustive method remains accessible as a *diagnostic oracle*
   through `Bot.debugAnvilTarget(..., true)`.
3. **Arena renderer:** compare final logical pixels before doing expensive
   PixelBox-to-terminal encoding when the roster has not moved. If any
   entity changes position/order, bypass the costly canvas comparison and
   encode immediately; this fixed the first prototype's slowdown for moving
   units. Pixel changes from effects, projectiles, HP flashes, special animated
   sprites and arbitrary phase transitions remain covered. Both player
   directions and original full encoder can be compared exactly using an
   optional diagnostic flag.

## Measured results

### Match simulation and crowded bot decisions, Lua 5.4

| Test | Original CPU | Optimized CPU | Approximate difference |
| --- | ---: | ---: | ---: |
| 3 fixed-seed full matches | 0.442898 s | 0.433679 s | 2.1% less |
| `Game.update`, 9,141 calls | 0.348674 s | 0.338974 s | 2.8% less |
| 35 crowded Anvil-enabled bot decisions | 0.008482 s | 0.007123 s | 16.0% less |
| 35 decisions without Anvil | 0.004772 s | 0.004580 s | 4.0% less |

Both versions produced **9,231 total simulation ticks and 340 bot actions**
for exactly the same three deterministic games. The profiler now asserts these
control totals to prevent future optimization patches from silently changing
the seeded match outcomes. This is not a comprehensive golden-state oracle
for every possible battle.

The small 2–3% difference in match CPU is within plausible CI runner noise;
do not claim a guaranteed production speedup until repeated paired samples
on the same machine corroborate it.

### Exact same-process PixelBox A/B comparison

The 55×40-character arena uses 110×120 logical pixels and the original
PixelBox 2×3 texel resolution. The `forceFullEncode` diagnostic argument
executes the exhaustive conversion, while the normal path enables
unchanged-frame elimination.

| Scenario (36 frames, Lua 5.4) | Cached mean CPU/frame | Exhaustive mean CPU/frame | Difference |
| --- | ---: | ---: | ---: |
| Static, 0 additional troops | 0.431 ms | 0.629 ms | ~31.5% faster |
| Static, 30 troops | 0.776 ms | 1.020 ms | ~23.9% faster |
| Moving, 30 troops | 1.067 ms | 1.024 ms | ~4.2% slower |

These are CPU times **per one virtual monitor**, not real network latency.
Moving frames incur a small roster-comparison overhead. The optimization is
most useful when troops/buildings/towers or idle lobbies produce identical
frames. A physical crowded-game measurement is required to decide its actual
frame-time benefit.

### Behavioral checks

- All **24 in-game mechanics scenarios pass** on Lua 5.2/5.4 CI.
- **183 exact Anvil optimized-vs-exhaustive comparisons** pass across both
  owners, clustered/sparse/cross-river layouts and overlapping pending spells.
- **38 pixel-diff checks**, including exact line/color equality against
  exhaustive PixelBox output for both player orientations, sprite movement,
  and countdown transitions.
- Existing target lock, Spatial AoE order, headless simulation parity,
  mirrored-side fairness, persistence and recovery suites pass.
- No performance timing limit is used to fail CI: absolute CPU timings
  fluctuate on shared GitHub runners.

## Follow-up / field verification

This does not close OP-001/002/003; on your real ATM10 server still check:

- Render both 8×5 monitors while units move continuously, then hold a static
  battle scene and compare observed frame lag.
- Fast-moving troops, Creeper fuses, Evoker Fang warnings/impacts, Ghast Portal
  shimmer, Guardian beam and sudden phase transitions should look identical.
- Run `mechanics_test`; upload the new report to verify the revision.
- Time 100–1000 seeded simulations before/after on the same CC:Tweaked
  computer, with fixed deck/context/seed and equal match outcomes.
- Monitor server TPS and catch-up loss before altering the fixed tick rate.

No hardware/real-server performance claim is made.
