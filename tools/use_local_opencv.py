"""Configure existing Android native build caches to use a local OpenCV archive.

This avoids repeating a failed CMake HTTP download; it does not replace or modify
the installed dartcv4 package. Run after a first build has created its cache:
  python tools/use_local_opencv.py .tooling/opencv-4.13.0.tar.gz
"""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve()
    source_parent = ROOT / '.tooling/native_sources'
    source_parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:gz') as bundle:
        roots = {name.split('/')[0] for name in bundle.getnames()}
        if len(roots) != 1 or not re.fullmatch(r'opencv-\d+\.\d+\.\d+', next(iter(roots))):
            raise ValueError('Expected an official OpenCV version archive')
        source = source_parent / next(iter(roots))
        if not (source / 'CMakeLists.txt').is_file():
            bundle.extractall(source_parent, filter='data')
    print(f'Archive SHA-256: {hashlib.sha256(archive.read_bytes()).hexdigest()}', flush=True)
    sdk = None
    for line in (ROOT / 'android/local.properties').read_text().splitlines():
        if line.startswith('sdk.dir='):
            sdk = Path(line.split('=', 1)[1].replace('\\\\', '\\'))
    if sdk is None:
        raise RuntimeError('Android SDK path is missing')
    cmakes = list((sdk / 'cmake').glob('*/bin/cmake.exe'))
    if not cmakes:
        raise RuntimeError('Install CMake using Android SDK Manager')
    cmake = sorted(cmakes, key=lambda p: [int(n) for n in p.parents[1].name.split('.')])[-1]
    configured = 0
    for cache in (ROOT / '.dart_tool/hooks_runner/shared/dartcv4/build').glob('*/CMakeCache.txt'):
        text = cache.read_text(encoding='utf-8')
        if not re.search(r'^ANDROID_ABI:[^=]+=arm64-v8a$', text, re.M):
            continue
        match = re.search(r'^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$', text, re.M)
        if not match:
            continue
        command = [str(cmake), '-S', match[1].strip(), '-B', str(cache.parent),
                   f'-DFETCHCONTENT_SOURCE_DIR_OPENCV={source.as_posix()}']
        print(f'Configuring Android OpenCV in {cache.parent}', flush=True)
        subprocess.run(command, check=True)
        configured += 1
    if not configured:
        raise RuntimeError('No Android arm64 dartcv4 cache found; start flutter build apk once first')
    print(f'Configured {configured} native build cache(s)', flush=True)


if __name__ == '__main__':
    main()
