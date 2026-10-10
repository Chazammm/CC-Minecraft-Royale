# CC-Minecraft Royale V1 - In-game test plan

Run these in order. Do not try to validate everything in one match; isolating one mechanic at a time makes bugs much easier to identify.

## 1. Hardware and orientation

- Build two separate 3x4 Advanced Monitor walls.
- Run the game.
- Confirm both monitors render at the configured `config.TEXT_SCALE` (default 0.5).
- Confirm one says PLAYER 1 and the other PLAYER 2.
- Confirm the displayed monitor peripheral names match the intended sides.
- If they are reversed, set config.MONITOR_NAMES explicitly.
- Confirm no warning about a small display appears.

Pass condition: both displays are stable, readable and assigned correctly.

## 2. Ready, countdown and mirrored view

- Press READY on Player 1 only.
- Confirm Player 2 sees that the opponent is ready and the match does not start.
- Ready Player 2.
- Confirm a 3-second countdown appears.
- When the arena appears, compare both screens.

Pass condition: the same arena state is shown from opposite perspectives and each player's own King Tower is at the bottom.

## 3. Touch selection and placement limits

- Select a card, then tap it again.
- Confirm selection cancels.
- Select Zombie and deploy on your own half.
- Try to deploy another troop on the enemy half.
- Select Arrow Volley and target the enemy half.

Pass condition: troop/building deployment is rejected on the enemy half, while Arrow Volley can target anywhere.

## 4. Emerald economy and card cycle

- Observe the Emerald counter rising.
- Spend a cheap card and confirm the exact cost is removed.
- Try to use a card you cannot afford.
- Play the first hand slot once and note which card replaces it.
- Cycle enough cards to verify the played card eventually returns.

Pass condition: max is 10, unaffordable cards cannot deploy, and the 8-card / 4-card cycle remains stable.

## 5. Zombie baseline combat

- Send one Zombie down a lane with no distractions.
- Watch it route through a bridge.
- Let it reach a tower.

Pass condition: movement, target acquisition, melee attacks, tower retaliation and HP reduction all work without the unit freezing in the river.

## 6. Bridge pathfinding

- Place ground troops at several far-left, center and far-right positions.
- Do this in both lanes and for both players.
- Try to force a target across the river on the opposite lane.

Pass condition: ground units never walk through water and consistently choose/reach one of the two bridges.

## 7. Skeleton ranged combat and kiting

- Send a Skeleton toward an enemy.
- Let the Skeleton attack from range.
- Push a melee unit close to it.

Pass condition: arrows/projectiles travel to the target and the Skeleton tries to create distance when an enemy gets too close.

## 8. Lane targeting and Iron Golem pulls

- Send a normal troop down the left lane with both enemy Princess Towers alive.
- Confirm it chooses the left Princess Tower rather than the opposite lane.
- Destroy that left Princess Tower while the match continues.
- Confirm surviving/new left-lane troops now advance toward the King Tower rather than crossing to the right Princess Tower.
- Place an enemy troop near an Iron Golem and confirm it ignores the troop.
- Place a defensive Cannon inside the Iron Golem's aggro range before it reaches a tower and confirm the Cannon can pull it away.
- Let the Iron Golem hit the tower once, then place another Cannon beside it.
- Repeat with a normal troop locked onto a tower, then spawn a new enemy troop beside it.

Pass condition: Crown Tower objectives stay lane-correct, pre-attack kiting/distraction still works, and after the first attack the unit stays locked to that target until it dies.

## 9. Bat Swarm flying

- Deploy Bat Swarm away from a bridge.
- Observe all three Bats.
- Let them cross the river.
- Put a ground-only Cannon in their path.
- Let a Princess Tower shoot one Bat.

Pass condition: three units spawn, fly directly over water, are ignored by the ground-only Cannon, and each Bat is fragile enough to die to one Princess Tower hit.

## 9b. Post-tower deployment pocket

- Before destroying a Princess Tower, try to deploy a troop just across the river on that enemy lane.
- Destroy the enemy left Princess Tower.
- Try the same placement again in the unlocked left-side pocket.
- Try placing on the still-protected right lane and in the centre near the King Tower.
- Place a building in a valid unlocked pocket position that is inside King Tower range.

Pass condition: only the destroyed lane gains the extra deployment area, the opposite lane/centre remain locked, and Crown Towers can shoot enemy pocket buildings.

## 10. Cannon building behavior

- Place a Cannon on your own half.
- Send enemy ground units into range.
- Then test an enemy Bat Swarm.
- Leave a Cannon alive long enough to expire.

Pass condition: Cannon is stationary, attacks ground troops, ignores flying troops, loses HP continuously from lifetime decay and dies naturally when that decay/damage exhausts its HP.

## 11. Arrow Volley AoE

- Cluster multiple enemy troops.
- Cast Arrow Volley over them.
- Also hit a tower with the edge/center of the spell.

Pass condition: multiple enemy units take damage once, the visible effect appears, and tower spell damage is reduced.

## 12. Creeper proximity fuse

- Put an enemy unit inside the Creeper's trigger range.
- Confirm the fuse starts instead of an instant melee hit.
- Let the fuse finish once and observe the AoE.
- Repeat, but kill the Creeper before the fuse completes.

Pass condition: the completed fuse explodes once and damages nearby enemies; a Creeper killed before detonation does not explode.

## 13. Slime split-on-death

- Deploy a Slime.
- Kill it while there is room around it.

Pass condition: exactly two Mini Slimes appear and continue fighting as normal units.

## 14. Tower scoring and regulation end

Regulation is currently 2:30. Temporarily lower config.MATCH.normalTime for a faster manual test if needed.

- Destroy one side tower and let regulation expire.

Pass condition: the player with more destroyed side towers wins at the end of regulation.

## 15. Overtime staged Emerald generation

For this test, temporarily lower normal/overtime times.

- Let normal time expire at an equal tower score.
- Measure/observe Emerald regeneration before and after overtime.
- Confirm most of overtime runs at approximately 2x generation.
- Confirm the final 30 seconds switch to approximately 3x generation and show the FINAL 30 notification.
- Destroy one side tower during overtime.

Pass condition: overtime begins only on a tie, uses 2x Emerald generation until 0:30, then 3x for the final 30 seconds, and the next destroyed tower ends the match immediately.

## 16. King Tower instant win

- Destroy the enemy King Tower during normal time.

Pass condition: the match ends immediately regardless of side-tower score or remaining time.

## 17. Tiebreaker

Temporarily set short regulation/overtime times.

- Reach overtime with an equal side-tower score.
- Destroy no tower before overtime expires.
- Give one side a clearly lower surviving tower HP value.

Pass condition: TIEBREAK appears, cards stop being playable, surviving towers visibly drain HP together, and the player whose weakest tower had more HP wins. Exact equal lowest HP may still produce a draw.

## 18. Simultaneous input stress test

- Have both players repeatedly select/deploy cards at roughly the same time.
- Create many units, spells and projectiles.
- Keep both screens active.

Pass condition: neither display desynchronizes, input remains responsive and no Lua error terminates the game.

## 19. Result/rematch flow

- Finish a match.
- Press REMATCH on one side only.
- Then press REMATCH on the other side.
- On another result screen, test DECK/LOBBY and EXIT.

Pass condition: one rematch vote waits for the opponent, two votes start a fresh countdown, and lobby buttons reset match state cleanly.

## Bug report format

When something fails, send:

- Test number
- Which player/screen
- What you touched/placed
- What you expected
- What actually happened
- A screenshot of both monitors if the issue is visual
- The complete Lua error if the computer crashes

That information is usually enough to reproduce and patch the bug quickly.
