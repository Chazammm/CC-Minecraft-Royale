"""Technical export of independently generated design masters; never upscales CC rows.

Preserve the source PNGs. Nearest sampling, binary alpha and a 40-colour
no-dither export provide clean logical pixels for nearest-filtered LÖVE drawing.
"""
from pathlib import Path
from PIL import Image
import json, hashlib
ROOT = Path(__file__).resolve().parents[1]
NAMES = ('piglich', 'martian_raptor', 'cyclops', 'wilden_chimera', 'sculk_behemoth')

def export(name):
    source = Image.open(ROOT / 'source' / (name + '.png')).convert('RGBA')
    # Generated opaque interiors use 253 alpha; discard soft edge/matte pixels.
    alpha = source.getchannel('A').point(lambda a: 255 if a >= 250 else 0)
    source.putalpha(alpha)
    crop = source.crop(alpha.getbbox())
    scale = min(224 / crop.width, 224 / crop.height)
    size = (round(crop.width * scale), round(crop.height * scale))
    crop = crop.resize(size, Image.Resampling.NEAREST)
    # Quantize only visible pixels: transparent RGB/matte never enters the palette.
    points = [rgb[:3] for rgb in crop.getdata() if rgb[3]]
    strip = Image.new('RGB', (len(points), 1)); strip.putdata(points)
    strip = strip.quantize(colors=40, method=Image.Quantize.MEDIANCUT,
                           dither=Image.Dither.NONE).convert('RGB')
    colors = iter(strip.getdata())
    crop.putdata([next(colors) + (255,) if p[3] else (0, 0, 0, 0)
                  for p in crop.getdata()])
    result = Image.new('RGBA', (256, 256))
    offset = ((256 - crop.width) // 2, 240 - crop.height)
    result.paste(crop, offset)
    # Discard detached alpha specks introduced by generation/matte extraction.
    # The design has one connected character and no floating particles.
    points = {(x,y) for y in range(256) for x in range(256) if result.getpixel((x,y))[3]}
    groups = []
    while points:
        todo = [points.pop()]; group = set(todo)
        while todo:
            x,y = todo.pop()
            for dx,dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)):
                p = x+dx,y+dy
                if p in points:
                    points.remove(p); group.add(p); todo.append(p)
        groups.append(group)
    for group in groups:
        if len(group)<=2:
            for p in group: result.putpixel(p,(0,0,0,0))
    return result

if __name__ == '__main__':
    for name in NAMES:
        export(name).save(ROOT / 'love2d' / (name + '.png'), optimize=True)
    print('Exported five 256x256 RGBA masters; 40 opaque colours, binary alpha, foot line y=240')
