#!/usr/bin/env python3
"""Rebuild the two patched guests from a pinned upstream checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    sha = subprocess.check_output(['git', '-C', str(args.upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if sha != manifest['upstream']:
        parser.error('upstream checkout does not match pinned revision')
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='wasi-http-contract-') as directory:
        work = Path(directory)
        # Read committed sources, never trust modifications in the checkout.
        prefix = 'tests/rust/wasm32-wasip3/'
        paths = subprocess.check_output(['git', '-C', str(args.upstream), 'ls-tree', '-r', '--name-only', sha, prefix], text=True).splitlines()
        wanted = {'src/cli.rs', 'src/http.rs', 'src/bin/http-fields.rs', 'src/bin/http-request.rs'}
        for path in paths:
            relative = path.removeprefix(prefix)
            if relative in wanted or relative.startswith('wit/'):
                dest = work / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(subprocess.check_output(['git', '-C', str(args.upstream), 'show', f'{sha}:{path}']))
        (work / 'src/lib.rs').write_text('pub mod cli;\npub mod http;\n')
        for name in ['Cargo.toml', 'Cargo.lock']:
            shutil.copyfile(ROOT / name, work / name)
        subprocess.run(['git', 'apply', str(ROOT / 'expectations.patch')], cwd=work, check=True)
        subprocess.run(['cargo', '+1.97.0', 'build', '--locked', '--release', '--target', 'wasm32-wasip2'], cwd=work, check=True)
        for name in manifest['files']:
            source = work / 'target/wasm32-wasip2/release' / name
            dest = args.output / name
            shutil.copyfile(source, dest)
            print(name, hashlib.sha256(dest.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
