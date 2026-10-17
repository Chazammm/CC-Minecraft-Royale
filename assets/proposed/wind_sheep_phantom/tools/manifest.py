"""Content inventory for this isolated concept package; never writes outside it."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
EXCLUDED={'MANIFEST.json'}

def inventory():
 captures=json.loads((ROOT/'evidence/captures52.json').read_text())
 files={}
 for path in sorted(ROOT.rglob('*')):
  if not path.is_file() or '__pycache__' in path.parts or path.suffix=='.pyc' or path.name in EXCLUDED:continue
  files[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
 return dict(schema=1,package='wind_sheep_phantom',status='ISOLATED_DESIGN_PROTOTYPES_NOT_REGISTERED',
             baseRevision=captures['baseRevision'],nativeMax=[16,18],palette='Unchanged default CC 16-color palette; dot transparency',
             icons=[12,12],nativePoses={k:len(v['frames']) for k,v in captures['units'].items()},
             effectFrames={k:len(v['frames']) for k,v in captures['effects'].items()},
             probeCasesPerLua=captures['totalProbeCases'],hardware='UNVERIFIED',filesSha256=files)

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
 expected=inventory();path=ROOT/'MANIFEST.json'
 if a.check:assert json.loads(path.read_text())==expected,'Package files changed; review then regenerate manifest'
 else:path.write_text(json.dumps(expected,indent=2,ensure_ascii=False)+'\n')
 print(('PASS: ' if a.check else 'Wrote ')+str(len(expected['filesSha256']))+' isolated package content hashes')
if __name__=='__main__':main()
