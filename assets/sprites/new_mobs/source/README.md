# Source artwork and authorship

The five source PNGs are independently generated design masters, revised after
the first visual audit. They use the approved CC Royale roster and inspected
upstream mod geometry/texture views; the Raptor revision also uses the secondary
in-game view linked in the parent README. They are not enlarged native CC
sprites. No upstream mod texture/model or third-party screenshot is bundled.

Original generated dimensions are recorded as `sourceDimensions` per asset in
`MANIFEST.json`; the five game exports remain 256×256. The first art pass's
actual game exports and CC terminal captures are preserved under
`evidence/revision1/`, with the original full-size masters still available in
Git at `22952924d1dceed8e01c85d63ed3fd7780229946`.

Revision 2 moves the humanoids toward frontal views, broader clean planes,
stronger hands and less surface noise. Piglich preserves its head/crown/coat;
Cyclops preserves the eye/horn/hide; Behemoth preserves its recessed head,
shoulder growths and heavy claws. Chimera uses cleaner fur tufts and a lower,
angular folded wing. The Raptor was corrected to two hind legs without the old
unverified front arms, with lower box-like head plates and dark toes instead
of large ivory claws. No animation frames were generated.

Generated source PNGs contain soft alpha and hidden matte RGB, so **use the
`love2d/` exports in a game**. `tools/export_love.py` keeps alpha >=250, fits
inside 224×224 with nearest sampling, quantizes only opaque pixels to 40 colours
without dithering, clears transparent RGB, removes disconnected 1–2 pixel
alpha specks, then places the result on a 256×256 canvas at foot line y=240.
These are deterministic technical export operations. Image generation itself
is not seed-reproducible; the preserved PNGs make export reproducible.

`author_cc.py` contains deliberately placed palette-token rows interpreted
from the revised masters. It writes the data-only native Lua module. CC frames
were adjusted against the real arena/PixelBox output rather than obtained by
an automatic high-resolution-to-CC conversion.

This is flat single-pose art pending owner approval. There are no layered
Aseprite/PSD sources, rig, animation frames or claim of hand-painting.
