"""Compose only actual runtime rasters, terminal blits and approved static PNGs."""
from pathlib import Path
import argparse
import importlib.util
import json
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('existing_preview_helpers',ROOT.parent/'frog_worm/tools/previews.py')
helpers=importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def compositions(data):
    result={}
    sheet=Image.new('RGB',(1040,770),helpers.BG)
    helpers.header(sheet,'BREEZE + ADVENTURE SHEEP / LIVE CC','Registered native sprites -> unchanged arena -> actual PixelBox blits; approved LOVE masters at 1x')
    draw=ImageDraw.Draw(sheet)
    for x,title in [(180,'LOVE master'),(510,'Native / 8x'),(820,'Actual PixelBox / 8x')]:
        draw.text((x,113),title,anchor='mm',font=helpers.font(18),fill='#a8c8d2')
    for i,key in enumerate(['breeze','adventure_sheep']):
        frame=data['captures'][key+'_idle']
        native=helpers.native(frame);decoded=helpers.decoded(frame)
        master=Image.open(ROOT/'love2d'/f'{key}.png')
        assert master.mode=='RGBA' and master.size==(256,256)
        assert set(master.getchannel('A').get_flattened_data())=={0,255}
        y=137+i*312
        helpers.paste(sheet,master,52,y)
        helpers.paste(sheet,native,510-native.width*4,y+55,8)
        helpers.paste(sheet,decoded,820-decoded.width*4,y+15,8)
        label='Breeze / 3E / 320 HP' if key=='breeze' else 'Adventure Sheep / 4E / 620 HP'
        draw.text((520,y+276),label,anchor='mm',font=helpers.font(20),fill='#f2eee1')
        result[f'previews/{key}_native.png']=native
        result[f'previews/{key}_pixelbox.png']=decoded
    result['previews/comparison.png']=sheet
    scene=helpers.decoded(data['liveScene'])
    result['previews/gameplay_1x.png']=scene
    result['previews/gameplay_6x.png']=scene.resize((scene.width*6,scene.height*6),Image.Resampling.NEAREST)
    return result


def clips(data):
    for key in ['breeze','adventure_sheep']:
        idle=[key+'_idle']
        if key=='breeze':idle.append('breeze_idle_b')
        sequences={'idle':idle,'movement':[key+'_move_a',key+'_move_b'],
                   'attack':[key+'_idle',key+'_windup',key+'_attack',key+'_recovery']}
        for action,sequence in sequences.items():
            images=[helpers.decoded(data['captures'][pose]) for pose in sequence]
            frames=[im.resize((im.width*8,im.height*8),Image.Resampling.NEAREST) for im in images]
            yield ROOT/'previews'/f'{key}_{action}.gif',frames,[300]*len(frames)


def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true')
    p.add_argument('--capture52',type=Path,default=ROOT/'evidence/captures52.json')
    p.add_argument('--capture54',type=Path,default=ROOT/'evidence/captures54.json')
    args=p.parse_args();data=json.loads(args.capture52.read_text())
    assert data==json.loads(args.capture54.read_text()),'Cross-Lua rendering differs'
    for rel,expected in compositions(data).items():
        if args.check:
            with Image.open(ROOT/rel) as stored:
                assert stored.mode==expected.mode and stored.size==expected.size
                assert stored.tobytes()==expected.tobytes(),rel
        else:expected.save(ROOT/rel)
    for path,frames,durations in clips(data):
        if args.check:
            with Image.open(path) as stored:
                assert stored.n_frames==len(frames),str(path)
                for i,frame in enumerate(frames):
                    stored.seek(i)
                    assert stored.convert('RGB').tobytes()==frame.tobytes(),f'{path} frame {i}'
                    assert stored.info['duration']==durations[i]
        else:frames[0].save(path,save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2,optimize=False)
    print('PASS: actual registered PNGs, exact PixelBox captures, cross-Lua parity, six pose GIFs and gameplay scene')


if __name__=='__main__':main()
