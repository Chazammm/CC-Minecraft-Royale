# Visual review — first round, 2026-10-15

Reviewed art revision: `22952924d1dceed8e01c85d63ed3fd7780229946`.
**Recommendation: request visual changes before approving the full set.**
This is an assistant's art audit, not owner approval. Technical validation and
previous green CI results remain valid for that revision; they do not establish
that the artwork meets the requested visual standard.

## Evidence inspected

- Existing approved roster, `assets/sprites/approved-model-revamp-1.webp`.
- Actual exported [LÖVE roster](new_mob_roster.png), including the [2× inspection](evidence/love_pixel_inspection.png).
- Actual [native CC rows](cc_native_roster.png), [arena/PixelBox captures](cc_tweaked_roster.png) and [side-by-side comparison](sprite_comparison.png).
- Source-derived Raptor and Chimera reference views retained in the working
  environment, plus the inspected Ad Astra Java model. Primary source revision
  links and reference limits remain in [README.md](README.md).

This round evaluates the delivered images and the captured virtual monitor.
It makes no claim about a physical Minecraft monitor.

## Findings

| Priority | Mob / platform | Visible finding | Recommended correction |
| --- | --- | --- | --- |
| High | Piglich / CC | The pale boar snout and tusks do not read clearly. Two large red blocks dominate the head. Crown points flatten into a yellow band after PixelBox encoding, and gold trim becomes a broad apron-like shape. The master's characteristic face and clothing are weakened. | Reserve a stronger pale snout/tusk cluster; reduce eye area; distinguish crown silhouette and charcoal coat from narrower gold trim. Check the emitted terminal pixels after each change. |
| High | Martian Raptor / CC | The master has a long balancing tail and a low forward body. The native version is much more upright and the tail reads as a short side projection. Green regions also lose separation against arena grass. | Reallocate existing pixels from head/upper body to a longer tail and a lower horizontal silhouette; keep two hind feet and pale jaw/claw cues. Improve body/background contrast within the existing palette. |
| High | Sculk Behemoth / CC | The broad plated shoulders, huge clawed hands and weight of the master become a relatively thin humanoid outline. The bright visor survives, but it dominates more than the shoulder mass or claws. | Increase solid shoulder/forearm mass inside the existing footprint; make hands/claws distinct; preserve a narrow visor and a readable chest fracture. Avoid relying on outline pixels alone. |
| Medium | Wilden Chimera / CC | Four legs and the dark face remain readable, but the folded wing becomes a brown hump/curl and orange spikes have little visual presence. Large cyan foot blocks depart from the master's darker green treatment, although they do improve grass contrast. | Make the folded wing silhouette more angular and wing-like; group a few orange spike pixels so they survive encoding. Reassess paw size and shade without losing leg separation. |
| Medium | Cyclops / CC | The single eye is the strongest identity cue in the native set. Pink torso/arm dots look like separate spots rather than coherent skin shading; hands and overall body mass could be clearer. | Keep the eye layout; simplify skin highlights into fewer coherent clusters and improve the arm/hand endpoints. |
| Medium | Whole set / LÖVE style | The masters share lighting and Minecraft-like volumes, but their heavily shaded three-quarter rendering is noticeably more sculptural than the flatter, mainly frontal approved roster. Pixel-level detail alone does not establish seamless style continuity. | In the next art pass, reduce surface noise and prioritise larger clean planes and clearer frontal shapes, while retaining the requested high-resolution detail. |
| Reference review | Martian Raptor / LÖVE | Small front clawlets remain an acknowledged interpretation. The inspected source has no separately named forelimb bones. Their canonical status is unresolved. | Verify against an authoritative in-game view of the target mod version, or remove the unverified additions before claiming faithful reproduction. Do not infer anatomy solely from missing bone names. |

## Positive findings

- All five masters have distinct silhouettes and consistent upper-left lighting.
- Piglich crown, skull-like face and dark/gold clothing are visible in the master.
- Cyclops retains one dominant eye in both resolutions.
- Wilden Chimera follows Ars Nouveau's specific white quadruped, dark face,
  horn/wing/spike design rather than a generic multi-headed chimera.
- The custom Behemoth has strong shoulder plates, recessed head and large claws
  in its master, with a recognisable cyan energy treatment.
- Transparent margins and complete body visibility make the files usable as
  assets; no portrait-only crops were used.

## Decision and next pass

Do not treat the ten files as visually approved production art yet. The main
remaining work is a native CC art pass, prioritising **Piglich, Raptor and
Behemoth**, followed by Chimera wing/spike readability and Cyclops shading.
LÖVE style continuity and the Raptor reference question also remain open.

This review changes no sprite pixels, gameplay data or renderer behaviour.
The existing PNGs remain available unchanged so the owner can compare them
with these findings. Final design acceptance belongs to the owner; no merge
or activation follows from this audit.
