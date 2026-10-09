# CC-Minecraft Royale

A Clash-Royale-inspired 1v1 arena game for CC:Tweaked / ATM10, designed for two synchronized Advanced Monitor walls.

## Current hardware target

- 1 Advanced Computer
- 2 separate **3x4 Advanced Monitor** walls
- Recommended text scale: **0.5**
- Wired Modems / networking so both monitors are visible to the same computer
- 2 Speakers recommended: one for SFX and one for streamed battle music
- One-speaker setups still work, but music and SFX share the device

If exactly two monitors are visible they are assigned in sorted peripheral-name order. If more than two are visible, set the exact names in `config.lua`.

## Match rules

- 8-card deck / 4-card hand / cycling queue
- Maximum 10 Emeralds
- Base generation: 1 Emerald every 2.8 seconds
- **2:30 regulation**
- **2:30 overtime** on an equal side-tower score
- Overtime uses **2x Emerald generation**, increasing to **3x for the final 30 seconds**
- Overtime is sudden death: the next destroyed side tower wins
- Destroying the King Tower always wins immediately
- If overtime expires without a winner, a visible **Tiebreaker** starts
- During Tiebreaker, cards are locked and all surviving towers lose equal raw HP until the first tower falls
- Exact equal lowest tower HP can still end in a true draw

Each monitor shows its own side at the bottom through a mirrored 180-degree view.

## Arena / combat

- Two lanes, river and two bridges
- Ground units route through bridges
- Flying units cross the river directly
- Troops and buildings can normally be deployed only on the player's half
- Global spells can target anywhere
- Units use lane-aware Crown Tower objectives plus aggro, retargeting and distraction logic
- A troop attacks its lane's Princess Tower first; after that tower falls it advances toward the King Tower instead of crossing to the opposite Princess Tower
- Destroying a Princess Tower unlocks a limited deployment pocket in that lane on the enemy side
- Crown Towers can attack both enemy units and enemy buildings in range
- Princess Towers use 42.5 range, beginning fire roughly two arena units after a troop leaves its bridge; King Tower range remains 27
- Defensive buildings can pull building-targeting troops such as Iron Golem before they commit an attack
- Units lock onto a target after their first attack; newly spawned troops/buildings cannot pull them away until that target dies
- Buildings lose HP continuously over time instead of staying full and disappearing instantly; natural decay currently runs at 1.15x
- Skeleton can kite; Snow Golem intentionally does not
- Projectiles, slows, summons, teleports, explosions and delayed spells are supported

## Current selectable cards

There are currently **22 selectable cards**:

1. Zombie
2. Skeleton
3. Iron Golem
4. Bat Swarm
5. Cannon
6. Arrow Volley
7. Creeper
8. Slime
9. Blaze
10. Witch
11. Evoker
12. Enderman
13. Spider
14. Snow Golem
15. Villager
16. Endermite
17. Wolf
18. Falling Anvil
19. Nether Portal
20. Wither Skeleton
21. Magma Cube
22. Pillager Outpost

**Guardian is currently benched as a DEV-ONLY card.** Guardian and Elder Guardian remain implemented and directly spawnable in the admin sandbox, but neither appears in normal card selection, random decks, bot/simulation card pools or the normal Evolution Slot.

Nether Portal summons the internal-only Piglin unit; Piglin is not directly selectable. Magma Cube splits into the internal-only Mini Magma Cube. Evoker summons the internal-only Vex unit.

## Important special mechanics

