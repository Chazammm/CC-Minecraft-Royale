# Phase 2 implementation plan — requires explicit approval

Nothing in this plan has been implemented. Existing Game/Card/Renderer files
and their values stay unchanged in Phase 1. Proposed behavior is NOT TESTED.

## Verified architecture and minimal future changes

`src/game.lua` owns entity lifecycle, movement, target locks, one ordinary
attack cooldown, projectiles, timed movement slows, aura composition and match
transitions. `src/cards.lua` owns cards, cloned Evolution payloads and cycles.
`src/arena.lua` owns Ground/Flying/Water navigation and placement.
`src/pixel_arena.lua` owns 35 inline static sprites, private palettes, projection,
2×3 snapping, HP bars, procedural projectiles/effects and encoding/caches.
`lib/pixelbox_lite.lua` is the common encoder. `src/render.lua` is the screen UI.
Bot observations/scoring are in `src/bot.lua`; headless matches reuse Game and
Bot through `src/headless_match.lua`. Installer runtime files are explicitly
listed; this Phase-1 directory is currently absent.

Future work adds three cards to cards.list and one Evolution to existing Spider,
with schema validation and descriptions. It must not change the 8-card deck,
boot-empty selection, current Evo cycle semantics, disabled-Evo behavior or
Dev-only Guardian content. Generic catalog-dependent labels must use their
actual new count instead of retaining a hardcoded 22-card headline.

Only the four new sprite sets need frame selection. Keep existing sprites and
the unmodified encoder path as defaults. Use movement/attack presentation
state to select prepared frames, cache loaded tables once, and load no PNGs
or JSON in the live loop. New projectile/effect visual IDs need explicit
dispatch; unknown IDs currently fall back to a white pixel/generic explosion.
Do not mistake successfully encoded isolated rasters for completed dispatch.
Re-run both monitor perspectives, phase/cache recovery and minimum layouts.

## Ravager Rider: independent weapons, one entity

Keep one owner/id/HP/position/spatial entry and the existing building-only
primary movement/target lock. Add a scoped secondary unit-only ranged channel
with its own lock and cooldown. Existing Piglin hybridAttack switches melee
versus ranged on ONE target/cooldown; it is not a two-weapon implementation.
Do not create two Game entities or let the rider steer the Ravager.

The rider targets legal enemy units, Ground and Flying, never buildings/towers.
It can fire while moving or during a primary building attack. Both channels
use normal engine damage/projectiles and the same sourceCardId for telemetry.
Validate/release each lock independently when its target dies/becomes invalid;
new spawns do not steal valid locks. Preserve deterministic ID/owner tie rules.

Primary values derive from current Iron Golem: damage 220, interval 3s. Secondary
values are required 20 / 2s; range 15 and shared HP 1300 are proposals. A
lifetime-scoped `initialBuildingImpactUsed` flag is set atomically with the
first valid building hit after reaching melee range. Spawn starts it false;
retargeting never resets it. After the immediate hit, arm the ordinary primary
cooldown. The current ordinary cooldown already starts at zero, so initial
impact is one first hit, **not an extra hit plus the normal ready attack**.
After a terminal match transition, stop both channels just like other combat.

Tests: same-tick dual attacks; own cooldowns; moving ranged attacks; main
building attack plus rider fire; Ground/Air rider filters; building-only main;
no duplicate first hit over several dt/boundary/retarget events; target death;
bridges, mirrored sides, shared HP/death/spatial cleanup and result freeze.

## Baby Ender Dragon: existing flying/splash engine

Use existing flying=true, canAttackAir=true and normal target locks. Existing
spawnProjectile already snapshots source, speed, visual, splashRadius/effect
and last known target position. Existing updateProjectiles handles enemy
Ground/Air splash and primary-target death. Reuse those rules; add only the
new visual dispatch/asset selection. No new random damage, special physics,
water shortcut exception or second simulation engine is necessary.

Tests: direct water flight on both sides; legal deployment; Ground/Air
acquisition; radius inside/exactly outside boundaries; duplicate-hit prevention;
dead primary splash at last position; tower damage; projectile cleanup; no
post-win splash damage; visible fireball/explosion across both cameras.

## Minoshroom: ordinary ground melee

