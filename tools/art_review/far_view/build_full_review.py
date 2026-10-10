"""Build portable (repo-relative) full-roster review; no aesthetic auto-approval."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'reports/art/20261009-far-view-all'
def main():
 manifest=json.loads((OUT/'manifest.json').read_text())
 captures=json.loads((OUT/'captures.json').read_text())
 inventory={'scope':'48 battle-only revisions; 56px style adopted; per-character human review pending','files':{}}
 for entry in manifest['characters'].values():
  for role in entry['roles'].values():
   p=ROOT/role['path']; inventory['files'][role['path']]=hashlib.sha256(p.read_bytes()).hexdigest()
 for capture in captures:
  p=OUT/capture['file'];inventory['files'][capture['file']]=hashlib.sha256(p.read_bytes()).hexdigest()
 (OUT/'inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2)+'\n')
 html=Path(__file__).with_name('full_review_template.html').read_text().replace('/*MANIFEST*/',json.dumps(manifest,ensure_ascii=False)).replace('/*CAPTURES*/',json.dumps(captures,ensure_ascii=False))
 (OUT/'review.html').write_text(html)
 print('Review:',OUT/'review.html')
if __name__=='__main__':main()