- **Falling Anvil**: delayed 2.7-second AoE, can hit multiple ground and flying targets
- **Nether Portal**: periodic Piglin spawner
- **Piglin**: crossbow only versus flying targets, axe versus grounded targets
- **Wither Skeleton**: Zombie sidegrade with lower HP and higher melee damage
- **Magma Cube**: Slime sidegrade with 5% less HP and 5% more damage before and after splitting
- **Pillager Outpost**: Cannon sidegrade that attacks air and ground with 25% lower HP and damage
- **Creeper**: proximity fuse; being killed before the fuse completes does not trigger the explosion
- **Slime**: splits into two Mini Slimes on death
- **Witch**: periodically summons Baby Zombies
- **Evoker**: 6E ground-control caster. Its 18-range Fang attack telegraphs for 0.4s, deals 85 ground-only damage in a line, and switches to a close ring burst inside 4 range. It summons three 75-HP flying Vexes after 4s and every 14s while fewer than three are alive; each Vex deals exactly 30 damage and expires after 9s.
- **Villager**: stationary Emerald-generation support
- **Guardian (DEV ONLY)**: benched from the production card/Evolution pools while its water-only targeting and balance are still being developed. In admin it remains a 6E stationary water tank counter with an 18-range ramping beam, 20% charge loss on incoming hits and 5% reflected damage against flying attackers.
- **Enderman**: teleporting melee attacker
- **Snow Golem**: ranged slow support without kiting

## Evolution Slot

The Evolution Slot duplicates one card that is already part of the normal 8-card deck; it does not replace or remove that card.

Only cards with an explicit `card.evolution` definition in `src/cards.lua` are eligible. Cards without an evolution cannot be placed in the slot.

Evolution timing is configured **per card** with `cycles`:

- `cycles = 0` -> every successful play is evolved
- `cycles = 1` -> one normal play, second play evolves
- `cycles = 2` -> two normal plays, third play evolves
- `cycles = 3` -> three normal plays, fourth play evolves
- and so on

After an evolved play the counter resets and the card starts charging again.

Each Evolution can also have its own Emerald cost. Supported forms include:

    cost = 4                      -- exact evolved cost
    cost = { delta = 1 }          -- base 3E -> evolved 4E
    cost = { multiplier = 1.5 }   -- multiply base cost
    cost = { set = 5 }            -- explicit exact cost
    costDelta = 1                 -- shorthand
    costMultiplier = 1.5          -- shorthand

The real play API, UI, bot affordability and telemetry all use the evolved cost only when that evolved play is actually ready.

Stats can be configured either as exact values or multipliers:

    evolution = {
        cycles = 3,
        cost = { delta = 1 },

        statMultipliers = {
            maxHp = 1.15,
            damage = 1.10,
        },

        stats = {
            attackRange = 18,
        },
    }

`stats` and `statMultipliers` automatically target the card's active unit/building/spell payload.

Abilities are deep-merged with `abilities`. This allows an Evolution to add or modify any mechanic already supported by the engine, for example:

    abilities = {
        onHitSlow = {
            factor = 0.75,
            duration = 2.0,
        },

        teleport = {
            minRange = 8,
            maxRange = 20,
            cooldown = 4,
        },

        canAttackAir = true,
    }

This same system can configure existing mechanics such as teleporting, slowing, splitting, proximity explosions, periodic summons, Emerald generation and target behavior. A completely new ability type still needs its gameplay handler implemented once in `Game.lua`; after that it can be configured per Evolution through the same data structure.

For more specialized Evolutions, the older section format remains supported:

    unit = {
        multipliers = { maxHp = 1.2 },
        overrides = { canAttackAir = true },
    }

and `patch = {...}` can deep-merge arbitrary whole-card data such as `spawnCount`, placement data, or future custom fields.

The battle UI shows the Evolution charge persistently in the status area and directly on the Evolution card whenever it is in hand. When the evolved play has a different Emerald cost, the hand displays the **actual evolved cost** and affordability state.

Evolution use is battle-only; the admin sandbox does not consume or trigger Evolution cycles.

The first gameplay Evolutions are enabled:

