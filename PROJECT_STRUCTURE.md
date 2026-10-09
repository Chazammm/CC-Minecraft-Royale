# Project structure

This repository is intentionally split by responsibility so gameplay, rendering,
platform integration, and benchmark tooling can evolve independently.

## Runtime entry points

- `main.lua` — normal two-monitor game loop.
- `admin.lua` — developer/admin sandbox.
- `startup.lua` — launches the normal game.
- `diagnose.lua` — hardware and monitor diagnostics.

## Core modules

- `src/game.lua` — authoritative match state and combat rules.
- `src/cards.lua` — selectable cards, dev-only cards, units, buildings,
  spells, and evolutions.
- `src/arena.lua` — arena geometry, placement, lanes, river/bridge rules,
  and navigation helpers.
- `src/bot.lua` — bot observation, scoring, and play decisions.
- `src/util.lua` — small general-purpose helpers.

## Presentation and hardware

- `src/render.lua` — normal UI.
- `src/admin_render.lua` — admin UI.
- `src/pixel_arena.lua` — arena pixel rendering and sprites.
- `src/hardware.lua` — monitor/speaker discovery and hardware mapping.
- `src/music.lua` / `src/music_manifest.lua` — streamed battle music.

## Benchmark and diagnostics tooling

- `simulate.lua` — deterministic balance benchmark.
- `compare.lua` — controlled card replacement A/B benchmark.
- `evo_compare.lua` — base-vs-evolution benchmark.
- `src/benchmark_utils.lua` — shared deterministic RNG/shuffle/statistics
  helpers used by benchmark tools.
- `src/headless_match.lua` — authoritative deterministic headless match loop
  shared by simulate/compare/evo_compare.
- `mechanics_test.lua` — in-game mechanics diagnostics.
- `tests/test_v1.lua` — legacy broad Lua smoke/regression suite.
- `tests/test_audit_regressions.lua` — focused cross-mechanic regressions.
- `tests/test_headless_runner.lua` — proves the shared runner preserves the
  historical tick/bot update order.
- `tests/test_platform_stubs.lua` — stubbed CC:Tweaked platform tests.
- `tests/test_install_manifest.lua` — verifies installed entry points include
  every recursively required project module.
- `tests/test_cli_manifest.lua` — CLI safety and immutable music metadata.

## Reporting

- `report_sync.lua` — CLI entry point.
- `src/report_sync.lua` — GitHub report-sync implementation.
- `reports/latest/` — latest uploaded reports.
- `reports/history/` — historical reports retained for comparison.

## Assets and third-party code

- `assets/` — music workflow documentation. Large DFPWM packs are referenced
  by immutable historical Git URLs instead of living on current main.
- `lib/pixelbox_lite.lua` — bundled PixelBox dependency.

## Maintenance rules

1. Gameplay authority stays in `src/game.lua`; renderers should only present
   state and never invent combat behavior.
2. Headless simulation must preserve the same combat decisions/timing as live
   play unless a benchmark-only optimization is proven equivalent.
3. The actual benchmark match loop belongs only in `src/headless_match.lua`;
   simulate/compare/evo_compare configure that runner instead of cloning it.
4. New RNG/statistics helpers shared by benchmark CLIs belong in
   `src/benchmark_utils.lua`.
5. Runtime-generated files belong in `.gitignore`; uploaded reports belong
   under `reports/`.
6. Every behavior fix should get a regression test where practical. New
   focused tests should go into separate files instead of growing test_v1.lua.
7. Dev-only cards must not enter the normal selectable card pool or standard
   comparison tooling.
