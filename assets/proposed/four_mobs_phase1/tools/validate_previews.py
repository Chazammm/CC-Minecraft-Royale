"""Independent PNG/atlas/GIF/source-safety and proposal-arithmetic checks."""
from pathlib import Path
import json,hashlib,math,sys,re
from PIL import Image
from preview import native,encoded,NAMES,TOKEN
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
checks=0
def check(ok,message):
 global checks;checks+=1
 assert ok,message
def blob(data):return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
def main():
 data=json.loads((ROOT/'evidence/captures.json').read_text())
 layout=json.loads((ROOT/'previews/atlas_layout.json').read_text())
 pngs,gifs=0,0
 for name in NAMES:
  with Image.open(ROOT/'previews'/(name+'_atlas.png')) as atlas:
   check(atlas.mode=='RGBA','Native atlas must retain transparency')
   for key,rect in layout[name].items():
    group,frame=key.split('/');src=data[group][name]['frames'][frame]
    x,y,w,h=rect['x'],rect['y'],rect['width'],rect['height']
    check(x>=0 and y>=0 and x+w<=atlas.width and y+h<=atlas.height,'Atlas clip')
    check(atlas.crop((x,y,x+w,y+h)).tobytes()==native(src).tobytes(),'PNG pixels differ from actual Lua-row capture')
  for key,seq in data['units'][name]['sequences'].items():
   with Image.open(ROOT/'previews'/(name+'_'+key+'.gif')) as gif:
    check(gif.n_frames==len(seq),'GIF dropped a required frame')
    for i,spec in enumerate(seq):
     gif.seek(i);check(gif.info['duration']==spec['durationMs'],'Wrong animation preview timing')
     expected=encoded(data['units'][name]['frames'][spec['frame']])
     # Inspect the displayed image centre, not its labels/background.
     x=round(210-expected.width*10/2);y=round(220-expected.height*10/2)
     actual=gif.convert('RGB').crop((x,y,x+expected.width*10,y+expected.height*10))
     target=expected.resize(actual.size,Image.Resampling.NEAREST)
     check(actual.tobytes()==target.tobytes(),'GIF is not the actual PixelBox frame')
  check(len({json.dumps(f['terminalCrop'],sort_keys=True) for f in data['units'][name]['frames'].values()})
   ==len(data['units'][name]['frames']),'Distinct poses collapsed in actual PixelBox capture')
 for path in (ROOT/'previews').glob('*'):
  if path.suffix in ['.png','.gif']:
   with Image.open(path) as im:im.verify()
   pngs+=path.suffix=='.png';gifs+=path.suffix=='.gif'
   check(path.stat().st_size>0,'Empty preview')
 guard=json.loads((ROOT/'evidence/baseline_guard.json').read_text())
 for path,sha in guard['baselineBlobSha'].items():
  original=(REPO/path).read_bytes()
  if path=='docs/AUDIT_REGISTER.md':
   text=original.decode()
   # Only one deliberately isolated feature-registration block may be added.
   cleaned,n=re.subn(r'\n### VIS-003.*?(?=\n\| ID \| Classification / priority)', '',text,flags=re.S)
   check(n==1,'Missing/duplicated Phase-1 audit registration')
   original=cleaned.encode()
  check(blob(original)==sha,'Existing file modified outside the Phase-1 documentation: '+path)
 p=json.loads((ROOT/'BALANCE_PROPOSALS.json').read_text());r=data['reference']
 hero=p['hero_spider'];spider=r['spider']['unit'];golem=r['iron_golem']['unit'];mino=p['minoshroom']
 check(p['status']=='PROPOSALS_ONLY_NOT_REGISTERED_NOT_SIMULATED','Proposals falsely marked active')
 for k,m in [('maxHp',1.1),('damage',1.02),('moveSpeed',1),('attackRange',1)]:
  check(math.isclose(hero[k],spider[k]*m,rel_tol=1e-12),'Incorrect derived Spider '+k)
 check(math.isclose(hero['attackCooldown'],spider['attackCooldown']/1.02,rel_tol=1e-12),'Attack frequency bonus calculated as interval percentage')
 check(hero['cost']==r['spider']['cost'] and hero['cycles']==2,'Incorrect Evo cost/cycles proposal')
 check(r['zombie']['unit']['maxHp']/2<=mino['damage']<r['zombie']['unit']['maxHp'],'Zombie would not require exactly two isolated hits')
 check(p['arithmeticOnly']['zombieHitsToKill']==2 and p['arithmeticOnly']['zombieHpAfterOneHit']==223,'Incorrect two-hit arithmetic')
 check(p['ravager_rider']['damage']==golem['damage']*2 and p['ravager_rider']['attackCooldown']==golem['attackCooldown']*2,'Incorrect required Ravager scaling')
 report={'status':'PASS','checks':checks,'pngs':pngs,'gifs':gifs,'baselineFilesVerified':len(guard['baselineBlobSha']),
  'gameplayIntegration':'NOT_STARTED','newGameplayTests':'NOT_TESTED','physicalMonitor':'NOT_TESTED'}
 out=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'evidence/preview_validation.json'
 out.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report))
if __name__=='__main__':main()
