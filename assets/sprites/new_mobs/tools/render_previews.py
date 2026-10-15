"""Compose previews exclusively from committed sprites and real PixelBox bytes."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1]
NAMES = ('piglich','martian_raptor','cyclops','wilden_chimera','sculk_behemoth')
LABELS = ('Piglich','Martian Raptor','Cyclops','Wilden Chimera','Sculk Behemoth')
ORIGINS = ('Allthemodium','Ad Astra','Ice and Fire','Ars Nouveau','Original · Deep Dark')
PALETTE = ['#F0F0F0','#F2B233','#E57FD8','#99B2F2','#DEDE6C','#7FCC19','#F2B2CC','#4C4C4C',
           '#999999','#4C99B2','#B266E5','#3366CC','#7F664C','#57A64E','#CC4C4C','#111111']
TOKENS = dict(zip('WOMAYLIDSC PBNGRK'.replace(' ',''), PALETTE))
BG = '#152729'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def font(size): return ImageFont.truetype(FONT,size)
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
    d=ImageDraw.Draw(im);d.text((32,22),title,font=font(29),fill='#F2EEE1')
    d.text((32,64),subtitle,font=font(15),fill='#9CB4B4')
    d.line((32,98,im.width-32,98),fill='#355052')

def compositions(data):
    result={}
    love=Image.new('RGB',(1600,460),BG)
    header(love,'CC ROYALE / NEW MOB DESIGN MASTERS','LÖVE · 256 × 256 RGBA · shared light direction · five independent designs')
    for i,(key,label,origin) in enumerate(zip(NAMES,LABELS,ORIGINS)):
        asset=Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA')
        paste(love,asset,(32+320*i,108))
        d=ImageDraw.Draw(love);d.text((160+320*i,393),label,font=font(20),anchor='mm',fill='#F2EEE1')
        d.text((160+320*i,425),origin,font=font(14),anchor='mm',fill='#9CB4B4')
    result['new_mob_roster.png']=love
    cc=Image.new('RGB',(1600,550),BG)
    header(cc,'CC ROYALE / PIXELBOX MONITOR ROSTER','Real arena + PixelBox sextants · default CC palette · 10× nearest-neighbour · virtual monitor capture')
    raw=Image.new('RGB',(1600,480),BG)
    header(raw,'CC ROYALE / NATIVE PIXEL ROSTER','Actual palette-token rows · 12× nearest-neighbour · 1× source-size swatches below')
    for i,(key,label) in enumerate(zip(NAMES,LABELS)):
        frame=data[key];logical=native(frame);displayed=encoded(frame)
        result['cc_tweaked/previews/'+key+'.png']=logical
        result['cc_tweaked/previews/'+key+'_pixelbox.png']=displayed
        paste(cc,displayed,(160+320*i-displayed.width*5,126),10)
        d=ImageDraw.Draw(cc);d.text((160+320*i,458),label,font=font(20),anchor='mm',fill='#F2EEE1')
        d.text((160+320*i,493),f"{frame['width']} × {frame['height']} native pixels",font=font(14),anchor='mm',fill='#9CB4B4')
        paste(raw,logical,(64+320*i,130+216-logical.height*12),12)
        d=ImageDraw.Draw(raw);d.text((160+320*i,383),label,font=font(20),anchor='mm',fill='#F2EEE1')
        paste(raw,logical,(152+320*i,417))
    result['cc_tweaked_roster.png']=cc;result['cc_native_roster.png']=raw
    compare=Image.new('RGB',(1120,1480),BG)
    header(compare,'CC ROYALE / DUAL-PLATFORM COMPARISON','Exact shipped files · LÖVE design master / deliberate CC reduction / actual PixelBox output')
    d=ImageDraw.Draw(compare)
    for x,title in [(290,'LÖVE · 256²'),(660,'CC · native rows, 10×'),(940,'PixelBox · 7×')]:
        d.text((x,122),title,font=font(16),anchor='mm',fill='#9CB4B4')
    for i,(key,label) in enumerate(zip(NAMES,LABELS)):
        y=150+i*260
        d.line((32,y+255,1088,y+255),fill='#294344')
        d.text((20,y+110),label.replace(' ','\n'),font=font(16),fill='#F2EEE1')
        paste(compare,Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA'),(160,y))
        logical=native(data[key]);pix=encoded(data[key])
        paste(compare,logical,(580,y+240-logical.height*10),10)
        paste(compare,pix,(940-pix.width*7//2,y+30),7)
    result['sprite_comparison.png']=compare
    # Fast visual inspection of actual exported masters at 2× pixel magnification.
    detail=Image.new('RGB',(1536,1100),BG)
    header(detail,'DESIGN MASTER / PIXEL INSPECTION','256 px sources enlarged exactly 2× · all visible pixels opaque · no smoothing')
    for i,key in enumerate(NAMES):
        x=i%3*512;y=110+i//3*490
        paste(detail,Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA'),(x,y),2)
    result['evidence/love_pixel_inspection.png']=detail
    return result

def main():
    data=json.loads((ROOT/'evidence/pixelbox_lua52.json').read_text())
    for path,im in compositions(data).items():
        im.save(ROOT/path,optimize=True)
    print('Composed native, real PixelBox, LÖVE and comparison sheets from actual asset files')
if __name__=='__main__': main()
