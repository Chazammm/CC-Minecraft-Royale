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

| AF-010 | CONFIRMED P2, stale Charged Creeper assertion | In-game mechanics report (2026-10-10, revision `b084252affcd`) shows 523 HP lost for each 523-HP Zombie; old fixture asserted 580 after `damageEntity` began clamping death HP at zero | Give isolated test targets at least 1,000 HP so exact 580 explosion damage is measurable without changing correct combat rules | `tests/test_mechanics_full_ci.lua` — FIXED_CI |
| AF-011 | CONFIRMED P2, stale Evoker Fang-line setup | Mechanics report shows nearer Skeleton receives 85 and farther Zombie receives 0 because uncommitted units now retarget nearer enemies; old test set `targetId` but assumed it persisted | Queue the long-target Fang line **before** a nearer Skeleton enters its warning path; then measure two 85-damage ground hits and unaffected Blaze | `tests/test_mechanics_full_ci.lua` — FIXED_CI |

## Deep core audit — 2026-10-10 (revision `6e0c6ebf07a7`)

Inventory: 118 tracked files at the audit baseline: 11 root Lua entry/config
files, 19 `src/` modules, 1 bundled PixelBox library, 17 existing Lua
test files, 58 report files, and 12 metadata/docs/asset-manifest files.
The Lua source/CI module families were individually fetched and searched for
unsafe filesystem outcomes, non-progress loops, unbounded work, RNG side
effects and missing state consistency tests. No claim of formally verifying
every execution path or physical peripheral is made.

| ID | Category / severity | Evidence / reproduction | Resolution | Regression / status |
| --- | --- | --- | --- | --- |
| AF-012 | CONFIRMED P1, preset persistence | `src/presets.lua` treated `pcall(fs.move/delete/write/close)` returning `true,false` as a successful file transaction; false-return move to final could delete the only old preset backup or report a false successful save. Regression deliberately failed on unpatched branch commit `3ef1a8f` (CI `38071951733`). | Require both no exception and no explicit `false`; reject write/close failures, protect a lone recovery backup, and retain temp/backup after failed promotion | `tests/test_preset_false_returns.lua` — FIXED_CI |
| AF-013 | RISK P2, music source seek | `src/music.lua:seekTo` accepted `seek(...) == false` as successful and on a stream wrapper returning `read(...) == ""` could loop forever without consuming bytes | Only accept correct numeric seek position; explicitly reject zero-byte fallback reads | `tests/test_music_seek_failures.lua` — FIXED_CI |
| AF-014 | RISK P1, installer fail-closed behavior | `install.lua` treated false-return `fs.delete/write/close` as success; a failed installation marker write could allow subsequent managed-file replacement without a reliable recovery marker. Fault-injected standalone installer test. | Reject false-return delete/write/close and abort before applying new project files | `tests/test_installer_false_returns.lua` — FIXED_CI |
| AF-015 | RISK P2, token logout reporting | `src/report_sync.lua:clearToken` reported GitHub token deletion after `fs.delete` returned `false` (or left file present), misleading the user into thinking local credentials were removed | Require successful deletion and confirm the token file no longer exists | `tests/test_report_logout_false.lua` — FIXED_CI |
| AF-016 | CONFIRMED P2, preset recovery deadlock | Secondary review of AF-012 found that `presets.save` rejected **any** orphan `.bak` when no final existed, even if that backup was corrupted and nonrecoverable; it also could overwrite a valid lone `.tmp`, or discard a valid backup when final was corrupted. Pre-fix test failed in CI run `38073192935`. | Distinguish valid recovery candidates from invalid readable debris; preserve valid or unreadable `.tmp`/`.bak` until `load()` recovers them, but allow fresh save when all orphan files are confirmed invalid and readable. | `tests/test_preset_false_returns.lua` — FIXED_CI |
| AF-017 | CONFIRMED P1, unreadable primary deck file | `presets.save` in release `8dbb7e40` treated `readBody(PRESET_FILE)` returning `nil` (failed open/read) or `false` (nonthrowing read failure) as a corrupt file. With no valid backup, it could overwrite the only intact deck data. Red-before-fix in CI `38073825458`. | Distinguish absent/corrupt-readable from existing but unreadable primary; refuse overwrites on I/O failure; require string read/serialization and successful handle close. | `tests/test_preset_false_returns.lua` — FIXED_CI |
| AF-018 | CONFIRMED P2, false-positive token setup | `src/report_sync.lua:writeAll` ignored `fs.makeDir`, write and close false-return results; `setupInteractive` could say GitHub report syncing was configured even if the token was never committed to disk. Fault-injected test red on unpatched branch CI. | Fail closed on directory/write/close errors and read back the exact stored token before returning success. | `tests/test_report_token_write_failures.lua` — FIXED_CI |

