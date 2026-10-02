"""Archive human-selected SFX losslessly; never promote historical alternatives."""
import collections
import hashlib
import html
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/audio/sfx/source/selected_20261001_v1'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    if path.exists() and path.read_text() != text:
        raise ValueError(f'Immutable package mismatch: {path}')
    path.write_text(text)


def copy_verified(source, target, expected=None):
    digest = sha(source)
    assert expected is None or digest == expected, source
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert sha(target) == digest, target
    else:
        shutil.copyfile(source, target)
    assert sha(target) == digest
    return dict(path=str(target.relative_to(DEST)), sha256=digest,
                bytes=target.stat().st_size)


def main():
    disposition = ROOT / 'tools/sfx/reviews/current_disposition.json'
    d = json.loads(disposition.read_text())
    selected = [x for x in d['items'] if x['status'] in ('adopt', 'adopt_previous')]
    assert len(selected) == 60 and len(d['cancelled_asset_ids']) == 62
    assert not any(x['status'] in ('redesign_semantics', 'revise_timbre') for x in d['items'])
    entries = []
    for x in selected:
        preview = ROOT / x['path']
        batch = ROOT / 'reports/audio' / x['batch_id']
        metadata = batch / x['category'] / (x['candidate_id'] + '.json')
        m = json.loads(metadata.read_text())
        assert m['preview']['sha256'] == x['sha256']
        raw = batch / m['raw']['path']
        target = DEST / x['category'] / x['id'].lower()
        audio = copy_verified(preview, target / 'selected.wav', x['sha256'])
        source = copy_verified(raw, target / 'raw.wav', m['raw']['sha256'])
        probe = json.loads(subprocess.check_output([
            'ffprobe', '-v', 'error', '-show_entries',
            'stream=codec_name,sample_rate,channels,duration,bits_per_raw_sample',
            '-of', 'json', str(target / 'selected.wav')]))['streams'][0]
        assert probe['codec_name'] == 'pcm_s24le' and probe['sample_rate'] == '48000'
        catalog = json.loads((batch / 'batch.json').read_text())
        asset = next(a for a in catalog['assets'] if a['id'] == x['id'])
        provenance = dict(selection=x, production=m, asset_design=asset,
                          source_batch_sha256=sha(batch / 'batch.json'))
        loudness = batch / 'loudness.json'
        if loudness.exists():
            provenance['loudness'] = json.loads(loudness.read_text()).get(x['candidate_id'])
        write_json(target / 'provenance.json', provenance)
        entries.append(dict(id=x['id'], title=x['title'], category=x['category'],
                            candidate_id=x['candidate_id'], batch_id=x['batch_id'],
                            selected=audio, raw=source,
                            provenance=str((target / 'provenance.json').relative_to(DEST)),
                            format=probe, loop=asset['loop'],
                            loop_points_frames=m.get('loop_points_frames'),
                            duration_review_required=m.get('duration_review_required', False),
                            source_overrange=m.get('source_peak', 0) > 1,
                            true_peak_4x_dbfs=m.get('true_peak_4x_dbfs'),
                            human_selection='accepted', runtime_ready=False))
    ids = {e['id'] for e in entries}
    assert not ids.intersection(d['cancelled_asset_ids'])
    for r in d['requirements']:
        assert set(r['assets']) <= ids, r
        if r['status'] != 'active_review_disposition':
            assert not r['assets'], r
    assert set().union(*(set(r['assets']) for r in d['requirements'])) == ids
    write_json(DEST / 'disposition_snapshot.json', d)
    for review in (ROOT / 'tools/sfx/reviews').glob('*.review.json'):
        copy_verified(review, DEST / 'reviews' / review.name)
    receipts = []
    for path in sorted((ROOT / 'tools/sfx').glob('*receipt*.json')):
        receipt = json.loads(path.read_text())
        if receipt.get('batch_id') in {e['batch_id'] for e in entries}:
            copy_verified(path, DEST / 'production' / path.name)
            receipts.append(str(path.name))
    manifest = dict(schema_version=1, package_id=DEST.name,
                    purpose='accepted_source_archive_not_runtime_manifest',
                    disposition_sha256=sha(disposition), assets=entries,
                    requirements=d['requirements'], cancelled_asset_ids=d['cancelled_asset_ids'],
                    production_receipts=receipts)
    write_json(DEST / 'manifest.json', manifest)
    validation = dict(selected=len(entries), cancelled=len(d['cancelled_asset_ids']),
                      requirements=dict(collections.Counter(r['status'] for r in d['requirements'])),
                      categories=dict(collections.Counter(e['category'] for e in entries)),
                      verified_wavs=len(entries)*2,
                      bytes=sum(e[k]['bytes'] for e in entries for k in ('selected', 'raw')),
                      loops=[e['id'] for e in entries if e['loop']],
                      duration_review=[e['id'] for e in entries if e['duration_review_required']],
                      source_overrange=[e['id'] for e in entries if e['source_overrange']],
                      preview_peak_warnings=[e['id'] for e in entries if e['true_peak_4x_dbfs'] is not None and e['true_peak_4x_dbfs'] > -1],
                      waveform_processing='none; byte-identical copies', runtime_integration='not_started')
    write_json(DEST / 'validation.json', validation)
    (DEST / '.gdignore').write_text('')
    lines = ['# 已采用音效素材索引', '', '采用版和生成源均原样保存；此包不是运行时资源。取消项与静默映射见 manifest.json。', '',
             '| ID | 名称 | 分类 | 采用候选 | 循环 | 采用版 |', '| --- | --- | --- | --- | --- | --- |']
    cards = []
    for e in entries:
        lines.append(f"| {e['id']} | {e['title']} | {e['category']} | {e['candidate_id']} | {'待循环验收' if e['loop'] else '单次'} | [WAV]({e['selected']['path']}) |")
        cards.append(f"<section><h2>{html.escape(e['id']+' '+e['title'])}</h2><p>{html.escape(e['category']+' / '+e['candidate_id'])}</p><audio controls preload='none' src='{e['selected']['path']}'></audio></section>")
    (DEST / 'inventory.md').write_text('\n'.join(lines)+'\n')
    (DEST / 'listen.html').write_text('<!doctype html><html lang="zh"><meta charset="utf-8"><title>已采用音效素材</title><style>body{font:16px system-ui;max-width:1000px;margin:40px auto;background:#102332;color:#eee}section{display:inline-block;vertical-align:top;width:44%;padding:2%;border-bottom:1px solid #456}audio{width:100%}</style><h1>60项已采用音效</h1><p>只读素材目录；保持已采用波形。循环与游戏混音另行验收。</p>'+''.join(cards)+'</html>')
    print(json.dumps(validation, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
