# Release quality gate

The goal is *traceable confidence*, not an impossible claim that every line is
proven correct. No change is considered audited solely because CI is green.

## Required order for every issue or feature

1. **Register:** create or update a stable ID in `docs/AUDIT_REGISTER.md`,
   label it CONFIRMED / RISK / OPTIMIZATION, set priority and prerequisites.
2. **Reproduce:** on CONFIRMED bugs, preserve an executable failing test before
   fixing the code. On RISK, create a targeted fault-injection scenario.
3. **Fix minimally:** one invariant at a time; preserve gameplay timing and
   symmetry unless the change intentionally alters them.
4. **Regression:** prove old failure, new behavior, negative case, and important
   interactions with existing fixtures. Name test files next to each finding.
5. **Verify:** run Lua 5.2 and Lua 5.4 syntax, smoke, card validation, installer
   manifest and recovery, platform stubs, headless/game parity, symmetry,
   refactor parity, audit suites, and the register consistency gate.
6. **Measure:** performance work requires before/after CPU/wall-time with
   identical seed, Lua version, scenario and quality/parity evidence.
7. **Release:** review changed-file list and CI on the PR head, merge only
   when required automated checks are green. For hardware-dependent changes,
   record physical test outcomes separately: untested is NOT 'verified'.
8. **Report:** distinguish fixed+automated from field-verified, identify any
   deferred risks, and give a real in-game update command when applicable.

## Merge-blocking checklist

- [ ] No P0/P1 without a reproducible failing test or documented mitigation
- [ ] Every fixed issue has test-path evidence in the audit register
- [ ] All installer-created runtime dependencies are in `install.lua`
- [ ] No user-generated files, saved decks, credentials, or complete reports
      are overwritten by an interrupted install, run or sync
- [ ] Two-platform Lua syntax+tests and all GitHub Actions jobs pass
- [ ] No unexplained drift in PvP symmetry / combat / simulation parity
- [ ] Changed game balance? Fresh revision-stamped headless comparisons required
- [ ] Changed renderer/audio/hardware? Mark field validation required, not done
- [ ] Record PR link, passing CI link and release commit SHA

## Fixed regression matrix

| Failure class | Automation |
| --- | --- |
| Unsafe manifest file deletion, failed HTTP handles | `tests/test_audit_fixes_20261010.lua`, `tests/test_recovery_hardening.lua` |
| Report corruption, crashed rename and recovery | `tests/test_audit_fixes_20261010.lua` |
| Stream Range mismatch, lost events, orphan responses | `tests/test_audit_fixes_20261010.lua`, `tests/test_platform_stubs.lua` |
| Targeting, movement, bot prediction, AoE | `tests/test_audit_fixes_20261010.lua`, `tests/test_audit_regressions.lua`, `tests/test_v1.lua` |
| Headless vs live timing / side fairness | `tests/test_headless_runner.lua`, `tests/test_side_symmetry.lua`, `tests/test_refactor_parity.lua` |
| Registry completeness / fixed-test references | `tests/test_release_gate.lua` |

## Additional deep-audit regression gates (2026-10-10)

- `tests/test_preset_false_returns.lua`: fail closed on silent
  disk/rename/write/close failure; protect deck presets and backups.
- `tests/test_installer_false_returns.lua`: never replace project files
  when the prior cleanup or recovery marker write fails.
- `tests/test_report_logout_false.lua`: never claim GitHub credential
  removal unless the credential is actually gone.
- `tests/test_music_seek_failures.lua`: failed seeks must not play the
  wrong song offsets or spin on empty reads.
- `tests/test_core_invariant_stress.lua`: seeded live combat snapshots
  verify ID/owner/spatial/economy invariants. Always run both Lua 5.2 and 5.4.

These checks prevent regression in the *exercised scenarios* but do not
substitute for actual CC:Tweaked monitor, filesystem and speaker testing.
The full scope and residual caveats are in
`docs/DEEP_CORE_AUDIT_20261010.md`.

## Explicit limits

GitHub CI uses Linux and synthetic CC:Tweaked APIs. A successful run does not
measure ATM10 tick lag, physical monitor frame throughput, real speaker playback
or Minecraft network outages. These results must come from physical testing;
they must never be invented or claimed from CI.