New reusable invariant diagnostic: `tests/test_core_invariant_stress.lua`
probes **8 seeded, real headless bot matches** over **21,254 ticks** and
**1,250 sampled live match states** with **244,969 assertions** for valid
finite HP/coordinates, owner and ID maps, entity-array order, spatial bucket
forward/reverse links, orphan and duplicate members, and Emerald bounds.
Both Lua 5.2 and 5.4 pass with the regular regression suites and all
24 mechanics cases. In-game monitor, network and speaker tests are still
needed; the assertions provide fault detection, not proof that no bug exists.

## Transaction integrity audit — 2026-10-10 (baseline `b5c3058b2beb`)

A fourth manual cross-file review targeted failure sequences that earlier
filesystem tests had missed: successful calls with *incorrect side effects*,
failed token replacements with existing credentials, broken report writes
and crash windows between renaming originals and publishing new files.

| ID | Category / severity | Reproduction / evidence | Resolution | CI regression / status |
| --- | --- | --- | --- | --- |
| AF-019 | CONFIRMED P1, silently corrupted deck saves | `presets.save` accepted a successful `write/close` that only stored a truncated temporary deck, or `fs.move` returning success without moving anything. A corrupt new file could displace the only previously good preset. Reproduced with a red-before-fix fault-injection CI step. | Byte-compare staged serialized data; verify old->backup and temp->final side effects and destination contents; preserve/read back recovery files before deletion. | `tests/test_preset_transaction_integrity.lua` — FIXED_CI |
| AF-020 | CONFIRMED P1, credential replacement | Re-running `report_sync setup` on a configured computer wrote directly to the active token. An injected write failure truncated/deleted the previously working credential. | Write new credentials to verified `.tmp`, move old credential into verified `.bak`, promote staged token and restore old token on failed publication. | `tests/test_atomic_token_reconfig.lua` — FIXED_CI |
| AF-021 | RISK P2, credential crash/logout residue | Interrupted token replacement can leave original valid token only in `.bak`; logout previously deleted only the active path, reporting success while usable secrets remained in temporary/backup files. | Backup fallback for credential reads and cleanup of all three credential paths on logout, verifying each removal. | `tests/test_token_backup_recovery.lua`, `tests/test_report_logout_false.lua` — FIXED_CI |
| AF-022 | CONFIRMED P2, benchmark report data integrity | `reportOutput.commit` accepted truncated temporary report content after supposedly successful writes and silently unsuccessful renames, then removed the only complete old report. | Check exact staged bytes and expected destination bytes, verify old report backup and new report promotion before deleting backup; rollback safely on mismatch. | `tests/test_report_transaction_integrity.lua` — FIXED_CI |
| AF-023 | RISK P1, installer marker/content verification | `install.lua` relied on no-exception `write/close`; a silently dropped installation marker could permit destructive updates without the intended on-disk startup guard. | Read back exact bytes of recovery marker, managed modules and metadata before considering write successful. | `tests/test_installer_false_returns.lua` — FIXED_CI |

