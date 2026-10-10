# Post-audit verification — actual ATM10 Mechanics upload, 2026-10-10

## Exact report/revision match

- User's uploaded file: `reports/latest/mechanics_report.txt`
- Uploaded by commit: `3010dfd7cca02a301ea915ac9318776ba981f570`
- Report `CODE_REVISION`:
  `28ef6cf29ecdb6e417fe0587ee9b731b2663e7c1`
- Audited code release:
  `28ef6cf29ecdb6e417fe0587ee9b731b2663e7c1`
- **24 PASS / 0 FAIL / 0 ERROR**, CraftOS 1.9,
  22 selectable cards, FORMAT_VERSION 21.
- Original merge CI passed:
  https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38072750988.

The source revision in the in-game report **exactly equals** the release
commit containing AF-012–AF-015. Uploading the mechanics report itself
created a *newer report-only Git commit*, which does not change installed
game code. Therefore comparing the report SHA to the latest main HEAD is
not a valid reason to reject its gameplay evidence.

## Directly evidenced by in-game report

The `evo_diamond_golem` scenario passed and measured:
- normal Iron Golem: **1514.7000 HP**
- evolved Diamond Golem: **1658.5965 HP** (`+9.5%`)
- stomp cadence: **2.0000 seconds actual walking**
- grounded hit: **25.0000 damage**
- flying hit: **0.0000 damage**
- stationary 2.3s hit period: **0.0000 stomp damage**, pulse timer unchanged
- quake visual effect flagged true

All 24 existing mechanics scenarios including side/tower target lock, bridge
range, Evo mechanics, Fangs/Vex, Charged Creeper, Tiebreaker and spawning
passed. `runtime_cpu_s=0.0000` is not an informative hardware performance
measurement; do not infer a zero-cost match or new throughput from it.

## Changes from deep-core audit PR #7: verification matrix

| Changed path | Verified evidence | Remaining scope |
| --- | --- | --- |
| `src/presets.lua` | `tests/test_preset_false_returns.lua` (original 15 fault assertions under Lua 5.2 and 5.4), `tests/test_recovery_hardening.lua` and existing platform/recovery stubs | This is **not** checked by `mechanics_test`; actual deck preset save/reboot required |
| `install.lua` | `tests/test_installer_false_returns.lua` passes under both Lua versions, old installer regression tests pass, and reported code revision matches deployed software | Real interruption mid-write still requires field/recovery test |
| `src/music.lua` | `tests/test_music_seek_failures.lua`, existing HTTP/Range platform stubs and full CI green | Actual speaker / music stream not verified by mechanics report |
| `src/report_sync.lua` | `tests/test_report_logout_false.lua` passes under both Lua versions; successful upload demonstrates working report-sync path | Token logout deletion not exercised by uploading reports |
| `tests/test_core_invariant_stress.lua` | 8 seeded game matches, 21,254 ticks, 1,250 samples, 244,969 assertions in both Lua 5.2 and 5.4 | In-game mechanics suite does not execute new standalone CI stress harness |
| Audit/docs/CI | Pull request and final main GitHub Actions succeeded, release gate includes new tests | No claim that synthetic tests certify physical hardware |

### Additional edge case found during this verification

**AF-016, preset recovery:** A conservative guard from AF-012 could
permanently reject fresh saves when only a **readable but invalid** orphan
backup remained, even though there was no valid deck to recover. Conversely
a valid orphan `.tmp` without `.bak` might be deleted by a new save.
The new regression **failed on the previously released code** in run
https://github.com/Chazammm/CC-Minecraft-Royale/actions/runs/38073192935.

The targeted follow-up distinguishes:
- Valid/unreadable recovery candidates: protect and require `presets.load()`
  to recover them first.
- Confirmed invalid *readable* orphan files: they may be replaced by a
  fresh valid preset, preventing save lock-out.

This fix changes no card balance, combat step, AI or graphics. It must pass
CI on the follow-up PR and must be published as a separate release; the
above in-game report predates it.

## On ATM10 after the follow-up release

1. Update using the documented pinned-commit installer.
2. Run `mechanics_test` and confirm all 24 pass at the **new revision**.
3. Save a named deck preset, reboot the computer, restore that preset.
4. Check both monitors and music playback during an actual match.
5. Optional: test interrupted update only in a safe test installation,
   not on the only copy of valuable saved decks.
