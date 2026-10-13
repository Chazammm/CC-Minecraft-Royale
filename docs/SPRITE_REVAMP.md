# Approved model revamp

All 35 arena sprite definitions in `src/pixel_arena.lua` now follow the approved
colourful Minecraft model designs. The game renders native palette-token rows;
it does not load the high-resolution proposal PNG as a texture.

- [Approved visual direction, rows 1–4](../assets/sprites/approved-model-revamp-1.webp)
- [Approved visual direction, rows 5–7](../assets/sprites/approved-model-revamp-2.webp)
- [All native sprite pixels](../assets/sprites/native-sprite-roster.png)
- [Actual PixelBox output on a virtual monitor](../assets/sprites/pixelbox-sprite-roster.png)

The concept artwork has been adapted to ComputerCraft's 16 colours and compact
footprints: at most 15 pixels wide and 17 pixels tall. Eye blocks are arranged
to retain their colour in PixelBox's two-colour 2×3 terminal cells. Transparent
pixels reveal terrain. Pink is now used for the Piglin's skin; `T` still maps
to the viewing player's light-blue/red team colour on tower banners.

The approved concept sheet is archived as two lossless WebP pages to keep
individual uploads small. Together they preserve every pixel of the full sheet.

The set includes base mobs, six evolution variants, summoned creatures,
buildings, portals, and the Princess and King towers. Each Bat Swarm entity
renders one bat: the existing card still spawns three bats. Spells and their
procedural effects, unit stats, targeting, collision and combat are unchanged.

`tests/test_sprite_roster.lua` validates roster completeness, palette tokens,
compact footprints, real terminal encoding, base and evolved selection,
stationary caching, damage-flash recovery, health/team overlays and removal
without ghost pixels for both viewing players. The existing 38-check frame
cache suite also passes. Local validation used the system Lua 5.4 library:
all 64 Lua files compiled, all 32 Lua test suites passed, and the four Python
report-retention tests passed. GitHub Actions runs the new renderer suite on
both Lua 5.2 and 5.4 before merge.

The PixelBox preview uses the real renderer and terminal encoding on a virtual
monitor. Physical CC:Tweaked/ATM10 monitor legibility and throughput still need
field validation; this is not a claim of hardware verification.

To install the replacements on the arena computer after merge:

```text
wget run https://raw.githubusercontent.com/Chazammm/CC-Minecraft-Royale/main/install.lua
diagnose
main
```
