"""Reproducible compositions from actual live renderer blits and committed PNGs."""
from pathlib import Path
import argparse,json,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
NAMES=('king_frog','nether_worm')
PALETTE=['#F0F0F0','#F2B233','#E57FD8','#99B2F2','#DEDE6C','#7FCC19','#F2B2CC','#4C4C4C','#999999','#4C99B2','#B266E5','#3366CC','#7F664C','#57A64E','#CC4C4C','#111111']
TOKENS=dict(zip('WOMAYLIDSCPBNGRK',PALETTE));BG='#152729'
def font(size):return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',size)
def decoded(frame):
 rows=frame['terminalCrop'];im=Image.new('RGB',(len(rows[0]['bytes'])*2,len(rows)*3))
 for y,row in enumerate(rows):
  for x,b in enumerate(row['bytes']):
   assert b==32 or 128<=b<=159
   for bit in range(6):
    token=row['fg'][x] if b>=128 and bit<5 and (b-128)&(1<<bit) else row['bg'][x]
    im.putpixel((x*2+bit%2,y*3+bit//2),tuple(bytes.fromhex(PALETTE[int(token,16)][1:])))
 return im

def native(frame):
 im=Image.new('RGBA',(frame['width'],frame['height']))
 for y,row in enumerate(frame['rows']):
  for x,t in enumerate(row):
   if t!='.':im.putpixel((x,y),tuple(bytes.fromhex(TOKENS[t][1:]))+(255,))
 return im

def paste(im,source,x,y,scale=1):
 source=source.resize((source.width*scale,source.height*scale),Image.Resampling.NEAREST)
 im.paste(source,(x,y),source if source.mode=='RGBA' else None)
def header(im,title,subtitle):
 d=ImageDraw.Draw(im);d.text((24,18),title,font=font(25),fill='#F2EEE1');d.text((24,57),subtitle,font=font(14),fill='#9CB4B4')
 d.line((24,89,im.width-24,89),fill='#355052')
def compositions(data):
 result={};frames=data['captures']
 sheet=Image.new('RGB',(1200,800),BG)
 header(sheet,'KING FROG + NETHER WORM / LIVE INTEGRATION','Actual shipped PNGs / registered runtime sprites / production arena -> PixelBox -> terminal blit')
 d=ImageDraw.Draw(sheet)
 for x,title in ((330,'LÖVE master / 1x'),(710,'Native / 10x'),(1000,'Actual PixelBox / 8x')):d.text((x,119),title,font=font(16),anchor='mm',fill='#9CB4B4')
 for i,key in enumerate(NAMES):
  y=145+320*i;name=key.replace('_',' ').title();hp=550 if i==0 else 350
  d.text((18,y+100),name.replace(' ','\n'),font=font(19),fill='#F2EEE1');d.text((18,y+158),f'3E / {hp}HP',font=font(15),fill='#9CB4B4')
  paste(sheet,Image.open(ROOT/'love2d'/(key+'.png')),202,y)
  raw=native(frames[key]);pic=decoded(frames[key])
  paste(sheet,raw,710-raw.width*5,y+238-raw.height*10,10);paste(sheet,pic,1000-pic.width*4,y+20,8)
  result['previews/'+key+'_native.png']=raw;result['previews/'+key+'_pixelbox.png']=pic
 result['previews/comparison.png']=sheet
 poses=Image.new('RGB',(1200,860),BG)
 header(poses,'REGISTERED NATIVE POSES / REAL PIXELBOX','4 Frog poses + 4 Worm poses + ground warning / 6x logical-pixel display / no fake HP on warning')
 for i,key in enumerate(sorted(frames)):
  pic=decoded(frames[key]);cx=200+i%3*400;y=110+i//3*245
  paste(poses,pic,cx-pic.width*3,y,6)
  ImageDraw.Draw(poses).text((cx,y+213),key.replace('_',' '),font=font(15),anchor='mm',fill='#F2EEE1')
 result['previews/runtime_poses.png']=poses
 scene=decoded(data['liveScene']);result['previews/gameplay_1x.png']=scene
 result['previews/gameplay_6x.png']=scene.resize((scene.width*6,scene.height*6),Image.Resampling.NEAREST)
 # The previous file/capture are preserved verbatim from the recorded Git
 # revision, so this review image compares actual assets and renderer output.
 review=Image.new('RGB',(1000,660),BG)
 header(review,'KING FROG / BODY + BROW REVISION','Actual 256px masters / native rows / real PixelBox captures; no concept mockups')
 old=json.loads((ROOT/'source/king_frog_before_capture.json').read_text())
 for offset,label,master,frame in (
     (0,'Vorher',ROOT/'source/king_frog_before.png',old),
     (500,'Überarbeitet',ROOT/'love2d/king_frog.png',frames['king_frog'])):
  draw=ImageDraw.Draw(review)
  draw.text((offset+250,120),label,font=font(22),anchor='mm',fill='#F2EEE1')
  paste(review,Image.open(master),offset+122,136)
  draw.text((offset+250,402),'LÖVE / 256 × 256',font=font(15),anchor='mm',fill='#9CB4B4')
  raw=native(frame);pic=decoded(frame)
  paste(review,raw,offset+145-raw.width*3,447,6)
  paste(review,pic,offset+345-pic.width*3,427,6)
  draw.text((offset+145,603),'Native CC / 6x',font=font(15),anchor='mm',fill='#9CB4B4')
  draw.text((offset+345,603),'Echte PixelBox / 6x',font=font(15),anchor='mm',fill='#9CB4B4')
 result['previews/king_frog_revision.png']=review
 return result

def validate(data,other):
 assert data==other,'Cross-Lua captures differ'
 assert data==json.loads((ROOT/'evidence/capture52.json').read_text()),'Committed capture stale'
 names=set(data['captures']);assert len(names)==9 and not any('crab' in k or 'centipede' in k for k in names)
 manifest=json.loads((ROOT/'MANIFEST.json').read_text())
 revision=manifest['kingFrogRevision']
 assert hashlib.sha256((ROOT/revision['source']).read_bytes()).hexdigest()==revision['sourceSha256']
 for path,digest in revision['beforeSha256'].items():
  assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,'Previous review source changed'
 for key in NAMES:
  im=Image.open(ROOT/'love2d'/(key+'.png'));assert im.mode=='RGBA' and im.size==(256,256)
  pixels=list(im.get_flattened_data());assert {p[3] for p in pixels}=={0,255}
  assert len({p for p in pixels if p[3]})==40
  assert all(p==(0,0,0,0) for p in pixels if not p[3])
  x1,y1,x2,y2=im.getbbox();assert min(x1,y1,256-x2,256-y2)>=16
  assert hashlib.sha256((ROOT/'love2d'/(key+'.png')).read_bytes()).hexdigest()==manifest['loveSha256'][key]
 for path,expected in compositions(data).items():
  actual=Image.open(ROOT/path)
  assert (actual.size,actual.mode,actual.tobytes())==(expected.size,expected.mode,expected.tobytes()),'Preview mismatch '+path
 assert hashlib.sha256((ROOT.parents[2]/manifest['nativeModule']).read_bytes()).hexdigest()==manifest['nativeSha256'],'Native module hash mismatch'
 assert data['liveScene']['pipeline']=='LIVE_GAMEPLAY_ARENA_AND_PIXELBOX'
 print('PASS: exact live captures, both Lua versions, 9 registered native frames, RGBA masters and exact composed previews')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--capture52',type=Path,default=ROOT/'evidence/capture52.json');p.add_argument('--capture54',type=Path,default=ROOT/'evidence/capture54.json');args=p.parse_args()
 data=json.loads(args.capture52.read_text())
 if args.check:validate(data,json.loads(args.capture54.read_text()))
 else:
  for path,im in compositions(data).items():im.save(ROOT/path,optimize=True)
  print('Composed exact live integration previews')
