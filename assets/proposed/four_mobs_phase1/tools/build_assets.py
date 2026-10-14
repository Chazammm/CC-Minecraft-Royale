"""Author original native CC palette-token art; never edit production assets.

Lua row files are the deliverable. PNG/GIF previews are rendered from those
files by the independent Lua capture tool, not drawn by this authoring script.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
TOKENS = '.KWSDGLBACRYNPMOI T'.replace(' ', '')

class Canvas:
    def __init__(self,w,h):self.w=w;self.h=h;self.p=[['.']*w for _ in range(h)]
    def put(self,x,y,c):
        assert 0<=x<self.w and 0<=y<self.h,(x,y,self.w,self.h)
        assert c in TOKENS;c0=self.p[y][x];self.p[y][x]=c;return c0
    def rect(self,x1,y1,x2,y2,c):
        for y in range(y1,y2+1):
            for x in range(x1,x2+1):self.put(x,y,c)
    def line(self,x1,y1,x2,y2,c):
        dx=abs(x2-x1);dy=-abs(y2-y1);sx=1 if x1<x2 else -1;sy=1 if y1<y2 else -1;err=dx+dy
        while True:
            self.put(x1,y1,c)
            if x1==x2 and y1==y2:break
            e=2*err
            if e>=dy:err+=dy;x1+=sx
            if e<=dx:err+=dx;y1+=sy
    def stamp(self,x,y,rows):
        for dy,row in enumerate(rows):
            for dx,c in enumerate(row):
                if c!='.':self.put(x+dx,y+dy,c)
    def frame(self):return {'width':self.w,'height':self.h,'rows':[''.join(r) for r in self.p]}

def lua(value,indent=0):
    if isinstance(value,str):return json.dumps(value,ensure_ascii=True)
    if isinstance(value,bool):return 'true' if value else 'false'
    if isinstance(value,(int,float)):return repr(value)
    pad='    '*(indent+1)
    if isinstance(value,list):return '{\n'+''.join(pad+lua(v,indent+1)+',\n' for v in value)+'    '*indent+'}'
    return '{\n'+''.join(pad+'['+lua(k)+'] = '+lua(v,indent+1)+',\n' for k,v in value.items())+'    '*indent+'}'

def save(kind,name,data):
    data={'assetSchema':1,'id':name,'phase':'PHASE_1_ONLY','runtimeRegistered':False,
          'format':'CC_ROYALE_PALETTE_TOKEN_ROWS','frameStatus':'PREPARED_STATIC_RASTER_NOT_LIVE_ANIMATION',**data}
    (ROOT/kind/(name+'.lua')).write_text('-- Original Phase-1 art. Data only; deliberately absent from install.lua and all runtime imports.\nreturn '+lua(data)+'\n')

def sequence(*frames):return [{'frame':frame,'durationMs':duration} for frame,duration in frames]

def ravager(pose):
    c=Canvas(16,18)
    # Four square legs; two-depth hooves read as a quadruped, not a biped.
    c.rect(2,13,13,14,'D');c.rect(3,14,4,16,'S');c.rect(11,14,12,16,'S')
    c.rect(2,16,4,17,'K');c.rect(11,16,13,17,'K')
    c.rect(5,14,6,16,'D');c.rect(9,14,10,16,'D');c.rect(5,16,6,16,'K');c.rect(9,16,10,16,'K')
    if pose=='walk_a':c.rect(2,17,4,17,'.');c.rect(10,17,13,17,'K')
    if pose=='walk_b':c.rect(11,17,13,17,'.');c.rect(1,17,4,17,'K')
    c.rect(1,9,14,13,'D');c.rect(2,9,12,10,'S');c.rect(2,11,4,12,'S')
    c.rect(5,8,11,9,'N');c.rect(6,9,10,9,'R')
    # Massive square face, white horns, dark brow, broad nostrils and jaw.
    head_y=10 if pose not in ('building_hit','combined_hit_shot') else 11
    if pose=='building_windup':head_y=9
    c.rect(5,head_y,12,head_y+4,'S');c.rect(5,head_y,12,head_y,'D')
    c.rect(6,head_y+1,7,head_y+1,'K');c.rect(10,head_y+1,11,head_y+1,'K')
    c.rect(6,head_y+2,11,head_y+3,'D');c.put(6,head_y+3,'K');c.put(11,head_y+3,'K')
    c.rect(7,head_y+4,10,head_y+4,'S')
    c.stamp(2,head_y-1,['W..','WWS']);c.stamp(13,head_y-1,['..W','SWW'])
    # Group secondary shades inside one 2x3 cell: avoid ambiguous colour ties.
    c.put(10,15,'S')
    # Pillager's distinct green eyes, grey head and burgundy/brown tunic.
    c.rect(5,4,10,6,'N');c.rect(6,4,9,4,'R');c.rect(6,6,9,7,'D')
    c.rect(4,5,5,6,'S');c.rect(10,5,11,6,'S')
    c.stamp(5,0,['SSSSS','SGSGS','SGSGS','SSNSS','SSDSS'])
    # Crossbow arm and stock occupy clear negative space on the right.
    if pose=='rider_reload':
        c.stamp(10,3,['.SNN..','NN.NS.','.NN...'])
    else:
        c.stamp(10,4,['...S..','.NNNSN','NNNN..','...N..'])
        if pose in ('rider_shot','combined_hit_shot'):c.put(15,4,'W');c.put(15,6,'Y')
    return c.frame()

def dragon(pose):
    c=Canvas(16,16)
    # Ribbed triangular wings; poses move wings while the oversized head stays stable.
    if pose in ('flight_up','attack_charge'):
        c.stamp(0,3,['DK..........KD','DPK........KPD','DPPK......KPPD','DPPPK....KPPPD','DKPPPK..KPPPKD'])
    elif pose=='flight_down':
        c.stamp(0,8,['.KK........KK.','KDPK......KP DK'.replace(' ',''),'DKPPK....KPPKD','.DKPPK..KPPKD.','..DKK....KKD..'])
    else:
        c.stamp(0,6,['KKK........KKK','DPPK......KPPD','DPPPK....KPPPD','DKPPPK..KPPPKD','.DKKK....KKKD.'])
    c.rect(8,6,10,11,'K');c.rect(8,9,9,11,'P');c.rect(10,9,11,12,'K')
    c.stamp(10,11,['...DKK','..DKK.','DKKK..'])
    # Short folded paws and a curled tail: no humanoid legs/Enderman silhouette.
    c.rect(5,9,7,10,'K');c.rect(5,11,6,11,'S')
    c.rect(9,12,10,12,'K');c.rect(10,13,11,13,'S')
    # Wide dragon skull with a projecting muzzle and tiny ivory fangs.
    c.rect(5,1,12,6,'K');c.rect(6,1,11,1,'D')
    c.rect(6,0,7,1,'S');c.rect(10,0,11,1,'S');c.put(6,0,'W');c.put(11,0,'W')
    c.rect(5,3,6,4,'P');c.rect(10,3,11,4,'P')
    c.rect(2,5,8,7,'K');c.rect(2,5,7,5,'D');c.rect(3,7,7,7,'D')
    c.put(2,6,'D');c.put(3,6,'K');c.put(4,7,'W');c.put(7,7,'W')
    if pose=='attack_charge':c.rect(2,6,4,6,'P');c.put(3,6,'M')
    if pose=='attack_release':c.rect(2,6,4,7,'M');c.rect(2,6,3,6,'W')
    return c.frame()

def minoshroom(pose):
    c=Canvas(16,18)
    # Lower mooshroom body with four separately visible legs/hooves.
    c.rect(2,11,12,14,'R');c.rect(2,11,4,12,'W');c.rect(10,13,12,14,'W')
    c.rect(6,12,8,13,'W');c.put(8,14,'R')
    for x in [2,5,9,12]:
        c.rect(x,14,x+1,16,'R');c.rect(x,16,x+1,17,'K')
    if pose=='walk_a':c.rect(2,17,3,17,'.');c.rect(9,17,10,17,'.')
    if pose=='walk_b':c.rect(5,17,6,17,'.');c.rect(12,17,13,17,'.')
    # Raised taur torso: heavy shoulders/arms, fur chest, white hide accents.
    c.rect(4,6,10,10,'N');c.rect(5,7,6,8,'R');c.rect(8,7,9,8,'R');c.rect(6,9,8,10,'D')
    c.rect(1,7,3,10,'N');c.rect(1,10,3,11,'R');c.rect(10,7,12,10,'N')
    c.stamp(4,1,['.RRRRR.','RRRRRRR','RKRRRKR','RNNNNNR','.NKKN..'])
    c.stamp(0,1,['W...','SS..','.SSS']);c.stamp(11,1,['...W','..SS','SSS.'])
    # Head mushroom and a smaller cap on the cow's haunch.
    c.stamp(6,0,['RWR','WWW']);c.stamp(2,9,['RWR','WWW','.N.'])
    # Original mob uses a diamond minotaur axe. One-handed heavy blade.
    if pose=='windup':
        c.line(11,8,13,2,'N');c.stamp(12,0,['CWAC','CWWC','.CC.']);c.rect(10,6,12,7,'R')
    elif pose=='swing':
        c.line(10,9,14,12,'N');c.stamp(12,11,['.CC.','CWWC','CAAC']);c.rect(10,9,12,10,'R')
    elif pose=='recovery':
        c.line(11,9,13,14,'N');c.stamp(12,10,['.CC.','CWWC','CAAC','.CC.']);c.rect(10,9,12,10,'R')
    else:
        c.line(12,6,13,13,'N');c.stamp(12,5,['.CC.','CWWC','CWAC','.CC.']);c.rect(11,9,12,10,'R')
    return c.frame()

def hero(pose):
    c=Canvas(16,10)
    # Four fan-shaped legs on EACH side; eight endpoints remain distinct.
    tips=[(0,1),(0,4),(0,7),(2,9),(15,1),(15,4),(15,7),(13,9)]
    if pose=='walk_a':tips=[(0,0),(0,4),(1,7),(2,8),(15,1),(14,4),(15,8),(13,9)]
    if pose=='walk_b':tips=[(0,1),(1,4),(0,8),(2,9),(15,0),(15,4),(14,7),(13,8)]
    for i,(x,y) in enumerate(tips):
        left=i<4;hipx=5 if left else 10;hipy=2+(i%4)
        jx=2 if left else 13;jy=y if i%4<2 else y-1
        c.line(hipx,hipy,jx,jy,'B');c.line(jx,jy,x,y,'R' if i%4<2 else 'B')
    c.stamp(5,0,['BBKBBB','BBKBBB','BKKKBB','BBKBBB'])
    # Red face, two large white comic eyes, black centre/web seam.
    c.stamp(4,3,['RRKRRKRR','RWWKKWWR','RWWRRWWR','RRKRRKRR'])
    c.stamp(6,7,['RKKR'])
    if pose=='web_charge':c.stamp(6,7,['RWWR'])
    if pose=='web_release':c.stamp(6,7,['WWWW']);c.rect(7,8,8,8,'W');c.put(6,6,'R')
    if pose=='melee_bite':c.stamp(6,7,['WKKW']);c.rect(7,8,8,8,'R')
    f=c.frame();f['limbTips']=[[x+1,y+1] for x,y in tips];return f

def effect(rows):
    w=max(map(len,rows));c=Canvas(w,len(rows));c.stamp(0,0,[r.ljust(w,'.') for r in rows]);return c.frame()

def main():
    save('sprites','ravager_rider',{'design':'Ravager quadruped plus grey Pillager and crossbow, one entity',
        'frames':{p:ravager(p) for p in ['idle','walk_a','walk_b','building_windup','building_hit','rider_reload','rider_shot','combined_hit_shot']},
        'previewSequences':{'walk':sequence(('idle',240),('walk_a',160),('idle',180),('walk_b',160)),
            'building_attack':sequence(('idle',500),('building_windup',180),('building_hit',160),('idle',500)),
            'rider_shot':sequence(('idle',500),('rider_reload',150),('rider_shot',150),('idle',500)),
            'combined':sequence(('walk_a',160),('combined_hit_shot',150),('walk_b',160),('idle',500))}})
    save('sprites','baby_ender_dragon',{'design':'Large baby dragon head, purple eyes, horns, ribbed wings, curved tail',
        'frames':{p:dragon(p) for p in ['idle','flight_up','flight_down','attack_charge','attack_release']},
        'previewSequences':{'fly':sequence(('flight_up',180),('idle',180),('flight_down',180),('idle',180)),
            'attack':sequence(('idle',500),('attack_charge',220),('attack_release',150),('idle',500))}})
    save('sprites','minoshroom',{'design':'Twilight Forest taur anatomy: mooshroom lower body, four hooves, horns, mushrooms, diamond axe',
        'frames':{p:minoshroom(p) for p in ['idle','walk_a','walk_b','windup','swing','recovery']},
        'previewSequences':{'walk':sequence(('idle',260),('walk_a',220),('idle',260),('walk_b',220)),
            'attack':sequence(('idle',500),('windup',300),('swing',150),('recovery',250),('idle',500))}})
    save('sprites','hero_spider',{'design':'Nonhumanoid Minecraft spider: eight legs, blue abdomen, red web-patterned mask and white eyes',
        'frames':{p:hero(p) for p in ['idle','walk_a','walk_b','web_charge','web_release','melee_bite']},
        'previewSequences':{'walk':sequence(('idle',180),('walk_a',120),('idle',180),('walk_b',120)),
            'web':sequence(('idle',500),('web_charge',200),('web_release',150),('idle',500)),
            'melee':sequence(('idle',500),('melee_bite',150),('idle',500))}})
    fx={
        'ravager_rider':{'crossbow_bolt':effect(['......S.','.NNNNNSW','......S.']),
            'muzzle':effect(['..Y..','.WYW.','..Y..']),
            'initial_impact_a':effect(['...S...','.S...S.','..WWW..','S.WKW.S','..WWW..','.S...S.','...S...']),
            'initial_impact_b':effect(['S.....S','..S.S..','.S...S.','...D...','.S...S.','..S.S..','S.....S'])},
        'baby_ender_dragon':{'fireball_a':effect(['..P..','.PMP.','PMWMP','.PMP.','..P..']),
            'fireball_b':effect(['.P.W.','PMMMP','.MWM.','PMMMP','.P.P.']),
            'splash_a':effect(['....M....','...MPM...','..MPWPM..','.MPWWWPM.','MPWWKWWPM','.MPWWWPM.','..MPWPM..','...MPM...','....M....']),
            'splash_b':effect(['..P...P..','P..M.M..P','.M.....M.','..M...M..','....P....','..M...M..','.M.....M.','P..M.M..P','..P...P..'])},
        'minoshroom':{'axe_hit_a':effect(['....W...','...WW...','..WW....','.WW.....','WW......','...SS...','..S..S..']),
            'axe_hit_b':effect(['..S.....','......S.','S.......','...S....','.......S','..S..S..','........'])},
        'hero_spider':{'web_projectile_a':effect(['..W..','.WSW.','WSWSW','.WSW.','..W..']),
            'web_projectile_b':effect(['.W.W.','W.S.W','.SWS.','W.S.W','.W.W.']),
            'web_hit_a':effect(['W...W...W','.W..W..W.','..W.W.W..','...WWW...','WWWWWWWWW','...WWW...','..W.W.W..','.W..W..W.','W...W...W']),
            'web_hit_b':effect(['..S...S..','S..S.S..S','.S.....S.','..S...S..','....W....','..S...S..','.S.....S.','S..S.S..S','..S...S..']),
            'web_status':effect(['WSW','SWS','WSW'])}}
    for name,frames in fx.items():save('effects',name,{'runtimeDispatchStatus':'NOT_IMPLEMENTED_REQUIRES_PHASE_2',
        'damageSemantics':'VISUAL_ONLY_NO_COMBAT_FUNCTIONS','frames':frames})
    print('Authored 8 data-only Lua sets: 25 unit frames + 15 projectile/effect frames')

if __name__=='__main__':main()
