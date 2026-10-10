# Deep technical core audit — CC-Minecraft-Royale (2026-10-10)

## Scope and audit method

Baseline commit: `6e0c6ebf07a7b5cf6901a3a585c269390a4be8fe`.
The full Git tree was inventoried (**118 files / 1,395,819 tracked bytes**):
11 root Lua entrypoints/configs, 19 `src/` modules, 1 bundled PixelBox
implementation, 17 existing test files, 58 generated reports/history files
and 12 documentation/workflow/metadata files.

Every active code module was inspected for broad patterns (file API error
handling, nonprogress loops, unbounded memory allocations, mutable state
ownership, module boundaries and cross-platform Lua assumptions). The main
game, bot and arena mechanics were cross-checked against the existing
in-game and synthetic regression suites, with additional testing concentrated
on risky persistence/installer/audio paths. This is a comprehensive *review
of the repository surface*, not a formal line-by-line proof of every
control-flow path or an actual peripheral integration test.

### Area-by-area scope

| Area | Files/operations inspected | Findings and coverage |
| --- | --- | --- |
| Combat/match state | `src/game.lua`, `src/spatial.lua`, `src/arena.lua`, `src/cards.lua`, `config.lua` | Existing 24 mechanics tests, target lock and parity; new seeded owner/ID/HP/economy/spatial consistency stress |
| Bot, strategy, Evolution | `src/bot.lua`, `src/headless_match.lua`, `src/benchmark_utils.lua` | Existing side symmetry/headless and exact Anvil-oracle parity; no behavior changes |
| Graphics/UI | `src/render.lua`, `src/admin_render.lua`, `src/ui_buffer.lua`, `src/pixel_arena.lua`, `lib/pixelbox_lite.lua` | Existing 38 pixel-image parity checks; moving-frame ~4% overhead remains an explicit optimization follow-up |
| Main/admin/platform | `main.lua`, `admin.lua`, `src/hardware.lua`, `diagnose.lua`, `startup.lua` | Existing platform stubs and hardware-reconnect tests; actual wireless monitors still pending |
| Installation/persistence | `install.lua`, `src/presets.lua`, `src/report_output.lua`, `src/version.lua` | Reproduced error handling gap for explicit false returns, fixed with fault-injection tests |
| HTTP/music | `src/music.lua`, `src/music_manifest.lua` | Seek failure/empty-read hang prevention; real streaming behavior still requires hardware |
| Reports/benchmarks | `simulate.lua`, `compare.lua`, `evo_compare.lua`, `report_sync.lua`, `src/report_sync.lua` | Existing identical-seed comparisons and atomic report tests; token logout now checks actual deletion |
| Tests/CI | `tests/*.lua`, `.github/workflows/lua-ci.yml`, `QUALITY_GATE.md` | Existing plus four new failure-mode tests and one full match invariant harness on Lua 5.2 / 5.4 |
| Report artifacts | `reports/latest`, `reports/history` | Historical outcome/balance artifacts are input evidence, not executable code. Latest reports predate the most recent Diamond-Golem buff; re-run for balance claims |
| Docs/metadata | `README.md`, `PROJECT_STRUCTURE.md`, `TEST_PLAN.md`, `docs/*`, `assets/README.txt`, `.gitignore`, `.gitattributes` | Inventory/consistency pass and updated audit register; not all historical claims are hardware-verified |

## Confirmed or fault-injected findings

- **AF-012 (P1, confirmed):** `src/presets.lua` could accept a
  `pcall` that succeeded while underlying `fs.move`, `fs.delete`,
  `handle.write` or `handle.close` returned `false`, then report a
  successful save or discard backup transaction files incorrectly. The new
  CI step demonstrably **failed** before the fix on run
  https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38071951733.
  Fixed and covered by `tests/test_preset_false_returns.lua`.
- **AF-013 (P2, risk, fault-injected):** Failed seeking in local DFPWM packs
  could be misclassified as success; an empty-read fallback could hang.
  Corrected in `src/music.lua`, covered by
  `tests/test_music_seek_failures.lua`.
- **AF-014 (P1, risk, fault-injected):** `install.lua` accepted explicit
  failed filesystem deletes and writes, potentially bypassing its
  protective installation marker. Fail-closed behavior covered by
  `tests/test_installer_false_returns.lua`.
- **AF-015 (P2, risk, fault-injected):** `report_sync logout` could say the
  credential was removed despite an explicit failed deletion.
  Corrected and covered by `tests/test_report_logout_false.lua`.

### New ongoing diagnostic coverage

`tests/test_core_invariant_stress.lua` runs genuine code paths (production
`Game.update`, `Bot.update` and the shared `Runner.run`) in seeded
decks with both sides and various unit/spell types. It checks a complete
bidirectional consistency snapshot every 17 game updates:

- living entity ID uniqueness and `entityById` membership
- live HP/maxHP positivity and finite positions
- `entitiesByOwner` counts and ordering
- `spatialIndex` bucket memberships, ownership, order, reverse pointers
  and duplicate/orphan entries
- valid two-sided Emerald balances

Initial CI: **8 matches, 21,254 ticks, 1,250 snapshots and 244,969
assertions**, independently green under Lua 5.2 and Lua 5.4.
This harness becomes part of every future GitHub CI run, including after
new cards/mechanics are added.

## Outstanding risks — not confirmed defects

1. **OP-003 main-loop catch-up:** `main.lua` caps delayed simulation catch-up
   to five ticks. Under sustained overloaded monitors/HTTP it deliberately
   drops simulation time. Measure real queue backlog and both displays before
   changing behavior; never skip combat ticks to make benchmarks look faster.
2. **OP-001 renderer:** Even pixel-identical final images still require terrain
   and sprite drawing. An earlier same-process A/B showed a ~4% CPU regression
   when units constantly move versus exhaustive conversion. Consider region
   invalidation only with exact dual-monitor pixel output equivalence.
3. **OP-004 report freshness:** Latest mixed/compare/evo results refer to
   `7ec97e417279...`. The audited base commit `6e0c6ebf...` includes the
   Diamond Golem health adjustment, so no fresh post-buff competitive
   effect can be asserted.
4. **OP-005 report history:** Every fresh diagnostic upload keeps history;
   long-term size/retention and any pruning should be explicitly designed
   before deleting user-generated research artifacts.
5. **Hardware-specific reliability:** HTTP streaming, actual display latency,
   modem disconnection and CC filesystem power-loss behavior require user
   testing in ATM10. Linux CI stubs deliberately do not claim to simulate
   physical device drivers.

## Acceptance / verification

Run `lua5.2` and `lua5.4` on the added fault injectors and stress test,
all existing project suites and 24 mechanics scenarios. Record the final
successful GitHub Actions run and resulting release commit in the PR.
After updating ATM10:

```lua
wget run https://raw.githubusercontent.com/Chazammm/CC-Minecraft-Royale/main/install.lua
mechanics_test
```

Verify saved deck presets across reboot, retry interrupted installation,
check music with actual speaker/GitHub availability, and verify
`report_sync logout` only if intentionally removing locally stored
credentials.

No game balance constants, combat behavior, tick rate, simulation accuracy,
sprite resolution or existing card names were changed in this audit.
