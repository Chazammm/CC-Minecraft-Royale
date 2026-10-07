Battle music asset folder

Expected file:
  battle_music.dfpwm

Expected HQ size:
  37,028,677 bytes

Encoding:
  DFPWM, mono, native 48 kHz
  Pre-filtered for CC:Tweaked speakers

The game streams this packed 34-track playlist from GitHub and uses
src/music_manifest.lua for track boundaries and shuffle order.

If the HTTP stream is interrupted, src/music.lua reconnects automatically and
skips a persistently broken track instead of stopping the match.
