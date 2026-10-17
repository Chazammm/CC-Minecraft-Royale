"""Inspect exported sprites and compose a preview from the exact delivered PNGs.

No painting, conversion of CC sprites, or animation generation is performed here.
Run after export.sh. Pillow is only used for inspection and contact-sheet layout.
"""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SPECS = {
    'breeze': ('Breeze', 256, 256, 128, 240, (0, 0, 570, 724)),
    'adventure_sheep': ('Adventure Sheep', 256, 256, 128, 240, (570, 0, 1250, 724)),
    'phantom': ('Phantom', 320, 256, 160, 240, (1250, 0, 2172, 724)),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect():
    master = Image.open(ROOT / 'source/sprite_master.png').convert('RGBA')
    assert master.size == (2172, 724), 'Source changed: review crop boundaries'
    approved = Image.open(ROOT / 'source/approved_concept.png')
    approved.verify()
    sprites = {}
    for name, (title, width, height, ax, ay, crop) in SPECS.items():
        path = ROOT / f'{name}.png'
        with Image.open(path) as file:
            assert file.format == 'PNG' and file.mode == 'RGBA', name
            file.verify()
        im = Image.open(path)
        assert im.size == (width, height), name
        pixels = list(im.get_flattened_data())
        assert {p[3] for p in pixels} == {0, 255}, 'Binary alpha required'
        assert all(p == (0, 0, 0, 0) for p in pixels if p[3] == 0), 'Hidden RGB fringe'
        bbox = im.getchannel('A').getbbox()
        assert bbox and 0 < bbox[0] < bbox[2] < width, 'Empty or horizontally clipped'
        assert 0 < bbox[1] < bbox[3] < height, 'Empty or vertically clipped'
        margins = [bbox[0], bbox[1], width - bbox[2], height - bbox[3]]
        assert min(margins) >= 16, 'Reserve margin for future animation'
        visible = [p for p in pixels if p[3]]
        colors = len({p[:3] for p in visible})
        assert 16 <= colors <= 48, 'Unexpected palette or empty placeholder'
        assert len(visible) > 8000, 'Unexpectedly empty sprite'
        assert 0 < ax < width and bbox[3] <= ay < height, 'Invalid base anchor'
        source_alpha = master.crop(crop).getchannel('A').point(lambda a: 255 if a >= 250 else 0)
        source_bounds = source_alpha.getbbox()
        assert source_bounds and source_bounds[0] > 0 and source_bounds[1] > 0
        assert source_bounds[2] < source_alpha.width and source_bounds[3] < source_alpha.height, 'Crop cuts character'
        sprites[name] = dict(name=title, file=path.name, width=width, height=height,
                             anchor=[ax, ay], anchorMeaning='bottom-center envelope; floating poses use same projected base',
                             pose='idle', frames=1, visibleBoundsExclusive=list(bbox),
                             visiblePixels=len(visible), visibleColors=colors, sha256=sha(path),
                             sourceCrop=list(crop))
    return dict(schema=1, status='STATIC_SPRITES_NOT_GAMEPLAY_INTEGRATED',
                filter=['nearest', 'nearest'], alpha='binary 0/255; RGB zero when transparent',
                lighting='upper left', sourceType='independently drawn high-resolution master; not CC upscale',
                sourceSha256=sha(ROOT/'source/sprite_master.png'),
                approvedConceptSha256=sha(ROOT/'source/approved_concept.png'), sprites=sprites)


def font(size):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', size)


def preview(metadata):
    sheet = Image.new('RGB', (1104, 364), '#142b2c')
    draw = ImageDraw.Draw(sheet)
    draw.text((24, 16), 'CC ROYALE / LOVE STATIC SPRITES', font=font(22), fill='#edf4f1')
    draw.text((24, 48), 'Exact PNG exports at 1:1  |  transparent assets  |  sideways mouth-held sword', font=font(13), fill='#a8c8d2')
    for i, (name, entry) in enumerate(metadata['sprites'].items()):
        sprite = Image.open(ROOT/entry['file']).convert('RGBA')
        x = i*368 + (368-sprite.width)//2
        sheet.paste(sprite, (x, 77), sprite)
        label = f"{entry['name']} / {entry['width']} x {entry['height']}"
        draw.text((i*368+184, 339), label, anchor='mm', font=font(15), fill='#edf4f1')
    return sheet


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--zip', type=Path)
    args = parser.parse_args()
    metadata = inspect()
    sheet = preview(metadata)
    if args.check:
        assert json.loads((ROOT/'index.json').read_text()) == metadata, 'Metadata changed'
        with Image.open(ROOT/'previews/roster.png') as stored:
            assert stored.mode == sheet.mode and stored.size == sheet.size
            assert stored.tobytes() == sheet.tobytes(), 'Preview differs from actual PNGs'
    else:
        (ROOT/'index.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False)+'\n')
        sheet.save(ROOT/'previews/roster.png')
    if args.zip:
        args.zip.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.zip, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(ROOT.rglob('*')):
                if not path.is_file() or '__pycache__' in path.parts or path.suffix == '.pyc':
                    continue
                entry = zipfile.ZipInfo('cc_royale_love_sprites/'+str(path.relative_to(ROOT)), (2026, 10, 17, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                archive.writestr(entry, path.read_bytes())
        with zipfile.ZipFile(args.zip) as archive:
            assert archive.testzip() is None, 'Corrupt ZIP'
        print(f'ZIP: {args.zip}')
    print('PASS: three PNGs, readable RGBA, binary alpha, clean hidden RGB, margins, anchors, palettes, source crop containment, metadata and actual-asset preview')


if __name__ == '__main__':
    main()