The diagnostics run under **Lua 5.2 and Lua 5.4**, next to the existing
24 mechanics cases, 8-match live-state invariant stress, Anvil and PixelBox
parity tests. Failure simulations do not replace real power-loss,
speaker/monitor or low-disk hardware testing. Full details:
`docs/TRANSACTION_INTEGRITY_AUDIT_20261010.md`.

## Repeated audit loop — 2026-10-10 (baseline `ac9e8952301b`)

This sequence continued through multiple new red-before-fix reproductions, then
stopped after an independent **125-case recovery matrix** plus all existing
gameplay/CI regressions ran green. These tests do not prove global
bug-freedom or real-world power-loss safety.

| ID | Category / severity | Reproduction / evidence | Resolution | Regression / status |
| --- | --- | --- | --- | --- |
| AF-024 | CONFIRMED P2, degraded active GitHub token | After interrupted credential publication a truncated active token could coexist with a valid `.bak`. `readStoredToken()` preferred the unreadable/too-short primary and disabled uploading; token setup could also discard the good backup. Red CI `38075884598`, `38075960940`. | Prefer valid backup only when active token is missing/degraded; recover it before transaction cleanup, and assert preservation of usable content rather than a particular backup pathname. | `tests/test_token_corrupt_active_fallback.lua`, `tests/test_atomic_token_reconfig.lua` — FIXED_CI |
| AF-025 | CONFIRMED P1, preset recovery after transient I/O failure | `presets.load()` could delete a temporarily unreadable primary `deck_presets.db` when restoring a valid `.tmp` or `.bak`, potentially losing newer contents. Red CI `38076121962`. | Return recoverable backup to memory, but do not promote/destructively clear an unreadable existing primary. | `tests/test_preset_false_returns.lua` — FIXED_CI |
| AF-026 | CONFIRMED P1, report backup lost on unreadable primary | `reportOutput.start()` deleted a saved report `.bak` if the primary existed, without verifying it was readable. Red CI `38076184415`. | Reject unsafe report start, preserve primary and backup until the active report can actually be read. | `tests/test_report_transaction_integrity.lua` — FIXED_CI |
| AF-027 | CONFIRMED P2, recovery cleanup erased unreadable copies | Successfully recovering a valid preset `.tmp` could discard an unreadable `.bak`, despite not knowing whether it contained older recoverable data. Red CI `38076254476`. | Only remove stale deck recovery artifacts after verifying they can be read. | `tests/test_preset_false_returns.lua`, `tests/test_preset_recovery_matrix.lua` — FIXED_CI |

The matrix enumerates **125 combinations** of absent/valid A/valid B/
corrupt/unreadable final, temporary and backup files, checking recovery
priority, preservation of unreadable entries and no loss of the only
recoverable deck. Tested on **Lua 5.2 and 5.4** as a permanent CI step.
Full scope and stopping criteria: `docs/ITERATIVE_AUDIT_20261010.md`.

## Full-system audit — 2026-10-11 (branch `audit-20261011-full-system`)

This pass re-read the active gameplay, simulation, test, persistence, installer,
rendering and hardware integration paths rather than treating the previous
green audit as proof of correctness. It also reconciles the targeting tests
with the current explicit gameplay contract: a valid target locks on
**acquisition**, not on first attack.

