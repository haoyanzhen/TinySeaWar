#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["soundfile==0.13.1"]
# ///
"""Build title Oggs from adopted WAVs without changing the source packages."""
import argparse
import hashlib
import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET_I = -20.0
PEAK_CEILING = -2.0


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def measure(path):
    result = subprocess.run(['ffmpeg', '-hide_banner', '-nostdin', '-i', str(path), '-af',
                             'loudnorm=I=-20:TP=-2:LRA=11:print_format=json', '-f', 'null', '-'],
                            capture_output=True, text=True, check=True)
    return json.loads(result.stderr[result.stderr.rfind('{'):result.stderr.rfind('}') + 1])


def build():
    import soundfile as sf
    catalog = json.loads((ROOT / 'assets/audio/music/catalog.json').read_text())
    out = ROOT / 'assets/audio/music/runtime'
    out.mkdir(parents=True, exist_ok=True)
    tracks = []
    for track in catalog['tracks']:
        source = ROOT / 'assets/audio/music' / track['audio']
        assert sha(source) == track['sha256'], track['id'] + ': source hash changed'
        original = measure(source)
        # A constant gain keeps the accepted performance and dynamic range intact.
        gain = min(TARGET_I - float(original['input_i']), PEAK_CEILING - float(original['input_tp']))
        samples, rate = sf.read(source, dtype='float64', always_2d=True)
        target = out / (track['id'] + '.ogg')
        for attempt in range(3):
            with sf.SoundFile(target, 'w', samplerate=rate, channels=2, format='OGG', subtype='VORBIS') as audio:
                for start in range(0, len(samples), 8192):
                    audio.write(samples[start:start + 8192] * (10 ** (gain / 20)))
            encoded = measure(target)
            peak = float(encoded['input_tp'])
            if peak <= PEAK_CEILING + 0.1:
                break
            gain -= peak - PEAK_CEILING + 0.1
        assert peak <= PEAK_CEILING + 0.1
        probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format',
                                                    '-of', 'json', str(target)], text=True))
        duration = float(probe['format']['duration'])
        assert abs(duration - track['duration_seconds']) < 0.1
        assert probe['streams'][0]['channels'] == 2 and probe['streams'][0]['sample_rate'] == '48000'
        tracks.append({'id': track['id'], 'title': track['title'],
                       'path': 'res://' + target.relative_to(ROOT).as_posix(), 'duration': duration,
                       'source_sha256': track['sha256'], 'sha256': sha(target), 'gain_db': round(gain, 5),
                       'integrated_lufs': float(encoded['input_i']), 'true_peak_dbfs': peak,
                       'loudness_range_lu': float(encoded['input_lra']),
                       'loop_start': 0.0, 'loop_end': duration, 'resume_points': [],
                       'human_loop_status': 'pending', 'human_mix_status': 'pending'})
        print(f"{track['title']}: {duration:.1f}s, {encoded['input_i']} LUFS, {peak:.2f} dBTP")
    manifest = {'schema_version': 1, 'main_theme_id': 'title_fleet_departure_v1',
                'scene_fade_seconds': 1.5, 'tracks': tracks,
                'processing': {'encoder': 'libsndfile Vorbis default quality, 48kHz stereo', 'target_lufs': TARGET_I,
                               'true_peak_ceiling_dbfs': PEAK_CEILING, 'method': 'constant gain; no compression, trim or new music',
                               'loop_policy': 'whole accepted song with hard cuts at the end; human three-cycle review pending',
                               'resume_policy': 'no verified phrase markers yet; advance queue on return'}}
    destination = ROOT / 'data/audio/music_manifest.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


def check():
    data = json.loads((ROOT / 'data/audio/music_manifest.json').read_text())
    for track in data['tracks']:
        path = ROOT / track['path'].removeprefix('res://')
        assert sha(path) == track['sha256']
        source = ROOT / 'assets/audio/music/source' / track['id'] / 'source.wav'
        assert sha(source) == track['source_sha256']
        assert math.isfinite(track['duration']) and track['duration'] > 4
        assert track['true_peak_dbfs'] <= PEAK_CEILING + 0.1
    print(f"Music assets: {len(data['tracks'])} source/runtime hash pairs verified")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    check() if args.check else build()
