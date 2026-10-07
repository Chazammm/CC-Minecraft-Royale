# CC-Minecraft Royale

A two-player Clash-Royale-inspired arena game built for CC:Tweaked in ATM10.

## V1 scope

V1 is intentionally a foundation rather than a finished balance pass.

- Two synchronized Advanced Monitor walls
- Recommended monitor size: **3 wide x 4 high per player**
- Text scale: **0.5**
- One authoritative Advanced Computer
- Optional speaker
- Mirrored perspective: each player sees their own side at the bottom
- Two lanes, river and two bridges
- Ground pathing through bridges
- Flying units can cross the river directly
- 8-card deck / 4-card hand / cycling queue
- Emerald resource system
- 3:00 normal match
- King Tower destruction = instant win
- At 3:00, the player with more destroyed side towers wins
- Tie -> 2:00 overtime
- Overtime = 3x Emerald generation and sudden death on the next tower
- Draw if overtime expires without another tower falling
- Ready screen, result screen and rematch voting

## The eight V1 test cards

1. **Zombie (3E)** - baseline ground melee.
2. **Skeleton (3E)** - ranged combat and kiting.
3. **Iron Golem (6E)** - tank that targets buildings/towers.
4. **Bat Swarm (2E)** - three flying units from one card.
5. **Cannon (4E)** - placeable defensive building with a lifetime.
6. **Arrow Volley (3E)** - AoE spell. This is the one current placement exception and can target anywhere.
7. **Creeper (4E)** - death explosion / AoE ability hook.
8. **Slime (3E)** - splits into two Mini Slimes on death.

The values are test balance only. They are deliberately easy to change later.

## Hardware

Recommended setup:

- 1 Advanced Computer
- 2 separate **3x4 Advanced Monitor** walls
- Wired Modems / networking so both monitor peripherals are visible to the computer
- 1 optional Speaker

If exactly two monitors are visible, V1 assigns them automatically in sorted peripheral-name order. The lobby screen tells you which physical monitor became Player 1 and Player 2.

If more than two monitors are visible, set their exact names in `config.lua`:

    config.MONITOR_NAMES = { "monitor_12", "monitor_13" }

This avoids accidentally binding the game to an unrelated monitor elsewhere on the wired network.

## Running

Put the repository contents on the arena computer and run:

    main.lua

If `startup.lua` is present on the computer, the arena starts automatically after a reboot.

Terminate with Ctrl+T. The program clears both monitors when it exits normally through termination.

## Controls

### Lobby

Both players press **TOGGLE READY**. The match begins after both are ready and the countdown completes.

### Battle

1. Touch one of the four cards at the bottom.
2. The selected card is highlighted.
3. Touch the arena to deploy it.
4. Touch the selected card again to cancel selection.

Troops and buildings are restricted to the player's own half. Arrow Volley can target anywhere so spell targeting is testable in V1.

### Result

- **REMATCH**: both players must vote for a rematch.
- **DECK/LOBBY**: returns both players to the lobby.
- **EXIT**: currently also returns to the lobby. It does not shut down the shared arena computer.

## Architecture

The world simulation uses virtual arena coordinates (100 x 160) and is independent of monitor resolution. The renderer converts world coordinates to the actual monitor size and rotates Player 2's view by 180 degrees.

Important modules:

- `config.lua` - match and arena tuning
- `src/cards.lua` - card data and internal units
- `src/arena.lua` - terrain, placement and bridge navigation
- `src/game.lua` - match state, Emeralds, targeting, combat, projectiles and abilities
- `src/render.lua` - monitor UI and arena rendering
- `src/hardware.lua` - monitor/speaker discovery
- `main.lua` - event loop
- `tests/test_v1.lua` - automated smoke tests

## Current deliberate simplifications

- Pathfinding is specialized for this two-bridge arena instead of running full A* every tick. Ground units route through the best bridge; flying units use direct movement.
- Units do not yet collide with each other.
- King Towers are active from the start.
- Card balance and visuals are placeholders.
- There are exactly eight cards, so the V1 lobby shows the fixed test deck rather than a meaningful deck-builder. Once card count exceeds eight, the existing deck/hand split can be extended into a real deck-builder.

See `TEST_PLAN.md` for the recommended in-game test order.
