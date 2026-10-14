"""Exact native data + displayed pixel oracle (unused glyph FG is irrelevant)."""
from pathlib import Path
import json,sys
from preview import encoded
a=json.loads(Path(sys.argv[1]).read_text());b=json.loads(Path(sys.argv[2]).read_text())
assert a['reference']==b['reference'],'Current reference stats differ across Lua versions'
count=0
for group in ['units','effects']:
 assert set(a[group])==set(b[group])
 for name in a[group]:
  aa,bb=a[group][name]['frames'],b[group][name]['frames']
  assert set(aa)==set(bb)
  for key,frame in aa.items():
   other=bb[key]
   assert frame['rows']==other['rows'] and frame['width']==other['width'] and frame['height']==other['height']
   assert encoded(frame).size==encoded(other).size
   assert encoded(frame).tobytes()==encoded(other).tobytes(),name+'/'+key+' changed displayed pixels'
   count+=1
legacy=encoded(a['comparison']['spider']).tobytes()!=encoded(b['comparison']['spider']).tobytes()
print('PASS: exact native and displayed-pixel parity for '+str(count)+' new frames; legacy Spider encoder variation='+str(legacy))
