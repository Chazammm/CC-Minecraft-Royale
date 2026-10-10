# Transaction integrity deep audit (2026-10-10)

**Baseline:** `b5c3058b2beb88039fabb36fb327a3b8b4f4b8e6`.
This is a repeat review of the earlier audit fixes themselves, not an
independent claim of formal verification. Scope: repository source paths
for deck persistence, automatic benchmarks, GitHub credential lifecycle,
installer and related CI, plus original gameplay and graphics parity suites.

## Audit method

Inspected the main Lua entrypoints, 19 gameplay/platform source modules,
bundled PixelBox, all test modules and report data history. In particular
reviewed every filesystem `pcall`, `move`, `delete`, `readAll`,
`write`, `close`, crash recovery branch and early return in these
data-preserving subsystems. Existing tests generally injected *exceptions*
or *explicit false*; they did not all inject a **successful API call which
silently performs no action or writes a partial file**.

New fault injectors now model those latter cases. Each regression lives
in CI with both Lua 5.2 and 5.4, as well as the existing match/renderer
parity tests.

## Findings and actual changes

- **AF-019: Preset integrity (P1).** A successful but truncated temp write
  could lead `presets.save` to promote invalid data and delete the only
  complete backup. No-op file moves could also report false save success.
  Validate staged serialized data and renamed output bytes; only discard
  recovery copies when the new data is byte-identical and fully readable.
  Regression: `tests/test_preset_transaction_integrity.lua`.
- **AF-020: Token replacement (P1).** Existing GitHub token was opened
  directly with `w` during `report_sync setup`. A failed reconfiguration
  could erase a working credential. Stage new token, verify content, move
  old token to `.bak`, promote `.tmp`, verify and restore old on failure.
  Regression: `tests/test_atomic_token_reconfig.lua`.
- **AF-021: Token crash residue (P2).** A reboot after the initial rename
  leaves the old token in `.bak`; `isConfigured/readToken` can now use
  that backup. `report_sync logout` removes active, temporary **and backup**
  credential copies, each with a verified delete result.
  Regressions: `tests/test_token_backup_recovery.lua` and
  `tests/test_report_logout_false.lua`.
- **AF-022: Report output (P2).** A partially written simulated-comparison
  or balance report could replace the complete prior output with no error
  if file APIs silently truncated data. The report writer records its
  intended chunks (small text reports), checks the staged bytes and
  post-rename destination exactly, and keeps/restores old reports if
  publication is incomplete. Regression:
  `tests/test_report_transaction_integrity.lua`.
- **AF-023: Installer verification (P1 risk).** A storage wrapper could
  falsely report a successful installer marker write and begin overwriting
  files without a valid crash guard. The installer now reads back exact
  marker, metadata and installed module content after writing. Regression
  extended in `tests/test_installer_false_returns.lua`.

## Nonchanges / constraints

No troop HP/damage/range/cost, Evolution cycle, bot scoring, fixed combat
step, seeded-match RNG ordering, target lock, monitor pixel resolution,
or rendered artwork were deliberately changed. Preset/report/token
writes do some additional I/O to validate content, a correctness-first
tradeoff for low-frequency persistence operations.

## Evidence and limitations

Existing deterministic CI covers **24 mechanics cases**, 8 seeded matches
with 21,254 total combat ticks/1,250 sampled states/**244,969 assertions**
per Lua interpreter, exact Anvil decision parity and two-perspective
PixelBox frame parity. This audit adds new fault injection; look at the
PR/Actions results for completion before calling it merged.

The latest physical ATM10 uploaded mechanics report is for older commit
`28ef6cf29ecd...`, **not** this revision. No real power-loss, real
speaker streaming, modem-reconnect, disk exhaustion or monitor-latency
test was performed as part of this change. Physical tests remain open.

After merging: install on ATM10 and run `mechanics_test`, save/load decks
across a reboot, run a short `simulate`, verify report sync, and play a
real match with sound and both monitors. Avoid deliberate power-loss
tests on the only valuable set of saved decks.
