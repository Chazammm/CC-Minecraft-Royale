# Source artwork and authorship

The five source PNGs are independent image-generation design masters, created
from the approved CC Royale roster and inspected upstream mod geometry/texture
reference views. They are not enlarged native CC sprites. No upstream mod
texture or model is bundled in this directory. Each file is preserved at its
original generated dimensions (1254×1254; the Raptor is 1536×1024).

The direction used for all five: one full-body transparent arena sprite,
front three-quarter orthographic view, Minecraft cuboid anatomy, controlled
pixel-cluster shading, light from the upper left, no labels, no scene or ground.
The individual directions preserve the features documented in the parent
README. The Raptor received an additional transparency cleanup generation.

Generated source PNGs contain soft alpha and hidden matte RGB, so **use the
`love2d/` exports in a game**. `tools/export_love.py` keeps alpha >=250, fits
inside 224×224 with nearest sampling, quantizes only opaque pixels to 40 colours
without dithering, clears transparent RGB, removes disconnected 1–2 pixel
alpha specks, then places the result on a 256×256 canvas at foot line y=240.
These are deterministic technical export operations, not an enlargement or a
substitute for making the five detailed designs. The original files remain
available for later manual refinement. Image generation itself is not
reproducible from a random seed; the preserved sources make export reproducible.

`author_cc.py` contains intentionally placed palette-token rows interpreted
from those completed masters. It writes the data-only native Lua module.
No automatic high-resolution-to-CC colour conversion is used. The two art
resolutions are related designs, not pixel-for-pixel resizes of each other.

This is a flat single-pose art delivery pending visual approval. There are no
layered Aseprite/PSD sources, rig, animation frames or claim of hand-painting.
