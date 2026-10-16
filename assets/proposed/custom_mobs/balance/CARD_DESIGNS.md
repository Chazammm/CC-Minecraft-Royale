# Four proposed cards — no active registration

All numbers below are **initial hypotheses**, not measured balance. HP/damage use engine units, speed is arena units/s, range is arena units, intervals are seconds. Each card deploys one grounded unit; none attacks flying enemies. `proposals.json` is documentation data, not a `src.cards` extension. The reproducible `current_cards.json` snapshot contains all **25** current base cards. Evolutions and spawned subunits are not additional base cards.

| Card | Emeralds | HP | Hit damage | Interval | Raw DPS* | Speed | Range | Aggro |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Netherite Crab | 5 | 1200 | 90 | 1.30 | 69.23 | 3.8 | 3 | 27 |
| King Frog | 4 | 520 | 40 | 1.40 | 28.57 | 5.0 | 12 | 27 |
| Nether Worm | 4 | 380 | 95 | 1.20 | 79.17 | 9.0 | 2.5 | 14 |
| Ore Centipede | 6 | 1650 | 105 | 1.60 | 65.63 | 3.5 | 3 | 27 |

*Damage / interval, excluding guard/channel downtime, first-hit bonuses, travel, retargeting and tower reduction. Ordinary attacks accept ground units, buildings and towers. No flying/water-only targets in the proposed v1: reuse existing ground-reach restrictions; no swimming. Troop combat is preferred before the existing lane-tower fallback. These are not win-rate predictions.

## Netherite Crab — armored melee frontline

**Identity:** low, wide blue-jointed crab with two differently sized armored pincers. Charcoal/brown-violet metal, narrow purple glints and warm claw interiors distinguish netherite from gray rock. The Mob Vote animal was a concept with one enormous claw; our two armored claws are explicitly an original adaptation, not a claim about released vanilla content.

**Chosen ability: Claw Guard.** When at or below 80% HP, an attackable ground enemy is within 6 units, and the 5-second cooldown is ready, show a 0.30-second unprotected pincer windup. Then reduce hostile incoming damage by **35% for 0.80 seconds**, while movement and attacks pause. Cooldown starts when windup begins; no stacking or timer extension. The first guard cannot trigger until 5 seconds after spawn. If the provoking enemy disappears during windup, cancel the guard and spend its cooldown. Damage during guard does not restart it. All hostile hit sources, including spells/reflection, use the same multiplier; no facing checks. Environmental lifetime/tiebreaker effects are not hostile combat hits and bypass this modifier. Counterplay does not depend on guessing a hidden frontal angle.

**Why distinct:** Iron Golem currently costs 5, has 1514.7 HP, 110 damage / 1.5s, speed 4.2 and exclusively seeks buildings. Crab has less raw HP and attacks ground troops. Its visible defensive pause trades offense and movement for a short mitigation window. A hypothetical permanently guarded crab would have 1846.15 damage-equivalent HP, but this is only an unattainable upper bound: the timed stance is not permanent armor.

**Useful against / weaknesses:** can hold a narrow grounded push and absorb a telegraphed heavy hit if timing aligns. Vulnerable to Bat Swarm and Baby Ender Dragon because it cannot retaliate, ranged kiting by Skeleton/Snow Golem, and multi-unit pressure: it has one-target attacks, no splash, reflect or knockback. Minoshroom's 300 hit is reduced to 195 only inside guard and still hits hard. Flanking has no special damage rule in v1; directional armor was rejected because facing and projectile impact orientation are absent from the current combat contract.

**VFX / bot risk:** pincer crossing is the authoritative readable cue; a brief violet plate edge is cosmetic. A bot that assumes Golem-style building focus would misuse it. The bot should value threatened friendly ground troops, guard readiness and lost attack time, not armor color.

## King Frog — grounded displacement support

