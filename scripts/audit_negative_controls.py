"""Run controlled mutations in disposable copies, never in the working tree.

Usage: python3 scripts/audit_negative_controls.py --lua lua5.4 --output results.json
Baseline tests must pass; each named mutation must make its assigned oracle fail.
This is a bounded sensitivity check, not a complete mutation-coverage score.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MUTATIONS = [
    ('frog_hp', 'src/cards.lua', 'maxHp = 550, damage = 40',
     'maxHp = 551, damage = 40', 'tests/test_frog_worm.lua'),
    ('tower_damage', 'src/custom_mob_rules.lua',
     'return damage*source.burrow.towerMultiplier', 'return damage', 'tests/test_frog_worm.lua'),
    ('hook_buildings', 'src/custom_mob_rules.lua', "and target.kind == 'unit'",
     'and true', 'tests/test_frog_worm.lua'),
    ('worm_placement', 'src/cards.lua', 'color = colors.red, placement = "burrow"',
     'color = colors.red, placement = "anywhere"', 'tests/test_frog_worm.lua'),
    ('hero_cycles', 'src/cards.lua', 'cycles = 2, name = "Hero Spider"',
     'cycles = 3, name = "Hero Spider"', 'tests/test_four_mobs.lua'),
    ('duplicate_deck', 'src/cards.lua', 'or seen[id]\n',
     'or false\n', 'tests/test_simulation_contracts.lua'),
    ('invalid_result', 'src/headless_match.lua', 'return state, bot1, bot2, ticks',
     'state.winner=3; return state, bot1, bot2, ticks', 'tests/test_headless_runner.lua'),
    ('missing_import', 'src/util.lua', '--',
     "local missing=require('src.audit_missing_module')\n--", 'tests/test_install_manifest.lua'),
    ('missing_registration', 'mechanics_test.lua',
     'require("src.frog_worm_mechanics").register(runTest)',
     '-- omitted by negative control', 'tests/test_mechanics_full_ci.lua'),
    ('missing_lua52_gate', '.github/workflows/lua-ci.yml', '            lua5.2 "$test"',
     '            true', 'tests/test_release_gate.lua'),
    ('bad_sprite_token', 'src/assets/custom_mobs/frames.lua', '"........RRRR...."',
     '"?.......RRRR...."', 'tests/test_frog_worm_rendering.lua'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua', default='lua5.4')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix='cc-negative-controls-') as temp:
        sandbox = Path(temp)
        for folder in ('src', 'lib', 'tests', '.github'):
            shutil.copytree(ROOT / folder, sandbox / folder,
                            ignore=shutil.ignore_patterns('__pycache__'))
        for path in ROOT.glob('*.lua'):
            shutil.copy2(path, sandbox / path.name)
        (sandbox / 'docs').mkdir()
        shutil.copy2(ROOT / 'docs/AUDIT_REGISTER.md', sandbox / 'docs/AUDIT_REGISTER.md')
        shutil.copy2(ROOT / 'QUALITY_GATE.md', sandbox / 'QUALITY_GATE.md')
        baselines = {}
        for name, file, before, after, test in MUTATIONS:
            if test not in baselines:
                baseline = subprocess.run([args.lua, test], cwd=sandbox,
                                          capture_output=True, text=True, timeout=120)
                assert baseline.returncode == 0, baseline.stdout + baseline.stderr
                baselines[test] = True
            path = sandbox / file
            original = path.read_bytes()
            body = original.decode()
            assert before in body, 'Mutation anchor missing: ' + name
            try:
                path.write_text(body.replace(before, after, 1))
                mutant = subprocess.run([args.lua, test], cwd=sandbox,
                                        capture_output=True, text=True, timeout=120)
            finally:
                path.write_bytes(original)
            results.append({'mutation': name, 'file': file, 'test': test,
                            'baseline': 'PASS', 'mutantExit': mutant.returncode,
                            'detected': mutant.returncode != 0,
                            'output': (mutant.stdout + mutant.stderr)[-1600:]})
    args.output.write_text(json.dumps(results, indent=2) + '\n')
    missed = [item['mutation'] for item in results if not item['detected']]
    assert not missed, 'Surviving controls: ' + ', '.join(missed)
    print(f'{len(results)} isolated negative controls detected under {args.lua}')


if __name__ == '__main__':
    main()
