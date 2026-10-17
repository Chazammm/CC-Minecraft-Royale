"""Compose actual native definitions / real PixelBox captures; no painted mockups."""
from pathlib import Path
import argparse,hashlib,json,base64
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
COLORS=['#F0F0F0','#F2B233','#E57FD8','#99B2F2','#DEDE6C','#7FCC19','#F2B2CC','#4C4C4C','#999999','#4C99B2','#B266E5','#3366CC','#7F664C','#57A64E','#CC4C4C','#111111']
TOKENS=dict(zip('WOMAYLIDSCPBNGRK',COLORS));BG='#152729';FG='#F0F0F0';MUTED='#99B2F2'
NAMES={'breeze':'Breeze','adventure_sheep':'Adventure Sheep','phantom':'Phantom'}
POSES=['idle','idle_b','move_a','move_b','windup','dive','attack','recovery','hit','hit_flash','death_a','death_b','death_c']

def rgb(color):return tuple(bytes.fromhex(color[1:]))
def font(n):return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',n)
def native(frame):
 im=Image.new('RGBA',(frame['width'],frame['height']))
 for y,row in enumerate(frame['rows']):
  for x,t in enumerate(row):
   if t!='.':im.putpixel((x,y),rgb(TOKENS[t])+(255,))
 return im