- **Charged Creeper** — Creeper, 2 cycles, same 4E cost. Doubles explosion damage from 290 to 580, expands the real blast radius from 8 to 12 and uses a much larger blue/cyan charged explosion visual.
- **Ghast Portal** — Nether Portal, 2 cycles, same 3E cost. Replaces the purple portal with a cyan/light-blue shimmer and summons exactly 2 Ghasts total.
  - **Ghast** — 220 HP flying artillery, 130 damage, 24 range, 2.8s attack cooldown, 5.5 splash radius. Two full hits kill the current 257-HP Blaze. The primary target is slowed by 35% for 1.5s; splash victims take damage but are not slowed.
- **Mega Mite** — Endermite, 4 cycles, so the 5th play evolves. Same 1E cost. Keeps all normal Endermite combat stats except max HP, which is exactly 5x (525 HP), and uses a visibly larger sprite.
- **Elder Guardian** — Guardian, 2 cycles, same 6E cost. Doubles HP from 90 to 180 and applies a battlefield-wide 5% movement-speed penalty to every enemy unit while alive. It inherits the Guardian's 18 range; beam ramp and spike reflection are otherwise unchanged.
- **Emerald Bank** — Villager, 3 cycles, same 7E cost. Keeps the exact 61.6% Emerald-generation boost, gains 5% HP (185 -> 194.25) and lasts 70s instead of 50s.
- **Diamond Golem** — Iron Golem, 2 cycles, same 5E cost. The base Iron Golem now has 1514.7 HP (+10% from 1377); Diamond Golem gains another 7.5% on top (1628.3025 HP). While it is actually walking, each accumulated 2.0s of movement triggers a stomp, creating a visible local quake that deals 25 damage in 8 radius to enemy grounded units only. Standing still to attack a building or Crown Tower pauses the stomp timer; flying and water-only units are ignored.

VS BOT automatically selects the first evolution-capable card in its deck when one exists and respects the configured evolved Emerald cost.

## Game modes

### PVP
Two human players use the two monitor walls.

### VS BOT
Either monitor can enable VS BOT. The player who enables it stays human and the opposite side becomes the AI.

Bot difficulty:
- Easy
- Normal
- Hard

The bot uses the normal card API and Emerald economy rather than special spawn cheats.

## Lobby

The lobby includes:

- 22-card paginated collection
- 8-card deck builder
- 1 extra **Evolution Slot** below the normal deck
- Random 8-card deck button
- Unit Info / card database
- PVP / VS BOT mode toggle
- Bot difficulty control
- Ready synchronization

The old 3-slot deck preset/loadout implementation is still kept in the codebase, but its controls are currently hidden from the normal lobby UI to free space for Evolutions.

### Match Ruleset

The lobby now has a shared **RULESET** button beside the game-mode control. Rules apply to the whole match and are visible from either monitor.

Current rule:

- **EVOLUTIONS: ON/OFF** — ON is the default. OFF preserves each player's selected Evolution Slot card in the deckbuilder, but the match completely suppresses Evolution charging, evolved costs, evolved stats and evolved abilities. Every card behaves as its base form.

Changing a Ruleset option automatically clears READY for both players so a match cannot begin under stale settings.

The Ruleset UI is intentionally data-oriented so additional match options can be added later without rebuilding the lobby flow.

## Admin sandbox

Run:

    admin

The admin sandbox can:

- pause/resume simulation
- spawn cards for either side
- load tower scenarios
- clear units/projectiles/effects
- enable a bot
- browse the paginated card pool


Evolution forms are also listed directly in the admin card pages. They are marked **EVO** and can be spawned immediately without charging cycles or paying Emeralds. Current direct admin forms are Charged Creeper, Ghast Portal, Mega Mite, Elder Guardian, Emerald Bank and Diamond Golem. Guardian and Elder Guardian are intentionally admin/dev-only while benched.
## Balance simulator

Run any whole-number match count from **100 to 1000**:

    simulate 100
    simulate 347
    simulate 500 mixed
    simulate 1000 mixed
    simulate 300 fixed

Usage:

    simulate <100-1000> [mixed|fixed] [seed]

Results are written to:

    balance_results.txt