Use targetMode=any, flying=false, canAttackAir=false, damage=300 and ordinary
single-target melee. Do not implement an AoE just because an impact graphic is
visible. Keep all damage on damageEntity, without Zombie-specific branching.
Current normal Zombie HP=523 and no armor justify two hits arithmetically; a
future actual combat regression must measure HP=223 after one successful hit
and death after the second with no other damage/healing. Test current Golem
HP, Diamond HP and towers through shared damage and lifecycle paths.

Tests: two exact real Zombie hits; no Flying attacks; high-HP heavy matchup
fixtures; target locks; bridge movement; slow cadence; single-target damage;
both owners; no collision/placement change from the larger visual footprint.

## Hero Spider: existing cycles, new permanent modifier

Reuse cards.evolvedCopy and current Game cycle tracking: cycles=2 gives the
third successful eligible Spider play, with progress reset after Evo. Proposal
stats are HP=275, damage=38.76, interval=0.8/1.02, range=2.2, speed=10.5,
cost=2. Never copy a separate cycle system into Bot or simulation.

The current movement slow list contains paired factor/remaining records and
selects the strongest active timed slow; global aura then multiplies separately.
There is no general attack-frequency modifier or permanent slow implementation.
**Do not set duration=math.huge**: that would pollute lifetime/utility statistics
and does not implement attack slow. Do not overwrite base moveSpeed,
attackCooldown or card templates permanently.

Suggested scoped status: one entity-owned heroWeb flag/record, with original
source owner/card attribution and finite factors 0.25. It stays on the target
when the source dies; normal entity removal/reset discards it. Spawn construction
initializes status anew; no global map keyed by recycled IDs carries it across
matches. Do not append a second instance when several Hero Spiders are alive.

Movement proposal: fold web factor into the existing strongest-local-slow
selection (`min(timedSlowFactor, 0.25)`), then preserve the global aura multiplier.
Attack proposal: separate frequency factor 0.25, equivalent to base interval×4;
compose future buffs/debuffs by source without destructive base edits. Verify
combinations explicitly. Use scoped fractional attack progress/time carry so
the +2% Evo frequency is observable at dt=0.1 without silently changing every
existing unit's approved interval rounding. Preserve progress coherently when
a modifier is applied rather than discarding or multiplying remaining time
twice. Long-run actual-hit counts are necessary.

Web acquisition selects only alive enemy **land Ground units**, not Flying,
water-only Dev units, buildings or either tower type. It excludes affected or
reserved targets and uses deterministic distance/ID ties. Range=12 and first
charge=10s are proposed choices requiring approval with the balance table.
After charging, no valid target means remain ready: no spent cooldown/projectile.
Ordinary melee has a separate timer and keeps operating.

For projectile-based application, reserve the target atomically by projectile
ID before emission; permit one pending web per source. Revalidate at impact,
apply one permanent record and clear the reservation. The 10s cooldown starts
at the validated launch, not ten seconds after impact; it continues while the
projectile travels. Failed/dead/invalid targets release the reservation and
refund the matching pending shot if its source still exists, never another
source's reservation. Apply exactly once even when impact
and retarget occur in the same tick. This transactional policy needs explicit
timing tests; offline GIF timing is not a gameplay specification.

Tests: cycle 2 and rematch reset; all stat multipliers/costs; long-run +2%
frequency; independent web/melee timers; 10s spacing; no-target readiness;
all invalid target classes; two sources competing for one target; in-flight
invalidity; source death; target death/removal/recycled IDs; permanence; no
stacking; temporary slow/aura/buff interactions; finite utility statistics;
disabled Evo; Dev spawn; Bot selection and mirrored targeting.

## Cross-system verification after approval

Update Bot DPS scoring to count both Ravager channels rather than selecting
the max as current hybridAttack does. Add bounded estimates for splash and
permanent web utility from publicly observable state; do not read opponent
hands or hidden pending choices. The same authoritative modifier helpers must
drive live combat, Bot forecasting, Runner and tests. Diagnostics gain relevant
finite/invariant checks; visual-only frame state stays separate from decisions.

Run all existing Lua 5.2/5.4/installer/renderer regressions, expanded mechanics,
live/headless state parity, side symmetry, multi-match reset and paired seeded
100/500/1000-match trials. Compare exact damage, attack clocks, Ground/Air
restrictions, economy, target locks, web reservations, lifecycle, memory and
result validity. Controlled replacement/Evo comparisons need enough contexts
and honest confidence intervals; no automatic balancing from win-rate flags.

**PHASE 2: NOT STARTED — WAITING FOR EXPLICIT USER APPROVAL.**
