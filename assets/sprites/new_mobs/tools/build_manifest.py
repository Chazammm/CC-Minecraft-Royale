"""Record reproducible asset metadata. Run after intentional art changes."""
from pathlib import Path
import json, hashlib
from PIL import Image
from render_previews import NAMES, LABELS, ORIGINS
ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[2]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
refs={
'piglich':('AllTheMods/AllTheModium','1d39a7cbbe7b69769bd28f09b758a3cdfa47167e','src/main/resources/assets/allthemodium/geo/piglich_anim.geo.json','src/main/resources/assets/allthemodium/textures/entity/piglich.png'),
'martian_raptor':('terrarium-earth/Ad-Astra','45abf0ec05ea837c3df457f42ae440b6675e9cf0','src/main/java/earth/terrarium/adastra/client/models/entities/mobs/MartianRaptorModel.java','src/main/resources/assets/ad_astra/textures/entity/mob/martian_raptor.png'),
'cyclops':('AlexModGuy/Ice_and_Fire','02b2922003cbce3c67dad55dfea79acf1721e0db','src/main/java/com/github/alexthe666/iceandfire/client/model/ModelCyclops.java','src/main/resources/assets/iceandfire/textures/models/cyclops/cyclops_0.png'),
'wilden_chimera':('baileyholl/Ars-Nouveau','fd8c9520722bb96a3e75febaf770d7078db5ac43','src/main/resources/assets/ars_nouveau/geo/wilden_chimera.geo.json','src/main/resources/assets/ars_nouveau/textures/entity/wilden_chimera.png')}
data=json.loads((ROOT/'evidence/pixelbox_lua52.json').read_text())
manifest={'schema':1,'baseRevision':'6e85dc77553bd17422deeb9cb51258cefda06fe5','activation':'asset_library_only',
          'availableFrames':['idle'],'futureAnimationStates':['movement','attack','hurt','death'],
          'loveCanvas':[256,256],'loveAnchor':[128,240],'loveFilter':'nearest','loveAlpha':'binary',
          'nativePalette':'src/pixel_arena.lua PALETTE / default CC RGB',
          'nativeModule':'assets/sprites/new_mobs/cc_tweaked/sprites.lua','assets':{}}
for key,label,origin in zip(NAMES,LABELS,ORIGINS):
 im=Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA');cc=data[key]
 colors=sorted({p[:3] for p in im.getdata() if p[3]})
 reference={'kind':'original_custom_design'}
 if key in refs:
  repo,rev,model,texture=refs[key]
  reference={'repository':repo,'revision':rev,'model':'https://github.com/'+repo+'/blob/'+rev+'/'+model,'texture':'https://github.com/'+repo+'/blob/'+rev+'/'+texture}
 entry={'name':label,'origin':origin,'reference':reference,
        'loveFile':'love2d/'+key+'.png','sourceFile':'source/'+key+'.png',
        'loveDimensions':list(im.size),'loveBounds':list(im.getbbox()),'loveAnchor':[128,240],
        'loveOpaquePixels':sum(p[3]>0 for p in im.getdata()),'lovePalette':['#%02x%02x%02x'%p for p in colors],
        'nativeKey':key,'nativeDimensions':[cc['width'],cc['height']],
        'nativeRendererAnchor':[cc['width']/2,cc['height']/2],
        'nativeTokens':sorted(set(''.join(cc['rows']))-{'.'}),
        'nativePreview':'cc_tweaked/previews/'+key+'.png',
        'pixelboxPreview':'cc_tweaked/previews/'+key+'_pixelbox.png',
        'sha256':{path:sha(ROOT/path) for path in ['love2d/'+key+'.png','source/'+key+'.png','cc_tweaked/previews/'+key+'.png']}}
 manifest['assets'][key]=entry
manifest['nativeModuleSha256']=sha(ROOT/'cc_tweaked/sprites.lua')
(ROOT/'MANIFEST.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
lines=['-- Asset metadata only; animation beyond the single idle pose is not implemented.','return {']
for key in NAMES:lines.append('    '+key+' = { file="'+key+'.png", width=256, height=256, anchorX=128, anchorY=240, frame="idle" },')
lines.append('}');(ROOT/'love2d/index.lua').write_text('\n'.join(lines)+'\n')
print('Manifest written with source revisions, exact bounds, palettes, anchors and hashes')
