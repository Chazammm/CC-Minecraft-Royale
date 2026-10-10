# Iterative core audit — 10 October 2026

Baseline: `ac9e8952301b9c7a59ab350b263fa3ac11c096c8`.

## The audit-loop rule

For each cycle: inspect source and known failure states, write a specific
regression **before changing the source**, confirm the faulty baseline fails,
make the smallest behavioral fix and rerun the full Lua 5.2 + 5.4 CI.
The final stabilization round adds a systematic state-space oracle and
reviews the new changes. Stop when no **new reproducible issue** is found
in that final coverage round and all CI checks are green. This is bounded
engineering validation, not a guarantee that every reachable program state
or physical peripheral fault has been proven correct.

## Round 1: credential recovery (new AF-024)

- Existing active token file truncated after power-loss-style failure, while
  a valid `.bak` survived. Reports could be read as unconfigured because
  the active short value always took precedence.
- A renewed setup attempt could remove the good backup before correcting
  the damaged primary.
- The new fallback test was **red before the fix** in GitHub Actions run
  `38075884598`. A setup transaction scenario also failed before fix in
  run `38075960940`.
- Fix: use a valid backup when the primary is missing or not a usable-length
  credential. During setup, restore the complete backup *first* before any
  new transaction cleanup.

## Round 2: recovery must not destroy unreadable originals (AF-025/026)

- Decks: `presets.load` could read a backup while a newer active
  `deck_presets.db` only temporarily failed to open, then delete the
  unreadable primary. A valid backup is now returned to memory without
  destructive replacement in this condition. Reproduced red in CI
  `38076121962`.
- Benchmarks: `reportOutput.start` used to delete an old complete
  `.bak` whenever the primary existed, even when the primary could
  not be read. It now refuses to start until the primary is readable,
  preserving both copies. Reproduced red in CI `38076184415`.

## Round 3: recovery cleanup and state-space oracle (AF-027)

- Deck recovery from a good staged `.tmp` could delete an unreadable
  older `.bak`. Cleanup now leaves unreadable recovery candidates
  in place. Reproduced red in CI `38076254476`.
- Added `tests/test_preset_recovery_matrix.lua`: an **exhaustive
  5 x 5 x 5 = 125-state** matrix for `deck_presets.db`,
  `deck_presets.db.tmp` and `deck_presets.db.bak`. Each may be
  absent, contain valid deck A, contain valid deck B, contain a
  readable corrupt body, or be temporarily unreadable. The invariant
  oracle checks **selection order**, persistence of recoverable content
  and preservation of unreadable files.
- The new matrix succeeded on both Lua 5.2 and Lua 5.4 without requiring
  another source change. This is the final independent clean check,
  supplemented by every old regression and seeded combat benchmark.

## Preserved gameplay and safety boundaries

- No intentional change to troop/building stats, Evolution benefits,
  entity attack targeting, collision, physics timestep, bot AI,
  monitor graphics or music processing.
- Prior suites remain: **24/24** mechanics cases,
  8 seeded matches with **21,254 game updates** and
  **244,969 sampled invariants per Lua interpreter**,
  exact Anvil comparison and 38 PixelBox parity checks.
- The last physical ATM10 Mechanics upload has
  `CODE_REVISION=28ef6cf29ecdb6e417fe0587ee9b731b2663e7c1`.
  Do **not** represent this as confirmation for these recent commits.
- Linux CI, synthetic fakes and even 125 combinations do not cover every
  adversarial filesystem behavior, real power loss, actual speakers,
  modem disconnects or monitor performance. In-game testing is needed.
- Newly revealed bugs should reopen an existing AF-ID or get a new one;
  they should *never* be suppressed to make a loop appear clean.

## Safe physical verification

Update in-game via the pinned GitHub installer, run `mechanics_test`,
save/reload/reboot a deck preset, run a short comparison or simulation and
confirm the generated report is legible and uploads through `report_sync`.
Keep an independent copy of valuable presets before destructive power-loss
experiments.
