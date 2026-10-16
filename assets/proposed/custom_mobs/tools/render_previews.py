"""Compose exact asset files and decoded *real* PixelBox output, never concept mockups."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
NAMES=('netherite_crab','king_frog','nether_worm','ore_centipede')
LABELS=('Netherite Crab','King Frog','Nether Worm','Ore Centipede')
PALETTE=['#F0F0F0','#F2B233','#E57FD8','#99B2F2','#DEDE6C','#7FCC19','#F2B2CC','#4C4C4C','#999999','#4C99B2','#B266E5','#3366CC','#7F664C','#57A64E','#CC4C4C','#111111']
TOKENS=dict(zip('WOMAYLIDSCPBNGRK',PALETTE));BG='#152729'
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def font(size):return ImageFont.truetype(FONT,size)
def native(frame):
 im=Image.new('RGBA',(frame['width'],frame['height']))
 for y,row in enumerate(frame['rows']):
  for x,t in enumerate(row):
   if t!='.':im.putpixel((x,y),tuple(bytes.fromhex(TOKENS[t][1:]))+(255,))
 return im

def encoded(frame):
 rows=frame['terminalCrop'];im=Image.new('RGB',(2*len(rows[0]['bytes']),3*len(rows)))
 for y,row in enumerate(rows):
  for x,b in enumerate(row['bytes']):
   assert b==32 or 128<=b<=159
   fg=PALETTE[int(row['fg'][x],16)];bg=PALETTE[int(row['bg'][x],16)]
   for bit in range(6):
    c=fg if b>=128 and bit<5 and (b-128)&(1<<bit) else bg
    im.putpixel((x*2+bit%2,y*3+bit//2),tuple(bytes.fromhex(c[1:])))
 return im

def paste(im,asset,xy,scale=1):
 if scale!=1:asset=asset.resize((asset.width*scale,asset.height*scale),Image.Resampling.NEAREST)
 im.paste(asset,xy,asset if asset.mode=='RGBA' else None)
def header(im,title,subtitle):
 d=ImageDraw.Draw(im);d.text((28,20),title,font=font(27),fill='#F2EEE1')
 d.text((28,62),subtitle,font=font(14),fill='#9CB4B4');d.line((28,94,im.width-28,94),fill='#355052')

def compositions(data,monitor_data=None):
 result={}
 if monitor_data is None:monitor_data=json.loads((ROOT/'evidence/full_monitor_lua52.json').read_text())
 full=encoded(monitor_data)
 result['previews/virtual_monitor_1x.png']=full
 result['previews/virtual_monitor_6x.png']=full.resize((full.width*6,full.height*6),Image.Resampling.NEAREST)
 love=Image.new('RGB',(1600,460),BG)
 header(love,'CC ROYALE / CUSTOM MOB DESIGN MASTERS','Four proposed cards / independent RGBA masters / upper-left light / nearest filter / not activated')
 raw=Image.new('RGB',(1600,480),BG)
 header(raw,'CC ROYALE / NATIVE CC SPRITES','Hand-authored palette rows / 12x nearest / 1x source-size swatches below / maximum 16 x 18')
 monitor=Image.new('RGB',(1600,520),BG)
 header(monitor,'CC ROYALE / REAL PIXELBOX OUTPUT','src.pixel_arena -> pixelbox_lite -> terminal blit / 51 x 40 virtual monitor / 10x logical-pixel magnification')
 compare=Image.new('RGB',(1280,1450),BG)
 header(compare,'CC ROYALE / DUAL PLATFORM COMPARISON','Exact committed files / real terminal bytes / palette loss is visible rather than concealed')
 d=ImageDraw.Draw(compare)
 for x,title in ((390,'LÖVE master / 1x'),(800,'Native CC / 10x'),(1090,'PixelBox / 7x')):d.text((x,122),title,font=font(17),anchor='mm',fill='#9CB4B4')
 for i,(key,label) in enumerate(zip(NAMES,LABELS)):
  asset=Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA')
  logical=native(data[key]);pix=encoded(data[key]);cx=200+400*i
  result['cc_tweaked/previews/'+key+'.png']=logical
  result['cc_tweaked/previews/'+key+'_pixelbox.png']=pix
  paste(love,asset,(cx-asset.width//2,110))
  paste(raw,logical,(cx-logical.width*6,330-logical.height*12),12);paste(raw,logical,(cx-8,420))
  paste(monitor,pix,(cx-pix.width*5,120),10)
  for sheet,y in ((love,391),(raw,382),(monitor,451)):
   ImageDraw.Draw(sheet).text((cx,y),label,font=font(21),anchor='mm',fill='#F2EEE1')
  ImageDraw.Draw(love).text((cx,426),f'{asset.width} x {asset.height} / RGBA',font=font(14),anchor='mm',fill='#9CB4B4')
  ImageDraw.Draw(monitor).text((cx,484),f"{logical.width} x {logical.height} native / two colours per 2x3 cell",font=font(13),anchor='mm',fill='#9CB4B4')
  y=160+320*i
  d.text((20,y+112),label.replace(' ','\n'),font=font(19),fill='#F2EEE1')
  paste(compare,asset,(390-asset.width//2,y))
  paste(compare,logical,(800-logical.width*5,y+240-logical.height*10),10)
  paste(compare,pix,(1090-pix.width*7//2,y+25),7)
  d.line((20,y+301,1260,y+301),fill='#294344')
 result.update({'previews/high_res_roster.png':love,'previews/cc_native_roster.png':raw,'previews/pixelbox_roster.png':monitor,'previews/comparison.png':compare})
 poses=Image.new('RGB',(1400,1100),BG)
 header(poses,'NATIVE POSES / REAL PIXELBOX CAPTURES','Isolated visual studies / no gameplay state machine or live animation registration')
 for i,key in enumerate(sorted(data)):
  pix=encoded(data[key]);cx=175+(i%4)*350;y=115+(i//4)*240
  paste(poses,pix,(cx-pix.width*3,y),6)
  ImageDraw.Draw(poses).text((cx,y+207),key.replace('_',' '),font=font(13),anchor='mm',fill='#F2EEE1')
 result['previews/native_poses.png']=poses
 selected=Image.new('RGB',(1280,810),BG)
 header(selected,'KING FROG + NETHER WORM / SECOND REVIEW','Selected for subsequent implementation / exact LÖVE files and actual PixelBox bytes / design only')
 d=ImageDraw.Draw(selected)
 for x,title in ((390,'LÖVE master / 1x'),(800,'Native CC / 10x'),(1090,'PixelBox / 7x')):d.text((x,122),title,font=font(17),anchor='mm',fill='#9CB4B4')
 proposals=json.loads((ROOT/'balance/proposals.json').read_text())
 specs={c['id']:c for c in proposals['cards']}
 for i,key in enumerate(('king_frog','nether_worm')):
  y=160+320*i;spec=specs[key]
  d.text((20,y+85),spec['name'].replace(' ','\n'),font=font(19),fill='#F2EEE1')
  d.text((20,y+145),f"{spec['cost']}E / {spec['hp']}HP",font=font(16),fill='#9CB4B4')
  asset=Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA');logical=native(data[key]);pic=encoded(data[key])
  paste(selected,asset,(390-asset.width//2,y))
  paste(selected,logical,(800-logical.width*5,y+240-logical.height*10),10)
  paste(selected,pic,(1090-pic.width*7//2,y+25),7)
  d.line((20,y+301,1260,y+301),fill='#294344')
 result['previews/selected_pair_review.png']=selected
 return result

SEQUENCES={
 'netherite_crab': [('netherite_crab',700),('netherite_crab_guard',800),('netherite_crab',500)],
 'king_frog':[('king_frog',700),('king_frog_tongue',280),('king_frog',500)],
 'nether_worm':[('nether_worm_warning',1400),('nether_worm_emerging',600),('nether_worm',250),('nether_worm_bite',250),('nether_worm',600)],
 'ore_centipede':[('ore_centipede',600),('ore_centipede_feeding',1000),('ore_centipede_reserve_2',700),('ore_centipede_reserve_1',700),('ore_centipede_reserve_0',700)]}
def gif_frames(data,key):
 frames=[];durations=[]
 for pose,duration in SEQUENCES[key]:
  im=Image.new('RGB',(360,380),BG);pic=encoded(data[pose]);paste(im,pic,((360-pic.width*10)//2,30),10)
  ImageDraw.Draw(im).text((180,350),pose.replace('_',' '),font=font(15),anchor='mm',fill='#F2EEE1')
  frames.append(im);durations.append(duration)
 return frames,durations

def main():
 data=json.loads((ROOT/'evidence/pixelbox_lua52.json').read_text())
 for path,im in compositions(data).items():im.save(ROOT/path,optimize=True)
 for key in NAMES:
  frames,durations=gif_frames(data,key)
  frames[0].save(ROOT/'previews'/(key+'_study.gif'),save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=False)
 print('Exact LÖVE / native / real PixelBox / comparison sheets + 4 native pose-study GIFs')
if __name__=='__main__':main()