**Identity:** an enlarged orange vanilla-style, four-legged frog, cream throat, raised eyes, compact gold crown and a short purple back mantle. There are no hands, upright torso or human weapon. The mantle must leave the rear legs visible.

**Chosen ability: Royal Tongue.** The regular attack is a 40-damage tongue lash with a 0.25-second windup inside its 1.4-second cadence. Every **4.2 seconds**, the next successful lash can additionally pull a light grounded troop **up to 4 units toward the frog**, stopping at 3 units distance. Pull has no separate damage, stun, attack reset or slow. First pull is ready on spawn; cooldown is consumed only by a successful eligible hit, not by swinging at a tower. If target dies, leaves range or becomes illegal during windup, the attack misses; no homing tongue across the arena.

Initial explicit pull whitelist: `zombie`, `skeleton`, `wither_skeleton`, `wolf`, `witch`, `evoker`, `snow_golem`, plus `piglin` when it is the actual spawned troop template. Resolve template identity independently of cosmetic/evolution name. All unlisted templates, flying/water units, buildings, towers, Minoshroom, Ravager Rider and Golems are immovable. Do not infer mass from current HP. This whitelist itself needs gameplay review, especially Witch/Evoker.

**Alternatives evaluated:** an attack/regen aura overlaps existing support roles, adds buff stacking and permanent-cluster incentives; rejected for v1. Combat jumps add river traversal/targetability rules; rejected. Pulling flying troops needs a separate height contract; rejected. Hops in future locomotion frames are cosmetic and do not cross illegal terrain or grant invulnerability.

**Useful against / weaknesses:** can disrupt a Wolf or draw a ground ranged support toward friendly melee troops; poor direct DPS. Compared with Snow Golem (3 emeralds, 250 HP, 26 / 1.05s, range 18, attacks air, slows to 80% for 1s), Frog pays more for HP and occasional displacement while losing air coverage and range. It spawns no minions and has no potion splash, unlike Witch. Skeleton and Witch can outrange it; swarms overwhelm its single lash; Minoshroom and Golem cannot be pulled. Air is a direct counter. Pull is not body blocking or an aggro reset.

**VFX / bot risk:** a straight tongue line must connect the real target and retract; a tiny crown nod marks a successful pull. Bots need to evaluate the post-pull location: pulling a dangerous unit toward one's own tower can be harmful. Repeated frogs must not fling a target through terrain or indefinitely stun it.

## Nether Worm — arena-wide ambush assassin

**Identity:** no legs; a compact S-shaped body of dark red/brown/black Nether plates, lava seams, a pointed tail and a large ivory-toothed maw. Contrast this rising silhouette with the long, low, many-legged Centipede. Sparks are separate future effects, not baked into the master.

**Chosen ability: Burrow Ambush.** Cast on valid walkable ground **anywhere in either half**, including behind enemy Princess and King towers. Show a fixed, owner-colored ground warning for **1.4 seconds**, create an **already targetable** emerging unit for **0.6 seconds**, then allow normal attacks and movement. There is no permanent underground entity and no repeat burrow. The first successful hit against a non-structure troop within 2 seconds of becoming active gains **+85 damage, once** (180 total); it does not add a second hit. The window expires if no eligible troop is hit. Hits against buildings/towers receive **0.35× base damage = 33.25**, never the opener bonus. The multiplier applies to *both* structures and towers so a Cannon cannot become a full-damage backdoor target.

**Support-focused rather than tower miner:** 180 can defeat the current 168-HP Skeleton if it is still in reach after warning. It cannot one-shot Witch (500 HP), Snow Golem (250), Wolf (330) or a tower. Pure structure DPS is 27.71 before travel and interruption. Cost/HP compare with Wolf (3 emeralds, 330 HP, 62 / 0.72s, speed 10.2): Worm pays more for deployment access, has a warning delay, lower speed and a severe structure penalty. An unassisted empty backfield cast should not be an efficient tower plan.

