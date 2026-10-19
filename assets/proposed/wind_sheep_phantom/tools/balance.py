"""Readonly current-stat research and a standalone in-range duel model.

No Game module is run, no card is registered and no production table is changed.
This model deliberately omits movement, targeting, towers, projectiles and AI.
"""
from pathlib import Path
from fractions import Fraction as F
import json,math,itertools
ROOT=Path(__file__).resolve().parents[1]

PROPOSALS={
 'breeze':dict(name='Breeze',cost=3,maxHp=320,damage=32,attackCooldown=1.4,moveSpeed=6.6,
               attackRange=15,aggroRange=30,flying=False,canAttackAir=False,
               targetTypes=['ground_units','buildings','towers'],projectileSpeed=46,
               control=dict(empoweredEveryShots=3,nominalEmpoweredInterval=4.2,
                            maxKnockback=4,maxModifiedWalkSeconds=1.0,sharedVictimImmunity=3.0,terrainSampleStep=.25,
                            preserveCurrentBridgeChoice=True,displaceImmobile=False,
                            primaryOnly=True,affectsBuildings=False,affectsAir=False,affectsWaterOnly=False)),
 'adventure_sheep':dict(name='Adventure Sheep',cost=4,maxHp=620,damage=82,attackCooldown=1.1,
                        moveSpeed=7.4,attackRange=2.5,aggroRange=27,flying=False,canAttackAir=False,
                        targetTypes=['ground_units','buildings','towers'],passive='none',
                        damageType='single_target_melee',attackWindupVisualMs=300),
 'phantom':dict(name='Phantom',cost=4,maxHp=280,damage=76,attackCooldown=1.3,moveSpeed=10,
                attackRange=2.2,aggroRange=28,flying=True,canAttackAir=True,
                targetTypes=['units','buildings','towers'],buildingMultiplier=.5,towerMultiplier=.5,
                priority=dict(acquisitionOnly=True,localPreferenceRadius=14,
                              preserveValidTargetLock=True,excludeWaterOnlyFromPreference=True),
                dive=dict(windup=.3,maxTravel=4,maxSpeed=16,durationCap=.3,cooldown=5,
                          bonusDamage=0,invulnerable=False,returnTeleport=False))
}


def duel(a,b,start_a=0,start_b=0,tie='simultaneous'):
    hp_a,hp_b=F(str(a['maxHp'])),F(str(b['maxHp']))
    da,db=F(str(a['damage'])),F(str(b['damage']))
    ca,cb=F(str(a['attackCooldown'])),F(str(b['attackCooldown']))
    na,nb=F(str(start_a)),F(str(start_b));hits_a=hits_b=0;trace=[]
    for _ in range(1000):
        now=min(na,nb);a_due=na==now;b_due=nb==now
        if a_due and b_due and tie=='simultaneous':
            hp_a-=db;hp_b-=da;hits_a+=1;hits_b+=1;na+=ca;nb+=cb
        else:
            order=('a','b') if tie!='opponent_first' else ('b','a')
            for who in order:
                if hp_a<=0 or hp_b<=0:break
                if who=='a' and a_due:hp_b-=da;hits_a+=1;na+=ca
                if who=='b' and b_due:hp_a-=db;hits_b+=1;nb+=cb
        trace.append(dict(t=float(now),aHp=float(max(0,hp_a)),bHp=float(max(0,hp_b))))
        if hp_a<=0 or hp_b<=0:
            return dict(winner='draw' if hp_a<=0 and hp_b<=0 else 'sheep' if hp_b<=0 else 'opponent',
                        seconds=float(now),sheepHp=float(max(0,hp_a)),opponentHp=float(max(0,hp_b)),
                        sheepHits=hits_a,opponentHits=hits_b,trace=trace)
    raise AssertionError('Unbounded duel model')