Invalid/help commands do not overwrite the previous report. Side-swapped match pairs also reuse the same future-proof gameplay RNG seed without consuming the independent deck-sampling RNG.

## Controlled replacement analysis

After a broad mixed benchmark, use the paired replacement analyzer to isolate whether one card actually improves otherwise identical decks:

    compare 30 all
    compare 100 zombie wither_skeleton
    compare 100 iron_golem enderman 2026

Each context creates one randomized 7-card shell and one randomized opponent deck. Card A and Card B occupy the same replacement slot, and both variants play once as P1 and once as P2. This removes most deck-composition and side bias from the comparison.

The default `all` suite compares:

- Zombie vs Wither Skeleton
- Slime vs Magma Cube
- Cannon vs Pillager Outpost
- Iron Golem vs Enderman (same-cost diagnostic)
- Skeleton vs Snow Golem (ranged-support diagnostic)
- Bat Swarm vs Spider (2E pressure diagnostic)

Results are written to:

    comparison_results.txt

The report includes score-rate delta, paired context wins, card efficiency and a paired 95% confidence interval. A raw edge whose interval still crosses zero is labeled LEAN; an interval fully on one side of zero is labeled CLEAR.

## Active mechanics diagnostics

Run:

    mechanics_test

This executes deterministic gameplay scenarios against the real game logic rather than only checking static values. It currently exercises target pull/lock behavior, building HP decay, Nether Portal spawn cadence, Magma Cube splitting, Falling Anvil air/ground AoE and delay, Creeper fuse behavior, Skeleton kiting, Pillager Outpost anti-air, full regulation/overtime/tiebreaker flow, Emerald multipliers and a live bot smoke test.

The runner writes a shareable machine-readable report to:

    mechanics_report.txt

The report contains PASS/FAIL status plus measured values (spawn times, HP decay, Emerald generation, tower drain, bot actions, etc.) so failures can be analyzed without reproducing the match manually.

## Evolution balance testing

Normal balance simulations already execute real Evolution gameplay. `Bot.prepare()` assigns the single Evolution Slot to the first eligible card in that bot's deck, and every play still goes through the normal `Game.playCardFromSlot()` path. This means cycles, changed Emerald cost, evolved stats, summons, splash, slow and other abilities are part of `simulate` and ordinary `compare` matches.

The mixed simulator reports an additional **EVOLUTIONS** table:

- `Slot%` - how often that card actually occupied the one Evolution Slot when it was present in a deck
- `Evo/SM` - evolved plays per match where it owned the slot
- `Evo%` - share of that card's plays that were evolved while selected
- `Cycles` and `EvoCost` - configured rule/cost

For a clean Evolution-only measurement use:

    evo_compare 30 all
    evo_compare 100 creeper
    evo_compare 100 nether_portal
    evo_compare 100 endermite
    evo_compare 100 villager
    evo_compare 100 iron_golem

`evo_compare` builds identical 8-card subject decks and identical opponents for BASE and EVO. BASE disables every Evolution Slot; EVO enables only the tested card. Each context is played from both sides, and corresponding BASE/EVO matches use the same gameplay RNG seed.

With Guardian/Elder Guardian benched, the normal pool currently has five selectable Evolutions, so `evo_compare 30 all` runs 600 matches.

The report is written to:

    evolution_results.txt

and, when report sync is configured, automatically uploaded to:

    reports/latest/evolution_results.txt
    reports/history/evolution/

This isolates the **raw power added by the Evolution Slot**. It does not measure the opportunity cost of choosing that Evolution instead of another one, so follow it with `simulate 1000 mixed` for the actual one-slot meta.

## GitHub report sync

Reports can be uploaded directly from the arena computer into this repository so the newest diagnostics are always available without screenshots.

One-time setup:

    report_sync setup

Enter a **fine-grained GitHub personal access token** restricted to `Chazammm/CC-Minecraft-Royale` with **Contents: Read and write**. The token is stored only on the Minecraft computer at:

    .cc_royale/github_token.txt