**Counterplay:** reposition the support before emergence; deploy a grounded defender beside the warning; use tower coverage, Wolves/Wither Skeleton or aerial damage. A Princess tower deals 80 per hit / 0.95s, King 105 / 0.9s; both may target the emerging worm immediately if eligible. Exact lock timing remains an integration test, not a guaranteed first-shot time. Arrow Volley deals 185, leaving 195 HP from a full-health worm. Falling Anvil deals 549 and can kill it if it stays in the radius, but its **2.7s delay is longer than the worm's 2.0s warning-plus-emergence**: a reactive anvil is not promised to prevent the first bite. The worm does not erase existing tower target locks or force all towers to switch to it.

**VFX / bot risk:** localized ash ring, contracting orange seams, then a rising head. Never an invisible damaging warning. Existing bots clamp ordinary troop casts to their own half; adding only a placement field would not teach them offensive ambushes. Shared validation and enemy-half candidate scoring are required later. See the explicit [state machine and validity rules](../documentation/TECHNICAL_DESIGN.md).

## Ore Centipede — finite sustain tank

**Identity:** low horizontal body with a massive head plate, two ivory mandibles, repeated iron/slate segments, copper joints and many pointed feet. Three visible ore caches: front gold/copper, middle diamond/lapis, rear redstone/emerald. Coal and iron are structural inclusions. These are **three reserves**, not eight separate resource types.

**Chosen ability: Consume Ore.** Start with **3 charges**. When HP ≤70%, missing HP ≥120, not already channeling and cooldown ready, stop attacks/movement and visibly eat one cache over **1.0s**. On successful completion heal **120 HP**, capped at maximum, and consume exactly one charge. The cache empties rear → middle → front. No max-HP increase, armor stat loss, income or ore pickup. All ore types heal identically. Thus the maximum extra healing budget is **360**, giving 2010 cumulative HP only if all three heals actually succeed; maximum displayed HP remains 1650.

Any positive actual hostile damage during the channel cancels it. A failed channel gives no heal and consumes no charge. A **6s cooldown starts on every channel attempt**, including interrupted attempts; therefore damage cannot create a rapid animation/retry loop. Completion after lethal damage is prohibited. If damage and completion occur at the same simulation timestamp, damage/death resolves first. Overheal from any future external heal is capped; zero effective healing must not consume a charge. No resurrection or death-trigger recharge. At most three successful channels per life.

**Useful against / weaknesses:** a single-target tank that can survive pauses between engagements; better recovery than a plain damage sponge, with resources visible to the opponent. Compare Iron Golem's 1514.7 HP / 73.33 DPS / building focus and Minoshroom's 2100 HP / 125 DPS / cost 8. Centipede costs 6, is slow (3.5 vs Mino 3.6) and hits for 65.63 raw DPS before feeding downtime. It cannot heal under uninterrupted damage. Bat Swarm, Baby Ender Dragon, Blaze and sustained ranged fire can deny channels; Minoshroom punishes a stationary feeding unit. No blanket claim that it wins a tank duel has been tested.

**VFX / bot risk:** one selected cache pulses, crumbs travel toward mandibles, then only that cache disappears on success. Cancellation retains the cache. A bot must score missing HP, remaining charges and incoming damage; evaluating only HP would overvalue an empty or constantly interrupted centipede. There is no dependency on mineable arena ore.

## Future balance acceptance before activation

Use deterministic seeded scenarios for single-card trades, support protection, behind-tower worm drops, aerial counters, multiple simultaneous frogs, cancelled feeds and late-game emerald rates. Compare against current decks, both owners, mirrored arena positions and `dt=0.05/0.10/0.25`. Count tower damage, realized healing, guard uptime, ambush success and opportunity cost. Add bot matchups only after bots use the same new-placement validator. Do not publish proposed DPS arithmetic as simulation evidence. No such new-mechanic match simulations were run in this asset PR.
