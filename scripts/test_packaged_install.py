#!/usr/bin/env python3
"""Install real module archives without the repository's sibling layout."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(args: list[str], cwd: Path) -> None:
    print('+ ' + ' '.join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def main() -> None:
    workspace = tomllib.loads((ROOT / 'moon.work').read_text())
    with tempfile.TemporaryDirectory(prefix='wasmoon-packaged-install-') as temporary:
        stage = Path(temporary)
        package_build = stage / 'package-build'
        members = []
        command = None
        for index, member in enumerate(workspace['members']):
            source = ROOT / member
            run(['moon', 'package', '--target-dir', str(package_build)], source)
            archives = list((package_build / 'publish').glob('*.zip'))
            if len(archives) != 1:
                raise RuntimeError(f'Expected one module archive, found {archives}')
            # Neither module names nor the original sibling topology survive.
            destination = stage / f'slot-{index}' / 'source'
            destination.mkdir(parents=True)
            with zipfile.ZipFile(archives[0]) as archive:
                archive.extractall(destination)
            archives[0].unlink()
            members.append(destination.relative_to(stage).as_posix())
            if source.name == 'wasmoon':
                command = destination / 'cmd/wasmoon'
        if command is None:
            raise RuntimeError('Wasmoon module is missing from the workspace')
        (stage / 'moon.work').write_text('members = ' + json.dumps(members) + '\n')
        build = stage / 'build'
        binaries = stage / 'bin'
        run(['moon', 'install', str(command), '--bin', str(binaries),
             '--target-dir', str(build)], stage)
        executable = binaries / ('wasmoon.exe' if os.name == 'nt' else 'wasmoon')
        guest = stage / 'smoke.wat'
        guest.write_text(r'''(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 16) "isolated-install-ok\n")
  (func (export "_start")
    (i32.store (i32.const 0) (i32.const 16))
    (i32.store (i32.const 4) (i32.const 20))
    (drop (call $write (i32.const 1) (i32.const 0)
      (i32.const 1) (i32.const 8)))))
''')
        for engine in [[], ['--no-jit']]:
            result = subprocess.run([str(executable), 'run', str(guest), *engine],
                                    cwd=stage, capture_output=True, text=True, check=True)
            if result.stdout != 'isolated-install-ok\n':
                raise RuntimeError(f'Unexpected guest output: {result.stdout!r}; {result.stderr}')
        print('Packaged installation and WASI execution passed on both engines.', flush=True)


if __name__ == '__main__':
    main()
