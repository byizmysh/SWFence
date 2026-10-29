#!/usr/bin/env python3
"""Create source release assets locally; never publish or include local Git data."""
import argparse
import hashlib
import io
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text().strip()
p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, default=ROOT / 'dist')
args = p.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
paths = ['packages', 'scripts', 'tests', 'docs', '.github', 'README.md', 'INSTALL.md',
         'LICENSE', 'CHANGELOG.md', 'CONTRIBUTING.md', 'VERSION', 'install.sh', '.gitignore']
archive = out / f'swfence-{VERSION}-source.tar.gz'
def public_member(member):
    if '__pycache__' in member.name or Path(member.name).suffix.lower() in ['.jpg', '.jpeg', '.png', '.webp', '.gif']:
        return None
    member.uid = member.gid = 0
    member.uname = member.gname = ''
    return member

with tarfile.open(archive, 'w:gz') as tf:
    for item in paths:
        path = ROOT / item
        if not path.exists():
            raise SystemExit(f'Missing release source: {item}')
        tf.add(path, arcname=f'SWFence/{item}', filter=public_member)
(out / 'install.sh').write_bytes((ROOT / 'install.sh').read_bytes())
(out / 'INSTALL.md').write_bytes((ROOT / 'INSTALL.md').read_bytes())
package_names = ['swfence-24.10.ipk', 'luci-app-swfence-24.10.ipk', 'swfence-25.12.apk', 'luci-app-swfence-25.12.apk']
files = [archive, out / 'install.sh', out / 'INSTALL.md'] + [out / name for name in package_names if (out / name).exists()]
if all((out / name).exists() for name in package_names):
    bundle = out / f'swfence-{VERSION}.tar.gz'
    members = {name: out / name for name in package_names + ['install.sh', 'INSTALL.md']}
    members.update({name: ROOT / name for name in ['README.md', 'LICENSE', 'VERSION']})
    manifest = ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}\n' for name, path in sorted(members.items())).encode()
    with tarfile.open(bundle, 'w:gz') as tf:
        for name, path in sorted(members.items()):
            tf.add(path, arcname=f'SWFence/{name}', filter=public_member)
        entry = tarfile.TarInfo('SWFence/SHA256SUMS')
        entry.mode = 0o644
        entry.size = len(manifest)
        tf.addfile(entry, io.BytesIO(manifest))
    files.append(bundle)
files.sort()
(out / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files))
print(f'Built {archive}; {len(files)} release checksums. No publication performed.')
