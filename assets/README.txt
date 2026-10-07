Battle music asset folder

Expected file:
  battle_music.dfpwm

Expected size:
  18,632,267 bytes

The game can run without this file. When present, src/music.lua reads the packed
34-track playlist using src/music_manifest.lua and shuffles tracks during battles.

The normal installer downloads the asset automatically from this folder once it
has been uploaded to the repository.
