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
- Defensive buildings can pull building-targeting troops such as Iron Golem
- Buildings lose HP continuously across their lifetime instead of staying full and disappearing instantly
- Skeleton can kite; Snow Golem intentionally does not
- Projectiles, slows, summons, teleports, explosions and delayed spells are supported

## Current selectable cards

There are currently **21 selectable cards**:

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
11. Enderman
12. Spider
13. Snow Golem
14. Villager
15. Endermite
16. Wolf
17. Falling Anvil
18. Nether Portal
19. Wither Skeleton
20. Magma Cube
21. Pillager Outpost

Nether Portal summons the internal-only Piglin unit; Piglin is not directly selectable. Magma Cube splits into the internal-only Mini Magma Cube.

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
- **Villager**: stationary Emerald-generation support
- **Enderman**: teleporting melee attacker
- **Snow Golem**: ranged slow support without kiting

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

- 21-card paginated collection
- 8-card deck builder
- 3 persistent deck presets per player
- Random 8-card deck button
- Unit Info / card database
- PVP / VS BOT mode toggle
- Bot difficulty control
- Ready synchronization

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

Invalid/help commands do not overwrite the previous report.

## Battle music

Battle music is shuffled and streamed as 48 kHz mono DFPWM from the repository's split music packs. When two speakers are available, SFX and music use separate devices. Streaming has reconnect/retry handling for interrupted HTTP requests.

## Install / update

On the arena computer:

    wget run https://raw.githubusercontent.com/Chazammm/CC-Minecraft-Royale/main/install.lua

Then run:

    diagnose
    main

`startup.lua` launches `main.lua` automatically on reboot.

## Architecture

- `config.lua` - match, arena and music tuning
- `src/cards.lua` - cards and internal summoned units
- `src/arena.lua` - placement, terrain and bridge navigation
- `src/game.lua` - match lifecycle, combat, targeting, spells and tiebreaker
- `src/bot.lua` - bot decisions and card usage
- `src/render.lua` - normal monitor UI
- `src/pixel_arena.lua` - semigraphics arena renderer
- `src/admin_render.lua` - admin UI
- `src/hardware.lua` - monitor/speaker discovery
- `src/music.lua` - streamed battle music controller
- `simulate.lua` - automated balance benchmark
- `tests/test_v1.lua` - automated logic regression/smoke tests

## Deliberate simplifications

- Navigation is specialized for the two-bridge arena instead of full A*
- Units do not physically collide with one another
- King Towers are active from match start
- Balance is intentionally iterative and is validated with repeated bot simulations plus real-monitor testing

See `TEST_PLAN.md` for the recommended in-game verification order.
