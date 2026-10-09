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
- `mechanics_test.lua` — in-game mechanics diagnostics.
- `tests/test_v1.lua` — Lua smoke/regression suite.
- `tests/test_platform_stubs.lua` — stubbed CC:Tweaked platform tests.

## Reporting

- `report_sync.lua` — CLI entry point.
- `src/report_sync.lua` — GitHub report-sync implementation.
- `reports/latest/` — latest uploaded reports.
- `reports/history/` — historical reports retained for comparison.

## Assets and third-party code

- `assets/` — battle-music packs.
- `lib/pixelbox_lite.lua` — bundled PixelBox dependency.

## Maintenance rules

1. Gameplay authority stays in `src/game.lua`; renderers should only present
   state and never invent combat behavior.
2. Headless simulation must preserve the same combat decisions/timing as live
   play unless a benchmark-only optimization is proven equivalent.
3. New benchmark helpers shared by two or more CLI tools belong in
   `src/benchmark_utils.lua`.
4. Runtime-generated files belong in `.gitignore`; uploaded reports belong
   under `reports/`.
5. Every behavior fix should get a regression test where practical.
6. Dev-only cards must not enter the normal selectable card pool or standard
   comparison tooling.
