# Audit register — CC-Minecraft-Royale

This file is the source of truth for findings. A green CI result is **not** proof
of physical monitor/audio/network correctness. Record findings here instead of
silently reclassifying performance ideas as bugs.

Audit baseline: `a674c658a2b5f16c50e0f82f70566158b909b197` (2026-10-10).
Fix branch: `fix-audit-findings-quality-gates-20261010`.

## Rules

- **CONFIRMED**: provide a deterministic reproduction and a failing regression
  before the fix, or a demonstrable invariant violation with direct evidence.
- **RISK**: state the prerequisites; do not describe as an observed failure.
- **OPTIMIZATION**: demonstrate measurement before modifying a stable path.
- **FIXED_CI**: changed source and corresponding automated regression passes.
  This does **not** mean `VERIFIED_HARDWARE`.
- **VERIFIED_HARDWARE**: an actual CC:Tweaked/ATM10 test with machine, version
  and observed result is recorded.
- **DEFERRED**: explicit reason and a condition for revisiting.
- Any reopened issue keeps the **same ID**. Never silently remove an entry.
- Release-blocking P0/P1 findings require a specific regression and successful
  CI before merging. Balance changes require fresh code-revision-tagged runs.

## Fixed findings — third audit

| ID | Category / severity | Evidence and reproduction | Resolution | Regression / status |
| --- | --- | --- | --- | --- |
| AF-001 | RISK P1, installer data loss | `install.lua` previously treated syntactically safe arbitrary `.cc_royale_managed` entries as owned and deleted them when stale; an injected `deck_presets.db` would be removed | Only explicitly allowlisted retired project files can be removed; preserve unknown manifest entries | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |
| AF-002 | RISK P2, installer network failure | Failed `http.get` may supply a third response handle not closed on failed HEAD resolution / file download | Close failure handles | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |
| AF-003 | CONFIRMED P2, report integrity | `simulate.lua`, `compare.lua`, `evo_compare.lua` truncated previous complete report at the beginning of a run | `src/report_output.lua` stages new reports, publishes after completion, restores backup on a failed rename and on interrupted replacement | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |
| AF-004 | RISK P2, orphan music response | A late `http_success` with an evicted/unknown request URL was ignored without closing its response handle | Close only recognized stale **music** handles; unrelated requests remain untouched | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |
| AF-005 | RISK P2, water approach | `arena.groundReachPoint` minimized target distance, sometimes selecting the opposite bank despite a nearer reachable firing location | Select within attack reach using attacker travel distance; preserve legacy/debug tie behavior | `tests/test_audit_fixes_20261010.lua`, `tests/test_audit_regressions.lua` — FIXED_CI |
| AF-006 | CONFIRMED model discrepancy P2, Anvil forecast | `predictedAnvilPosition` directly advanced virtual coordinates while real `moveToward` checks river/bridge collision | Prediction now observes terrain collision and relevant unit movement attributes | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |
| AF-007 | RISK P3, async music stall | `httpPending` previously had no application-level timeout if the expected event was lost | Bound pending time; abandon stale request and retry with backoff | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |
| AF-008 | RISK P3, ranged HTTP data | An invalid/missing `Content-Range` under HTTP 206 could be passed to DFPWM decoding | Validate start/end/total, case-insensitive header key; reject malformed/missing range | `tests/test_audit_fixes_20261010.lua`, `tests/test_platform_stubs.lua` — FIXED_CI |
| AF-009 | CONFIRMED invariant P3, health | `damageEntity` subtracted raw damage so dead HP could go below 0 while actual-damage telemetry was capped | Clamp resulting HP to zero | `tests/test_audit_fixes_20261010.lua` — FIXED_CI |

## Open follow-ups — not confirmed gameplay bugs

| ID | Classification | Evidence / limitation | Next action and acceptance condition |
| --- | --- | --- | --- |
| OP-001 | OPTIMIZATION, monitor | `src/pixel_arena.lua` suppresses unchanged blit rows but still regenerates each pixel frame | Measure draw CPU time and network blits on both 8×5 monitors; try dirty rectangles only with screenshot/parity assertions and a proven speedup |
| OP-002 | OPTIMIZATION, bot | `src/bot.lua:bestAnvilTarget` still performs a quadratic predicted-target scan | Benchmark crowded matches and only introduce spatial buckets if same chosen targets/scores and lower measured CPU |
| OP-003 | DESIGN/MEASUREMENT, timestep | `main.lua` deliberately caps catch-up at 5 ticks to prevent unsafe physics leaps; sustained overload drops simulated time | Instrument frame delay/catch-up loss in a physical arena before changing timing semantics |
| OP-004 | EVIDENCE, stale balance | Latest reports are from 2026-10-09 and precede the corrected revision | In ATM10 run `mechanics_test`, `simulate 1000 mixed`, controlled `compare`/`evo_compare`; verify CODE_REVISION before balance decisions |
| OP-005 | MAINTENANCE, reports | History grows with each upload; not a correctness defect at present | Review pruning after a documented size/retention limit; preserve newest and reproducibility |

## Field validation required before declaring a release hardware-verified

- Two real Advanced Monitors, correct orientation, touch zones, no stuck
  countdown pixels after phase changes, stable real-world frame cadence.
- Wireless/wired peripheral detach/re-attach and at least one-speaker and
  two-speaker setups, streaming HTTP retry and valid Range behavior.
- Real match vs normal/hard bots, spells, bridges, water-only Dev units,
  overtime, tiebreaker and rematch.
- Interrupted installer retry and preset preservation on the target computer.
- Latest `mechanics_test` report and comparable deterministic balance data.

See `QUALITY_GATE.md` for the precise release decision process.