| ID | Category / severity | Evidence / reproduction | Resolution | Regression / status |
| --- | --- | --- | --- | --- |
| AF-028 | CONFIRMED P1, target-lock gameplay | `updateCombatEntity` deliberately allowed an unlocked troop to abandon an already selected tower/unit for a newly spawned closer target until its first attack. Legacy tests explicitly required that old behavior, contradicting the current target-lock rule. | Commit the first valid target immediately into `lockedTargetId`; release only when that target becomes invalid. Update stale legacy/hardening/mechanics expectations and the manual test plan. | `tests/test_v1.lua`, `tests/test_audit_hardening_20261010.lua`, `tests/test_mechanics_full_ci.lua` — FIXED_CI |
| AF-029 | CONFIRMED P2, building HP invariant | Natural lifetime decay subtracted HP directly, so the dead building object could retain negative HP even though direct combat damage had already been hardened to clamp at zero. | Clamp natural-decay HP at zero before death cleanup. | `tests/test_mechanics_full_ci.lua` — FIXED_CI |
| AF-030 | RISK P2, building-decay configuration | `BUILDINGS.lifetimeDecayMultiplier` was used arithmetically without config validation; nonnumeric input could crash a battle, zero silently disabled decay, and negative input could heal buildings. | Require a finite positive decay multiplier during startup config validation. | `tests/test_audit_followups.lua` — FIXED_CI |
| AF-031 | RISK P1, tiebreaker configuration | Negative `MATCH.tiebreakerDamagePerSecond` would make equal-HP drain add HP and could prevent tiebreak completion. The field was not validated. | Require a finite positive tiebreaker damage rate at config validation. | `tests/test_audit_followups.lua` — FIXED_CI |
| AF-032 | CONFIRMED P2, consecutive-match state | `Game.resetLobby` cleared live entities but retained prior-match telemetry, clocks and player feedback until the next countdown, exposing stale match-local state in the lobby. | Reinitialize countdown/timeLeft/stats and clear feedback/timers while preserving intended lobby choices such as decks/ruleset/mode. | `tests/test_audit_followups.lua` — FIXED_CI |
| AF-033 | RISK P2, malformed placement API | `arena.placementAllowed` compared coordinates without checking their types; a malformed bot/UI call with nil coordinates could throw instead of returning an invalid-placement result. | Reject nil, NaN and infinite placement coordinates at the arena API boundary. | `tests/test_audit_regressions.lua` — FIXED_CI |
| AF-034 | TEST-COVERAGE P3, forward-placement symmetry | Side symmetry tests covered normal deployment and bridge navigation but not post-Princess-Tower forward-placement pockets, leaving an explicit mirrored gameplay rule without a regression. | Add mirrored pocket probes plus opposite-lane and King-centre lock assertions. | `tests/test_side_symmetry.lua` — FIXED_CI |
| AF-035 | CONFIRMED P2, stale passive target lock | A unit switched dynamically to `passive=true` or `targetMode="none"` cleared `targetId` but retained `lockedTargetId` (and beam/fuse transient state), allowing old aggro state to survive a Dev/Admin disable-enable cycle. | Clear committed target and target-specific transient state whenever targeting is disabled. | `tests/test_audit_followups.lua` — FIXED_CI |

The intentional AF-028 gameplay change moves the three seeded performance
control matches from **9231 ticks / 340 bot actions** to the reviewed
**9143 ticks / 339 bot actions**. The performance diagnostic now prints its
control counts before checking the frozen baseline so future intentional
contract changes are reviewable rather than opaque.

Final verification on commit `8cfe3061d047` completed successfully:
**24/24 mechanics**, **290,177 core-invariant assertions** on both Lua 5.2 and
5.4, **183 Anvil exhaustive/grid parity comparisons**, **38 PixelBox frame
checks**, and deterministic mixed simulations of **100 / 500 / 1000** matches.
The 1000-match run produced P1 **50.6%**, P2 **49.2%**, draws **0.2%**, with no
technical timeout. A subsequent clean read of the changed targeting, reset,
movement-slow, configuration and symmetry paths found no additional relevant
software finding. Physical ATM10 monitor/audio/network verification remains a
separate hardware gate.

## October 13 cross-system audit — lobby-only mutation contracts

