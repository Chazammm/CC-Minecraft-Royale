"""Asset integrity and real-renderer oracles, independent of runtime activation."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from PIL import Image
from export_love import export
from render_previews import ROOT,NAMES,TOKENS,native,encoded,compositions,gif_frames
p=argparse.ArgumentParser()
for name,default in [('capture52','pixelbox_lua52.json'),('capture54','pixelbox_lua54.json'),('monitor52','full_monitor_lua52.json'),('monitor54','full_monitor_lua54.json')]:p.add_argument('--'+name,type=Path,default=ROOT/'evidence'/default)
p.add_argument('--snapshot',type=Path,default=ROOT/'balance/current_cards.json')
a=p.parse_args();checks=0

def check(ok,message):
 global checks;checks+=1
 assert ok,message

def same(left,right,message):check(left.mode==right.mode and left.size==right.size and left.tobytes()==right.tobytes(),message)
def read(path):return json.loads(path.read_text())
m=read(ROOT/'MANIFEST.json');data=read(a.capture52);other=read(a.capture54)
monitor=read(a.monitor52);monitor_other=read(a.monitor54)
check(data==other,'Lua 5.2/5.4 capture mismatch')
check(monitor==monitor_other,'Lua 5.2/5.4 full monitor mismatch')
check(data==read(ROOT/'evidence/pixelbox_lua52.json'),'Committed native capture stale')
check(monitor==read(ROOT/'evidence/full_monitor_lua52.json'),'Committed full monitor stale')
check(set(m['assets'])==set(NAMES),'Incomplete design set')
check(len(data)==13 and set(data)==set(m['nativePoses']),'Incomplete native pose set')
module=(ROOT/'cc_tweaked/sprites.lua').read_text()
for key,frame in data.items():
 block=re.search(r'\b'+key+r' = \{(.*?)\n    \}',module,re.S)
 check(block is not None,'Capture key absent in Lua source '+key)
 rows=re.findall(r'"([.A-Z]+)"',block.group(1))
 check(rows==frame['rows'],'Lua rows/capture disagree '+key)
 check(1<=frame['width']<=16 and 1<=frame['height']<=18,'Footprint overflow '+key)
 check(len(rows)==frame['height'] and all(len(r)==frame['width'] for r in rows),'Ragged rows '+key)
 check(set(''.join(rows))<=set(TOKENS)|{'.'},'Bad token '+key)
 check('.' in ''.join(rows) and sum(c!='.' for r in rows for c in r)>30,'Empty or opaque background '+key)
 check(all(len(r['bytes'])==len(r['fg'])==len(r['bg']) for r in frame['terminalCrop']),'Broken blit '+key)
# Critical identity cues must survive lossy two-colour sextant encoding.
def cue(key,bounds,token):
 pic=encoded(data[key]);rgb=tuple(bytes.fromhex(TOKENS[token][1:]));x1,y1,x2,y2=bounds
 return {(x,y) for y in range(y1,y2) for x in range(x1,x2) if pic.getpixel((x+4,y+6))==rgb}
check(bool(cue('netherite_crab',(0,0,6,5),'O')) and bool(cue('netherite_crab',(10,0,16,5),'O')),'Claw interiors disappeared')
check(bool(cue('netherite_crab',(0,7,16,12),'C')),'Crab legs disappeared')
for region in [(2,0,4,2),(6,0,8,2),(10,0,12,2)]:check(len(cue('king_frog',region,'Y'))>=2,'Crown tip disappeared')
for region in [(2,4,4,6),(10,4,12,6)]:check(len(cue('king_frog',region,'K'))>=2,'Frog pupil disappeared')
check(len(cue('nether_worm',(0,11,10,16),'W'))>=4,'Worm teeth disappeared')
check(bool(cue('nether_worm',(0,0,16,11),'O')),'Worm seam disappeared')
for region,t in [((4,0,6,3),'O'),((8,0,10,3),'A'),((12,0,14,3),'R')]:check(len(cue('ore_centipede',region,t))>=4,'Ore cache disappeared '+t)
for key in NAMES:
 spec=m['assets'][key];path=ROOT/spec['loveFile']
 with Image.open(path) as source:
  check(source.format=='PNG' and source.mode=='RGBA','Invalid PNG '+key);im=source.copy()
 width=384 if key in ('netherite_crab','ore_centipede') else 256
 check(im.size==(width,256)==tuple(spec['loveDimensions']),'Master canvas '+key)
 pixels=list(im.get_flattened_data());opaque=[v for v in pixels if v[3]]
 check({v[3] for v in pixels}=={0,255},'Non-binary/missing alpha '+key)
 check(all(v==(0,0,0,0) for v in pixels if not v[3]),'Hidden matte '+key)
 check(len(opaque)>15000 and len(set(opaque))==40,'Empty/poorly controlled master '+key)
 x1,y1,x2,y2=im.getbbox()
 check(min(x1,y1,width-x2,256-y2)>=16,'Clipped body / missing margin '+key)
 check(238<=y2<=240 and spec['loveAnchor']==[width//2,240],'Foot anchor drift '+key)
 check(spec['loveBounds']==list(im.getbbox()),'Bounds stale '+key)
 same(im,export(key),'Export differs from independent source '+key)
 points={(x,y) for y in range(256) for x in range(width) if im.getpixel((x,y))[3]}
 todo=[next(iter(points))];seen=set(todo)
 while todo:
  x,y=todo.pop()
  for dx,dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)):
   point=x+dx,y+dy
   if point in points and point not in seen:seen.add(point);todo.append(point)
 check(len(seen)==len(points),'Detached alpha specks '+key)
 same(native(data[key]),Image.open(ROOT/spec['nativePreview']),'Native PNG mismatch '+key)
 same(encoded(data[key]),Image.open(ROOT/spec['pixelboxPreview']),'PixelBox PNG mismatch '+key)
 for path,digest in spec['sha256'].items():check(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,'Hash mismatch '+path)
 frames,durations=gif_frames(data,key)
 with Image.open(ROOT/'previews'/(key+'_study.gif')) as gif:
  check(gif.n_frames==len(frames),'Missing study frames '+key)
  for i,expected in enumerate(frames):
   gif.seek(i);check(gif.info['duration']==durations[i],'Wrong study duration '+key)
   # Captured arena pixels must survive GIF encoding; captions may be quantized.
   same(gif.convert('RGB').crop((0,20,360,330)),expected.crop((0,20,360,330)),'GIF is not the actual capture '+key)
for path,digest in m['hashes'].items():check(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,'Hash mismatch '+path)
for path,expected in compositions(data,monitor).items():same(Image.open(ROOT/path),expected,'Composed preview differs '+path)
current=read(ROOT/'balance/current_cards.json');fresh=read(a.snapshot)
check(current==fresh,'Baseline card snapshot differs from current engine')
check(len(current['cards'])==25 and len({x['id'] for x in current['cards']})==25,'Baseline count changed')
proposals=read(ROOT/'balance/proposals.json')
check(proposals['status']=='proposal_only_not_playable_not_balance_validated','Proposal mislabeled')
check({x['id'] for x in proposals['cards']}==set(NAMES),'Missing card concept')
check(not set(NAMES)&{x['id'] for x in current['cards']},'Proposals became playable')
proposed={x['id']:x for x in proposals['cards']}
w=proposed['nether_worm'];ore=proposed['ore_centipede']
check(w['placement']=='all_arena_walkable_ground' and not w['ability']['reburrow'],'Worm arena-wide contract lost')
check(w['ability']['warning']+w['ability']['exposedEmergence']==2,'Warning/emergence timing changed')
check(w['damage']*w['ability']['structureMultiplier']==33.25,'Structure damage arithmetic')
check(ore['ability']['charges']*ore['ability']['healPerCharge']==360 and not ore['ability']['arenaMining'],'Finite reserve changed')
repo=ROOT.parents[2]
if (repo/'.git').exists():
 changed=subprocess.check_output(['git','diff','--name-only',m['baseRevision']],cwd=repo,text=True).splitlines()
 check(all(x.startswith('assets/proposed/custom_mobs/') or x=='.github/workflows/custom-mob-concepts.yml' for x in changed),'Unexpected production-file changes: '+repr(changed))
print(f'PASS: {checks} asset contracts; PNG/alpha/source export, 13 native poses, critical cues, exact previews/GIFs, cross-Lua real captures, baseline stats, additive scope')
