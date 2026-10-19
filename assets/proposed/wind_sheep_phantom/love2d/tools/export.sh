#!/usr/bin/env bash
# Technical export of the independently drawn, approved high-resolution designs.
# Image cleanup/design uses image generation; this only splits and exports PNGs.
set -euo pipefail
asset_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export_sprite() {
  local sprite_name="$1" crop_geometry="$2" canvas_width="$3" max_width="$4"
  magick "$asset_root/source/sprite_master.png" \
    -crop "$crop_geometry" +repage \
    -channel A -threshold 98% +channel -trim +repage \
    -filter point -resize "${max_width}x224" -dither None -colors 49 \
    -channel A -threshold 50% +channel \
    -background none -gravity south -extent "${canvas_width}x240" \
    -gravity north -extent "${canvas_width}x256" \
    -background black -alpha background -strip \
    -define png:exclude-chunks=date,time \
    "PNG32:$asset_root/$sprite_name.png"
}
export_sprite breeze '570x724+0+0' 256 224
export_sprite adventure_sheep '680x724+570+0' 256 224
export_sprite phantom '922x724+1250+0' 320 288
