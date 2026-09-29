#!/usr/bin/env python3
"""Versioned music-review registry and a generated human-readable Markdown table."""
from __future__ import annotations
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import html
import json
import math
import os
from pathlib import Path
import urllib.parse

import music

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = Path(__file__).resolve().parent/'reviews'/'registry.json'
DECISIONS = {'pending':'待评审','preferred':'偏好候选','revise':'需改良','reject':'不采用'}
CATEGORIES = {'title':'标题','battle':'出击','victory':'胜利','defeat':'失败','neutral':'中性'}
PRIORITIES = {'high':'高','medium':'中','low':'低','unset':'未排期'}


def now():
    return datetime.now(timezone.utc).isoformat()


def file_hash(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()


def register(registry, folder, parent=None, remote_dir=None):
    """Register immutable audio versions; optional parent identifies an improvement source."""
    new=copy.deepcopy(registry)
    batch=music.validate(music.read(folder/'manifest.json'))
    assert all(r['batch_sha256']==music.digest(batch) for r in new['records'].values()
               if r['batch_id']==batch['id']), 'Existing batch changed; create a new batch'
    if parent:
        assert len(batch['tracks'])==1, '--parent currently supports a single-track revision batch'
        assert parent in new['records'], 'Unknown parent version'
    reports=music.read(folder/'validation_summary.json')
    by_id={t['id']:t for t in reports}
    for track in batch['tracks']:
        slug=track['id'];key=f'{batch["id"]}/{slug}'
        path=folder/f'{slug}.wav';sha=file_hash(path)
        report=by_id[slug]['validation']
        assert report['sha256']==sha, 'Audio hash differs from validation; rerun review'
        assert by_id[slug]['request']==track['request'], 'Validation request differs'
        if key in new['records']:
            old=new['records'][key]
            assert old['audio_sha256']==sha and old['batch_sha256']==music.digest(batch), 'Existing version changed; create a new batch'
            assert not parent or old['parent_id']==parent, 'Cannot relink an existing version'
            continue
        assert parent!=key, 'Self-parent rejected'
        new['records'][key]={
            'record_id':key,'batch_id':batch['id'],'batch_sha256':music.digest(batch),'track_id':slug,
            'title':track['title'],'category':track['category'],'audio_sha256':sha,
            'audio_path':os.path.relpath(path.resolve(),ROOT),'remote_audio_path':f'{remote_dir.rstrip("/")}/{slug}.wav' if remote_dir else None,
            'request':track['request'],'technical_snapshot':report,'parent_id':parent,
            'registered_at':now(),'reviews':[],'plans':[]}
    return new


def import_feedback(registry, payload, source):
    """Validate the entire import before changing anything; keep original reviewer text."""
    assert payload.get('version')==1 and isinstance(payload.get('tracks'),list)
    assert isinstance(payload.get('reviewer'),str) and payload['reviewer'].strip(), 'Reviewer required'
    assert isinstance(source,str) and source.strip(), 'Review source required'
    new=copy.deepcopy(registry);seen=set()
    for row in payload['tracks']:
        assert row['id'] not in seen, 'Duplicate review row'
        seen.add(row['id'])
        key=f'{payload["batch_id"]}/{row["id"]}'
        record=new['records'][key]
        assert record['batch_sha256']==payload['batch_sha256'], 'Batch hash differs'
        assert record['audio_sha256']==row['audio_sha256'], 'Audio version differs'
        assert row['decision'] in DECISIONS and isinstance(row['notes'],str)
        assert type(row['loop_checked']) is bool
        assert isinstance(row['timestamps'],list)
        duration=record['technical_snapshot']['duration_seconds']
        assert all(type(t) in (int,float) and math.isfinite(t) and 0<=t<=duration for t in row['timestamps']), 'Invalid issue time'
        if row['decision']=='pending' and not row['notes'].strip() and not row['timestamps'] and not row['loop_checked']:
            continue  # An untouched row in a full-page export is not a new review.
        reviewed_at=payload.get('exported_at') or payload.get('reviewed_on')
        assert isinstance(reviewed_at,str) and reviewed_at, 'Review date required'
        datetime.fromisoformat(reviewed_at.replace('Z','+00:00'))
        event={'reviewer':payload['reviewer'],'source':source,'decision':row['decision'],
               'notes':row['notes'],'timestamps':row['timestamps'],'loop_checked':row['loop_checked']}
        event_id=music.digest(event)
        if any(r['event_id']==event_id for r in record['reviews']):continue
        event.update(event_id=event_id,reviewed_at=reviewed_at,imported_at=now())
        record['reviews'].append(event)
        # Date order, not import order, determines the newest actual review.
        record['reviews'].sort(key=lambda r:review_time(r['reviewed_at']))
    return new


def review_time(value):
    dt=datetime.fromisoformat(value.replace('Z','+00:00'))
    if dt.tzinfo is None:dt=dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def plan(registry, key, actions, priority, author):
    assert priority in PRIORITIES and isinstance(actions,str) and actions.strip()
    assert author.strip()
    new=copy.deepcopy(registry);record=new['records'][key]
    entry={'actions':actions,'priority':priority,'author':author}
    if record['plans'] and all(record['plans'][-1][k]==v for k,v in entry.items()):return new
    record['plans'].append({**entry,'recorded_at':now()})
    return new


def cell(value):
    return html.escape(str(value)).replace('|','&#124;').replace('\n','<br>')


def render(registry, output):
    records=registry['records']
    lines=['# 音乐评审跟踪表','',
           '由 `tools/music/tracker.py` 从 `registry.json` 生成；请通过工具登记和导入意见，不直接编辑本表。',
           '一条记录对应一个音频版本。人工偏好不等于正式资产验收；新版本不继承旧版本的试听结论。音频在被忽略的 reports 中，台账、提示词和反馈留在 Git；远端路径用于找回文件。','',
           '| 曲目 | 用途 | 人工结论 | 改良优先级 | 最近反馈 | 改良计划（制作方） | 版本与复查 |',
           '| --- | --- | --- | --- | --- | --- | --- |']
    for key,r in records.items():
        review=r['reviews'][-1] if r['reviews'] else {}
        p=r['plans'][-1] if r['plans'] else {}
        children=[c for c in records.values() if c['parent_id']==key]
        state='待首次评审' if not review else '已记录反馈'
        if r['parent_id']:state='改良版待复查' if not review else '改良版已有反馈（见详情）'
        if children:state+='；后继版本 '+str(len(children))+' 个，需对照复查'
        values=[r['title'],CATEGORIES[r['category']],DECISIONS[review.get('decision','pending')],
                PRIORITIES[p.get('priority','unset')],review.get('notes','—'),p.get('actions','—'),state]
        lines.append('| '+' | '.join(cell(v) for v in values)+' |')
    lines+=['','## 版本与评审历史','']
    for key,r in records.items():
        audio=ROOT/r['audio_path'];relative=os.path.relpath(audio,output.parent)
        lines += [f'### {cell(r["title"])}','',f'- 记录：`{key}`',
                  f'- 音频 SHA256：`{r["audio_sha256"]}`',
                  f'- [本地试听 WAV]({urllib.parse.quote(relative,safe="/")})',
                  f'- 远端音频：`{r["remote_audio_path"] or "未登记；请补充归档位置"}`',
                  f'- 改良来源：`{r["parent_id"] or "初始候选"}`',
                  '- 后继版本：'+', '.join('`'+k+'`' for k,v in records.items() if v['parent_id']==key) if any(v['parent_id']==key for v in records.values()) else '- 后继版本：无',
                  f'- 技术检测提示：{cell(", ".join(r["technical_snapshot"].get("issues",[])) or "无自动提示；不代表人工通过")}',
                  '- 人工历史：']
        for event in r['reviews']:
            lines += [f'  - {cell(event["reviewed_at"])} · {cell(event["reviewer"])} · {DECISIONS[event["decision"]]}：{cell(event["notes"])}',
                      f'    来源：{cell(event["source"])}；问题秒数：{cell(event["timestamps"])}；循环自查：{"已标记" if event["loop_checked"] else "未标记"}。']
        if not r['reviews']:lines+=['  - 待评审。']
        if r['plans']:
            lines+=['- 改良计划历史（不属于用户原话）：']
            for p in r['plans']:lines+=[f'  - {cell(p["recorded_at"])} · {cell(p["author"])} · {PRIORITIES[p["priority"]]}：{cell(p["actions"])}']
        lines+=['']
    output.write_text('\n'.join(lines)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry',type=Path,default=DEFAULT)
    subs=parser.add_subparsers(dest='command',required=True)
    r=subs.add_parser('register');r.add_argument('--batch-dir',type=Path,required=True);r.add_argument('--parent');r.add_argument('--remote-dir')
    i=subs.add_parser('import');i.add_argument('--feedback',type=Path,required=True);i.add_argument('--source',required=True)
    p=subs.add_parser('plan');p.add_argument('--record',required=True);p.add_argument('--actions',required=True);p.add_argument('--priority',choices=PRIORITIES,required=True);p.add_argument('--author',default='Codex（制作计划）')
    subs.add_parser('render')
    a=parser.parse_args()
    a.registry.parent.mkdir(parents=True,exist_ok=True)
    # Advisory lock avoids lost writes between simultaneous imports. Lock is a temporary runtime artifact.
    import fcntl,tempfile
    lock=Path(tempfile.gettempdir())/('music-registry-'+hashlib.sha256(str(a.registry.resolve()).encode()).hexdigest()+'.lock')
    with lock.open('a') as f:
        fcntl.flock(f,fcntl.LOCK_EX)
        registry=music.read(a.registry) if a.registry.exists() else {'version':1,'records':{}}
        assert registry['version']==1
        if a.command=='register':registry=register(registry,a.batch_dir,a.parent,a.remote_dir)
        elif a.command=='import':registry=import_feedback(registry,music.read(a.feedback),a.source)
        elif a.command=='plan':registry=plan(registry,a.record,a.actions,a.priority,a.author)
        tmp=a.registry.with_suffix('.json.tmp')
        tmp.write_text(json.dumps(registry,ensure_ascii=False,indent=2)+'\n')
        tmp.replace(a.registry)
        output=a.registry.with_suffix('.md');render(registry,output)
    print(json.dumps({'records':len(registry['records']),'review_events':sum(len(r['reviews']) for r in registry['records'].values()),'table':str(output)},ensure_ascii=False))

if __name__=='__main__':main()
