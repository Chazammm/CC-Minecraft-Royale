"""Independent contracts plus exact source/export/preview and cross-Lua oracles."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
from PIL import Image
from export_love import export
from render_previews import ROOT, NAMES, TOKENS, encoded, native, compositions
parser=argparse.ArgumentParser()
parser.add_argument('--capture52',type=Path,default=ROOT/'evidence/pixelbox_lua52.json')
parser.add_argument('--capture54',type=Path,default=ROOT/'evidence/pixelbox_lua54.json')
args=parser.parse_args()
manifest=json.loads((ROOT/'MANIFEST.json').read_text())
left=json.loads(args.capture52.read_text());right=json.loads(args.capture54.read_text())
module=(ROOT/'cc_tweaked/sprites.lua').read_text()
checks=0

def check(value,message):
 global checks;checks+=1
 assert value,message

def identical(a,b,message):
 check(a.mode==b.mode and a.size==b.size and a.tobytes()==b.tobytes(),message)

check(set(manifest['assets'])==set(NAMES),'Incomplete manifest')
for key in NAMES:
 spec=manifest['assets'][key]
 with Image.open(ROOT/spec['loveFile']) as original:
  check(original.format=='PNG' and original.mode=='RGBA','Not an RGBA PNG '+key)
  im=original.copy()
 check(im.size==(256,256),'Bad master size '+key)
 pixels=list(im.getdata());opaque=[p for p in pixels if p[3]]
 check(set(p[3] for p in pixels)=={0,255},'Soft/missing alpha '+key)
 check(all(p==(0,0,0,0) for p in pixels if p[3]==0),'Matte hidden in transparent RGB '+key)
 check(len(opaque)>10000,'Empty or undersized art '+key)
 check(24<=len(set(opaque))<=40,'Uncontrolled/placeholder colour count '+key)
 check(list(im.getbbox())==spec['loveBounds'],'Stale bounds '+key)
 x1,y1,x2,y2=im.getbbox()
 check(min(x1,y1,256-x2,256-y2)>=16,'Sprite touches crop boundary '+key)
 check(spec['loveAnchor']==[128,240] and 238<=y2<=240,'Inconsistent foot anchor '+key)
 identical(im,export(key),'Export does not reproduce actual design source '+key)
 # Require one eight-connected silhouette: detached matte pixels are not art.
 points={(x,y) for y in range(256) for x in range(256) if im.getpixel((x,y))[3]}
 pending=[next(iter(points))];seen=set(pending)
 while pending:
  x,y=pending.pop()
  for dx,dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)):
   p=(x+dx,y+dy)
   if p in points and p not in seen:seen.add(p);pending.append(p)
 check(len(seen)==len(points),'Detached alpha artifacts '+key)
 block=re.search(r'\b'+key+r' = \{(.*?)\n    \}',module,re.S).group(1)
 rows=re.findall(r'"([.A-Z]+)"',block)
 for capture in [left,right]:
  frame=capture[key]
  check(rows==frame['rows'],'Capture stale against native Lua source '+key)
  check([frame['width'],frame['height']]==spec['nativeDimensions'],'Stale native dimensions '+key)
  check(all(len(r)==frame['width'] and not set(r)-set(TOKENS)-{'.'} for r in rows),'Broken native rows '+key)
 identical(encoded(left[key]),encoded(right[key]),'Visible cross-Lua encoder differences '+key)
 identical(native(left[key]),Image.open(ROOT/spec['nativePreview']),'Native PNG mismatch '+key)
 for path,sha in spec['sha256'].items():
  check(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==sha,'Asset hash mismatch '+path)
check(hashlib.sha256((ROOT/'cc_tweaked/sprites.lua').read_bytes()).hexdigest()==manifest['nativeModuleSha256'],'Native module hash stale')
for path,expected in compositions(left).items():
 identical(Image.open(ROOT/path),expected,'Preview not composed from actual files '+path)
# Critical cues must survive the actual lossy terminal encoder, in their source region.
# The crop adds four logical pixels left and six above the aligned sprite origin.
regions={'piglich':(4,3,12,5,'R'),'martian_raptor':(3,4,5,6,'W'),
         'cyclops':(6,3,10,6,'K'),'wilden_chimera':(2,8,8,10,'R'),
         'sculk_behemoth':(6,6,10,8,'A')}
for key,(x1,y1,x2,y2,t) in regions.items():
 pic=encoded(left[key]);rgb=tuple(bytes.fromhex(TOKENS[t][1:]))
 check(any(pic.getpixel((x+4,y+6))==rgb for y in range(y1,y2) for x in range(x1,x2)),
       'Identity cue lost during encoding '+key)
# This feature is strictly additive; fail if any pre-existing tracked path changes.
repo=ROOT.parents[2]
if (repo/'.git').exists():
 changed=subprocess.check_output(['git','diff','--name-only',manifest['baseRevision']],cwd=repo,text=True).splitlines()
 check(all(p.startswith('assets/sprites/new_mobs/') or p=='.github/workflows/new-mob-assets.yml' for p in changed),
       'Unexpected existing-file/gameplay changes: '+repr(changed))
print(f'PASS: {checks} asset checks; source exports, alpha, dimensions, cues, palettes, hashes, exact previews, cross-Lua pixels and additive-only scope')
