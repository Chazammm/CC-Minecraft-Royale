Battle music is intentionally NOT stored as large binary blobs on the current
main branch.

The active manifest pins both DFPWM packs to an immutable historical commit, so
existing audio bytes and track offsets can never drift when main changes:

  src/music_manifest.lua

Current packs:
  battle_music_1.dfpwm  (17,476,124 bytes)
  battle_music_2.dfpwm  (19,552,553 bytes)

Encoding:
  DFPWM, mono, native 48 kHz

Tracks 1-17 are in part 1.
Tracks 18-34 are in part 2.

The game streams the selected byte range directly from the pinned pack URL and
shuffles all 34 tracks as one playlist. Keeping the packs out of the current
working tree makes fresh shallow checkouts/CI much smaller while preserving the
exact audio through immutable Git object history.

When replacing the music library, upload/version new packs first and update
src/music_manifest.lua to immutable URLs for that exact pack revision. Never
point the manifest at a moving /main/ asset URL.