| ID | Category / severity | Reproduction and root cause | Resolution | Regression / status |
| --- | --- | --- | --- | --- |
| AF-036 | CONFIRMED P2, public deck/preset state mutation | `Game.toggleDeckCard`, `Game.randomizeDeck`, `Game.loadDeckPreset` and `Game.saveDeckPreset` assumed callers had already enforced lobby phase. Direct dev/script calls during countdown, battle, result or admin could mutate the equipped deck/Evolution, or persist an unintended deck; `randomizeDeck` could also consume global gameplay RNG. Nil/noninteger preset slots could throw or index unintended slots. The new Lua 5.2 CI regression failed **before** the fix, run [38393556660](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38393556660). | Guard every deck/preset write API with `state.phase == "lobby"`; validate preset slot as an integer 1–3 before comparing/indexing; reject without mutating decks, cycles or RNG. No balance or live tick behavior changes. | `tests/test_lobby_state_mutators.lua` — FIXED_CI: [38393721568](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38393721568), Lua 5.2 and 5.4 |

The existing three deck preset slots remain intentionally **UI-hidden** to
make room for the Evolution Slot (README documentation), not a newly detected
missing control. The fix is defensive API hardening; normal touch paths were
already lobby-gated.

## Additional defensive findings from the independent follow-up pass

| ID | Category / severity | Reproduction / impact | Minimal fix | Regression / status |
| --- | --- | --- | --- | --- |
| AF-037 | RISK P2, card-schema projectile lifecycle | A declared `projectileSpeed = 0` passed `cards.validate()` even though Lua treats `0` as truthy: `performAttack` spawns the projectile but `updateProjectiles` advances it by `0 * dt`. A projectile spawned farther than its impact radius would persist, wasting memory and potentially accumulating. Reproduced with a failing schema regression on [CI 38394153080](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38394153080). Current shipped projectile definitions all use positive speeds. | Require a finite **positive** projectileSpeed when the field is present; do not change any existing card speed or melee rule. | `tests/test_projectile_speed_schema.lua` — FIXED_CI: [38394284436](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38394284436), both Lua interpreters |
| AF-038 | RISK P2, river collision geometry | `config.validate()` used numeric comparisons on the `riverTop`/`riverBottom` boundaries without first checking finiteness; `NaN` comparisons all evaluate false and could pass startup validation. `arena.isRiver` would then stop identifying the river and ground pathing could illegally cross. Red-first test: [CI 38394462184](https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38394462184). Ordinary configuration is valid. | Validate both river bounds with existing finiteNumber helper before enforcing ordering, preserving all normal geometry values. | `tests/test_finite_river_bounds.lua` — FIXED_CI on final green run, both Lua interpreters |

## Open follow-ups — not confirmed gameplay bugs

| ID | Classification | Evidence / limitation | Next action and acceptance condition |
| --- | --- | --- | --- |
| OP-001 | OPTIMIZATION, monitor | `src/pixel_arena.lua` suppresses unchanged blit rows but still regenerates each pixel frame | Measure draw CPU time and network blits on both 8×5 monitors; try dirty rectangles only with screenshot/parity assertions and a proven speedup |
| OP-002 | OPTIMIZATION, bot | `src/bot.lua:bestAnvilTarget` still performs a quadratic predicted-target scan | Benchmark crowded matches and only introduce spatial buckets if same chosen targets/scores and lower measured CPU |
| OP-003 | DESIGN/MEASUREMENT, timestep | `main.lua` deliberately caps catch-up at 5 ticks to prevent unsafe physics leaps; sustained overload drops simulated time | Instrument frame delay/catch-up loss in a physical arena before changing timing semantics |
| OP-004 | EVIDENCE, stale balance | Latest reports are from 2026-10-09 and precede the corrected revision | In ATM10 run `mechanics_test`, `simulate 1000 mixed`, controlled `compare`/`evo_compare`; verify CODE_REVISION before balance decisions |
| OP-005 | MAINTENANCE, reports | The working report tree is bounded by the retention workflow; historical Git objects still grow with uploads | Review pruning after a documented size/retention limit; preserve newest and reproducibility |

## Reproducible CPU baseline

