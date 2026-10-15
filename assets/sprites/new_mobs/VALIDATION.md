# Validation — 2026-10-15

Baseline: `6e85dc77553bd17422deeb9cb51258cefda06fe5` (`main`). Remote `main`
was rechecked before publishing. No open PR was found at initial inspection.
The feature lives on `assets/dual-platform-mobs-20261015`; no existing tracked
file was edited. The sole additional path outside this asset directory is the
asset-only GitHub Actions workflow.

| Check | Result |
| --- | --- |
| All existing `tests/test_*.lua` suites | PASS: 47 under Lua 5.2.4 and 47 under Lua 5.4.8; 94 successful process runs. [Per-suite evidence](evidence/regressions.json). |
| Existing 35-model roster | PASS: 556 real-renderer checks per Lua version. |
| Existing frame-diff/cache suite | PASS: 38 checks per version. |
| Previously integrated four-mob renderer/animation regressions | PASS on both; existing 25 approved unit frames and 15 effects preserved. |
| All Lua syntax, including isolated proposed assets | PASS: 109 files under both compilers. |
| Existing Python report-retention suite | PASS: 5 tests. |
| New native sprites + importable LÖVE metadata | PASS: 20,891 assertions per Lua version; 30 real-renderer cases each. |
| Native palette, rows and footprint | PASS: five non-empty frames; all 16 wide, heights 18/15/18/18/18; valid existing palette tokens only. |
| Terrain transparency | PASS: each dot leaves the exact pre-sprite canvas pixel untouched. |
| Native overlays/cache/state | PASS: cached/full-encode parity, stationary zero writes, white damage flash/recovery, HP/team/web overlay and recovery, movement round trip/removal; render leaves entity state and original registry intact. |
| LÖVE PNGs | PASS: 256×256 RGBA, 40 opaque colours each, binary alpha, transparent RGB zero, >10,000 visible pixels each, >=16 px margins, one connected silhouette per sprite. |
| Export provenance and authentic previews | PASS: exact regeneration from preserved design sources; each native PNG matches Lua rows; all composited sheets match actual PNGs and terminal captures. |
| Asset contracts | PASS: 133 Python checks, including metadata/hashes and additive-only Git scope. |
| Cross-Lua visual parity | PASS: zero decoded pixel differences in all five central 51×40 capture crops. Raw unused foreground bytes are not compared. |
| Critical encoded identity cues | PASS: Piglich red eyes, Raptor pale eye, Cyclops single dark pupil, Chimera red eyes, Behemoth cyan/light-blue visor remain in the expected regions after encoding. |
| No activation/gameplay changes | PASS: no edits to `src/`, `lib/`, card pool, configuration, installer, save/economy, simulation or bot files; new names/variants still resolve to the ordinary fallback before/after isolated preview injection. |
| Visual inspection | Performed on exported master roster, native roster, real monitor roster and comparison; owner's final art approval pending. |
| Physical CC:Tweaked/ATM10 monitor | **NOT TESTED — hardware unavailable.** |
| Running the future LÖVE game | **NOT TESTED — no LÖVE application is delivered; PNG/metadata contracts verified.** |

## Renderer, palette and performance conclusions

The current renderer paints palette-token strings on its native canvas, snaps
sprite origins to 2×3 cell boundaries, applies flash/team/HP overlays and caches
encoded terminal rows on weak-key monitor surfaces. PixelBox reduces every
2×3 cell to two colours. Existing normal sprites reach 15×17, and the current
suite allows up to 16×18; the separately integrated four-mob frames already use
16×18. No envelope change was needed. Only pixel placement and palette choices
were adjusted. No renderer or cache implementation changed.

The new modules are not imported during a normal match, so the feature adds no
match-time decode, raster, cache or memory work. A before/after renderer timing
comparison is not applicable to this additive inactive library. No hardware
throughput claim is made.

The existing unchanged diagnostic profile was also run under both interpreters:
[Lua 5.2 log](evidence/profile_lua52.txt), [Lua 5.4 log](evidence/profile_lua54.txt).
Its 30-unit/two-virtual-monitor static case emitted **zero additional blits**
for repeated unchanged frames. Deterministic control remained 9,174 ticks and
336 bot actions. Timings are host CPU microprofiles, not monitor refresh rates,
Minecraft network latency or Cobalt hardware measurements. Existing gameplay
suites were executed for regression only; no balance changes were proposed.

## Limits still requiring review

- Upstream references are pinned, but installed ATM10 mod/resource-pack versions
  are not available. The Raptor's interpreted small foreclaws are explicitly
  identified in the README; no claim of canonical anatomy is made for them.
- Native 16-colour approximations and two-colour terminal cells lose fine detail;
  physical monitor size, cell aspect and custom palettes still need field review.
- All ten deliverables are single idle poses; flat sources need more art for
  movement, attack, hurt and death. No animation/combat logic is included.
- The owner must approve the new designs visually before merge. This document
  records technical readiness, not production art sign-off.
