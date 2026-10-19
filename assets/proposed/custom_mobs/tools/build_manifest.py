"""Record exact files, reference provenance, bounds, palettes and import anchors."""
import json,hashlib
from PIL import Image
from render_previews import ROOT,NAMES,LABELS
from export_love import WIDE
BASE='6e85dc77553bd17422deeb9cb51258cefda06fe5'
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
data=json.loads((ROOT/'evidence/pixelbox_lua52.json').read_text())
refs={
 'netherite_crab':{'kind':'original_custom_adaptation','primary':'https://www.minecraft.net/en-us/article/mob-vote-crab','image':'https://www.minecraft.net/content/dam/minecraftnet/games/minecraft/game-updates/CRAB_Header_1170x500.jpg','note':'Unreleased 2023 Mob Vote concept; one huge claw in reference. Our asymmetric pair and netherite armor are original additions.'},
 'king_frog':{'kind':'original_custom_adaptation','primary':'https://www.minecraft.net/en-us/article/mob-menagerie--frog','image':'https://www.minecraft.net/content/dam/minecraftnet/games/minecraft/screenshots/frog_C.jpg','note':'Orange vanilla frog anatomy; crown and short mantle are original additions.'},
 'nether_worm':{'kind':'original_custom_design','note':'Original Nether organism; no canonical Minecraft mob claimed.'},
 'ore_centipede':{'kind':'original_custom_design','note':'Original ore-eating arthropod; no canonical Minecraft mob claimed.'}}
m={'schema':1,'status':'proposed_assets_only_no_gameplay_activation','baseRevision':BASE,'inspected':'2026-10-16','styleReference':'assets/sprites/approved-model-revamp-1.webp','nativeModule':'cc_tweaked/sprites.lua','nativePalette':'src/pixel_arena.lua PALETTE; default ComputerCraft RGB; dot alpha','nativeMaxDimensions':[16,18],'loveFilter':'nearest','loveAlpha':'binary','loveFrames':['idle'],'nativePoses':sorted(data),'assets':{}}
lines=['-- Import metadata only. Single main pose; no animation or gameplay registration.','return {']
for key,label in zip(NAMES,LABELS):
 im=Image.open(ROOT/'love2d'/(key+'.png')).convert('RGBA');width=im.width;cc=data[key]
 paths=['source/'+key+'.png','love2d/'+key+'.png','cc_tweaked/previews/'+key+'.png','cc_tweaked/previews/'+key+'_pixelbox.png']
 m['assets'][key]={'name':label,'origin':'Custom / CC Royale','reference':refs[key],'referenceAccessed':'2026-10-16','loveFile':paths[1],'sourceFile':paths[0],'sourceDimensions':list(Image.open(ROOT/paths[0]).size),'loveDimensions':list(im.size),'loveBounds':list(im.getbbox()),'loveAnchor':[width//2,240],'loveOpaquePixels':sum(p[3]>0 for p in im.get_flattened_data()),'lovePalette':sorted({'#%02x%02x%02x'%p[:3] for p in im.get_flattened_data() if p[3]}),'nativeKey':key,'nativeDimensions':[cc['width'],cc['height']],'nativeRendererAnchor':[cc['width']/2,cc['height']/2],'nativeTokens':sorted(set(''.join(cc['rows']))-{'.'}),'nativePreview':paths[2],'pixelboxPreview':paths[3],'sha256':{p:sha(p) for p in paths}}
 lines.append('    '+key+' = { file="'+key+'.png", width='+str(width)+', height=256, anchorX='+str(width//2)+', anchorY=240, frame="idle" },')
lines+=['}'];(ROOT/'love2d/index.lua').write_text('\n'.join(lines)+'\n')
m['hashes']={p:sha(p) for p in ['cc_tweaked/sprites.lua','love2d/index.lua','balance/current_cards.json','balance/proposals.json']}
(ROOT/'MANIFEST.json').write_text(json.dumps(m,indent=2,ensure_ascii=False)+'\n')
print('Manifest: 4 masters, 13 native poses, exact hashes/anchors/reference provenance')