It is not part of the installer and is never committed to the repository.

After setup, `mechanics_test`, `simulate`, and `compare` automatically upload their completed report. Reports are organized as:

    reports/latest/mechanics_report.txt
    reports/latest/balance_results.txt
    reports/latest/comparison_results.txt
    reports/latest/evolution_results.txt

and timestamped history copies under:

    reports/history/mechanics/
    reports/history/balance/
    reports/history/comparison/
    reports/history/evolution/

Manual commands:

    report_sync
    report_sync status
    report_sync logout

`report_sync` uploads every currently available local report. If an upload fails, the local report is kept and the game/test itself does not fail.

## Battle music

Battle music is shuffled and streamed as 48 kHz mono DFPWM from two immutable, commit-pinned music packs. The large binaries are intentionally not kept in the current main working tree, so fresh shallow checkouts and CI stay lightweight while old installed manifests can never drift to incompatible pack bytes. When two speakers are available, SFX and music use separate devices. Streaming has reconnect/retry handling for interrupted HTTP requests.

## Install / update

On the arena computer:

    wget run https://raw.githubusercontent.com/Chazammm/CC-Minecraft-Royale/main/install.lua

The bootstrap installer resolves `main` once and pins the entire update to that
single immutable commit SHA before downloading managed files. Every downloaded
Lua file is syntax-checked before the first live write. The installer keeps a
small recovery marker during the apply phase, preserves unrelated custom
`startup.lua` files, tracks its managed-file set so removed/renamed runtime
files are cleaned on later updates, and performs low-space RAM rollback for
both ordinary write failures and unexpected filesystem exceptions.

Then run:

    diagnose
    main

`startup.lua` launches `main.lua` automatically on reboot.

## Architecture

- `config.lua` - match, arena and music tuning
- `src/cards.lua` - cards, Evolution definitions and internal summoned units
- `src/arena.lua` - placement, terrain and bridge navigation
- `src/game.lua` - match lifecycle, combat, targeting, spells and tiebreaker
- `src/bot.lua` - bot decisions and card usage
- `src/render.lua` - normal monitor UI
- `src/pixel_arena.lua` - semigraphics arena renderer
- `src/admin_render.lua` - admin UI
- `src/hardware.lua` - monitor/speaker discovery
- `src/music.lua` - streamed battle music controller
- `simulate.lua` - automated balance benchmark
- `compare.lua` - paired controlled card replacement analysis
- `evo_compare.lua` - paired base-vs-Evolution analysis
- `src/benchmark_utils.lua` - shared deterministic benchmark RNG/statistics
- `src/headless_match.lua` - one authoritative headless match driver for every benchmark
- `mechanics_test.lua` - active deterministic gameplay diagnostics + shareable report
- `report_sync.lua` - GitHub report sync setup/manual uploader
- `src/report_sync.lua` - authenticated report upload/history helper; manual sync batches all available reports into one commit
- `tests/test_v1.lua` - legacy broad logic smoke/regression suite
- `tests/test_audit_regressions.lua` - cross-mechanic and symmetry regressions
- `tests/test_headless_runner.lua` - benchmark-driver parity test
- `tests/test_platform_stubs.lua` - hardware/music/report-sync platform stubs
- `tests/test_install_manifest.lua` - installer dependency coverage
- `tests/test_cli_manifest.lua` - CLI and immutable music-manifest checks
- `tests/test_side_symmetry.lua` - focused arena/bot side-symmetry checks
- `tests/test_audit_followups.lua` - second-pass audit regressions for slows, UI, bot cadence, persistence, statistics and report batching

## Deliberate simplifications

- Navigation is specialized for the two-bridge arena instead of full A*
- Units do not physically collide with one another
- King Towers are active from match start
- Balance is intentionally iterative and is validated with repeated bot simulations plus real-monitor testing

See `TEST_PLAN.md` for the recommended in-game verification order.
