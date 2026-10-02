#!/usr/bin/env python3
"""Verify Godot 4.6 PCK directory, file digests, release boundaries and PE target."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/windows-20261002'
APP = OUT / 'TinySeaWar-Windows10-x64'


def main():
    entries = []
    with (APP / 'TinySeaWar.pck').open('rb') as f:
        magic, version, major, minor, patch, flags, base, directory = struct.unpack('<6I2Q', f.read(40))
        assert magic == 0x43504447 and version == 3 and flags & 1 == 0
        f.seek(directory)
        count, = struct.unpack('<I', f.read(4))
        for _ in range(count):
            length, = struct.unpack('<I', f.read(4))
            path = f.read(length).rstrip(b'\0').decode()
            offset, size = struct.unpack('<QQ', f.read(16))
            md5 = f.read(16).hex()
            file_flags, = struct.unpack('<I', f.read(4))
            entries.append({'path': path, 'bytes': size, 'offset': offset, 'md5': md5, 'flags': file_flags})
        for entry in entries:
            f.seek(base + entry['offset'])
            assert hashlib.md5(f.read(entry['bytes'])).hexdigest() == entry['md5'], entry['path']
    names = {e['path'] for e in entries}
    forbidden = ('scripts/tests/', 'addons/', 'tools/', 'reports/', 'docs/', 'workorder/', 'data/terrain/authoring/', 'data/simulations/')
    assert not [n for n in names if n.startswith(forbidden)]
    assert not [n for n in names if '/source/' in n or '/source_alpha/' in n or '/raw/' in n]
    inventory = json.loads((OUT / 'runtime_asset_inventory.json').read_text())
    required = [e['path'] for e in inventory['files'] if Path(e['path']).suffix in {'.json', '.tscf'}]
    assert set(required) <= names, set(required) - names
    pe = (APP / 'TinySeaWar.exe').read_bytes()
    assert pe[:2] == b'MZ'
    pe_start, = struct.unpack_from('<I', pe, 0x3c)
    assert pe[pe_start:pe_start + 4] == b'PE\0\0'
    machine, = struct.unpack_from('<H', pe, pe_start + 4)
    assert machine == 0x8664
    (OUT / 'pck_inventory.json').write_text(json.dumps({'engine': [major, minor, patch], 'file_count': count, 'all_md5_verified': True, 'windows_pe_machine': 'AMD64', 'files': entries}, ensure_ascii=False, indent=2) + '\n')
    print(f'PCK: {count} entries verified; {len(required)} required raw data files present; production sources/tests/tools excluded; PE AMD64 verified')


if __name__ == '__main__':
    main()