The read-only GitHub CI probe recorded CPU time for real deterministic
headless matches, high-density Bot decisions, and two-display static
PixelBox renders under Lua 5.2/5.4. See
[`PERFORMANCE_BASELINE_20261010.md`](PERFORMANCE_BASELINE_20261010.md)
for method, numbers and hardware limitations. This measurement does **not**
close OP-001, OP-002 or OP-003; no speedup has been implemented or validated.

## First optimization pass — measured, not field-verified

See [`PERFORMANCE_OPTIMIZATION_20261010.md`](PERFORMANCE_OPTIMIZATION_20261010.md)
for the precise changes, seeded match controls, and same-process
PixelBox cached-vs-exhaustive A/B measurements. The Anvil scoring grid has
183 exhaustive-oracle comparisons, and both monitor perspectives have 38
pixel-image checks including appearance and expiry of stationary effects.

Under Lua 5.4 CI, Anvil-heavy decisions were approximately 16% cheaper;
static frames were approximately 24–32% faster, while continuously moving
frames incurred ~4% extra CPU. Three matches showed ~2% less CPU but this
may be benchmark noise. **OP-001/002/003 remain OPEN pending ATM10
hardware measurements**; do not label these as resolved defects or claim a
real-server throughput increase.

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

## Approved sprite redesign — 2026-10-13

| ID | Classification / priority | Prerequisites and scope | Validation / status |
| --- | --- | --- | --- |
| VIS-001 | RISK P2, monitor legibility | User-approved redesign of all 35 arena models. Requires native 16-colour sprites, preserved variant selection and team colours, bounded footprints, and real PixelBox rendering. Gameplay, combat timing and balance are unchanged. | `tests/test_sprite_roster.lua` — 556 real-renderer checks in both perspectives; existing `tests/test_pixel_frame_diff.lua` — 38 checks. All 32 local Lua 5.4 suites pass; CI executes the new suite under Lua 5.2 and 5.4. Native and virtual-monitor previews are in `docs/SPRITE_REVAMP.md`. Physical CC:Tweaked monitor validation remains required. |

## Arena appearance redesign — 2026-10-14

| ID | Classification / priority | Prerequisites and scope | Validation / status |
| --- | --- | --- | --- |
| VIS-002 | RISK P2, terrain/coordinate parity | Simplified skin revision removes the stone pads, paths, banks and grass confetti, retaining the original clean field with subtle water and bridge detail. Requested arena skin must preserve the 100×160 world, exact river and bridge footprints, six tower coordinates, projection, collision, navigation, deployment and touch zones. Decoration must not consume gameplay RNG or mutate simulation state. | `tests/test_arena_skin_parity.lua` — 314,874 native/encoded terrain pixels, 68,034 coordinate cases, a bridge-width fault injection, and 240 identical combat ticks with old/new/no rendering. All 33 local suites pass in Lua 5.2 and 5.4; CI runs the new suite in both. Actual previews and preserved coordinates: `docs/ARENA_SKIN.md`. Physical monitor validation remains required. |


## Complete-system audit — 2026-10-14

### VIS-003 — Four-mob Phase-1 asset package (no gameplay activation)

RISK P2, visual readability and future integration. User authorizes native
Ravager Rider, Baby Ender Dragon, Minoshroom and Hero Spider art, prepared
animation/effect frames, isolated renderer tests and balancing proposals ONLY.
`assets/proposed/four_mobs_phase1/` remains absent from card registration,
runtime imports and installer manifests. Animation sequencing, new projectile
dispatch, dual attacks and permanent Hero Web are explicitly NOT IMPLEMENTED.
Validation: `assets/proposed/four_mobs_phase1/tools/test_assets.lua` and
`assets/proposed/four_mobs_phase1/tools/validate_previews.py`; statuses and
limitations are recorded in the package's `VALIDATION.md`. Phase 2 and merge
remain blocked on explicit user authorization, not on a technical assumption.

