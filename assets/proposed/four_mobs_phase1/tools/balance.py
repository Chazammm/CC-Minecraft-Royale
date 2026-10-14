"""Read actual baseline stats; propose numbers only. Never run proposed combat."""
from pathlib import Path
import json,math
ROOT=Path(__file__).resolve().parents[1]
def main():
 data=json.loads((ROOT/'evidence/captures.json').read_text());r=data['reference'];s=r['spider'];g=r['iron_golem'];z=r['zombie']
 hp={k:r[k]['unit']['maxHp'] for k in ['zombie','wither_skeleton','iron_golem']}
 hp['diamond_golem']=r['diamond_golem']['unit']['maxHp']
 hp.update({kind+'_tower':value['maxHp'] for kind,value in r['towers'].items()})
 p={'status':'PROPOSALS_ONLY_NOT_REGISTERED_NOT_SIMULATED','baseCommit':data['baselineRevision'],
  'ravager_rider':{'cost':5,'maxHp':1300,'moveSpeed':4.4,'attackRange':3,
   'damage':g['unit']['damage']*2,'attackCooldown':g['unit']['attackCooldown']*2,
   'riderDamage':20,'riderAttackCooldown':2,'riderRange':15,'projectileSpeedProposal':58},
  'baby_ender_dragon':{'cost':5,'maxHp':600,'damage':70,'attackCooldown':1.8,
   'attackRange':14,'projectileSplashRadius':4,'moveSpeed':5.2,'projectileSpeedProposal':38},
  'minoshroom':{'cost':8,'maxHp':2100,'damage':300,'attackCooldown':2.4,'attackRange':2.5,'moveSpeed':3.6},
  'hero_spider':{'cost':s['cost'],'maxHp':s['unit']['maxHp']*1.1,'damage':s['unit']['damage']*1.02,
   'attackCooldown':s['unit']['attackCooldown']/1.02,'attackRange':s['unit']['attackRange'],
   'moveSpeed':s['unit']['moveSpeed'],'cycles':2,'webCooldown':10,'webRangeProposal':12,
   'initialWebDelayProposal':10,'webMoveFrequencyFactor':0.25,'webAttackFrequencyFactor':0.25},
  'arithmeticOnly':{'targetHp':hp,'zombieHpAfterOneHit':z['unit']['maxHp']-300,
   'zombieHitsToKill':math.ceil(z['unit']['maxHp']/300),
   'damageConstraints':'HP/2 <= damage < HP; normal unmodified Zombie; no healing/other damage',
   'matchupsAt300':{k:math.ceil(v/300) for k,v in hp.items()}}}
 (ROOT/'BALANCE_PROPOSALS.json').write_text(json.dumps(p,indent=2)+'\n')
 print('Proposals derived from current card/tower data; no proposed gameplay executed')
if __name__=='__main__':main()
