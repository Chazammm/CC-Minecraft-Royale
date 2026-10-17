"""Hand-authored palette-row prototypes. Exports isolated Lua data, no live imports.

The rows below are the editable pixel-art source. Poses use deliberate row edits;
there is no conversion from a concept image, and no production sprite is touched.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
TOKENS = set('.WOMAYLIDSCPBNGRK')


def frame(rows, width=16, height=18):
    rows = list(rows)
    assert len(rows) <= height
    for row in rows:
        assert len(row) <= width, (len(row), row)
        assert set(row) <= TOKENS, row
    return {'width': width, 'height': height,
            'rows': [row.ljust(width, '.') for row in rows] + ['.' * width] * (height-len(rows))}


def edit(base, changes):
    rows = base['rows'].copy()
    for y, row in changes.items():
        assert len(row) <= base['width']
        rows[y] = row.ljust(base['width'], '.')
    return frame(rows, base['width'], base['height'])


def shift(base, dx=0, dy=0):
    # Small hand-specified pose recoil / hover offsets within a fixed canvas.
    rows = ['.' * base['width'] for _ in range(base['height'])]
    for y, row in enumerate(base['rows']):
        for x, token in enumerate(row):
            if token != '.':
                assert 0 <= x+dx < base['width'] and 0 <= y+dy < base['height'], 'Pose shift would clip painted pixels'
                dest = list(rows[y+dy]);dest[x+dx] = token;rows[y+dy] = ''.join(dest)
    return frame(rows, base['width'], base['height'])


def white_flash(base):
    return frame([''.join('W' if t != '.' else '.' for t in row) for row in base['rows']])


def seq(*steps):
    return [dict(frame=f, durationMs=((ms+99)//100)*100) for f, ms in steps]


breeze_idle = frame([
    '....SSSSSSSS....',
    '....ASSSSSAA....',
    '....AAAAAAAA....',
    '....DDAAAADD....',
    '....WWDDWWDD....',
    '....WWDDWWDD....',
    '..SS........SS..',
    '.SS..AAA...SS...',
    '.S..AWWA..SS....',
    'SS...AA..SS.....',
    '..SS....SS..SS..',
    '...SSSSSS..SS...',
    '.....SS...SS....',
    '..SS..SSSS......',
    '...SS..SS.......',
    '....SSSS........',
    '......SS........',
    '................',
])
breeze_turn = edit(breeze_idle, {
    6:'...SS......SS...', 7:'....SSAAA...SS..', 8:'.....AWWA....SS.',
    9:'..SS..AA......SS', 10:'...SS....SS..SS.', 11:'....SSSSSS..SS..',
    12:'..SS....SS......', 13:'...SS..SS.......',14:'....SSSS........',
    15:'.....SS.........',16:'......SS........',
})
breeze_float = shift(breeze_turn, dy=1)
breeze_charge = edit(breeze_idle, {
    6:'....SS....SS....', 7:'.....SSSSSS.....',8:'.....AWWA.......',
    9:'..SS.AWWA.SS....',10:'...SSAAAA.SS....',11:'....SSSSSS......',
    12:'....SS..SS......',13:'.....SSSS.......',14:'......SS........',
    15:'.....SSSS.......',16:'....SS..SS......',
})
breeze_release = edit(breeze_turn, {
    6:'..SS........SS..',7:'.SS..AAAA....SS.',8:'SS..AWWWA.....SS',
    9:'....AAAA....SS..',10:'..SS......SS....',11:'.SSSSSSSSSS.....',
    12:'....SS..........',13:'.....SSSS.......',14:'...SS..SS.......',
})
breeze_death_a = edit(breeze_idle, {
    0:'................',1:'...AAA....AAA...',2:'...ASA....SAA...',
    3:'....DD....DD....',4:'...WW......WW...',5:'....D......D....',
    6:'.SS..........SS.',7:'SS............SS',8:'....AA..AA......',
    9:'.SS..........SS.',10:'SS............SS',11:'.....SSSSSS.....',
    12:'...SS......SS...',13:'..SS........SS..',14:'....SS....SS....',
    15:'.....SSSSSS.....',16:'......SSSS......',
})
breeze_death_b = frame([
    '................','................','..SS........SS..','...S........S...',
    '......AA........','........AA......','.SS..........SS.','..S..........S..',
    '................','....SS....SS....','.....S....S.....','................',
    '..SS........SS..','...S........S...','......SSSS......','....SS....SS....',
    '................','................'])
breeze_death_c = frame(['................']*12+['..S.........S...','................','.....SS..SS.....','................'])

# Selected side / three-quarter sheep: horizontal wool barrel, four staggered
# legs, a diamond helmet on the head at right, and a blade attached to the mouth.
sheep_idle = frame([
    '........CCCCCC..',
    '........CAAAAC..',
    '........CCCCCC..',
    '..WWWWWWCCNNCC..',
    '.WWWWWWWCCNKCC..',
    '.WWSSWWWCCNNCC..',
    'WWWWWWWWSSNDNN..',
    'WWWWSSWWSSNDSSWW',
    'SWWWWWWWSSNDSSWW',
    '.SWWWWWSSSSSSS..',
    '..SSSSSSSSSSSS..',
    '..NN.NN.NN.NN...',
    '..NN.NN.NN.NN...',
    '..DD.DD.DD.DD...',
    '................',
    '................',
    '................',
    '................',
])
sheep_breathe = edit(sheep_idle,{5:'.WWWWSWWCCNNCC..',8:'SWWWSWWWSSNDSSWW',9:'.SSWWWWSSSSSSS..'})
sheep_walk_a = edit(sheep_idle,{11:'..NN.NN.NN.NN...',12:'.NN...NN.NN.NN..',13:'.DD...DD.DD.DD..'})
sheep_walk_b = edit(sheep_idle,{11:'..NN.NN.NN.NN...',12:'...NN.NN.NN.NN..',13:'...DD.DD.DD.DD..'})
sheep_windup = edit(sheep_idle,{
    0:'......CCCCCC....',1:'......CAAAAC....',2:'......CCCCCC....',
    3:'..WWWWCCNNCC....',4:'.WWWWWCCNKCC....',5:'.WWSSWCCNNCC....',
    6:'WWWWWWSSNDNN....',7:'WWWWSSSSNDSSWW..',8:'SWWWWWSSNDSSWW..',
    9:'.SWWWWWSSSSSSS..',
})
sheep_slash = edit(sheep_idle,{
    0:'................',1:'................',2:'................',
    3:'..WWWWWWCCCCCC..',4:'.WWWWWWWCAAAAC..',5:'.WWSSWWWCCCCCC..',
    6:'WWWWWWWWCCNNCC..',7:'WWWWSSWWCCNKCC..',8:'SWWWWWWWCCNNCC..',
    9:'.SWWWWWSSSNDNN..',10:'..SSSSSSSSNDSS..',11:'..NN..NN.NN..SS.',
    12:'..NN..NN.NN..NWW',13:'..DD..DD.DD..DDW',
})
sheep_recover = edit(sheep_idle,{7:'WWWWSSWWSSNNNN..',8:'SWWWWWWWSSNNSS..',9:'.SWWWWWSSSNN.SSW',10:'..SSSSSSSS....WW'})
sheep_death_a = edit(sheep_slash,{
    9:'.SWWWWWSSSNNNN..',10:'..SSSSSSSSNNSSWW',11:'..NNNN...NNNSSWW',
    12:'..DDDD...DDD....',13:'................',
})
sheep_death_b = frame(['................']*9+[
    '......CCCCCC....','..WWWWCAAAAC....','.WWWWWCCCCCC....',
    'WWWSSWWWNNNNSSWW','SWWWWWWSSNNNSSWW','.SSSSSSSSNN.....',
    '..NN.NN.NN.NN...','..DD.DD.DD.DD...'])
sheep_death_c = frame(['................']*12+[
    '..S.........S...','...W....A.......','.......CC.......','..S........S....'])

# Put the standing poses on the common ground baseline without changing their
# 16x18 envelope. A 3-row offset preserves the helmet/eye texel alignment.
sheep_idle=shift(sheep_idle,dy=3)
sheep_breathe=shift(sheep_breathe,dy=3)
sheep_walk_a=shift(sheep_walk_a,dy=3)
sheep_walk_b=shift(sheep_walk_b,dy=3)
sheep_windup=shift(sheep_windup,dy=3)
sheep_slash=shift(sheep_slash,dy=3)
sheep_recover=shift(sheep_recover,dy=3)
sheep_death_a=shift(sheep_death_a,dy=3)

# Rejected front-ish variant, kept for genuine native monitor comparison.
sheep_front = frame([
    '....AACCCCAA....','....ACCCCCCA....','....CCCCCCCC....',
    '...SSCNNNNCS....','...WWNKKNKWW....','...WWNNIINWW....',
    '.SWWWWWNNWWWS...','.WWWWWWWWWWWW...','.WWSSWWWWSSWW...',
    '.SWWWWWWWWWSS...','..SSWWWWWWSS....','...SSSSSSSS.....',
    '...NN.NN.NN.NN..','...NN.NN.NN.NN..','...DD.DD.DD.DD..',
    '................','................','................'])
sheep_front = edit(sheep_front,{6:'...WWWWNSSSSSWWW',7:'.SWWWWWNNSSSSSSS'})

phantom_idle = frame([
    '................','BB..........BB..','BCB........BCB..',
    '.BCCB....BCCB...','..BCCBBBBCCB....','...BCCSSCCB.....',
    '....BBBBBBBB....','....LLKKLLKK....','....LLKKLLKK....',
    '.....CCCCCC.....','......CSSC......','......CCCC......',
    '.......CC.......','.......CC.......','.......BD.......',
    '........D.......','................','................'])
phantom_up = edit(phantom_idle,{
    0:'BB..........BB..',1:'BCB........BCB..',2:'BCCB......BCCB..',
    3:'.BCCB....BCCB...',4:'..BCCBBBBCCB....',5:'...BCCSSCCB.....',
})
phantom_down = edit(phantom_idle,{
    0:'................',1:'................',2:'................',
    3:'................',4:'....BBBBBBBB....',5:'..BBCCSSCCBB....',
    6:'.BBB BBBBBBBB BB.'.replace(' ',''),
    7:'BBCBLLKKLLKKBCBB',8:'BCBBLLKKLLKKBBCB',
    9:'BB...CCCCCC...BB',10:'B.....CSSC.....B',
})
phantom_glide = edit(phantom_idle,{
    1:'................',2:'................',3:'................',
    4:'BBBBBBBBBBBBBBBB',5:'.BBCCCSSCCCCCBB.',
})
phantom_windup = edit(phantom_up,{
    9:'......CCCC......',10:'......CSSC......',11:'.......CC.......',
    12:'.......CC.......',13:'.......BD.......',14:'........D.......',15:'................',
})
phantom_dive = frame([
    '................','................','......BBBB......',
    '......BCCB......','......CSSC......','......CCCC......',
    '....BBBBBBBB....','....LLKKLLKK....','....LLKKLLKK....',
    '......CCCC......','......CSSC......','......CCCC......',
    '........D.......','................','................',
    '................','................','................'])
phantom_strike = edit(phantom_down,{
    9:'BB....SSSS....BB',10:'B.....SCCS.....B',11:'......CCCC......',
})
phantom_recover = edit(phantom_glide,{9:'.....CCCCCC.....',10:'......WSSW......',11:'......CCCC......'})
phantom_death_a = edit(phantom_dive,{7:'....DDKKDDKK....',8:'....DDKKDDKK....',9:'.....DDDDDD.....'})
phantom_death_b = frame(['................']*6+[
    '..BB........BB..','...BCB....BCB...','....BCCBBCCB....',
    '.....DDDDDD.....','.....DDKKDD.....','......DDDD......',
    '.......CC.......','....S.....S.....','......S.........'])
phantom_death_c = frame(['................']*10+[
    '..S.........S...','....C.....C.....','.......S........',
    '................','.....D..D.......','................'])


def unit(key, design, poses, sequences, icon):
    return dict(assetSchema=1, id=key, phase='ISOLATED_CONCEPT_ONLY', runtimeRegistered=False,
                format='CC_ROYALE_PALETTE_TOKEN_ROWS', design=design,
                anchor={'x':8,'y':17,'meaning':'fixed canvas foot/hover reference; not a hitbox'},
                frames=poses, previewSequences=sequences, deckIcon=icon)

assets={
 'breeze':unit('breeze','Minecraft Breeze: grey-blue cube head, bright eyes, three rotating wind bands; visual hover, ground gameplay proposal',
    dict(idle=breeze_idle,idle_b=breeze_float,move_a=breeze_turn,move_b=breeze_float,
         windup=breeze_charge,attack=breeze_release,recovery=breeze_turn,
         hit=shift(breeze_idle,dx=1),hit_flash=white_flash(breeze_idle),
         death_a=breeze_death_a,death_b=breeze_death_b,death_c=breeze_death_c),
    dict(idle=seq(('idle',300),('idle_b',300),('move_a',300),('idle_b',300)),
         movement=seq(('move_a',160),('move_b',160),('idle',160),('idle_b',160)),
         attack=seq(('idle',400),('windup',300),('attack',120),('recovery',180),('idle',400)),
         hit=seq(('hit_flash',70),('hit',100),('idle',230)),
         death=seq(('idle',250),('death_a',150),('death_b',180),('death_c',200))),
    frame(['..SSSSSSSS..','..ASSSSSAA..','..AAAAAAAA..','..DDAAAADD..','..WWDDWWDD..','..WWDDWWDD..','.SS......SS.','SS......SS..','.SSSSSSSS...','...SS..SS...','....SSSS....','.....SS.....'],12,12)),
 'adventure_sheep':unit('adventure_sheep','Four-legged white Minecraft sheep, cyan diamond helmet, iron sword held sideways in mouth; no hands or humanoid torso',
    dict(idle=sheep_idle,idle_b=sheep_breathe,move_a=sheep_walk_a,move_b=sheep_walk_b,
         windup=sheep_windup,attack=sheep_slash,recovery=sheep_recover,
         hit=sheep_windup,hit_flash=white_flash(sheep_idle),
         death_a=sheep_death_a,death_b=sheep_death_b,death_c=sheep_death_c),
    dict(idle=seq(('idle',400),('idle_b',400)),
         movement=seq(('move_a',180),('idle',100),('move_b',180),('idle_b',100)),
         attack=seq(('idle',350),('windup',220),('attack',100),('recovery',180),('idle',250)),
         hit=seq(('hit_flash',70),('hit',90),('idle',220)),
         death=seq(('idle',250),('death_a',140),('death_b',230),('death_c',250))),
    frame(['......CCCC..','......CAAC..','......CCCC..','..WWWWCCNN..','.WWWWWCCNK..','.WWWWWCCNN..','WWWWWWSSND..','WWWSWWSSNDSS','SWWWWWSSNNSS','..N.N..N.N..','..N.N..N.N..','..N.N..N.N..'],12,12)),
 'phantom':unit('phantom','Minecraft Phantom: wide angular navy/cyan wings, pale underside and green eyes; distinguish from purple bat scallops',
    dict(idle=phantom_idle,idle_b=phantom_glide,move_a=phantom_up,move_b=phantom_down,
         windup=phantom_windup,dive=phantom_dive,attack=phantom_strike,recovery=phantom_recover,
         hit=shift(phantom_glide,dy=1),hit_flash=white_flash(phantom_glide),
         death_a=phantom_death_a,death_b=phantom_death_b,death_c=phantom_death_c),
    dict(idle=seq(('move_a',160),('idle',140),('move_b',160),('idle_b',180)),
         movement=seq(('move_a',100),('idle',100),('move_b',100),('idle_b',100)),
         attack=seq(('idle_b',350),('windup',250),('dive',120),('attack',100),('recovery',200),('move_a',170),('idle',250)),
         hit=seq(('hit_flash',60),('hit',90),('idle',220)),
         death=seq(('idle',250),('death_a',140),('death_b',180),('death_c',250))),
    frame(['BB........BB','.BBB....BBB.','..BBBBBBBB..','..BBBBBBBB..','..LLKKLLKK..','..LLKKLLKK..','....CCCC....','....CSSC....','....CCCC....','.....CC.....','.....CC.....','.....CC.....'],12,12)),
}

effects={
 'breeze':dict(wind_charge=frame(['................','....A......A....','.....SSSSSS.....','....SS....SS....','...SS..WW..SS...','...SS.WWWW.SS...','....SS.WW.SS....','.....SSSSSS.....','....A......A....'],16,12),
               wind_gust_a=frame(['................','..SSSS..........','.SS..SS..SS.....','SS....SS..SS....','.SS..SS....SS...', '..SSSSSSSSSSSS..','.............SS.','..SSSSSSSSSSSS..','.SS..SS....SS...','SS....SS..SS....','.SS..SS..SS.....','..SSSS..........'],16,12),
               wind_gust_b=frame(['................','.....SSSS.......','....SS..SS..SS..','...SS....SS..SS.','....SS..SS....SS','.....SSSSSSSSSS.','...............S','.....SSSSSSSSSS.','....SS..SS....SS','...SS....SS..SS.','....SS..SS..SS..','.....SSSS.......'],16,12)),
 'adventure_sheep':dict(sword_arc_a=frame(['..............WW','............WWSS','..........WWSS..','.........WSS....','........WS......','........S.......','................','................','................','................','................','................'],16,12),
                       sword_arc_b=frame(['................','................','................','................','..............S.','.............WS.','............WS..','..........WWSS..','........WWSS....','......WWSS......','....WWSS........','................'],16,12)),
 'phantom':dict(dive_trail=frame(['....S..S........','.....CC.........','......S.........','.....CC.........','......S.........','.......C........','................'],16,12),
                feathers=frame(['..S.........S...','...C.......C....','.......S........','................','....D.....D.....','................'],16,12)),
}


def lua(value, level=0):
    if isinstance(value,bool):return 'true' if value else 'false'
    if isinstance(value,str):return json.dumps(value,ensure_ascii=False)
    if isinstance(value,(int,float)):return str(value)
    if isinstance(value,list):return '{\n'+''.join('    '*(level+1)+lua(v,level+1)+',\n' for v in value)+'    '*level+'}'
    return '{\n'+''.join('    '*(level+1)+'['+json.dumps(k)+'] = '+lua(v,level+1)+',\n' for k,v in value.items())+'    '*level+'}'


def main():
    for key,asset in assets.items():
        (ROOT/'sprites'/f'{key}.lua').write_text('-- Isolated design data; never required by production.\nreturn '+lua(asset)+'\n')
        (ROOT/'effects'/f'{key}.lua').write_text('-- Isolated native effect prototypes; no gameplay behavior.\nreturn '+lua(dict(frames=effects[key]))+'\n')
    variants=dict(frames={'side_selected':sheep_idle,'front_rejected':sheep_front})
    (ROOT/'sprites/sheep_variants.lua').write_text('-- Alternative silhouettes for visual comparison only.\nreturn '+lua(variants)+'\n')
    print('Exported 37 hand-authored native unit frames, 7 effect frames, 3 icons and 2 Sheep variants; no runtime registration.')

if __name__=='__main__':main()
