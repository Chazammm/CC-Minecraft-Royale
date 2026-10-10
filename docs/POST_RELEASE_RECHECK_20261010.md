# Fourth review: post-release persistence and report-sync verification

Audit date: 2026-10-10. Audited GitHub main revision before this
review: `8dbb7e40af70c67c442b14bf02d7e72a980c29c9`.

## What the physical upload proves

The latest user-uploaded `reports/latest/mechanics_report.txt` is stamped
`CODE_REVISION|28ef6cf29ecdb6e417fe0587ee9b731b2663e7c1` and
`SUMMARY|pass=24|fail=0|error=0|total=24`. It is a successful ATM10
gameplay test from an **older revision**. It does **not** exercise the more
recent PR #8 (`8dbb7e40`) or any changes described below. Do not imply
an in-game test has been uploaded for those revisions.

## Test-before-fix failures verified in GitHub CI

### AF-017 — a file read failure is not proof that a preset is corrupt

`src/presets.lua` originally refused to overwrite recoverable `.bak`
and `.tmp` candidates, but could still overwrite a temporarily unreadable
`deck_presets.db` if neither backup existed. The `readAll()` false case
was also interpreted as corruption, allowing deletion of an unreadable
recovery file. In some file wrapper failure scenarios, those are the only
existing user presets.

- Red-before-fix: `tests/test_preset_false_returns.lua` on GitHub Actions
  run `38073825458`, failed for unreadable primary files.
- Fix: require a valid string from `readAll`, check read-handle close, and
  refuse to save if an **existing** main file cannot be read; a demonstrably
  corrupt but readable file can still be replaced.
- `presets.save` now rejects a non-string serialization result as well.
- Regression count after fixes: 31 assertions on **each** Lua 5.2 and 5.4.

### AF-018 — GitHub token setup must verify the saved credential

`src/report_sync.lua:writeAll` previously ignored non-throwing failure
returns from creating the credential directory, writing the file or closing
its handle, and returned success without verifying its contents.

- Red-before-fix: `tests/test_report_token_write_failures.lua` in CI on
  unpatched branch. Scenarios: mkdir false, write false, close false,
  silent dropped content and normal success.
- Fix: fail closed on all three file API failure modes; re-read the token
  file and compare exact bytes before reporting successful setup.
- 17 assertions on each supported Lua version.

## Repeat regression and diagnostic matrix

- 24 existing in-game mechanics scenarios: **all pass in CI**.
- `tests/test_core_invariant_stress.lua`: 8 complete bot matches,
  21,254 ticks, 1,250 sampled snapshots and 244,969 assertions per
  Lua interpreter.
- PixelBox exact two-perspective frame comparisons: 38 parity checks.
- Anvil spatial-vs-exhaustive comparisons: 183.
- CI additionally runs platform stubs, installer recovery, token logout,
  fixed seed/gameplay parity, side symmetry and quality gate audits.

The changes affect only file handling; they do not change troop/structure
statistics, target selection, frame rendering, simulation seeds or timing.

## Remaining limits

- A green CI run cannot verify actual power loss during disk writes or
  hardware-specific behavior of ATM10 peripherals. Keep backup copies of
  valuable deck presets and test save/reload/reboot on the real system.
- Re-run `mechanics_test` after installing the newly merged revision.
- Real-world music streaming, speaker buffering, monitor latency and
  sustained tick catch-up are still hardware tasks.
- `runtime_cpu_s=0.0000` in the previously uploaded report is **not**
  evidence of zero runtime or improved performance.

All findings retain stable identifiers in `docs/AUDIT_REGISTER.md`.
