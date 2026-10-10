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

## Open follow-ups — not confirmed gameplay bugs

| ID | Classification | Evidence / limitation | Next action and acceptance condition |
| --- | --- | --- | --- |
| OP-001 | OPTIMIZATION, monitor | `src/pixel_arena.lua` suppresses unchanged blit rows but still regenerates each pixel frame | Measure draw CPU time and network blits on both 8×5 monitors; try dirty rectangles only with screenshot/parity assertions and a proven speedup |
| OP-002 | OPTIMIZATION, bot | `src/bot.lua:bestAnvilTarget` still performs a quadratic predicted-target scan | Benchmark crowded matches and only introduce spatial buckets if same chosen targets/scores and lower measured CPU |
| OP-003 | DESIGN/MEASUREMENT, timestep | `main.lua` deliberately caps catch-up at 5 ticks to prevent unsafe physics leaps; sustained overload drops simulated time | Instrument frame delay/catch-up loss in a physical arena before changing timing semantics |
| OP-004 | EVIDENCE, stale balance | Latest reports are from 2026-10-09 and precede the corrected revision | In ATM10 run `mechanics_test`, `simulate 1000 mixed`, controlled `compare`/`evo_compare`; verify CODE_REVISION before balance decisions |
| OP-005 | MAINTENANCE, reports | History grows with each upload; not a correctness defect at present | Review pruning after a documented size/retention limit; preserve newest and reproducibility |

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