def decoded(frame):
 rows=frame['terminalCrop'];im=Image.new('RGB',(len(rows[0]['bytes'])*2,len(rows)*3))
 for y,row in enumerate(rows):
  for x,b in enumerate(row['bytes']):
   assert b==32 or 128<=b<=159
   for bit in range(6):
    color=row['fg'][x] if b>=128 and bit<5 and (b-128)&(1<<bit) else row['bg'][x]
    im.putpixel((2*x+bit%2,3*y+bit//2),rgb(COLORS[int(color,16)]))
 return im

def paste(im,pic,cx,y,scale):
 pic=pic.resize((pic.width*scale,pic.height*scale),Image.Resampling.NEAREST)
 im.paste(pic,(round(cx-pic.width/2),y),pic if pic.mode=='RGBA' else None)
def text(im,xy,s,size=18,color=FG,anchor=None):ImageDraw.Draw(im).text(xy,s,font=font(size),fill=color,anchor=anchor)
def header(im,title,sub):
 text(im,(22,18),title,25);text(im,(22,54),sub,14,MUTED)
 ImageDraw.Draw(im).line((22,86,im.width-22,86),fill='#4C99B2')

def compositions(data):
 out={};roster=Image.new('RGB',(1120,590),BG)
 header(roster,'BREEZE / ADVENTURE SHEEP / PHANTOM','Isolated CC prototypes / real PixelBox captures / no registered cards or live sprite changes')
 for i,(key,name) in enumerate(NAMES.items()):
  unit=data['units'][key];cx=190+i*370
  text(roster,(cx,120),name,22,anchor='mm')
  paste(roster,native(unit['frames']['idle']),cx,170,8)
  text(roster,(cx,335),'Native 16×18 / 8×',15,MUTED,'mm')
  paste(roster,decoded(unit['frames']['idle']),cx,365,6)
  text(roster,(cx,565),'Actual PixelBox / 6×',15,MUTED,'mm')
 out['previews/roster.png']=roster
 for key,name in NAMES.items():
  unit=data['units'][key];keys=[p for p in POSES if p in unit['frames']]
  sheet=Image.new('RGB',(1120,110+230*((len(keys)+3)//4)),BG)
  header(sheet,name.upper()+' / NATIVE POSES','Native (left, 5×) and actual PixelBox (right, 5×) / isolated data / no simulated damage')
  for i,pose in enumerate(keys):
   frame=unit['frames'][pose];col=i%4;row=i//4;left=col*280;top=110+row*230
   paste(sheet,native(frame),left+70,top+25,5);paste(sheet,decoded(frame),left+205,top+5,5)
   text(sheet,(left+140,top+182),pose.replace('_',' '),16,anchor='mm')
   out[f'previews/frames/{key}/{pose}_native.png']=native(frame)
   out[f'previews/frames/{key}/{pose}_pixelbox.png']=decoded(frame)
  out[f'previews/{key}_sheet.png']=sheet
  out[f'icons/{key}.png']=native(unit['icon'])
  out[f'previews/frames/{key}/removed_pixelbox.png']=decoded({'terminalCrop':unit['frames']['death_c']['clearedCrop']})
  for name,frame in data['showcases'][key]['frames'].items():out[f'previews/frames/{key}/{name}_pixelbox.png']=decoded(frame)
 variants=Image.new('RGB',(1040,500),BG)
 header(variants,'ADVENTURE SHEEP / SILHOUETTE COMPARISON','Two hand-authored native designs / actual PixelBox / selection is a visual judgement')
 for i,(key,label) in enumerate((('side_selected','Selected: side / three-quarter'),('front_rejected','Alternative: front-biased'))):
  cx=260+i*520;frame=data['variants'][key]
  text(variants,(cx,120),label,18,anchor='mm')
  paste(variants,native(frame),cx-110,190,7);paste(variants,decoded(frame),cx+110,170,6)
  text(variants,(cx-110,370),'Native / 7×',15,MUTED,'mm');text(variants,(cx+110,370),'PixelBox / 6×',15,MUTED,'mm')
 out['previews/sheep_variants.png']=variants
 icons=Image.new('RGB',(1040,500),BG)
 header(icons,'DECK ICON PROPOSALS / 12×12 NATIVE PIXELS','Optional compact icon layout / current live deckbuilder is text-only / no UI change')
 for i,(key,name) in enumerate(NAMES.items()):
  cx=175+345*i;item=data['units'][key]['icon']
  text(icons,(cx,120),name,20,anchor='mm')
  paste(icons,native(item),cx-75,185,10);paste(icons,decoded(item),cx+85,160,8)
  text(icons,(cx,385),'Native icon → actual PixelBox',14,MUTED,'mm')
  text(icons,(cx,435),('BREEZE / 3E','ADV.SHEEP / 4E','PHANTOM / 4E')[i],17,anchor='mm')
 out['previews/deck_icons.png']=icons
 fx=Image.new('RGB',(1120,560),BG)
 header(fx,'NATIVE EFFECT PROTOTYPES','Wind charge / wind gust / sword arc / dive trail / no physics or damage logic')
 items=[(key,pose,f) for key in NAMES for pose,f in data['effects'][key]['frames'].items()]
 for i,(key,pose,frame) in enumerate(items):
  cx=140+(i%4)*280;top=120+(i//4)*210
  paste(fx,decoded(frame),cx,top,6);text(fx,(cx,top+165),pose.replace('_',' '),14,anchor='mm')
 out['previews/effects.png']=fx
 for viewer,scenes in data['scenes'].items():
  for i,scene in enumerate(scenes):out[f'previews/arena_p{viewer}_{i}.png']=decoded(scene)
  preview=Image.new('RGB',(750,840),BG)
  header(preview,f'STAGED ARENA / VIEWER {viewer}','6 concept overlays + 6 existing units / actual arena + PixelBox / not a combat simulation')
  paste(preview,decoded(scenes[2]),375,115,6)
  out[f'previews/arena_p{viewer}.png']=preview
 return out


def gif_palette():
 colors=COLORS+[BG,FG,MUTED,'#4C99B2']
 vals=[value for color in colors for value in rgb(color)]
 im=Image.new('P',(1,1));im.putpalette(vals+[0]*(768-len(vals)))
 return im

def animations(data):
 palette=gif_palette();result={}
 for key,name in NAMES.items():
  unit=data['units'][key]
  for action,seq in unit['sequences'].items():
   images=[];times=[]
   for step in seq:
    im=Image.new('RGB',(490,360),BG)
    header(im,name.upper()+' / '+action.upper(),'Actual isolated CC → PixelBox / 6× logical pixels')
    paste(im,decoded(unit['frames'][step['frame']]),245,115,6)
    text(im,(245,320),step['frame'].replace('_',' '),17,MUTED,'mm')
    images.append(im.quantize(palette=palette,dither=Image.Dither.NONE));times.append(step['durationMs'])
   if action=='death':
    im=Image.new('RGB',(490,360),BG)
    header(im,name.upper()+' / DEATH','Actual cleared capture / sprite and HP bar removed')
    paste(im,decoded({'terminalCrop':unit['frames']['death_c']['clearedCrop']}),245,115,6)
    text(im,(245,320),'removed',17,MUTED,'mm')
    images.append(im.quantize(palette=palette,dither=Image.Dither.NONE));times.append(600)
   result[f'previews/{key}_{action}.gif']=(images,times)
 for key,show in data['showcases'].items():
  images=[];times=[]
  for step in show['sequence']:
   im=Image.new('RGB',(590,380),BG)
   header(im,NAMES[key].upper()+' / ATTACK + EFFECTS','Actual shared PixelBox canvas / visual timing only / no gameplay behavior')
   paste(im,decoded(show['frames'][step['frame']]),295,120,6)
   text(im,(295,340),step['pose'],17,MUTED,'mm')
   images.append(im.quantize(palette=palette,dither=Image.Dither.NONE));times.append(step['durationMs'])
  result[f'previews/{key}_showcase.gif']=(images,times)
 for viewer,scenes in data['scenes'].items():
  images=[]
  for scene in scenes:
   im=Image.new('RGB',(750,840),BG)
   header(im,f'STAGED ARENA / VIEWER {viewer}','Visual timing study / no attacks, pathfinding or knockback are simulated')
   paste(im,decoded(scene),375,115,6)
   images.append(im.quantize(palette=palette,dither=Image.Dither.NONE))
  result[f'previews/arena_p{viewer}.gif']=(images,[400,300,200,400])
 return result


def review_html(data):
 frames={}
 for key,unit in data['units'].items():
  frames[key]={name:base64.b64encode((ROOT/f'previews/frames/{key}/{name}_pixelbox.png').read_bytes()).decode() for name in unit['frames']}
 sequences={k:dict(v['sequences']) for k,v in data['units'].items()}
 for key in frames:
  frames[key]['removed']=base64.b64encode((ROOT/f'previews/frames/{key}/removed_pixelbox.png').read_bytes()).decode()
  sequences[key]['death']=sequences[key]['death']+[{'frame':'removed','durationMs':600}]
 for key,show in data['showcases'].items():
  for name in show['frames']:frames[key][name]=base64.b64encode((ROOT/f'previews/frames/{key}/{name}_pixelbox.png').read_bytes()).decode()
  sequences[key]['attack_fx']=show['sequence']
 payload=json.dumps({'units':frames,'sequences':sequences},ensure_ascii=False)
 return '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>CC Royale – isolierte Kartenentwürfe</title>
<style>body{background:#152729;color:#f0f0f0;font:17px system-ui;max-width:1120px;margin:32px auto;padding:0 18px}h1{font-size:28px}p{color:#b9cbcb}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:20px}article{background:#203639;padding:20px;border-radius:12px}img{image-rendering:pixelated;width:192px;height:216px;object-fit:contain;display:block;margin:20px auto}button,select,input{font:inherit;margin:5px;padding:7px;background:#304c50;color:white;border:1px solid #4c99b2;border-radius:5px}label{display:block}small{color:#b9cbcb}a{color:#99b2f2}</style>
<h1>CC Royale – Breeze, Adventure Sheep, Phantom</h1><p>Isolierte CC-Sprite-Prototypen. Die Bilder zeigen echte PixelBox-Captures eines virtuellen Monitors. Keine Karte ist registriert; Vorschauzustände lösen keine Spielmechanik aus.</p>
<button id="play">Pause</button><button id="reset">Von vorn</button><label>Tempo <input id="speed" type="range" min="0.5" max="2" step="0.25" value="1"><span id="speedvalue">1×</span></label><section id="cards"></section>
<p><a href="roster.png">Roster</a> · <a href="sheep_variants.png">Schafvarianten</a> · <a href="arena_p1.gif">Gestellte Arenaszene</a> · <a href="deck_icons.png">Icon-Vorschläge</a></p><small>Die Live-Deckansicht ist weiterhin textbasiert. Todessequenzen halten im Viewer am letzten Frame an; GIF-Dateien wiederholen sich für den Vergleich. Kein Hardware-Benchmark.</small>
<script>const data=PAYLOAD;let playing=true,speed=1;const state={};for(const key of ['breeze','adventure_sheep','phantom']){const a=document.createElement('article');const name={breeze:'Breeze',adventure_sheep:'Adventure Sheep',phantom:'Phantom'}[key];a.innerHTML=`<h2>${name}</h2><select aria-label="Animation für ${name}">${Object.keys(data.sequences[key]).map(s=>`<option>${s}</option>`).join('')}</select><img alt="Echte PixelBox-Vorschau von ${name}"><label>Frame <input aria-label="Frame für ${name}" type="range" min="0" value="0"></label><small></small>`;document.querySelector('#cards').appendChild(a);state[key]={a,action:'idle',index:0,elapsed:0};const slider=a.querySelector('input');a.querySelector('select').onchange=e=>{Object.assign(state[key],{action:e.target.value,index:0,elapsed:0});show(key)};slider.oninput=e=>{state[key].index=+e.target.value;state[key].elapsed=0;show(key)};show(key)}function show(key){const s=state[key],steps=data.sequences[key][s.action],step=steps[s.index];const img=s.a.querySelector('img');img.onload=()=>{img.style.width=img.naturalWidth*6+'px';img.style.height=img.naturalHeight*6+'px'};img.src='data:image/png;base64,'+data.units[key][step.frame];s.a.querySelector('input').max=steps.length-1;s.a.querySelector('input').value=s.index;s.a.querySelector('small').textContent=step.frame+' · '+step.durationMs+' ms'}document.querySelector('#reset').onclick=()=>{for(const key in state){state[key].index=0;state[key].elapsed=0;show(key)}};document.querySelector('#play').onclick=e=>{playing=!playing;e.target.textContent=playing?'Pause':'Abspielen'};document.querySelector('#speed').oninput=e=>{speed=+e.target.value;document.querySelector('#speedvalue').textContent=speed+'×'};let last=performance.now();function tick(now){const dt=Math.min(100,now-last)*speed;last=now;if(playing)for(const key in state){const s=state[key],steps=data.sequences[key][s.action];s.elapsed+=dt;if(s.elapsed>=steps[s.index].durationMs){s.elapsed-=steps[s.index].durationMs;if(s.index<steps.length-1)s.index++;else if(s.action!=='death')s.index=0;else{s.elapsed=0;continue}show(key)}}requestAnimationFrame(tick)}requestAnimationFrame(tick);</script></html>'''.replace('PAYLOAD',payload)


def main():
 parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
 data=json.loads((ROOT/'evidence/captures52.json').read_text());other=json.loads((ROOT/'evidence/captures54.json').read_text())
 assert data==other,'Lua versions produced different captures'
 for file,expected in compositions(data).items():
  path=ROOT/file
  if args.check:
   actual=Image.open(path);assert (actual.mode,actual.size,actual.tobytes())==(expected.mode,expected.size,expected.tobytes()),file
  else:path.parent.mkdir(parents=True,exist_ok=True);expected.save(path)
 for file,(frames,durations) in animations(data).items():
  path=ROOT/file
  if args.check:
   actual=Image.open(path);assert actual.n_frames==len(frames),file
   for i,(expected,ms) in enumerate(zip(frames,durations)):
    actual.seek(i);assert actual.info['duration']==ms,(file,i,'duration')
    assert actual.convert('RGB').tobytes()==expected.convert('RGB').tobytes(),(file,i,'pixels')
  else:frames[0].save(path,save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2,optimize=False)
 html=review_html(data)
 if args.check:assert (ROOT/'previews/review.html').read_text()==html,'Stale interactive review'
 else:(ROOT/'previews/review.html').write_text(html)
 print(('PASS: exact PNG/GIF/HTML previews and cross-Lua captures' if args.check else 'Composed actual native/Pix elBox PNGs, 20 animation GIFs and interactive review').replace('Pix el','Pixel'))
if __name__=='__main__':main()
