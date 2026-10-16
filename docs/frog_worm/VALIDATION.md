# Validation and performance — 2026-10-16

Baseline: `6e85dc77553bd17422deeb9cb51258cefda06fe5`. Host runtimes Lua5.2.4 /5.4.8, Python3.12.14, Pillow12.3.0.

| Evidence | Result |
|---|---|
| Complete Lua suite | **50 suites ×2 runtimes =100 passed**,0 failed; [per-run results](regressions.json) |
| New mechanics | **41 actual-engine cases per runtime**, with both owners and multiple supported `dt` values inside timing/pull/cadence cases |
| New live rendering | **25,267 assertions per runtime**;54 pose/view/size cases plus a real gameplay state |
| Full new-card match parity | **262 checks per runtime**; two owner-side live drivers, equivalent headless runs and deterministic replays |
| Syntax | All114 Lua files parsed under both runtimes, including the future LÖVE metadata |
| Existing Python suite |5 tests passed |
| Asset authenticity | Fresh cross-Lua captures match committed data; exact PNG compositions, master alpha/margins/palettes/hashes and native module hash pass |
| Whitespace / packaging | `git diff --check` clean; installed-module dependency scan passes |

## Functional coverage

Frog: zero-damage hook → melee, exact destination/range, all heavy unit sizes, stationary Bank lifetime/income preserved, buildings/air/water/allies excluded, walkability sweep, immediate spatial indexing without a rebuild oracle, dead/out-of-range cancellation, independent attack progress and same-tick multi-Frog victim guard.

Worm:3E transaction and invalid-cast rejection; both arena halves and behind-tower positions; bridge versus river/border/finite coordinates; nonentity warning; no bite before2s; targetable and killable emergence; all relevant unit/building/tower classes and actual damage telemetry; once-only / expired opener; full Bank assassination through delayed deployment and removal of its income source; economy target priority and retained locks; bounded visible correction, last-instant cancellation, refund cap / accounting / hand-cycle preservation; staggered pending-list compaction and no duplicate spawn; result/rematch/lobby/dev-clear cleanup.

Bots: legal enemy-half economy candidates, actual card plays, owner-mirrored positions under full tower coverage, no ground-only Worm response to an urgent flying threat. Existing bot difficulty/default-deck behavior remains covered by unchanged regression suites. New card schema guards reject invalid mechanic fields, flying burrow payloads and injected transient state.

Real renderer: nine registered rasters (four Frog, four Worm, one ground warning), palette/footprints, exact pixels over terrain, both viewers,45×42 /51×40 /57×62 monitors, stationary cache, forced full-encode equality, same-entity pose changes and restoration, damage/HP/team/web overlays, removal without ghosts, warning without fake entity/HP, target-linked actual hook scene and unchanged authoritative snapshots. No private sprite-slot injection is used for the new runtime capture.

## Seeded new-card matches

Both runtimes produce the same recorded trajectory for each scenario. The selected deck includes Frog/Worm/Villager plus five existing cards; the opponent includes Minoshroom, Villager and air/ground defenders. Each selected side plays Frog11 times and Worm12 times and records actual damage for each. Seeds20261017 /20261018 exercise the selected deck asP1 /P2 respectively. Both matches reach result after3058 ticks, with the opposing deck winning (winner2 /winner1). The live and headless states, pending deployments, bot actions and replay snapshots agree; updates after result do not resume combat.

These two scenarios prove implementation/parity, **not balanced win rates**, favorable matchups or optimal bot play. No card values were retuned to make these scenarios win.

## Before / after renderer and simulation control

[Raw host profile](performance.json) runs the existing unmodified `tests/performance_profile.lua` on baseline and this implementation with the same explicit legacy decks/scenes.

| Runtime / synthetic frame case | Before CPU ms | After CPU ms |
|---|---:|---:|
| Lua5.2,30 static units,2 monitors, per frame pair |4.8454|2.8546|
| Lua5.2,30 static units,1 cached monitor |2.3433|1.3033|
| Lua5.2,30 units with movement,1 cached monitor |3.0007|1.6382|
| Lua5.4,30 static units,2 monitors, per frame pair |2.2968|2.0717|
| Lua5.4,30 static units,1 cached monitor |0.9420|0.9527|
| Lua5.4,30 units with movement,1 cached monitor |1.1931|1.2324|

These are single diagnostic host runs, sensitive to load, CPU frequency and GC; **do not interpret the faster samples as an optimization claim** or the table as physical CC throughput. The implementation adds custom dispatch and small render passes; it does not change canvas dimensions, old sprites, palette or the frame-identity contract. Both revisions retain zero redundant `blit` calls for unchanged frames.

All four profile runs preserve the reviewed legacy control exactly: **9174 aggregate ticks and336 bot actions** across the three fixed matches, on both Lua versions. This is stronger behavior evidence than comparing timing alone, but still covers a controlled set of decks, not all possible games. Existing four-mob approved-frame and original35-sprite regressions pass unchanged.

## Limits

No physical Minecraft server/CC:Tweaked monitor or running LÖVE/GPU instance was available. Raster captures are real pipeline output on a virtual monitor; they do not measure peripheral latency or prove physical aspect/contrast. Only static LÖVE masters are provided. Native movement/ability poses use the existing dispatcher, hurt flash and generic death effects; full LÖVE animation sets remain future work.

The dedicated `King Frog and Nether Worm` workflow runs every Lua regression on both versions and checks newly captured previews against the committed files. Existing project CI also runs its usual mechanics, installer, rendering, replay and profiling gates. No merge or deployment is performed by these checks.