def analyze(reference):
    sheep=PROPOSALS['adventure_sheep'];comparisons={}
    for key in ('zombie','wither_skeleton','wolf','spider','enderman','iron_golem'):
        card=reference['cards'][key];u=card['unit']
        comparisons[key]=dict(cost=card['cost'],hp=u['maxHp'],damage=u['damage'],cooldown=u['attackCooldown'],
                              dps=u['damage']/u['attackCooldown'],moveSpeed=u['moveSpeed'],
                              attackRange=u['attackRange'],targetMode=u['targetMode'])
    e=reference['evolutions']['iron_golem']['unit']
    comparisons['diamond_golem']=dict(cost=reference['cards']['iron_golem']['cost'],hp=e['maxHp'],
       damage=e['damage'],cooldown=e['attackCooldown'],dps=e['damage']/e['attackCooldown'],
       moveSpeed=e['moveSpeed'],attackRange=e['attackRange'],targetMode=e['targetMode'],
       caveat='Building-targeting evolution; moving-only pulse is excluded from scalar DPS. Not a standard duel opponent.')
    results={};sensitivity=[]
    for key in ('zombie','wither_skeleton'):
        opponent=reference['cards'][key]['unit']
        nominal=duel(sheep,opponent)
        variants=[]
        for start_a,start_b,tie in itertools.product((0,.1,.3),(0,.1),('simultaneous','sheep_first','opponent_first')):
            r=duel(sheep,opponent,start_a,start_b,tie)
            variants.append(dict(sheepStart=start_a,opponentStart=start_b,tieRule=tie,
                                 **{k:v for k,v in r.items() if k!='trace'}))
        results[key]=dict(nominal=nominal,phaseCases=variants,
                          sheepWins=sum(r['winner']=='sheep' for r in variants),cases=len(variants))
        for hp,damage,cd in itertools.product((600,620,640),(78,82,86),(1.0,1.1,1.2)):
            candidate={**sheep,'maxHp':hp,'damage':damage,'attackCooldown':cd}
            r=duel(candidate,opponent,.3,0,'opponent_first')
            sensitivity.append(dict(opponent=key,hp=hp,damage=damage,cooldown=cd,
                                    **{k:v for k,v in r.items() if k!='trace'}))
    windSafety=[]
    for key,card in reference['cards'].items():
        unit=card.get('unit')
        if not unit or unit.get('flying') or unit.get('waterOnly'):continue
        for factor,label in ((1.0,'normal'),(.25,'Hero Spider 75 percent slow')):
            speed=unit.get('moveSpeed',0)*factor
            distance=min(4,speed*1.0) if speed>0 else 0
            returnSeconds=distance/speed if speed>0 else 0
            assert distance==0 or returnSeconds<=1.0+1e-9
            windSafety.append(dict(card=key,modifier=label,effectiveSpeed=speed,
              pushCap=distance,straightReturnSeconds=returnSeconds,
              remainingImmunitySeconds=3.0-returnSeconds))
    modelChecks={
      'damage82NeedsSevenHitsAgainstZombie':math.ceil(reference['cards']['zombie']['unit']['maxHp']/sheep['damage'])==7,
      'damage82NeedsSixHitsAgainstWither':math.ceil(reference['cards']['wither_skeleton']['unit']['maxHp']/sheep['damage'])==6,
      'costExceedsBothThreeEmeraldPeers':all(sheep['cost']>reference['cards'][k]['cost'] for k in ('zombie','wither_skeleton')),
      'sheepDpsBelowBothPeers':all(sheep['damage']/sheep['attackCooldown']<comparisons[k]['dps'] for k in ('zombie','wither_skeleton')),
      'nominalSheepNotTankHp':sheep['maxHp']<comparisons['iron_golem']['hp']/2,
    }
    assert all(modelChecks.values())
    return dict(status='STANDALONE_ARITHMETIC_MODEL_NOT_HEADLESS_MATCH_RESULTS',
                baseRevision='e80ad6919b7eb21a1d3464290d177ee3ab210eee',
                assumptions=['Already in mutual melee range at time zero; no approach or spawn delay.',
                             'Constant direct single-target attacks; exact rational event times.',
                             'No movement, kiting, AI, spells, shields, towers, evolutions or healing.',
                             'Simultaneous damage is the nominal tie rule; sequential rules are sensitivity cases.',
                             'Proposed animation timings are previews, not an implemented combat schedule.'],
                proposals=PROPOSALS,comparison=comparisons,duels=results,sensitivity=sensitivity,
                burstBreakpoints={
                  'fallingAnvilDamage':reference['cards']['falling_anvil']['spell']['damage'],
                  'sheepAfterAnvil':sheep['maxHp']-reference['cards']['falling_anvil']['spell']['damage'],
                  'minoshroomDamage':reference['cards']['minoshroom']['unit']['damage'],
                  'sheepSurvivesTwoMinoshroomHits':sheep['maxHp']>2*reference['cards']['minoshroom']['unit']['damage']},
                windScalarSafety=windSafety,
                checks=modelChecks,cardCount=len(reference['cards']),evolutionCount=len(reference['evolutions']))


