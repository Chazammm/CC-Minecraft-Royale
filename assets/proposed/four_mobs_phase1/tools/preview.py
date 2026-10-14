"""Render only captured native rows and actual PixelBox terminal bytes.

No generated art is painted here; all model/effect pixels come from Lua files.
"""
from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
PALETTE=['#F0F0F0','#F2B233','#E57FD8','#99B2F2','#DEDE6C','#7FCC19','#F2B2CC','#4C4C4C',
    '#999999','#4C99B2','#B266E5','#3366CC','#7F664C','#57A64E','#CC4C4C','#111111']
# Spell it out to keep the raster contract independent of authoring code.
TOKEN={'W':PALETTE[0],'O':PALETTE[1],'M':PALETTE[2],'A':PALETTE[3],'Y':PALETTE[4],
 'L':PALETTE[5],'I':PALETTE[6],'D':PALETTE[7],'S':PALETTE[8],'C':PALETTE[9],
 'P':PALETTE[10],'B':PALETTE[11],'N':PALETTE[12],'G':PALETTE[13],'R':PALETTE[14],'K':PALETTE[15],'T':PALETTE[3]}
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font=ImageFont.truetype(FONT,22);small=ImageFont.truetype(FONT,16);title=ImageFont.truetype(FONT,32)
NAMES=['ravager_rider','baby_ender_dragon','minoshroom','hero_spider']
LABELS={'ravager_rider':'Ravager Rider','baby_ender_dragon':'Baby Ender Dragon','minoshroom':'Minoshroom','hero_spider':'Hero Spider'}

def native(frame):
 im=Image.new('RGBA',(frame['width'],frame['height']),(0,0,0,0))
 for y,row in enumerate(frame['rows']):
  for x,token in enumerate(row):
   if token!='.':im.putpixel((x,y),tuple(bytes.fromhex(TOKEN[token][1:]))+(255,))
 return im