| ID | Classification / priority | Root cause / reproduction | Minimal fix | Validation / status |
| --- | --- | --- | --- | --- |
| AF-039 | CONFIRMED P1, terminal-state mutation | The projectile outer loop continued after a winning impact, so a later projectile damaged another tower after `Game.finish`. Independent regression loses 100 extra HP on the baseline. | Stop the battle projectile batch immediately on its first result transition. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-040 | CONFIRMED P1, spawn side asymmetry | Bat/Vex swarms, single summons and death splits use absolute world offsets; corresponding mirrored bodies have X sums 106/107/108 rather than 100, and split Y offsets are also not mirrored. | Mirror both axes of owner-2 deployment, periodic summon and death-split offsets; preserve counts, radii and stats. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-041 | RISK P2, nonfinite simulation delta | NaN delta passes comparison-only clamping, poisoning timers, economy and positions. Infinity is silently clamped and malformed strings fail later with incidental type errors. | Reject nonfinite/nonnumeric dt before mutation; ignore nonpositive dt and reject malformed slow factors/durations. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-042 | RISK P2, malformed admin coordinates | Admin spawn clamps inputs before checking types/finiteness; nil throws and infinity is silently converted into an edge spawn. | Reject malformed coordinates before ID/spatial mutation; retain clamping for finite coordinates. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-043 | CONFIRMED P2, headless transition contract | `startHeadlessBattle` resets the lobby before rejecting zero dt; a configured zero countdown skips zero ticks while live performs one transition tick. | Validate dt before reset; reproduce every live countdown transition, including zero and nonintegral countdowns. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-044 | CONFIRMED P2, headless side effects | The Lua `headless and nil or callback` idiom evaluates to the live callback even in headless mode; a headless start emitted two sound callbacks. | Use an explicit non-headless callback condition. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-045 | RISK P1, simulation validity | Exhausting the defensive tick budget called `Game.finish(..., nil, TIMEOUT)`, so benchmark aggregators counted a technically failed run as a genuine draw. Fault injection freezes `Game.update` and reproduces the invalid accepted result. | Raise a diagnostic timeout before any benchmark can score the failed match. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-046 | CONFIRMED P2, Emerald rounding | The accepted 0.0001 affordability tolerance was followed by raw subtraction, permitting small negative Emerald balances. | Clamp accepted Emerald debits at zero without changing price or affordability tolerance. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-047 | CONFIRMED P2, admin spell/index desync | Direct admin coordinate edits are supported, but an immediate Arrow cast used stale spatial buckets before the next admin tick; the independent regression misses all 185 damage. | Reconcile spatial positions at the admin spell API, matching the normal play API. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-048 | RISK P2, mechanics test isolation | `runTest` catches an exception but does not restore shared card/config definitions modified by that case, contaminating subsequent tests and reports. | Snapshot/restore the shared definition graph after every mechanics case, including thrown errors; retain original table identities. | `tests/test_mechanics_isolation.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-049 | RISK P2, HTTP response lifecycle | Report-sync HTTP get/post, response metadata/read/close and JSON decode exceptions escape the public API; a response read error skips handle closure. | Protect HTTP requests, metadata/read/close and JSON parsing, including nested permissions/ref/tree/commit shapes; always attempt closure and reject invalid SHA responses before branch writes. | `tests/test_audit_io_boundaries.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-050 | RISK P2, replay input validation | NaN/infinite or excessively large seeds, bot-order offsets and yield intervals can fail after staging a report or silently disable reproducibility/cooperative yielding. | Validate finite replay inputs before RNG, state or report mutation; reduce seed terms before adding offsets to preserve exact cross-Lua arithmetic. | `tests/test_simulation_contracts.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-051 | RISK P2, undersized monitor interaction | Layouts assume fixed lobby/admin content height. A physically small/temporarily resized monitor can produce an invalid arena window and overlapping invisible touch zones. | Display a minimum-size diagnostic and reject unavailable touch zones; retain valid layouts and query monitor size once per draw. | `tests/test_audit_monitor_boundaries.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-052 | RISK P2, report retention race | Rebase after a failed retention push preserves a deletion computed against stale pins; a new pin on main can then be deleted without a conflict. | Discard only unpushed CI cleanup after a push race, fetch current main and recompute pins/index/deletions; never force push. | `tests/test_report_retention.py` — FIXED_CI (five Python cases including a real local-Git push race; GitHub scheduling field validation pending) |
| AF-053 | CONFIRMED P2, owner-relative tie orientation | Equal-HP Princess targets, Villager X variation and exact bridge-distance ties select the same absolute world side for both owners, despite the 180-degree player-view contract. | Resolve exact ties and Villager variation in mirrored owner-relative coordinates, including centre-lane objectives. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-054 | CONFIRMED P2, renderer cache acknowledgement | A stationary-frame canvas snapshot is marked current before a blit succeeds; after a transient failed write the next identical frame can be skipped. The new small-monitor fallback also needs to discard the previous arena cache so restoring the same monitor size repaints cleared arena rows. | Invalidate failed frame acknowledgements and discard arena surfaces when entering the size fallback; force repaint after recovery. | `tests/test_pixel_failure_recovery.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-055 | CONFIRMED P1, floating-point combat timing | Subtracting 0.1 repeatedly can leave a positive residual around 1e-16 at an exact cooldown/lifetime boundary. A comparison against zero then adds an entire extra tick: 1.0s Zombie and 0.9s King attacks can occur at 1.1s and 1.0s. Existing tests checked fields/one hit, not exact repeated cadence. | Use one timer decrement helper with a 1e-9 residual tolerance for engine and bot clocks; preserve genuine timestep quantization and configured values. | `tests/test_timer_precision.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-056 | CONFIRMED P2, water-target reachability | Ground-target eligibility measures distance to the river boundary, while pathing stops 0.01 units outside it. A Zombie can lock a Guardian at exactly 2.5 units from the boundary but cannot reach attack range at the actual walkable point. | Measure the actual walkable bank used by navigation and apply consistent 1e-9 reach tolerance. | `tests/test_system_audit_20261014.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-057 | RISK P1, optional music failure isolation | A local seek-fallback read or pack open can throw out of `Music.start`, crashing the live main loop despite music being optional. Pending speaker exception retries bypass their scheduled backoff. | Protect optional local music discovery/open/seek/read/decode and HTTP metadata; honor pending-audio retry deadlines. | `tests/test_music_fault_boundaries.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-058 | RISK P1, queued monitor-touch disconnect | A queued touch can be delivered after its monitor disconnects. Both live entry loops call peripheral-dependent `layoutFor` without the render error guard, terminating the program. | Protect only peripheral-dependent layout acquisition; report/discard the failed touch and keep the game loop running. | `tests/test_touch_disconnect.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-059 | RISK P2, simulated deck validity | An invalid caller-supplied simulation deck is silently replaced by the default deck at countdown, making the reported experiment differ from its inputs. | Reject non-nil invalid decks before RNG reseeding or match construction; retain nil/default-deck behavior. | `tests/test_simulation_contracts.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-060 | CONFIRMED P2, delayed-spell terminal transition | A winning pending Anvil is resolved before aura reconciliation and combatTick advancement. Those paths then mutate the already-finished match even though later entity/projectile batches are frozen. | Return immediately after a terminal pending-spell transition. | `tests/test_system_audit_20261014.lua`, `tests/test_mechanics_full_ci.lua` — FIXED_CI (dual-Lua automated regression; hardware untested) |
| AF-061 | CONFIRMED P2, new audit-tool runtime compatibility | Follow-up review of the newly added runner found unconditional native-Lua `collectgarbage` calls. Cobalt BaseLib does not expose that function; a real CraftOS run would fail while sampling memory. | Probe optional GC safely, print unavailable memory honestly, and distinguish native CPU time from CraftOS uptime. | `tests/test_audit_runtime_gc.lua` — FIXED_CI (missing, count-only and throwing GC fixtures under both Lua versions; hardware untested) |