def report(d):
    s=PROPOSALS['adventure_sheep'];lines=['# Balance research — proposals only','',
      'Source: current `main` revision `e80ad6919b7eb21a1d3464290d177ee3ab210eee`. '+
      'All existing stats are read from the Lua capture. No proposed card exists in the live registry.','',
      '## Proposed starting values','',
      '| Card | E | HP | Damage | Interval | Raw DPS | Speed | Reach |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for v in PROPOSALS.values():lines.append(f"| {v['name']} | {v['cost']} | {v['maxHp']} | {v['damage']} | {v['attackCooldown']:.2f}s | {v['damage']/v['attackCooldown']:.2f} | {v['moveSpeed']} | {v['attackRange']} |")
    lines+=['','Phantom building/tower damage: 38 per hit, 29.23 raw DPS. Breeze knockback only on every third shot (nominal 4.2s between empowered shots); no damage bonus. Sheep has no passive. All costs and values are unapproved starting proposals.','',
      '## Existing melee comparison','',
      '| Card | E | HP | Damage | Interval | Raw DPS | Speed | Target rule |','|---|---:|---:|---:|---:|---:|---:|---|']
    for key,v in d['comparison'].items():lines.append(f"| {key} | {v['cost']} | {v['hp']:.2f} | {v['damage']} | {v['cooldown']:.2f}s | {v['dps']:.2f} | {v['moveSpeed']} | {v['targetMode']} |")
    lines+=['','Iron/Diamond Golems target buildings; they do not normally accept an isolated Sheep duel. Diamond Golem also has a 25-damage moving ground pulse every 2s, omitted from raw weapon DPS. No forced Golem-vs-Sheep match is claimed.','',
      '## Adventure Sheep: modeled 1v1 results','',
      '**These are fixed-position arithmetic duel forecasts, not production-engine matches or win rates.** '+
      'Both fighters begin in mutual range, attack at time zero, then at their exact intervals. '+
      'The nominal tie rule applies both simultaneous hits, even if lethal.','',
      '| Opponent | Sheep hits needed | Opponent hits needed | Nominal finish | Sheep HP left | Phase cases |','|---|---:|---:|---:|---:|---|']
    for key,v in d['duels'].items():
        r=v['nominal'];peer=d['comparison'][key]
        lines.append(f"| {key} | {math.ceil(peer['hp']/s['damage'])} | {math.ceil(s['maxHp']/peer['damage'])} | {r['seconds']:.2f}s | {r['sheepHp']:.0f} | {v['sheepWins']}/{v['cases']} Sheep wins in this bounded model |")
    lines+=['','The 18 cases per opponent vary Sheep first-hit delay (0/0.10/0.30s), enemy delay (0/0.10s), and simultaneous/Sheep-first/opponent-first handling. '+
      'They are deterministic parameter cases, **not 18 random matches**. The retained JSON contains every hit trace and all 54 stat-sensitivity cases.','',
      'Against Zombie, the nominal 60-HP margin is deliberately narrow. The 4E Sheep has 18.55% more HP than Zombie but lower DPS (74.55 versus 80); '+
      'Wither Skeleton has higher DPS (88), lower cost, and 88 versus 82 damage per hit. Sheep therefore does not dominate either unit on cost or damage output. '+
      'A large first-hit disadvantage, kiting or supporting fire can overturn the modeled win.','',
      f"At 4E, Sheep supplies {s['maxHp']/s['cost']:.2f} HP/E and {s['damage']/s['attackCooldown']/s['cost']:.2f} DPS/E. Zombie supplies 174.33 HP/E and 26.67 DPS/E; Wither Skeleton supplies 156.67 HP/E and 29.33 DPS/E. The conservative 4E proposal is therefore not justified by per-Emerald efficiency alone. A future playtest must prove that its single-body durability is useful.",'',
      f"One concrete burst breakpoint: the current 3E Falling Anvil deals {d['burstBreakpoints']['fallingAnvilDamage']} troop damage, leaving Sheep at {d['burstBreakpoints']['sheepAfterAnvil']} HP while killing a full normal Zombie or Wither Skeleton. Two unmodified 300-damage Minoshroom hits leave Sheep at 20 HP. These are arithmetic breakpoints, not modeled wins against Minoshroom or guaranteed spell trades.",'',
      'The optional helmet block is not recommended: it adds a timer/state and would conceal whether ordinary stats already meet the duel goal. '+
      'Retain it only as an alternative to evaluate if real future engine duels fail; do not add it on top of a successful stat line.','',
      '## Matchup interpretation','',
      '- Groups: single-target attacks cannot clear Bat Swarm or cheap ground swarms efficiently; no sword-arc area damage.',
      '- Ranged: normal movement and no dash allow Skeleton kiting, Snow Golem slow and focused fire. Use an ally or terrain to close distance.',
      '- Flying: Sheep cannot hit air; Blaze and Baby Ender Dragon are direct threats. An air ally is still required.',
      '- Buildings/towers: normal damage without a bonus, normal half-side deployment rules, and lower DPS than Wither Skeleton. Golems remain much harder to remove.',
      '- Enderman: also 620 HP but 95 damage/1.10s and teleport at 5E. Sheep pays less by giving up teleport and DPS.',
      '- King Frog: 3E/550 HP/40 per 1.4s plus positional pull. Sheep is a 4E direct fighter, not a replacement controller.',
      '- Nether Worm: 3E/350 HP with ambush placement and conditional opener. Sheep has neither deployment surprise nor burst.',
      '',
      '## Wind and existing slow interaction','',
      'The push cap is min(4 world units, one second of the victim\'s current modified move speed). A stopped/immobile victim is not displaced. For every current ordinary ground-card stat line, the JSON checks the normal speed and Hero Spider\'s 0.25 movement factor. The scalar straight-line return budget is at most one second, leaving at least two seconds of the shared three-second immunity. This is not a navigation or multi-Breeze simulation. The proposed bridge-choice guard still needs real engine tests.','',
      '## Later validation required','',
      'After explicit implementation approval: real engine duels with approach distances, both owners/entity orders, projectile travel, towers, movement modifiers and the final first-hit windup; '+
      'mixed decks, bot classification and full matches. No proposed-card headless or bot simulation is possible without adding the cards, which this package intentionally does not do.','']
    return '\n'.join(lines)


def main():
    data=json.loads((ROOT/'evidence/captures52.json').read_text())
    result=analyze(data['reference'])
    (ROOT/'evidence/balance_model.json').write_text(json.dumps(result,indent=2)+'\n')
    (ROOT/'BALANCE_PROPOSALS.json').write_text(json.dumps(dict(status='PROPOSALS_ONLY_NOT_REGISTERED',cards=PROPOSALS),indent=2)+'\n')
    (ROOT/'BALANCE.md').write_text(report(result))
    for key,value in result['duels'].items():print(key,value['nominal']['seconds'],value['nominal']['sheepHp'],value['sheepWins'],'/',value['cases'],'bounded arithmetic cases')
    print('PASS: current stats read; independent duel arithmetic and 54 sensitivity cases computed. No Game/AI code executed.')
if __name__=='__main__':main()