def encoded(frame):
 rows=frame['terminalCrop'];im=Image.new('RGB',(len(rows[0]['bytes'])*2,len(rows)*3))
 for y,row in enumerate(rows):
  for x,b in enumerate(row['bytes']):
   fg=PALETTE[int(row['fg'][x],16)];bg=PALETTE[int(row['bg'][x],16)]
   assert b==32 or 128<=b<=159,(x,y,b)
   for bit in range(6):
    color=fg if b>=128 and bit<5 and ((b-128)&(1<<bit)) else bg
    im.putpixel((2*x+bit%2,3*y+bit//2),tuple(bytes.fromhex(color[1:])))
 return im

def paste(canvas,im,center,scale):
 im=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
 canvas.paste(im,(round(center[0]-im.width/2),round(center[1]-im.height/2)),im if im.mode=='RGBA' else None)

def render_sheet(data,monitor=False):
 sheet=Image.new('RGB',(1440,590),'#19272A');d=ImageDraw.Draw(sheet)
 d.text((32,22),'CC ROYALE — PHASE 1 ASSETS',font=title,fill='#F0F0F0')
 desc='Actual arena + PixelBox output · virtual monitor · no gameplay integration' if monitor else 'Native sprite files · 16 CC colours · exact pixels, enlarged without smoothing'
 d.text((32,66),desc,font=small,fill='#ADBEBC')
 for i,name in enumerate(NAMES):
  f=data['units'][name]['frames']['idle'];im=encoded(f) if monitor else native(f)
  paste(sheet,im,(180+i*360,292),10 if monitor else 16)
  d.text((180+i*360,478),LABELS[name],font=font,fill='#F0F0F0',anchor='mm')
  subtitle='Spider evolution · 2 cycles' if name=='hero_spider' else ('8 Emeralds' if name=='minoshroom' else '5 Emeralds')
  d.text((180+i*360,517),subtitle,font=small,fill='#ADBEBC',anchor='mm')
  d.text((180+i*360,544),f"{f['width']} × {f['height']} logical pixels",font=small,fill='#819694',anchor='mm')
 path=ROOT/'previews'/('monitor_roster.png' if monitor else 'native_roster.png');sheet.save(path)

def detail(data,name):
 specs={
 'ravager_rider':[('idle','Idle'),('walk_a','Walk A'),('walk_b','Walk B'),('building_hit','Ravager hit'),('rider_shot','Crossbow shot'),('combined_hit_shot','Both layers'),('fx:crossbow_bolt','Bolt'),('fx:initial_impact_a','Initial impact')],
 'baby_ender_dragon':[('idle','Idle / hover'),('flight_up','Wings up'),('flight_down','Wings down'),('attack_release','Dragon breath'),('fx:fireball_a','Ender fireball'),('fx:fireball_b','Fireball pulse'),('fx:splash_a','Splash'),('fx:splash_b','Splash fade')],
 'minoshroom':[('idle','Idle'),('walk_a','Walk A'),('walk_b','Walk B'),('windup','Axe windup'),('swing','Heavy hit'),('recovery','Recovery'),('fx:axe_hit_a','Hit graphic'),('fx:axe_hit_b','Hit fade')],
 'hero_spider':[('baseline','Normal Spider'),('idle','Hero Spider'),('walk_a','Eight-leg gait'),('web_release','Web shot'),('fx:web_projectile_a','Web projectile'),('fx:web_hit_a','Web hit'),('zombie','Visual on Zombie'),('fx:web_status','Permanent marker')]}
 sheet=Image.new('RGB',(1440,940),'#19272A');d=ImageDraw.Draw(sheet)
 d.text((32,22),LABELS[name]+' — ASSET SET',font=title,fill='#F0F0F0')
 note='Native rows above · PixelBox below · Zombie overlay shown as monitor output' if name=='hero_spider' else 'Native rows above · actual PixelBox below · prepared poses, not live mechanics'
 d.text((32,69),note,font=small,fill='#ADBEBC')
 for i,(key,label) in enumerate(specs[name]):
  row,col=divmod(i,4);cx=180+360*col;cy=260+row*390
  if key=='baseline':frame=data['comparison']['spider']
  elif key=='zombie':frame=data['webOnZombie']
  elif key.startswith('fx:'):frame=data['effects'][name]['frames'][key[3:]]
  else:frame=data['units'][name]['frames'][key]
  if key=='zombie':
   paste(sheet,encoded(frame),(cx,cy-35),7)
  else:paste(sheet,native(frame),(cx,cy-42),10 if frame['height']>12 else 13)
  paste(sheet,encoded(frame),(cx,cy+128),5 if frame['height']>12 else 6)
  d.text((cx,cy+213),label,font=font,fill='#F0F0F0',anchor='mm')
 sheet.save(ROOT/'previews'/(name+'_set.png'))

def animate(data,name,mode):
 seq=data['units'][name]['sequences'][mode];frames=[];durations=[]
 for spec in seq:
  pic=Image.new('RGB',(420,420),'#19272A');d=ImageDraw.Draw(pic)
  frame=data['units'][name]['frames'][spec['frame']]
  d.text((210,27),LABELS[name],font=font,fill='#F0F0F0',anchor='mm')
  d.text((210,59),'Real PixelBox frames · offline playback',font=small,fill='#ADBEBC',anchor='mm')
  paste(pic,encoded(frame),(210,220),10)
  d.text((210,378),mode.replace('_',' ').title(),font=small,fill='#ADBEBC',anchor='mm')
  frames.append(pic);durations.append(spec['durationMs'])
 frames[0].save(ROOT/'previews'/(name+'_'+mode+'.gif'),save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2,optimize=False)

def main():
 data=json.loads((ROOT/'evidence/captures.json').read_text())
 layout={}
 for name in NAMES:
  entries=[]
  for group in ['units','effects']:
   for key,frame in data[group][name]['frames'].items():
    entries.append((group,key,frame))
  atlas=Image.new('RGBA',(80,24*((len(entries)+3)//4)),(0,0,0,0));layout[name]={}
  for i,(group,key,frame) in enumerate(entries):
   x=20*(i%4)+2;y=24*(i//4)+3;atlas.paste(native(frame),(x,y))
   layout[name][group+'/'+key]={'x':x,'y':y,'width':frame['width'],'height':frame['height']}
  atlas.save(ROOT/'previews'/(name+'_atlas.png'))
  detail(data,name)
  for mode in data['units'][name]['sequences']:animate(data,name,mode)
 render_sheet(data);render_sheet(data,True)
 (ROOT/'previews/atlas_layout.json').write_text(json.dumps(layout,indent=2)+'\n')
 print('Native sheets, actual monitor previews, four transparent PNG atlases and offline GIF sequences saved')

if __name__=='__main__':main()
