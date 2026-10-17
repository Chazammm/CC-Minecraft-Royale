# Balance research — proposals only

Source: current `main` revision `e80ad6919b7eb21a1d3464290d177ee3ab210eee`. All existing stats are read from the Lua capture. No proposed card exists in the live registry.

## Proposed starting values

| Card | E | HP | Damage | Interval | Raw DPS | Speed | Reach |
|---|---:|---:|---:|---:|---:|---:|---:|
| Breeze | 3 | 320 | 32 | 1.40s | 22.86 | 6.6 | 15 |
| Adventure Sheep | 4 | 620 | 82 | 1.10s | 74.55 | 7.4 | 2.5 |
| Phantom | 4 | 280 | 76 | 1.30s | 58.46 | 10 | 2.2 |

Phantom building/tower damage: 38 per hit, 29.23 raw DPS. Breeze knockback only on every third shot (nominal 4.2s between empowered shots); no damage bonus. Sheep has no passive. All costs and values are unapproved starting proposals.

## Existing melee comparison

| Card | E | HP | Damage | Interval | Raw DPS | Speed | Target rule |
|---|---:|---:|---:|---:|---:|---:|---|
| zombie | 3 | 523.00 | 80 | 1.00s | 80.00 | 7.4 | any |
| wither_skeleton | 3 | 470.00 | 88 | 1.00s | 88.00 | 7.4 | any |
| wolf | 3 | 330.00 | 62 | 0.72s | 86.11 | 10.2 | any |
| spider | 2 | 250.00 | 38 | 0.80s | 47.50 | 10.5 | any |
| enderman | 5 | 620.00 | 95 | 1.10s | 86.36 | 7 | any |
| iron_golem | 5 | 1514.70 | 110 | 1.50s | 73.33 | 4.2 | buildings |
| diamond_golem | 5 | 1658.60 | 110 | 1.50s | 73.33 | 4.2 | buildings |

Iron/Diamond Golems target buildings; they do not normally accept an isolated Sheep duel. Diamond Golem also has a 25-damage moving ground pulse every 2s, omitted from raw weapon DPS. No forced Golem-vs-Sheep match is claimed.

## Adventure Sheep: modeled 1v1 results

**These are fixed-position arithmetic duel forecasts, not production-engine matches or win rates.** Both fighters begin in mutual range, attack at time zero, then at their exact intervals. The nominal tie rule applies both simultaneous hits, even if lethal.

| Opponent | Sheep hits needed | Opponent hits needed | Nominal finish | Sheep HP left | Phase cases |
|---|---:|---:|---:|---:|---|
| zombie | 7 | 8 | 6.60s | 60 | 18/18 Sheep wins in this bounded model |
| wither_skeleton | 6 | 8 | 5.50s | 92 | 18/18 Sheep wins in this bounded model |

The 18 cases per opponent vary Sheep first-hit delay (0/0.10/0.30s), enemy delay (0/0.10s), and simultaneous/Sheep-first/opponent-first handling. They are deterministic parameter cases, **not 18 random matches**. The retained JSON contains every hit trace and all 54 stat-sensitivity cases.

Against Zombie, the nominal 60-HP margin is deliberately narrow. The 4E Sheep has 18.55% more HP than Zombie but lower DPS (74.55 versus 80); Wither Skeleton has higher DPS (88), lower cost, and 88 versus 82 damage per hit. Sheep therefore does not dominate either unit on cost or damage output. A large first-hit disadvantage, kiting or supporting fire can overturn the modeled win.

At 4E, Sheep supplies 155.00 HP/E and 18.64 DPS/E. Zombie supplies 174.33 HP/E and 26.67 DPS/E; Wither Skeleton supplies 156.67 HP/E and 29.33 DPS/E. The conservative 4E proposal is therefore not justified by per-Emerald efficiency alone. A future playtest must prove that its single-body durability is useful.

One concrete burst breakpoint: the current 3E Falling Anvil deals 549 troop damage, leaving Sheep at 71 HP while killing a full normal Zombie or Wither Skeleton. Two unmodified 300-damage Minoshroom hits leave Sheep at 20 HP. These are arithmetic breakpoints, not modeled wins against Minoshroom or guaranteed spell trades.

The optional helmet block is not recommended: it adds a timer/state and would conceal whether ordinary stats already meet the duel goal. Retain it only as an alternative to evaluate if real future engine duels fail; do not add it on top of a successful stat line.

## Matchup interpretation

- Groups: single-target attacks cannot clear Bat Swarm or cheap ground swarms efficiently; no sword-arc area damage.
- Ranged: normal movement and no dash allow Skeleton/Snow Golem kiting and focused fire. Use an ally or terrain to close distance.
- Flying: Sheep cannot hit air; Blaze and Baby Ender Dragon are direct threats. An air ally is still required.
- Buildings/towers: normal damage without a bonus, normal half-side deployment rules, and lower DPS than Wither Skeleton. Golems remain much harder to remove.
- Enderman: also 620 HP but 95 damage/1.10s and teleport at 5E. Sheep pays less by giving up teleport and DPS.
- King Frog: 3E/550 HP/40 per 1.4s plus positional pull. Sheep is a 4E direct fighter, not a replacement controller.
- Nether Worm: 3E/350 HP with ambush placement and conditional opener. Sheep has neither deployment surprise nor burst.

## Later validation required

After explicit implementation approval: real engine duels with approach distances, both owners/entity orders, projectile travel, towers, movement modifiers and the final first-hit windup; mixed decks, bot classification and full matches. No proposed-card headless or bot simulation is possible without adding the cards, which this package intentionally does not do.
