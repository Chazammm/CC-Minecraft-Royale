# Balance proposals — not implemented or simulated

All numbers below are proposals for later Phase 2 except the explicitly required
Ravager scaling and Hero Spider bonuses, which derive from current data.
Machine-readable values are in `BALANCE_PROPOSALS.json`. No new-unit gameplay
test or balance simulation has been executed; those require user authorization.

## Current references verified in code

| Existing unit | Cost | HP | Damage | Interval (s) | Range | Speed |
| --- | --- | --- | --- | --- | --- | --- |
| Zombie | 3 | 523 | 80 | 1.00 | 2.5 | 7.4 |
| Wither Skeleton | 3 | 470 | 88 | 1.00 | 2.5 | 7.4 |
| Iron Golem | 5 | 1514.7 | 110 | 1.50 | 3.0 | 4.2 |
| Diamond Golem | 5 | 1658.5965 | 110 + movement-only stomp | 1.50 | 3.0 | 4.2 |
| Blaze | 4 | 257 | 64 | 1.20 | 17 | 7.1 |
| Bat (three per card) | 2 | 45 each | 17 each | 0.85 | 2.2 | 10 |
| Skeleton | 3 | 168 | 30 | 1.10 | 15 | 7.5 |
| Spider | 2 | 250 | 38 | 0.80 | 2.2 | 10.5 |
| Ghast (portal summon) | — | 220 | 130 splash | 2.80 | 24 | 4.8 |

Ghast already uses `projectileSplashRadius=5.5` and hits air/ground through the
existing projectile engine. Blaze is flying but its fireball is single-target.
Iron/Diamond Golem target buildings; they do not fight back against a normal
ground unit merely because that unit attacks them.

## Concrete initial proposals

| Unit | Cost | HP | Damage | Interval (s) | Range | Speed |
| --- | --- | --- | --- | --- | --- | --- |
| Ravager Rider | 5 | 1300 shared | Ravager **220**, rider **20** | Ravager **3.0**, rider **2.0** | Building 3.0, rider 15 | 4.4 |
| Baby Ender Dragon | 5 | 600 | 70 splash | 1.8 | 14 | 5.2 |
| Minoshroom | 8 | 2100 | 300, single target | 2.4 | 2.5 | 3.6 |
| Hero Spider | **2** | **275** | **38.76** | **0.8 / 1.02 = 0.78431372549…** | **2.2** | **10.5** |

Ravager building DPS remains Iron Golem's nominal 73.333…: doubling both
damage and interval preserves sustained DPS but changes initial burst. The
separate rider adds at most 10 nominal unit DPS and anti-air coverage; lower
shared HP compensates some of that utility. The first building hit is immediate
once per entity lifetime, never a fresh initial bonus on every retarget.

Dragon trades Blaze's 53.333… nominal DPS/range/speed for 38.889 DPS, durability
and radius-4 splash. It can clear Bats in one successful splash, but has no
slow, healing, extreme burst or summon ability. Suggested projectile speed 38
lies between Ghast 32 and Blaze 46. It remains susceptible to ranged anti-air,
Blaze/Skeleton, Outpost and Towers; melee ground units cannot retaliate.

Minoshroom offers 125 nominal melee DPS and HP above both Golem versions, at
8 Emeralds and slow movement. The proposed 300 damage satisfies
`523 / 2 <= damage < 523`: a full-health normal Zombie retains **223 HP after
one hit** and dies to the second. Damage is an integer, well clear of either
boundary. Current `damageEntity` applies raw nonnegative damage with HP clamps;
the normal Zombie has no armor/resistance or other damage modifier. This
statement assumes no healing or other intervening damage, not every possible
future modifier. Pure arithmetic hit counts at 300 damage:

| Target | Hits to kill | Ideal time after immediate first hit |
| --- | --- | --- |
| Zombie / Wither Skeleton | 2 | 2.4s |
| Iron / Diamond Golem | 6 | 12.0s |
| Princess Tower (1501 HP) | 6 | 12.0s |
| King Tower (2565 HP) | 9 | 19.2s |

These are isolated hit-count calculations, **not duel simulations**. Movement,
Tower DPS, Golem building attacks/stomps, spells, kiting, cheap swarms and
support units alter real outcomes. No splash and no air targeting create clear
counterplay. Do not add a special Zombie-only damage rule.

Hero Spider uses exactly current cost/range/speed. +2% attack frequency means
divide interval by 1.02, not multiply by 0.98. Cycles=2 means two normal plays,
then the third successful eligible Spider play evolves, using the existing
cycle implementation. Suggested web acquisition range **12** and first-charge
delay **10s** are explicitly open balance proposals; the required repeat
cooldown is 10s. They are not silently established gameplay rules.

## Timestep and permanent-control risks

Current attacks clamp cooldown to zero and reset the full interval after a
hit. At dt=0.1, both 0.80 and 0.784314 become eight ticks: merely adding the
new numeric field does **not** realize +2% frequency. Phase 2 needs scoped
fractional progress/time carry, with a long-run actual-hit regression and
proof that existing units' approved cadence stays unchanged.

Hero Web is powerful permanent control on a cheap Evolution. Attack frequency
0.25 means an interval multiplier **4**, not a duration of 0.25 or a 75% damage
reduction. A webbed normal Zombie would nominally move at 1.85 and attack every
4s, retaining 80 hit damage. A webbed Minoshroom would nominally move at 0.9
and attack every 9.6s. Other modifiers need an explicit composition contract.
Counters are source targeting/removal before a shot, spreading threats, air
units, cheap expendable ground targets and avoiding unopposed long-lived Hero
Spiders. No cleanse/immunity rule is invented for Phase 1.

## Emerald economy

Verified match rules: cap 10, start 5, base `1 / 2.8` Emerald/s. Normal time
150s, overtime 150s at 2×, final 30s at 3×. From zero, a 5E card needs 14/7/4.667s
at 1×/2×/3×; an 8E card needs 22.4/11.2/7.467s. At match start, Minoshroom
requires saving another 3E (8.4s at base rate), while either 5E card can be
played immediately. Villager's existing boost and cap waste still apply.
Triple Emerald increases heavy/support combinations and the number of
simultaneous web sources, so paired normal/overtime/late-game simulations are
required later. No present card, economy, Evo or bot parameter is changed.
