#!/usr/bin/env python3
"""Inventory runtime inputs and write a reproducible Windows export preset."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/windows-20261002'


def included(path):
    parts = path.parts
    name = path.name
    if path.suffix in {'.import', '.uid'} or name.startswith('.'):
        return False
    if parts[0] == 'scenes':
        return path.suffix == '.tscn'
    if parts[0] == 'scripts':
        return parts[1] != 'tests' and path.suffix == '.gd'
    if parts[0] == 'data':
        return not {'authoring', 'simulations'}.intersection(parts) and path.suffix in {'.json', '.tscf'}
    if parts[0] != 'assets':
        return False
    if {'source', 'source_alpha', 'raw', 'meta', 'concept', 'generated'}.intersection(parts):
        return False
    if parts[1] == 'characters' and ('processed' not in parts or 'qa' in parts):
        return False
    if 'qa' in parts:
        return path.as_posix() in {'assets/ui/qa/ui_asset_manifest.json', 'assets/vfx/combat/qa/combat_vfx_asset_manifest.json'}
    if parts[1] == 'audio' and 'runtime' not in parts:
        return False
    if name.endswith(('_delivery_review.json', '_source_review.json')) or 'prompt' in name:
        return False
    return path.suffix in {'.json', '.png', '.ogg', '.wav', '.gdshader', '.tres', '.ttf', '.otf'}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    paths = sorted(p.relative_to(ROOT) for folder in ['assets', 'data', 'scripts', 'scenes']
                   for p in (ROOT / folder).rglob('*') if p.is_file() and included(p.relative_to(ROOT)))
    resources = [p for p in paths if p.suffix not in {'.json', '.tscf'}]
    raw = [p for p in paths if p.suffix in {'.json', '.tscf'}]
    preset = '''[preset.0]
name="Windows 10 x64"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="resources"
export_files=PackedStringArray(%s)
include_filter="%s"
exclude_filter=""
export_path="build/windows-20261002/TinySeaWar-Windows10-x64/TinySeaWar.exe"
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
''' % (', '.join(json.dumps('res://' + p.as_posix()) for p in resources), ','.join(p.as_posix() for p in raw))
    (ROOT / 'export_presets.cfg').write_text(preset)
    entries = []
    for p in paths:
        data = (ROOT / p).read_bytes()
        entries.append({'path': p.as_posix(), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    (OUT / 'runtime_asset_inventory.json').write_text(json.dumps({'engine': '4.6.3.stable', 'target': 'Windows 10 x86_64', 'files': entries}, ensure_ascii=False, indent=2) + '\n')
    groups = {}
    for e in entries:
        p = Path(e['path']); key = '/'.join(p.parts[:2])
        count, size = groups.get(key, (0, 0)); groups[key] = (count + 1, size + e['bytes'])
    lines = ['# Windows 游戏打包素材清单', '', '| 类别 | 文件数 | 原始大小 MiB |', '|---|---:|---:|']
    lines += [f'| {key} | {count} | {size / 1048576:.2f} |' for key, (count, size) in groups.items()]
    lines += ['', '另含 project.godot 转换后的项目配置、Godot 自动收集的依赖与导入缓存，以及官方 Windows x64 Release 引擎。最终包内文件以 pck_inventory.json 为准。', '', '排除角色/地图/音频制作源、source_alpha、提示词、测试、报告、模拟实验、地形作者数据和编辑器插件。保留位于 qa 下的两份正式 UI/VFX 清单。', '', '中文当前使用系统字体回退；Windows 10 实际文字显示由人工测试。']
    (OUT / '打包素材清单.md').write_text('\n'.join(lines) + '\n')
    print(f'{len(paths)} runtime inputs, {sum(e["bytes"] for e in entries)/1048576:.1f} MiB')


if __name__ == '__main__':
    main()
