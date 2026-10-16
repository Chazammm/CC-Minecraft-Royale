# King Frog and Nether Worm — shipped asset subset

Only these two custom mobs are registered by this implementation. Their reviewed art derives from [PR #21](https://github.com/Chazammm/CC-Minecraft-Royale/pull/21), source revision `a0da310becfbdb028780ab698fa3d80a047e46a5`. There is no runtime dependency on that unmerged branch and no Crab/Centipede art in the runtime subset.

![Exact dual-platform comparison](previews/comparison.png)

[All nine registered native frames](previews/runtime_poses.png) · [Actual gameplay,6×](previews/gameplay_6x.png) · [Actual gameplay,1×](previews/gameplay_1x.png)

- Native Lua rows: `src/assets/custom_mobs/frames.lua`; dispatcher in the same folder. Frames stay within16×18 and use the original CC palette/dot transparency.
- Future LÖVE: `love2d/king_frog.png`, `love2d/nether_worm.png`;256×256 RGBA, one main pose each, nearest filter, foot anchor(128,240). Metadata in `love2d/index.lua`. These PNGs are independent reviewed design masters, not enlarged native rows; no complete LÖVE animation set is claimed.
- Native Frog: idle / crouched walk / tongue / melee. Worm: idle / move / bite / exposed emergence. Separate16×5 ground warning with owner cue has no entity or HP bar. Ordinary hurt, HP/team/web and death handling remain shared.
- `evidence/capture52.json` / `capture54.json` contain real registered renderer outputs, not injected preview slots. The gameplay scene contains an actual hook windup, an exposed Worm and a pending deployment.
- `tools/previews.py` composes only those captures and committed PNGs, and verifies exact pixel identity, cross-Lua equality, alpha/margins and master hashes. The original approved source-generation PNGs and animal reference links remain documented in PR #21.

Reproduce from repository root (host only; Lua5.2/5.4, Python3.12, Pillow12.3.0, DejaVu Sans):

```sh
lua5.2 tests/test_frog_worm_rendering.lua /tmp/frog-worm52.json
lua5.4 tests/test_frog_worm_rendering.lua /tmp/frog-worm54.json
python3 assets/sprites/frog_worm/tools/previews.py --check --capture52 /tmp/frog-worm52.json --capture54 /tmp/frog-worm54.json
```

[Runtime behavior and technical details](../../../docs/frog_worm/IMPLEMENTATION.md). CC installer ships only runtime Lua files; these PNGs, captures and host tools do not add in-match image loading or rendering work. Virtual-monitor images use square logical pixels; physical terminal-cell appearance and timing still need on-device review.
