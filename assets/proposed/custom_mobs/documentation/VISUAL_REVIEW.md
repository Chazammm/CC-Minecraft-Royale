# Visual audit and provenance — 2026-10-16

## References actually inspected

- Repository `assets/sprites/approved-model-revamp-1.webp`, native sprite roster, `docs/SPRITE_REVAMP.md`, current PixelBox renderer and previous extra-mob asset packages. PR #20's polished roster was additional context only; this branch is based on main and imports nothing from that PR. The user's supplied roster screenshot establishes the same dark-background Minecraft silhouette language.
- [Minecraft's Crab Mob Vote article](https://www.minecraft.net/en-us/article/mob-vote-crab) and its [official header](https://www.minecraft.net/content/dam/minecraftnet/games/minecraft/game-updates/CRAB_Header_1170x500.jpg): blue body, orange inner claw, one very large claw. This is the **2023 unimplemented candidate**, not a released vanilla crab. Two armored pincers, netherite plating and the native stylization are original design choices.
- [Official Frog article](https://www.minecraft.net/en-us/article/mob-menagerie--frog) and [frog screenshot](https://www.minecraft.net/content/dam/minecraftnet/games/minecraft/screenshots/frog_C.jpg): orange cuboid anatomy, broad head, raised eyes, cream throat and four legs. Crown and short mantle are custom.
- Netherite color/material language is interpreted from Minecraft's familiar dark warm metal, with restrained violet highlights. No new official crab armor model or canonical Nether Worm / Ore Centipede source exists or is claimed. The ore combinations are custom thematic caches, not a simulated mineral metabolism.

Official reference images were inspected locally but are not redistributed in this package. `MANIFEST.json` records reference URLs and access date. Generated source PNGs, exported sprites and native rows are included for future art revisions. Source generation used the approved roster and the two official animal references; it did not use native rows to generate high-resolution masters.

## Export / material decisions

Each independently generated full-character source is retained at its original resolution in `source/`. Technical export thresholds source alpha at250, crops the opaque character, fits within a16px safe border, uses nearest sampling, quantizes **visible pixels only** to40 colors without dither, zeros hidden RGB and removes detached1–2px alpha specks. No CC image is involved. This processing establishes logical pixel resolution and clean runtime alpha; it does not constitute drawing missing animation frames.

The broad Crab and Centipede canvases are384×256; Frog/Worm256×256. Assets use a shallow front-left/front view with top planes visible, consistent upper-left highlights and grounded lower silhouettes. They are game poses rather than portraits. The planned LÖVE camera/direction system is not yet defined; the static masters are usable for an initial fixed arena view but are not proof of final camera compatibility. The metal is somewhat more dimensional than the smallest legacy roster figures; visual approval should explicitly assess that fit.

## Inspection of actual exported PNGs and captures

| Mob | Master cues | Native interpretation / deliberate loss |
|---|---|---|
| Crab | Asymmetric open pincers, orange interiors, warm dark armor, teal joints and legs, small eyes under front plate |16×12 broad body; open claw notches, orange inner pixels, gray/violet metal, cyan legs. Fewer shell bevels and six summarized leg tips. |
| Frog | Four-legged orange animal, broad raised eyes, cream belly, small gold crown, short back mantle |16×16; three enlarged crown tips, strong eyes, orange/tan body, purple edge. Fine toes and gold mantle trim are omitted. |
| Worm | Rising plated S, dark maw, ivory teeth, narrow lava seams, pointed rear |16×17; folded body loop, bright seam and tooth clusters. Fewer visible segments and no detached lava/ash. |
| Centipede | Long segmented slate/iron back, mandibles, copper hinges, many feet, three visually distinct caches |16×11; horizontal segmented body and feet, pale mandibles/eye, orange / light-blue / red reserve blocks. Eight detailed ore textures compress into three caches; full20+ feet do not fit. |

The raw CC rows were visually inspected before and after actual sextant encoding. Initial claw details and crown tips lost contrast; revisions used larger color clusters, broader gaps and compact bodies. The comparison sheet deliberately shows remaining palette loss. Default green terrain provides a harsh practical check; the high-resolution roster uses the requested dark display background. The1× monitor PNG and native1× swatches are included so magnification does not masquerade as higher native resolution.

**Checked by image inspection:** whole characters in frame, readable material differences, distinct broad/frog/coil/long silhouettes, no embedded labels/background, paired platform identity, and3 separately visible ore reserves. **Checked mechanically:** alpha, margins, dimensions, exact source export, palette, source hashes, native token consistency, renderer output, overlays/cache, preview pixel identity and cross-Lua parity. Automated checks cannot certify subjective visual quality or substitute for the owner's approval.

## Remaining limits

- Four complete static LÖVE poses, not full movement/combat/death animation sets or layered editable Aseprite files. Original PNGs and reproducible export scripts are supplied.
- Thirteen native poses are isolated studies, not active animation state handling. Warning now uses a separate ground-overlay capture without a fake entity or HP bar. Native feeding frames compress ore art rather than removing physical collision segments.
- No running LÖVE application / GPU capture, physical CC:Tweaked hardware, real monitor aspect/timing measurement or many-unit new-mob benchmark. Logical-pixel enlargements use square pixels; physical terminal cells may have a different apparent aspect.
- Native palette cannot reproduce burgundy Nether Worm shadows or subtle netherite violet exactly. No global palette remap was introduced; team/terrain colors retain their established meaning.
- Stat and ability proposals have no new-mechanic simulation validation. No production changes, live cards, special attacks or bot behavior are included.

## Second review — owner-selected pair

All four master PNGs, the native roster, all13 native poses and actual PixelBox output were inspected again. No alpha/crop defects were found in the four masters; they are unchanged. King Frog remains recognizably quadruped and royal; Worm keeps the distinct rising coil, maw/teeth and lava seam. Native detail loss remains visible: the Frog summarizes rear toes/cape and the Worm loses fine plate segmentation/shadow shades. These are not full directional/animation sets or physical monitor inspection.

Two concrete defects were corrected: the Frog's earlier circular mouth study did not communicate an extended tongue; it now has a narrow pink ribbon projecting between the forefeet. The Worm warning was incorrectly presented with the unit harness's test HP bar; its capture now overlays only the ground pixels into the real PixelBox pipeline, with no unit entity or health bar. Emergence retains its HP bar, matching the future targetability contract. New cue checks cover tongue extension and absence of a warning HP bar.

Only King Frog and Nether Worm are candidates for subsequent implementation, at3E/550HP and3E/350HP. This review does not approve or activate gameplay. Their focused comparison is `previews/selected_pair_review.png`; the four-mob art library is retained for future use.
