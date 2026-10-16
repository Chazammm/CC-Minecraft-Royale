# Animation and effect handoff

**Delivered now:** one fully rendered LÖVE main pose per mob;13 actual native frames;4 offline native pose-study GIFs. These GIFs show real PixelBox-captured poses and held timing, not smooth completed runtime animations. No LÖVE animation sheets, directional sets, runtime dispatcher, tongue projectile or combat effects are claimed complete.

| Mob | Actual native entries | Offline study |
|---|---|---|
| Crab | `netherite_crab`, `netherite_crab_guard` | [guard study](../previews/netherite_crab_study.gif) |
| Frog | `king_frog`, `king_frog_tongue` | [tongue study](../previews/king_frog_study.gif) |
| Worm | `nether_worm`, `_warning`, `_emerging`, `_bite` | [warning / emergence / bite](../previews/nether_worm_study.gif) |
| Centipede | `ore_centipede`, `_feeding`, `_reserve_2`, `_reserve_1`, `_reserve_0` | [finite reserve study](../previews/ore_centipede_study.gif) |

All13 entries use the same existing unit-renderer test harness so palette, HP/team overlays and cache tests are comparable. **The warning row study consequently has a test HP bar.** In a future real deployment it must render as a ground effect with no unit HP bar until EMERGING; this package does not register that effect. The Centipede GIF compresses three feed cycles into a reserve-readability study; only the first channel pose is shown. It does not claim to reproduce6-second retry timing. Frog's short native tongue is a silhouette study, not a range-12 beam or target-linked line.

## Future LÖVE / native frame plan

Keep each creature on its documented canvas and foot anchor; do not recrop individual frames. Use named states and indexed frames rather than filenames containing ability timing. Upper-left light remains constant. Ore caches should be separate future art layers (or four explicit reserve variants), not baked glow pulses. Visual highlights should never obscure telegraph silhouettes.

| State | Crab | Frog | Worm | Centipede |
|---|---|---|---|---|
| Idle |2–3 frames, subtle joint/pincer lift |3–4, blink + throat breath |3–4, segment compression |3–4, leg ripple |
| Movement |4–6, clear sideways step; body stays low |4–6, crouch → hop → land, purely cosmetic |4–6, aboveground coil advance after deployment |6–8, stagger leg pairs and segment wave |
| Basic attack |4–5, anticipation → heavy close → recover |4–5 plus separate target-linked tongue line |4–5, mouth plates open → bite → recoil |4–5, mandibles open → close → recover |
| Special |3–4,0.3s windup then0.8s crossed guard |crown nod only when a pull succeeds; no aura |warning ground strip, emergence6–8 frames over0.6s |4–6, selected cache pulse → consume → dim |
| Hurt |existing native white flash; future2-frame recoil |same; never stretch into humanoid posture |same; expose seams without moving anchor |same; caches persist unless heal succeeds |
| Death |5–6, legs fold and armor drops |4–5, crouch/collapse, crown tips |5–6, plates slacken; no invulnerable retreat |6–8, sequential segments settle |

Proposed counts are a production handoff, not delivered frames. Keep movement clocks cosmetic; attack contact, guard windows, emergence unlock, pull and healing must follow simulation events. A missed/cancelled attack retracts visual effects without applying a hit.

## Effect contracts for a later implementation

- Crab: muted violet plate rim on guard; no giant shield polygon covering neighboring units. Damage flash remains renderer-owned.
- Frog: tongue originates at mouth and terminates at the actual hit position; separate extension/retraction, clipped to arena. Royal feedback is a crown glint, not a persistent buff ring.
- Worm: localized dark ash / orange fissure with owner-colored edge. Location is fixed during the warning except for the explicitly signaled bounded correction. No damaging particles. Show HP only from exposed emergence.
- Centipede: highlight exactly the cache being consumed; successful completion removes it, interruption restores its ordinary color. Small ore crumbs are cosmetic and grant no emeralds/items.

Native warning/tongue/effect layers would need explicit future `src.mob_assets` / draw-effect entries; none are activated here. Keep VFX dimensions/cost bounded and avoid one runtime entity per leg, ore or particle. Future live LÖVE inspection, body-layer cleanup, walking loops and direction/facing decisions remain open art tasks after the main poses are approved.
