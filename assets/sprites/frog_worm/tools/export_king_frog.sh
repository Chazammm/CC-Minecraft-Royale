#!/usr/bin/env bash
# Technical export only: generated independent master -> existing game format.
# Requires ImageMagick 7; run from repository root. No native raster is upscaled.
set -euo pipefail
root=assets/sprites/frog_worm
magick "$root/source/king_frog_revision.png" \
  -channel A -threshold 98% +channel -trim +repage \
  -filter point -resize 224x224 -dither None -colors 43 \
  -channel A -threshold 50% +channel \
  -background none -gravity south -extent 256x240 \
  -gravity north -extent 256x256 -background black -alpha background \
  -strip -define png:exclude-chunks=date,time \
  "PNG32:$root/love2d/king_frog.png"
